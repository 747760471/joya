//! Joya M:N Goroutine Scheduler
//!
//! Architecture:
//! - M OS worker threads (M = CPU count)
//! - N user-space goroutines (Fibers on Windows)
//! - Global run queue + per-worker local queue
//! - Channel blocking yields the current goroutine, unblocking re-enqueues it
//!
//! Flow:
//!   go {} → create Fiber → enqueue to global queue
//!   Worker thread: convert to fiber → loop { dequeue → switch_to(fiber) → fiber yields back → repeat }
//!   Chan send/recv full/empty → yield to scheduler → scheduler picks next
//!   Chan signal → enqueue waiting goroutine

const std = @import("std");
const windows = std.os.windows;
const WINAPI = windows.WINAPI;
const LPVOID = windows.LPVOID;
const SIZE_T = windows.SIZE_T;

const PFIBER_START_ROUTINE = *const fn (?LPVOID) callconv(WINAPI) void;

// Windows Fiber API
extern "kernel32" fn CreateFiber(SIZE_T, PFIBER_START_ROUTINE, ?LPVOID) callconv(WINAPI) ?LPVOID;
extern "kernel32" fn SwitchToFiber(LPVOID) callconv(WINAPI) void;
extern "kernel32" fn DeleteFiber(LPVOID) callconv(WINAPI) void;
extern "kernel32" fn ConvertThreadToFiber(?LPVOID) callconv(WINAPI) ?LPVOID;
extern "kernel32" fn ConvertFiberToThread() callconv(WINAPI) i32;

/// A single goroutine (user-space coroutine)
pub const Goroutine = struct {
    fiber: LPVOID,              // Windows Fiber handle
    scheduler_fiber: LPVOID,    // scheduler fiber to yield back to
    state: State,
    id: u64,

    pub const State = enum {
        runnable,
        running,
        blocked,
        done,
    };
};

/// The global scheduler — shared across all worker threads
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    global_queue: std.ArrayList(*Goroutine),  // runnable goroutines
    next_id: u64,
    worker_count: usize,
    workers: []WorkerThread,
    all_goroutines: std.ArrayList(*Goroutine), // track all for cleanup

    pub fn init(allocator: std.mem.Allocator, worker_count: usize) !*Scheduler {
        const sched = try allocator.create(Scheduler);
        sched.* = .{
            .allocator = allocator,
            .mutex = .{},
            .global_queue = std.ArrayList(*Goroutine).init(allocator),
            .next_id = 0,
            .worker_count = worker_count,
            .workers = &.{},
            .all_goroutines = std.ArrayList(*Goroutine).init(allocator),
        };
        return sched;
    }

    pub fn deinit(self: *Scheduler) void {
        for (self.all_goroutines.items) |g| {
            if (g.state != .done) {
                DeleteFiber(g.fiber);
            }
            self.allocator.destroy(g);
        }
        self.all_goroutines.deinit();
        self.global_queue.deinit();
        if (self.workers.len > 0) self.allocator.free(self.workers);
        self.allocator.destroy(self);
    }

    /// Spawn a new goroutine with user data
    pub fn spawn(self: *Scheduler, comptime func: *const fn (*Goroutine, ?*anyopaque) void, user_data: ?*anyopaque) !*Goroutine {
        const g = try self.allocator.create(Goroutine);
        g.* = .{
            .fiber = undefined,
            .scheduler_fiber = undefined,
            .state = .runnable,
            .id = blk: {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.next_id += 1;
                break :blk self.next_id - 1;
            },
        };

        // Create the fiber with a wrapper entry point
        const ctx = try self.allocator.create(GoroutineLaunchCtx);
        ctx.* = .{ .sched = self, .goroutine = g, .func = func, .user_data = user_data };
        const fiber = CreateFiber(0, goroutineEntry, @ptrCast(@alignCast(ctx)));
        if (fiber == null) return error.FiberCreationFailed;
        g.fiber = fiber.?;

        // Track and enqueue
        self.mutex.lock();
        try self.all_goroutines.append(g);
        try self.global_queue.append(g);
        self.mutex.unlock();

        return g;
    }

    /// Enqueue a goroutine (make it runnable again)
    pub fn enqueue(self: *Scheduler, g: *Goroutine) void {
        g.state = .runnable;
        self.mutex.lock();
        self.global_queue.append(g) catch {};
        self.mutex.unlock();
    }

    /// Dequeue a runnable goroutine (returns null if queue empty)
    pub fn dequeue(self: *Scheduler) ?*Goroutine {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.global_queue.items.len == 0) return null;
        return self.global_queue.orderedRemove(0);
    }

    /// Check if all goroutines are done
    pub fn allDone(self: *Scheduler) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.all_goroutines.items) |g| {
            if (g.state != .done) return false;
        }
        return true;
    }

    /// Block current goroutine (used by chan when full/empty)
    pub fn blockCurrent(_: *Scheduler, g: *Goroutine) void {
        g.state = .blocked;
        // Yield back to scheduler
        SwitchToFiber(g.scheduler_fiber);
    }

    /// Unblock a goroutine (used by chan when data available)
    pub fn unblock(self: *Scheduler, g: *Goroutine) void {
        self.enqueue(g);
    }
};

/// Context passed to goroutine entry wrapper
const GoroutineLaunchCtx = struct {
    sched: *Scheduler,
    goroutine: *Goroutine,
    func: *const fn (*Goroutine, ?*anyopaque) void,
    user_data: ?*anyopaque,
};

/// Windows Fiber entry point wrapper
fn goroutineEntry(param: ?LPVOID) callconv(WINAPI) void {
    const ctx: *GoroutineLaunchCtx = @ptrCast(@alignCast(param.?));
    const sched = ctx.sched;
    const g = ctx.goroutine;
    const func = ctx.func;
    const user_data = ctx.user_data;
    sched.allocator.destroy(ctx);

    g.state = .running;
    func(g, user_data);

    g.state = .done;
    // Yield back to scheduler — goroutine is finished
    SwitchToFiber(g.scheduler_fiber);
}

/// Per-worker thread state
const WorkerThread = struct {
    sched: *Scheduler,
    thread: std.Thread,
    id: usize,
    scheduler_fiber: LPVOID,
    current_goroutine: ?*Goroutine,
};

/// Thread-local: current goroutine and scheduler fiber for the running worker
pub threadlocal var tls_current_goroutine: ?*Goroutine = null;
pub threadlocal var tls_scheduler_fiber: ?LPVOID = null;
pub threadlocal var tls_scheduler: ?*Scheduler = null;

/// Start the scheduler: launch worker threads and wait for completion
pub fn run(sched: *Scheduler) !void {
    const num_workers = sched.worker_count;
    sched.workers = try sched.allocator.alloc(WorkerThread, num_workers);

    for (sched.workers, 0..) |*worker, i| {
        worker.* = .{
            .sched = sched,
            .thread = undefined,
            .id = i,
            .scheduler_fiber = undefined,
            .current_goroutine = null,
        };
        worker.thread = try std.Thread.spawn(.{}, workerMain, .{worker});
    }

    // Wait for all workers to finish
    for (sched.workers) |*worker| {
        worker.thread.join();
    }
}

fn workerMain(worker: *WorkerThread) void {
    const sched = worker.sched;

    // Convert this OS thread to a fiber (required for fiber scheduling)
    const scheduler_fiber = ConvertThreadToFiber(null) orelse {
        std.debug.print("Worker {}: ConvertThreadToFiber failed\n", .{worker.id});
        return;
    };
    worker.scheduler_fiber = scheduler_fiber;
    tls_scheduler_fiber = scheduler_fiber;
    tls_scheduler = sched;

    // Worker loop: dequeue goroutines and execute them
    while (!sched.allDone()) {
        const g = sched.dequeue() orelse {
            // No runnable goroutines — brief sleep then retry
            std.time.sleep(1 * std.time.ns_per_ms);
            continue;
        };

        // Set up TLS for this worker
        tls_current_goroutine = g;
        g.scheduler_fiber = scheduler_fiber;
        worker.current_goroutine = g;
        g.state = .running;

        // Switch to the goroutine fiber
        SwitchToFiber(g.fiber);

        // Goroutine yielded back to us (blocked or done)
        tls_current_goroutine = null;
        worker.current_goroutine = null;
    }

    // Convert back to normal thread
    _ = ConvertFiberToThread();
}

/// Yield the current goroutine (e.g., when chan is blocked)
pub fn yield() void {
    const g = tls_current_goroutine orelse return;
    const sched = tls_scheduler orelse return;
    sched.blockCurrent(g);
}
