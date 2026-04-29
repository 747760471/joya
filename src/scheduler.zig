//! Joya M:N Goroutine Scheduler (Cross-platform)
//!
//! Architecture:
//! - M OS worker threads (M = CPU count)
//! - N user-space goroutines (Fibers)
//! - Global run queue + per-worker local queue
//! - Channel blocking yields the current goroutine, unblocking re-enqueues it
//!
//! Platform support:
//!   Windows → Win32 Fiber API
//!   Linux   → ucontext_t
//!   macOS   → ucontext_t
//!   Other   → fallback (error at scheduler init, OS thread mode used instead)
//!
//! Flow:
//!   go {} → create Fiber → enqueue to global queue
//!   Worker thread: convert to fiber → loop { dequeue → switch_to(fiber) → fiber yields back → repeat }
//!   Chan send/recv full/empty → yield to scheduler → scheduler picks next
//!   Chan signal → enqueue waiting goroutine

const std = @import("std");
const fiber = @import("fiber.zig");

/// A single goroutine (user-space coroutine)
pub const Goroutine = struct {
    fiber_handle: fiber.FiberHandle,  // cross-platform fiber handle
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
                fiber.deleteFiber(g.fiber_handle);
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
            .fiber_handle = undefined,
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
        const fiber_handle = fiber.createFiber(0, goroutineEntry, @ptrCast(@alignCast(ctx))) catch {
            self.allocator.destroy(ctx);
            self.allocator.destroy(g);
            return error.FiberCreationFailed;
        };
        g.fiber_handle = fiber_handle;

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
        fiber.switchToFiber(fiber.getMasterFiber());
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

/// Cross-platform fiber entry point wrapper
fn goroutineEntry(param: ?*anyopaque) callconv(.C) void {
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
    fiber.switchToFiber(fiber.getMasterFiber());
}

/// Per-worker thread state
const WorkerThread = struct {
    sched: *Scheduler,
    thread: std.Thread,
    id: usize,
};

/// Thread-local: current goroutine and scheduler for the running worker
pub threadlocal var tls_current_goroutine: ?*Goroutine = null;
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
    const master_fiber = fiber.convertThreadToFiber() catch {
        std.debug.print("Worker {}: convertThreadToFiber failed\n", .{worker.id});
        return;
    };
    _ = master_fiber;
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
        g.state = .running;

        // Switch to the goroutine fiber
        fiber.switchToFiber(g.fiber_handle);

        // Goroutine yielded back to us (blocked or done)
        tls_current_goroutine = null;
    }

    // Convert back to normal thread
    fiber.convertFiberToThread();
}

/// Yield the current goroutine (e.g., when chan is blocked)
pub fn yield() void {
    const g = tls_current_goroutine orelse return;
    const sched = tls_scheduler orelse return;
    sched.blockCurrent(g);
}
