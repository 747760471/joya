const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const scheduler = @import("scheduler.zig");

pub const Value = union(enum) {
    int: i64,
    string: []const u8,
    bool: bool,
    float: f64,
    chan: *Chan,
    array: *JoyaArray,
    map: *JoyaMap,
    object: *JoyaObject,
    closure: *Closure,
    ref_cell: *RefCell,
    null_val,
    void,
};

pub const JoyaObject = struct {
    class_name: []const u8,
    fields: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, class_name: []const u8) !*JoyaObject {
        const obj = try allocator.create(JoyaObject);
        obj.* = .{
            .class_name = class_name,
            .fields = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        return obj;
    }

    pub fn deinit(self: *JoyaObject) void {
        self.fields.deinit();
        self.allocator.destroy(self);
    }
};

/// Runtime closure: captures an environment snapshot + AST params/body
pub const Closure = struct {
    params: []const ast.Param,
    body: *ast.Statement,
    captured_env: Environment,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, params: []const ast.Param, body: *ast.Statement, captured_env: Environment) !*Closure {
        const cl = try allocator.create(Closure);
        cl.* = .{
            .params = params,
            .body = body,
            .captured_env = captured_env,
            .allocator = allocator,
        };
        return cl;
    }

    pub fn deinit(self: *Closure) void {
        self.captured_env.deinit();
        self.allocator.destroy(self);
    }
};

/// Reference cell for closure reference capture: shared mutable box holding a Value
pub const RefCell = struct {
    value: Value,
};

pub const JoyaArray = struct {
    elem_type: ast.Type,
    items: std.ArrayList(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, elem_type: ast.Type, size: usize, default: Value) !*JoyaArray {
        const arr = try allocator.create(JoyaArray);
        var items = std.ArrayList(Value).init(allocator);
        errdefer {
            items.deinit();
            allocator.destroy(arr);
        }
        var i: usize = 0;
        while (i < size) : (i += 1) {
            try items.append(default);
        }
        arr.* = .{
            .elem_type = elem_type,
            .items = items,
            .allocator = allocator,
        };
        return arr;
    }

    pub fn deinit(self: *JoyaArray) void {
        self.items.deinit();
        self.allocator.destroy(self);
    }

    pub fn defaultForType(typ: ast.Type) Value {
        return switch (typ) {
            .int => Value{ .int = 0 },
            .float => Value{ .float = 0.0 },
            .string => Value{ .string = "" },
            .bool => Value{ .bool = false },
            .fn_ref => Value{ .null_val = {} },
            else => Value.void,
        };
    }
};

pub const JoyaMap = struct {
    key_type: ast.Type,
    value_type: ast.Type,
    entries: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, key_type: ast.Type, value_type: ast.Type) !*JoyaMap {
        const m = try allocator.create(JoyaMap);
        m.* = .{
            .key_type = key_type,
            .value_type = value_type,
            .entries = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        return m;
    }

    pub fn deinit(self: *JoyaMap) void {
        self.entries.deinit();
        self.allocator.destroy(self);
    }
};

pub const Chan = struct {
    elem_type: ast.Type,
    capacity: usize,
    queue: std.ArrayList(Value),
    mutex: std.Thread.Mutex,
    send_waiters: std.ArrayList(*scheduler.Goroutine),
    recv_waiters: std.ArrayList(*scheduler.Goroutine),
    closed: bool = false,
    allocator: std.mem.Allocator,
    use_scheduler: bool,

    pub fn init(allocator: std.mem.Allocator, elem_type: ast.Type, capacity: usize) !*Chan {
        const ch = try allocator.create(Chan);
        ch.* = .{
            .elem_type = elem_type,
            .capacity = capacity,
            .queue = std.ArrayList(Value).init(allocator),
            .mutex = .{},
            .send_waiters = std.ArrayList(*scheduler.Goroutine).init(allocator),
            .recv_waiters = std.ArrayList(*scheduler.Goroutine).init(allocator),
            .allocator = allocator,
            .use_scheduler = false,
        };
        return ch;
    }

    pub fn deinit(self: *Chan) void {
        self.send_waiters.deinit();
        self.recv_waiters.deinit();
        self.queue.deinit();
        self.allocator.destroy(self);
    }

    pub fn send(self: *Chan, val: Value) !void {
        self.mutex.lock();

        while (self.queue.items.len >= self.capacity and !self.closed) {
            if (self.use_scheduler and scheduler.tls_current_goroutine != null) {
                // Yield: save current goroutine as waiter and switch to scheduler
                const g = scheduler.tls_current_goroutine.?;
                self.send_waiters.append(g) catch {};
                self.mutex.unlock();
                scheduler.yield();
                self.mutex.lock();
            } else {
                // Fallback: use condvar (non-scheduler mode or main goroutine)
                // We need a condition variable for non-scheduler mode
                self.mutex.unlock();
                std.time.sleep(1 * std.time.ns_per_us);
                self.mutex.lock();
            }
        }

        if (self.closed) {
            self.mutex.unlock();
            return error.ChannelClosed;
        }

        try self.queue.append(val);

        // Wake up a receiver if any
        if (self.recv_waiters.items.len > 0) {
            const waiter = self.recv_waiters.orderedRemove(0);
            const sched = scheduler.tls_scheduler orelse {
                self.mutex.unlock();
                return;
            };
            sched.unblock(waiter);
        }

        self.mutex.unlock();
    }

    pub fn receive(self: *Chan) !?Value {
        self.mutex.lock();

        while (self.queue.items.len == 0 and !self.closed) {
            if (self.use_scheduler and scheduler.tls_current_goroutine != null) {
                const g = scheduler.tls_current_goroutine.?;
                self.recv_waiters.append(g) catch {};
                self.mutex.unlock();
                scheduler.yield();
                self.mutex.lock();
            } else {
                self.mutex.unlock();
                std.time.sleep(1 * std.time.ns_per_us);
                self.mutex.lock();
            }
        }

        if (self.closed and self.queue.items.len == 0) {
            self.mutex.unlock();
            return null;
        }

        const val = self.queue.orderedRemove(0);

        // Wake up a sender if any
        if (self.send_waiters.items.len > 0) {
            const waiter = self.send_waiters.orderedRemove(0);
            const sched = scheduler.tls_scheduler orelse {
                self.mutex.unlock();
                return val;
            };
            sched.unblock(waiter);
        }

        self.mutex.unlock();
        return val;
    }

    pub fn close(self: *Chan) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
        // Wake up all waiters
        if (self.use_scheduler) {
            const sched = scheduler.tls_scheduler;
            if (sched) |s| {
                for (self.send_waiters.items) |waiter| {
                    s.unblock(waiter);
                }
                for (self.recv_waiters.items) |waiter| {
                    s.unblock(waiter);
                }
            }
        }
        self.send_waiters.clearRetainingCapacity();
        self.recv_waiters.clearRetainingCapacity();
    }
};

/// Thread-safe allocator wrapper: serializes all alloc/free calls through a mutex
const ThreadSafeAlloc = struct {
    child: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    const vtable = std.mem.Allocator.VTable{
        .alloc = tsAlloc,
        .resize = tsResize,
        .free = tsFree,
    };

    pub fn init(child: std.mem.Allocator) ThreadSafeAlloc {
        return .{ .child = child, .mutex = .{} };
    }

    pub fn allocator(self: *ThreadSafeAlloc) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn tsAlloc(ctx: *anyopaque, len: usize, log2_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *ThreadSafeAlloc = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.child.rawAlloc(len, log2_align, ret_addr);
    }

    fn tsResize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *ThreadSafeAlloc = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.child.rawResize(buf, log2_buf_align, new_len, ret_addr);
    }

    fn tsFree(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
        const self: *ThreadSafeAlloc = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();
        self.child.rawFree(buf, log2_buf_align, ret_addr);
    }
};

const Environment = struct {
    allocator: std.mem.Allocator,
    vars: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Environment {
        return .{
            .allocator = allocator,
            .vars = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Environment) void {
        self.vars.deinit();
    }

    /// Set a variable: if the existing binding is a ref_cell, update the cell's value (reference write-back)
    pub fn set(self: *Environment, name: []const u8, val: Value) !void {
        // Check if the current binding is a ref_cell — write through the reference
        if (self.vars.get(name)) |existing| {
            if (existing == .ref_cell) {
                existing.ref_cell.value = val;
                return;
            }
        }
        try self.vars.put(name, val);
    }

    /// Get a variable: automatically dereference ref_cell to get the actual value
    pub fn get(self: *Environment, name: []const u8) ?Value {
        const raw = self.vars.get(name) orelse return null;
        if (raw == .ref_cell) return raw.ref_cell.value;
        return raw;
    }

    /// Define a variable as a reference cell (for closure capture)
    pub fn defineRef(self: *Environment, name: []const u8, cell: *RefCell) !void {
        try self.vars.put(name, Value{ .ref_cell = cell });
    }

    /// Get the raw Value (may be ref_cell) — used internally for reference checking
    pub fn getRaw(self: *Environment, name: []const u8) ?Value {
        return self.vars.get(name);
    }

    pub fn clone(self: *Environment) !Environment {
        var copy = Environment.init(self.allocator);
        var iter = self.vars.iterator();
        while (iter.next()) |entry| {
            try copy.vars.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        return copy;
    }
};

/// Runtime context tracking channels and heap strings for cleanup (thread-safe)
const RuntimeCtx = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    channels: std.ArrayList(*Chan),
    arrays: std.ArrayList(*JoyaArray),
    maps: std.ArrayList(*JoyaMap),
    objects: std.ArrayList(*JoyaObject),
    closures: std.ArrayList(*Closure),
    ref_cells: std.ArrayList(*RefCell),
    heap_strings: std.ArrayList([]const u8),
    program: ?*const ast.Program,
    return_value: ?Value,
    thrown_value: ?Value,

    pub fn init(allocator: std.mem.Allocator) RuntimeCtx {
        return .{
            .allocator = allocator,
            .mutex = .{},
            .channels = std.ArrayList(*Chan).init(allocator),
            .arrays = std.ArrayList(*JoyaArray).init(allocator),
            .maps = std.ArrayList(*JoyaMap).init(allocator),
            .objects = std.ArrayList(*JoyaObject).init(allocator),
            .closures = std.ArrayList(*Closure).init(allocator),
            .ref_cells = std.ArrayList(*RefCell).init(allocator),
            .heap_strings = std.ArrayList([]const u8).init(allocator),
            .program = null,
            .return_value = null,
            .thrown_value = null,
        };
    }

    pub fn deinit(self: *RuntimeCtx) void {
        for (self.channels.items) |ch| ch.deinit();
        self.channels.deinit();
        for (self.arrays.items) |arr| arr.deinit();
        self.arrays.deinit();
        for (self.maps.items) |m| m.deinit();
        self.maps.deinit();
        for (self.objects.items) |obj| obj.deinit();
        self.objects.deinit();
        for (self.closures.items) |cl| cl.deinit();
        self.closures.deinit();
        for (self.ref_cells.items) |rc| self.allocator.destroy(rc);
        self.ref_cells.deinit();
        for (self.heap_strings.items) |s| self.allocator.free(s);
        self.heap_strings.deinit();
    }

    pub fn trackChan(self: *RuntimeCtx, ch: *Chan) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.channels.append(ch);
    }

    pub fn trackArray(self: *RuntimeCtx, arr: *JoyaArray) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.arrays.append(arr);
    }

    pub fn trackMap(self: *RuntimeCtx, m: *JoyaMap) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.maps.append(m);
    }

    pub fn trackObject(self: *RuntimeCtx, obj: *JoyaObject) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.objects.append(obj);
    }

    pub fn trackClosure(self: *RuntimeCtx, cl: *Closure) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.closures.append(cl);
    }

    pub fn createRefCell(self: *RuntimeCtx, val: Value) !*RefCell {
        self.mutex.lock();
        defer self.mutex.unlock();
        const cell = try self.allocator.create(RefCell);
        cell.* = .{ .value = val };
        try self.ref_cells.append(cell);
        return cell;
    }

    pub fn trackString(self: *RuntimeCtx, s: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.heap_strings.append(s);
    }
};

const ReturnSignal = struct {
    value: Value,
};

fn eval_expression(env: *Environment, ctx: *RuntimeCtx, expr: ast.Expression) !Value {
    switch (expr) {
        .int_literal => |v| return Value{ .int = v },
        .float_literal => |v| return Value{ .float = v },
        .string_literal => |v| return Value{ .string = v },
        .bool_literal => |v| return Value{ .bool = v },
        .null_literal => return Value{ .null_val = {} },
        .this_ref => return env.get("this") orelse return error.NoThisContext,
        .identifier => |name| return env.get(name) orelse return error.UndefinedVariable,
        .binary_op => |op| {
            const left = try eval_expression(env, ctx, op.left.*);
            switch (op.op) {
                .amp_amp => {
                    if (left == .bool and !left.bool) return Value{ .bool = false };
                    const right = try eval_expression(env, ctx, op.right.*);
                    if (right == .bool) return Value{ .bool = right.bool };
                    return error.InvalidOperation;
                },
                .pipe_pipe => {
                    if (left == .bool and left.bool) return Value{ .bool = true };
                    const right = try eval_expression(env, ctx, op.right.*);
                    if (right == .bool) return Value{ .bool = right.bool };
                    return error.InvalidOperation;
                },
                else => {},
            }
            const right = try eval_expression(env, ctx, op.right.*);
            switch (op.op) {
                .plus => {
                    if (left == .int and right == .int) {
                        return Value{ .int = left.int + right.int };
                    }
                    if (left == .float and right == .float) {
                        return Value{ .float = left.float + right.float };
                    }
                    if (left == .float and right == .int) {
                        return Value{ .float = left.float + @as(f64, @floatFromInt(right.int)) };
                    }
                    if (left == .int and right == .float) {
                        return Value{ .float = @as(f64, @floatFromInt(left.int)) + right.float };
                    }
                    if (left == .string or right == .string) {
                        var buf = std.ArrayList(u8).init(env.allocator);
                        if (left == .string) try buf.appendSlice(left.string);
                        if (left == .int) try buf.writer().print("{}", .{left.int});
                        if (left == .float) try buf.writer().print("{}", .{left.float});
                        if (left == .bool) try buf.writer().print("{}", .{left.bool});
                        if (left == .null_val) try buf.appendSlice("null");
                        if (right == .string) try buf.appendSlice(right.string);
                        if (right == .int) try buf.writer().print("{}", .{right.int});
                        if (right == .float) try buf.writer().print("{}", .{right.float});
                        if (right == .bool) try buf.writer().print("{}", .{right.bool});
                        if (right == .null_val) try buf.appendSlice("null");
                        const s = try buf.toOwnedSlice();
                        try ctx.trackString(s);
                        return Value{ .string = s };
                    }
                    return error.InvalidOperation;
                },
                .minus => {
                    if (left == .int and right == .int) return Value{ .int = left.int - right.int };
                    if (left == .float and right == .float) return Value{ .float = left.float - right.float };
                    if (left == .float and right == .int) return Value{ .float = left.float - @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .float = @as(f64, @floatFromInt(left.int)) - right.float };
                    return error.InvalidOperation;
                },
                .star => {
                    if (left == .int and right == .int) return Value{ .int = left.int * right.int };
                    if (left == .float and right == .float) return Value{ .float = left.float * right.float };
                    if (left == .float and right == .int) return Value{ .float = left.float * @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .float = @as(f64, @floatFromInt(left.int)) * right.float };
                    return error.InvalidOperation;
                },
                .slash => {
                    if (left == .int and right == .int) return Value{ .int = @divTrunc(left.int, right.int) };
                    if (left == .float and right == .float) return Value{ .float = left.float / right.float };
                    if (left == .float and right == .int) return Value{ .float = left.float / @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .float = @as(f64, @floatFromInt(left.int)) / right.float };
                    return error.InvalidOperation;
                },
                .percent => return Value{ .int = @rem(left.int, right.int) },
                .lt => {
                    if (left == .int and right == .int) return Value{ .bool = left.int < right.int };
                    if (left == .float and right == .float) return Value{ .bool = left.float < right.float };
                    if (left == .float and right == .int) return Value{ .bool = left.float < @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .bool = @as(f64, @floatFromInt(left.int)) < right.float };
                    if (left == .string and right == .string) return Value{ .bool = std.mem.lessThan(u8, left.string, right.string) };
                    return error.InvalidOperation;
                },
                .gt => {
                    if (left == .int and right == .int) return Value{ .bool = left.int > right.int };
                    if (left == .float and right == .float) return Value{ .bool = left.float > right.float };
                    if (left == .float and right == .int) return Value{ .bool = left.float > @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .bool = @as(f64, @floatFromInt(left.int)) > right.float };
                    if (left == .string and right == .string) return Value{ .bool = std.mem.lessThan(u8, right.string, left.string) };
                    return error.InvalidOperation;
                },
                .lt_eq => {
                    if (left == .int and right == .int) return Value{ .bool = left.int <= right.int };
                    if (left == .float and right == .float) return Value{ .bool = left.float <= right.float };
                    if (left == .float and right == .int) return Value{ .bool = left.float <= @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .bool = @as(f64, @floatFromInt(left.int)) <= right.float };
                    return error.InvalidOperation;
                },
                .gt_eq => {
                    if (left == .int and right == .int) return Value{ .bool = left.int >= right.int };
                    if (left == .float and right == .float) return Value{ .bool = left.float >= right.float };
                    if (left == .float and right == .int) return Value{ .bool = left.float >= @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .bool = @as(f64, @floatFromInt(left.int)) >= right.float };
                    return error.InvalidOperation;
                },
                .eq_eq => {
                    if (left == .int and right == .int) return Value{ .bool = left.int == right.int };
                    if (left == .float and right == .float) return Value{ .bool = left.float == right.float };
                    if (left == .float and right == .int) return Value{ .bool = left.float == @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .bool = @as(f64, @floatFromInt(left.int)) == right.float };
                    if (left == .string and right == .string) return Value{ .bool = std.mem.eql(u8, left.string, right.string) };
                    if (left == .bool and right == .bool) return Value{ .bool = left.bool == right.bool };
                    if (left == .null_val and right == .null_val) return Value{ .bool = true };
                    if (left == .null_val or right == .null_val) return Value{ .bool = false };
                    return Value{ .bool = false };
                },
                .not_eq => {
                    if (left == .int and right == .int) return Value{ .bool = left.int != right.int };
                    if (left == .float and right == .float) return Value{ .bool = left.float != right.float };
                    if (left == .float and right == .int) return Value{ .bool = left.float != @as(f64, @floatFromInt(right.int)) };
                    if (left == .int and right == .float) return Value{ .bool = @as(f64, @floatFromInt(left.int)) != right.float };
                    if (left == .string and right == .string) return Value{ .bool = !std.mem.eql(u8, left.string, right.string) };
                    if (left == .bool and right == .bool) return Value{ .bool = left.bool != right.bool };
                    if (left == .null_val and right == .null_val) return Value{ .bool = false };
                    if (left == .null_val or right == .null_val) return Value{ .bool = true };
                    return Value{ .bool = true };
                },
                else => return error.UnsupportedOperator,
            }
        },
        .new_chan => |nc| {
            const ch = try Chan.init(env.allocator, nc.elem_type, @intCast(nc.capacity));
            ch.use_scheduler = scheduler.tls_scheduler != null;
            try ctx.trackChan(ch);
            return Value{ .chan = ch };
        },
        .new_map => |nm| {
            const m = try JoyaMap.init(env.allocator, nm.key_type, nm.value_type);
            try ctx.trackMap(m);
            return Value{ .map = m };
        },
        .new_array => |na| {
            const size_val = try eval_expression(env, ctx, na.size.*);
            const size: usize = @intCast(size_val.int);
            const default = JoyaArray.defaultForType(na.elem_type);
            const arr = try JoyaArray.init(env.allocator, na.elem_type, size, default);
            try ctx.trackArray(arr);
            return Value{ .array = arr };
        },
        .array_literal => |al| {
            const arr = try JoyaArray.init(env.allocator, al.elem_type, 0, .void);
            for (al.elements) |elem_expr| {
                const val = try eval_expression(env, ctx, elem_expr);
                try arr.items.append(val);
            }
            try ctx.trackArray(arr);
            return Value{ .array = arr };
        },
        .array_index => |ai| {
            const collection = try eval_expression(env, ctx, ai.array.*);
            const idx_val = try eval_expression(env, ctx, ai.index.*);
            const idx: usize = @intCast(idx_val.int);
            if (collection == .array) {
                if (idx >= collection.array.items.items.len) return error.ArrayIndexOutOfBounds;
                return collection.array.items.items[idx];
            }
            if (collection == .string) {
                if (idx >= collection.string.len) return error.ArrayIndexOutOfBounds;
                // Return single character as a string
                const ch = collection.string[idx..][0..1];
                return Value{ .string = ch };
            }
            return error.NotIndexable;
        },
        .new_object => |no| {
            // Find the class
            if (ctx.program) |prog| {
                for (prog.classes) |*class| {
                    if (std.mem.eql(u8, class.name, no.class_name)) {
                        // Create object and initialize fields
                        const obj = try JoyaObject.init(env.allocator, no.class_name);
                        for (class.fields) |field| {
                            try obj.fields.put(field.name, JoyaArray.defaultForType(field.typ));
                        }
                        try ctx.trackObject(obj);
                        // Find and call constructor if exists
                        for (class.methods) |*method| {
                            if (std.mem.eql(u8, method.name, no.class_name)) {
                                // Evaluate arguments
                                var arg_vals = std.ArrayList(Value).init(env.allocator);
                                defer arg_vals.deinit();
                                for (no.args) |arg_expr| {
                                    try arg_vals.append(try eval_expression(env, ctx, arg_expr));
                                }
                                // Create constructor environment
                                var ctor_env = Environment.init(env.allocator);
                                try ctor_env.set("this", Value{ .object = obj });
                                for (method.params, 0..) |param, i| {
                                    if (i < arg_vals.items.len) {
                                        try ctor_env.set(param.name, arg_vals.items[i]);
                                    }
                                }
                                ctx.return_value = null;
                                var local_threads = std.ArrayList(std.Thread).init(env.allocator);
                                const result = execute_statement(&ctor_env, ctx, method.body, &local_threads);
                                for (local_threads.items) |t| t.join();
                                ctor_env.deinit();
                                _ = result catch |err| switch (err) {
                                    error.ReturnSignal => {},
                                    else => return err,
                                };
                                break;
                            }
                        }
                        return Value{ .object = obj };
                    }
                }
            }
            return error.UndefinedClass;
        },
        .method_call => |mc| {
            // Direct invocation: expr(args) — method name is empty (from parsePostfix)
            if (mc.method.len == 0) {
                const obj_val = try eval_expression(env, ctx, mc.object.*);
                if (obj_val == .closure) {
                    return evalClosureCall(env, ctx, obj_val.closure, mc.args);
                }
                return error.NotCallable;
            }

            // Closure variable: if object is an identifier and resolves to a closure
            // Takes priority over static method dispatch
            if (mc.object.* == .identifier) {
                if (env.get(mc.object.*.identifier)) |var_val| {
                    if (var_val == .closure) {
                        return evalClosureCall(env, ctx, var_val.closure, mc.args);
                    }
                }
            }

            // Check for static method call: ClassName.method(args)
            // If the object is an identifier that matches a class name, call statically
            if (mc.object.* == .identifier) {
                const class_name = mc.object.*.identifier;
                if (ctx.program) |prog| {
                    for (prog.classes) |*class| {
                        if (std.mem.eql(u8, class.name, class_name)) {
                            return evalStaticMethod(env, ctx, class, mc.method, mc.args);
                        }
                    }
                }
            }

            const obj_val = try eval_expression(env, ctx, mc.object.*);

            // String built-in methods
            if (obj_val == .string) {
                return evalStringMethod(env, ctx, obj_val.string, mc.method, mc.args);
            }

            // Array built-in methods
            if (obj_val == .array) {
                return evalArrayMethod(env, ctx, obj_val.array, mc.method, mc.args);
            }

            // Map built-in methods
            if (obj_val == .map) {
                return evalMapMethod(env, ctx, obj_val.map, mc.method, mc.args);
            }

            if (obj_val != .object) return error.NotAnObject;
            const obj = obj_val.object;
            // Find method in the object's class
            if (ctx.program) |prog| {
                for (prog.classes) |*class| {
                    if (std.mem.eql(u8, class.name, obj.class_name)) {
                        for (class.methods) |*method| {
                            if (std.mem.eql(u8, method.name, mc.method)) {
                                // Evaluate arguments
                                var arg_vals = std.ArrayList(Value).init(env.allocator);
                                defer arg_vals.deinit();
                                for (mc.args) |arg_expr| {
                                    try arg_vals.append(try eval_expression(env, ctx, arg_expr));
                                }
                                // Create method environment with this bound
                                var method_env = Environment.init(env.allocator);
                                try method_env.set("this", Value{ .object = obj });
                                for (method.params, 0..) |param, i| {
                                    if (i < arg_vals.items.len) {
                                        try method_env.set(param.name, arg_vals.items[i]);
                                    }
                                }
                                ctx.return_value = null;
                                var local_threads = std.ArrayList(std.Thread).init(env.allocator);
                                const result = execute_statement(&method_env, ctx, method.body, &local_threads);
                                for (local_threads.items) |t| t.join();
                                method_env.deinit();
                                _ = result catch |err| switch (err) {
                                    error.ReturnSignal => {},
                                    else => return err,
                                };
                                const return_val = ctx.return_value orelse Value.void;
                                ctx.return_value = null;
                                return return_val;
                            }
                        }
                    }
                }
            }
            return error.UndefinedMethod;
        },
        .unary_not => |operand| {
            const val = try eval_expression(env, ctx, operand.*);
            if (val == .bool) return Value{ .bool = !val.bool };
            return error.InvalidOperation;
        },
        .lambda => |lam| {
            // Reference capture: create RefCells shared between outer and closure environments
            var closure_env = Environment.init(env.allocator);
            var iter = env.vars.iterator();
            while (iter.next()) |entry| {
                const name = entry.key_ptr.*;
                const raw = entry.value_ptr.*;
                if (raw == .ref_cell) {
                    // Already a ref_cell — share it
                    try closure_env.defineRef(name, raw.ref_cell);
                } else {
                    // Create a new RefCell and rebind in both environments
                    const cell = try ctx.createRefCell(raw);
                    try env.defineRef(name, cell);
                    try closure_env.defineRef(name, cell);
                }
            }
            const cl = try Closure.init(env.allocator, lam.params, lam.body, closure_env);
            try ctx.trackClosure(cl);
            return Value{ .closure = cl };
        },
        .field_access => |fa| {
            // .length on arrays and strings
            if (std.mem.eql(u8, fa.field, "length")) {
                const obj = try eval_expression(env, ctx, fa.object.*);
                if (obj == .array) return Value{ .int = @intCast(obj.array.items.items.len) };
                if (obj == .string) return Value{ .int = @intCast(obj.string.len) };
            }
            // Object field access
            const obj = try eval_expression(env, ctx, fa.object.*);
            if (obj == .object) {
                return obj.object.fields.get(fa.field) orelse Value{ .null_val = {} };
            }
            return obj;
        },
        .call => |c| {
            // Built-in: send
            if (std.mem.eql(u8, c.name, "send")) {
                const ch_val = try eval_expression(env, ctx, c.args[0]);
                const val = try eval_expression(env, ctx, c.args[1]);
                try ch_val.chan.send(val);
                return .void;
            }
            // Built-in: receive
            if (std.mem.eql(u8, c.name, "receive")) {
                const ch_val = try eval_expression(env, ctx, c.args[0]);
                const val = try ch_val.chan.receive();
                return val orelse Value{ .null_val = {} };
            }
            // Built-in: close
            if (std.mem.eql(u8, c.name, "close")) {
                const ch_val = try eval_expression(env, ctx, c.args[0]);
                ch_val.chan.close();
                return .void;
            }
            // Built-in: print
            if (std.mem.eql(u8, c.name, "print")) {
                const val = try eval_expression(env, ctx, c.args[0]);
                try printValue(val, false);
                return .void;
            }
            // Built-in: println
            if (std.mem.eql(u8, c.name, "println")) {
                const val = try eval_expression(env, ctx, c.args[0]);
                try printValue(val, true);
                return .void;
            }
            // Check if the name refers to a closure variable in the current environment
            if (env.get(c.name)) |var_val| {
                if (var_val == .closure) {
                    return evalClosureCall(env, ctx, var_val.closure, c.args);
                }
            }
            // User-defined method call
            if (ctx.program) |prog| {
                // Evaluate arguments
                var arg_vals = std.ArrayList(Value).init(env.allocator);
                defer arg_vals.deinit();
                for (c.args) |arg_expr| {
                    try arg_vals.append(try eval_expression(env, ctx, arg_expr));
                }
                // Search for method across all classes
                for (prog.classes) |*class| {
                    for (class.methods) |*method| {
                        if (std.mem.eql(u8, method.name, c.name)) {
                            // Create new environment with parameters bound
                            var method_env = Environment.init(env.allocator);
                            for (method.params, 0..) |param, i| {
                                if (i < arg_vals.items.len) {
                                    try method_env.set(param.name, arg_vals.items[i]);
                                }
                            }
                            // Execute method body
                            ctx.return_value = null;
                            var local_threads = std.ArrayList(std.Thread).init(env.allocator);
                            const result = execute_statement(&method_env, ctx, method.body, &local_threads);
                            for (local_threads.items) |t| t.join();
                            method_env.deinit();
                            // Capture return value
                            _ = result catch |err| switch (err) {
                                error.ReturnSignal => {},
                                else => return err,
                            };
                            const return_val = ctx.return_value orelse Value.void;
                            ctx.return_value = null;
                            return return_val;
                        }
                    }
                }
            }
            return error.UndefinedFunction;
        },
    }
}

// ---- Goroutine entry point for scheduler mode ----

const GoCtx = struct {
    env_copy: Environment,
    ctx_copy: *RuntimeCtx,
    body_copy: ast.Statement,
};

/// Evaluate a built-in string method
fn evalStringMethod(env: *Environment, ctx: *RuntimeCtx, s: []const u8, method: []const u8, args: []const ast.Expression) !Value {
    if (std.mem.eql(u8, method, "substring")) {
        // s.substring(start) or s.substring(start, end)
        if (args.len < 1) return error.WrongNumberOfArguments;
        const start_val = try eval_expression(env, ctx, args[0]);
        const start: usize = @intCast(start_val.int);
        if (args.len >= 2) {
            const end_val = try eval_expression(env, ctx, args[1]);
            const end: usize = @intCast(end_val.int);
            if (start > end or end > s.len) return error.StringIndexOutOfBounds;
            const result = try env.allocator.dupe(u8, s[start..end]);
            try ctx.trackString(result);
            return Value{ .string = result };
        }
        if (start > s.len) return error.StringIndexOutOfBounds;
        const result = try env.allocator.dupe(u8, s[start..]);
        try ctx.trackString(result);
        return Value{ .string = result };
    }

    if (std.mem.eql(u8, method, "indexOf")) {
        // s.indexOf(sub) → int (-1 if not found)
        if (args.len < 1) return error.WrongNumberOfArguments;
        const sub_val = try eval_expression(env, ctx, args[0]);
        if (sub_val != .string) return error.InvalidOperation;
        if (sub_val.string.len == 0) return Value{ .int = 0 };
        if (sub_val.string.len > s.len) return Value{ .int = -1 };
        for (0..(s.len - sub_val.string.len + 1)) |i| {
            if (std.mem.eql(u8, s[i..][0..sub_val.string.len], sub_val.string)) {
                return Value{ .int = @intCast(i) };
            }
        }
        return Value{ .int = -1 };
    }

    if (std.mem.eql(u8, method, "contains")) {
        // s.contains(sub) → bool
        if (args.len < 1) return error.WrongNumberOfArguments;
        const sub_val = try eval_expression(env, ctx, args[0]);
        if (sub_val != .string) return error.InvalidOperation;
        if (sub_val.string.len == 0) return Value{ .bool = true };
        if (sub_val.string.len > s.len) return Value{ .bool = false };
        for (0..(s.len - sub_val.string.len + 1)) |i| {
            if (std.mem.eql(u8, s[i..][0..sub_val.string.len], sub_val.string)) {
                return Value{ .bool = true };
            }
        }
        return Value{ .bool = false };
    }

    if (std.mem.eql(u8, method, "startsWith")) {
        if (args.len < 1) return error.WrongNumberOfArguments;
        const prefix_val = try eval_expression(env, ctx, args[0]);
        if (prefix_val != .string) return error.InvalidOperation;
        return Value{ .bool = std.mem.startsWith(u8, s, prefix_val.string) };
    }

    if (std.mem.eql(u8, method, "endsWith")) {
        if (args.len < 1) return error.WrongNumberOfArguments;
        const suffix_val = try eval_expression(env, ctx, args[0]);
        if (suffix_val != .string) return error.InvalidOperation;
        return Value{ .bool = std.mem.endsWith(u8, s, suffix_val.string) };
    }

    if (std.mem.eql(u8, method, "toUpperCase")) {
        const result = try env.allocator.dupe(u8, s);
        for (result) |*ch| {
            if (ch.* >= 'a' and ch.* <= 'z') ch.* = ch.* - 32;
        }
        try ctx.trackString(result);
        return Value{ .string = result };
    }

    if (std.mem.eql(u8, method, "toLowerCase")) {
        const result = try env.allocator.dupe(u8, s);
        for (result) |*ch| {
            if (ch.* >= 'A' and ch.* <= 'Z') ch.* = ch.* + 32;
        }
        try ctx.trackString(result);
        return Value{ .string = result };
    }

    if (std.mem.eql(u8, method, "trim")) {
        var start: usize = 0;
        while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) {
            start += 1;
        }
        var end: usize = s.len;
        while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\n' or s[end - 1] == '\r')) {
            end -= 1;
        }
        const result = try env.allocator.dupe(u8, s[start..end]);
        try ctx.trackString(result);
        return Value{ .string = result };
    }

    if (std.mem.eql(u8, method, "replace")) {
        // s.replace(old, new) → string
        if (args.len < 2) return error.WrongNumberOfArguments;
        const old_val = try eval_expression(env, ctx, args[0]);
        const new_val = try eval_expression(env, ctx, args[1]);
        if (old_val != .string or new_val != .string) return error.InvalidOperation;
        const old_str = old_val.string;
        const new_str = new_val.string;
        if (old_str.len == 0) {
            const result = try env.allocator.dupe(u8, s);
            try ctx.trackString(result);
            return Value{ .string = result };
        }
        // Count occurrences to size the result buffer
        var count: usize = 0;
        var i: usize = 0;
        while (i + old_str.len <= s.len) {
            if (std.mem.eql(u8, s[i..][0..old_str.len], old_str)) {
                count += 1;
                i += old_str.len;
            } else {
                i += 1;
            }
        }
        const new_len = s.len + count * new_str.len - count * old_str.len;
        var buf = try env.allocator.alloc(u8, new_len);
        var src: usize = 0;
        var dst: usize = 0;
        while (src + old_str.len <= s.len) {
            if (std.mem.eql(u8, s[src..][0..old_str.len], old_str)) {
                @memcpy(buf[dst..][0..new_str.len], new_str);
                dst += new_str.len;
                src += old_str.len;
            } else {
                buf[dst] = s[src];
                dst += 1;
                src += 1;
            }
        }
        while (src < s.len) : (src += 1) {
            buf[dst] = s[src];
            dst += 1;
        }
        try ctx.trackString(buf);
        return Value{ .string = buf };
    }

    if (std.mem.eql(u8, method, "split")) {
        // s.split(delim) → string[]
        if (args.len < 1) return error.WrongNumberOfArguments;
        const delim_val = try eval_expression(env, ctx, args[0]);
        if (delim_val != .string) return error.InvalidOperation;
        const delim = delim_val.string;
        const arr = try JoyaArray.init(env.allocator, .{ .string = {} }, 0, .void);
        if (delim.len == 0) {
            // Split into individual characters
            for (s) |ch| {
                const single = try env.allocator.dupe(u8, &[_]u8{ch});
                try ctx.trackString(single);
                try arr.items.append(Value{ .string = single });
            }
        } else {
            var start: usize = 0;
            while (start < s.len) {
                var found = false;
                for (0..(s.len - start + 1)) |offset| {
                    if (start + offset + delim.len <= s.len and
                        std.mem.eql(u8, s[start + offset..][0..delim.len], delim))
                    {
                        const part = try env.allocator.dupe(u8, s[start .. start + offset]);
                        try ctx.trackString(part);
                        try arr.items.append(Value{ .string = part });
                        start = start + offset + delim.len;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    const part = try env.allocator.dupe(u8, s[start..]);
                    try ctx.trackString(part);
                    try arr.items.append(Value{ .string = part });
                    break;
                }
            }
        }
        try ctx.trackArray(arr);
        return Value{ .array = arr };
    }

    return error.UndefinedStringMethod;
}

/// Evaluate a built-in array method
fn evalArrayMethod(env: *Environment, ctx: *RuntimeCtx, arr: *JoyaArray, method: []const u8, args: []const ast.Expression) !Value {
    if (std.mem.eql(u8, method, "push")) {
        // arr.push(val) — append value
        if (args.len < 1) return error.WrongNumberOfArguments;
        const val = try eval_expression(env, ctx, args[0]);
        try arr.items.append(val);
        return Value{ .int = @intCast(arr.items.items.len) };
    }

    if (std.mem.eql(u8, method, "pop")) {
        // arr.pop() → value
        if (arr.items.items.len == 0) return Value{ .null_val = {} };
        return arr.items.pop();
    }

    if (std.mem.eql(u8, method, "contains")) {
        // arr.contains(val) → bool
        if (args.len < 1) return error.WrongNumberOfArguments;
        const val = try eval_expression(env, ctx, args[0]);
        for (arr.items.items) |item| {
            if (val == .int and item == .int and val.int == item.int) return Value{ .bool = true };
            if (val == .string and item == .string and std.mem.eql(u8, val.string, item.string)) return Value{ .bool = true };
            if (val == .bool and item == .bool and val.bool == item.bool) return Value{ .bool = true };
        }
        return Value{ .bool = false };
    }

    if (std.mem.eql(u8, method, "indexOf")) {
        // arr.indexOf(val) → int (-1 if not found)
        if (args.len < 1) return error.WrongNumberOfArguments;
        const val = try eval_expression(env, ctx, args[0]);
        for (arr.items.items, 0..) |item, i| {
            if (val == .int and item == .int and val.int == item.int) return Value{ .int = @intCast(i) };
            if (val == .string and item == .string and std.mem.eql(u8, val.string, item.string)) return Value{ .int = @intCast(i) };
            if (val == .bool and item == .bool and val.bool == item.bool) return Value{ .int = @intCast(i) };
        }
        return Value{ .int = -1 };
    }

    if (std.mem.eql(u8, method, "join")) {
        // arr.join(sep) → string
        if (args.len < 1) return error.WrongNumberOfArguments;
        const sep_val = try eval_expression(env, ctx, args[0]);
        if (sep_val != .string) return error.InvalidOperation;
        var buf = std.ArrayList(u8).init(env.allocator);
        for (arr.items.items, 0..) |item, i| {
            if (i > 0) try buf.appendSlice(sep_val.string);
            switch (item) {
                .int => try buf.writer().print("{}", .{item.int}),
                .string => try buf.appendSlice(item.string),
                .bool => try buf.writer().print("{}", .{item.bool}),
                .float => try buf.writer().print("{}", .{item.float}),
                .null_val => try buf.appendSlice("null"),
                else => try buf.writer().print("?", .{}),
            }
        }
        const result = try buf.toOwnedSlice();
        try ctx.trackString(result);
        return Value{ .string = result };
    }

    if (std.mem.eql(u8, method, "removeAt")) {
        // arr.removeAt(index) → value
        if (args.len < 1) return error.WrongNumberOfArguments;
        const idx_val = try eval_expression(env, ctx, args[0]);
        const idx: usize = @intCast(idx_val.int);
        if (idx >= arr.items.items.len) return error.ArrayIndexOutOfBounds;
        return arr.items.orderedRemove(idx);
    }

    if (std.mem.eql(u8, method, "reverse")) {
        // arr.reverse() — in-place reverse
        var i: usize = 0;
        var j: usize = arr.items.items.len;
        if (j == 0) return Value.void;
        j -= 1;
        while (i < j) {
            const tmp = arr.items.items[i];
            arr.items.items[i] = arr.items.items[j];
            arr.items.items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
        return Value.void;
    }

    if (std.mem.eql(u8, method, "sort")) {
        // arr.sort() — in-place ascending sort (int only for now)
        // Simple insertion sort
        const items = arr.items.items;
        for (1..items.len) |i| {
            const key = items[i];
            var j: usize = i;
            while (j > 0) : (j -= 1) {
                const should_swap = switch (items[j - 1]) {
                    .int => key == .int and items[j - 1].int > key.int,
                    .float => key == .float and items[j - 1].float > key.float,
                    .string => key == .string and std.mem.lessThan(u8, items[j - 1].string, key.string) == false and !std.mem.eql(u8, items[j - 1].string, key.string),
                    else => false,
                };
                if (should_swap) {
                    items[j] = items[j - 1];
                } else break;
            }
            items[j] = key;
        }
        return Value.void;
    }

    if (std.mem.eql(u8, method, "map")) {
        // arr.map(fn) → new array with fn applied to each element
        if (args.len < 1) return error.WrongNumberOfArguments;
        const func_val = try eval_expression(env, ctx, args[0]);
        if (func_val != .closure) return error.ExpectedClosure;
        const result_arr = try JoyaArray.init(env.allocator, arr.elem_type, 0, .void);
        try ctx.trackArray(result_arr);
        for (arr.items.items) |item| {
            const mapped = try callClosureWithArgs(env, ctx, func_val.closure, &[_]Value{item});
            try result_arr.items.append(mapped);
        }
        return Value{ .array = result_arr };
    }

    if (std.mem.eql(u8, method, "filter")) {
        // arr.filter(fn) → new array with elements where fn returns true
        if (args.len < 1) return error.WrongNumberOfArguments;
        const func_val = try eval_expression(env, ctx, args[0]);
        if (func_val != .closure) return error.ExpectedClosure;
        const result_arr = try JoyaArray.init(env.allocator, arr.elem_type, 0, .void);
        try ctx.trackArray(result_arr);
        for (arr.items.items) |item| {
            const result = try callClosureWithArgs(env, ctx, func_val.closure, &[_]Value{item});
            if (result == .bool and result.bool) {
                try result_arr.items.append(item);
            }
        }
        return Value{ .array = result_arr };
    }

    if (std.mem.eql(u8, method, "forEach")) {
        // arr.forEach(fn) — call fn for each element (returns void)
        if (args.len < 1) return error.WrongNumberOfArguments;
        const func_val = try eval_expression(env, ctx, args[0]);
        if (func_val != .closure) return error.ExpectedClosure;
        for (arr.items.items) |item| {
            _ = try callClosureWithArgs(env, ctx, func_val.closure, &[_]Value{item});
        }
        return Value.void;
    }

    if (std.mem.eql(u8, method, "reduce")) {
        // arr.reduce(fn, initial) → accumulated value
        // fn takes (accumulator, currentElement)
        if (args.len < 2) return error.WrongNumberOfArguments;
        const func_val = try eval_expression(env, ctx, args[0]);
        if (func_val != .closure) return error.ExpectedClosure;
        var accumulator = try eval_expression(env, ctx, args[1]);
        for (arr.items.items) |item| {
            accumulator = try callClosureWithArgs(env, ctx, func_val.closure, &[_]Value{ accumulator, item });
        }
        return accumulator;
    }

    return error.UndefinedArrayMethod;
}

/// Evaluate a built-in map method
fn evalMapMethod(env: *Environment, ctx: *RuntimeCtx, m: *JoyaMap, method: []const u8, args: []const ast.Expression) !Value {
    if (std.mem.eql(u8, method, "put")) {
        // m.put(key, value)
        if (args.len < 2) return error.WrongNumberOfArguments;
        const key_val = try eval_expression(env, ctx, args[0]);
        const val = try eval_expression(env, ctx, args[1]);
        // Convert key to string representation for HashMap
        const key_str = try valueToMapKey(env, ctx, key_val);
        try m.entries.put(key_str, val);
        return Value.void;
    }

    if (std.mem.eql(u8, method, "get")) {
        // m.get(key) → value or null
        if (args.len < 1) return error.WrongNumberOfArguments;
        const key_val = try eval_expression(env, ctx, args[0]);
        const key_str = try valueToMapKey(env, ctx, key_val);
        return m.entries.get(key_str) orelse Value{ .null_val = {} };
    }

    if (std.mem.eql(u8, method, "remove")) {
        // m.remove(key) → value or null
        if (args.len < 1) return error.WrongNumberOfArguments;
        const key_val = try eval_expression(env, ctx, args[0]);
        const key_str = try valueToMapKey(env, ctx, key_val);
        if (m.entries.fetchRemove(key_str)) |entry| {
            return entry.value;
        }
        return Value{ .null_val = {} };
    }

    if (std.mem.eql(u8, method, "containsKey")) {
        // m.containsKey(key) → bool
        if (args.len < 1) return error.WrongNumberOfArguments;
        const key_val = try eval_expression(env, ctx, args[0]);
        const key_str = try valueToMapKey(env, ctx, key_val);
        return Value{ .bool = m.entries.contains(key_str) };
    }

    if (std.mem.eql(u8, method, "size")) {
        // m.size() → int
        return Value{ .int = @intCast(m.entries.count()) };
    }

    if (std.mem.eql(u8, method, "isEmpty")) {
        // m.isEmpty() → bool
        return Value{ .bool = m.entries.count() == 0 };
    }

    if (std.mem.eql(u8, method, "keys")) {
        // m.keys() → array of keys (as strings)
        const arr = try JoyaArray.init(env.allocator, .{ .string = {} }, 0, .void);
        var iter = m.entries.keyIterator();
        while (iter.next()) |key| {
            const key_copy = try env.allocator.dupe(u8, key.*);
            try ctx.trackString(key_copy);
            try arr.items.append(Value{ .string = key_copy });
        }
        try ctx.trackArray(arr);
        return Value{ .array = arr };
    }

    if (std.mem.eql(u8, method, "values")) {
        // m.values() → array of values
        const arr = try JoyaArray.init(env.allocator, .void, 0, .void);
        var iter = m.entries.valueIterator();
        while (iter.next()) |val| {
            try arr.items.append(val.*);
        }
        try ctx.trackArray(arr);
        return Value{ .array = arr };
    }

    if (std.mem.eql(u8, method, "clear")) {
        // m.clear()
        m.entries.clearRetainingCapacity();
        return Value.void;
    }

    return error.UndefinedMapMethod;
}

/// Evaluate a closure call: bind args to params, execute body in captured environment
fn evalClosureCall(env: *Environment, ctx: *RuntimeCtx, cl: *Closure, args: []const ast.Expression) !Value {
    // Evaluate arguments
    var arg_vals = std.ArrayList(Value).init(env.allocator);
    defer arg_vals.deinit();
    for (args) |arg_expr| {
        try arg_vals.append(try eval_expression(env, ctx, arg_expr));
    }
    return callClosureWithArgs(env, ctx, cl, arg_vals.items);
}

/// Call a closure with pre-evaluated Value arguments (used by array higher-order methods)
fn callClosureWithArgs(env: *Environment, ctx: *RuntimeCtx, cl: *Closure, args: []const Value) !Value {
    // Create method environment from captured environment (clone shares ref_cell pointers)
    var closure_env = try cl.captured_env.clone();
    // Bind parameters as new local variables (use put directly to override any captured binding)
    for (cl.params, 0..) |param, i| {
        if (i < args.len) {
            try closure_env.vars.put(param.name, args[i]);
        }
    }
    ctx.return_value = null;
    var local_threads = std.ArrayList(std.Thread).init(env.allocator);
    const result = execute_statement(&closure_env, ctx, cl.body.*, &local_threads);
    for (local_threads.items) |t| t.join();
    closure_env.deinit();
    _ = result catch |err| switch (err) {
        error.ReturnSignal => {},
        else => return err,
    };
    const return_val = ctx.return_value orelse Value.void;
    ctx.return_value = null;
    return return_val;
}

/// Evaluate a static method call: ClassName.method(args)
/// No 'this' binding — the method runs in a clean environment
fn evalStaticMethod(env: *Environment, ctx: *RuntimeCtx, class: *const ast.Class, method_name: []const u8, args: []const ast.Expression) !Value {
    for (class.methods) |*method| {
        if (std.mem.eql(u8, method.name, method_name)) {
            // Evaluate arguments
            var arg_vals = std.ArrayList(Value).init(env.allocator);
            defer arg_vals.deinit();
            for (args) |arg_expr| {
                try arg_vals.append(try eval_expression(env, ctx, arg_expr));
            }
            // Create method environment without 'this'
            var method_env = Environment.init(env.allocator);
            for (method.params, 0..) |param, i| {
                if (i < arg_vals.items.len) {
                    try method_env.set(param.name, arg_vals.items[i]);
                }
            }
            ctx.return_value = null;
            var local_threads = std.ArrayList(std.Thread).init(env.allocator);
            const result = execute_statement(&method_env, ctx, method.body, &local_threads);
            for (local_threads.items) |t| t.join();
            method_env.deinit();
            _ = result catch |err| switch (err) {
                error.ReturnSignal => {},
                else => return err,
            };
            const return_val = ctx.return_value orelse Value.void;
            ctx.return_value = null;
            return return_val;
        }
    }
    return error.UndefinedMethod;
}

/// Convert a Value to a string key for use in the map's StringHashMap.
/// int → "42", string → "hello", bool → "true"/"false", float → "3.14"
fn valueToMapKey(env: *Environment, ctx: *RuntimeCtx, val: Value) ![]const u8 {
    switch (val) {
        .int => {
            var buf = std.ArrayList(u8).init(env.allocator);
            try buf.writer().print("{}", .{val.int});
            const result = try buf.toOwnedSlice();
            try ctx.trackString(result);
            return result;
        },
        .string => return val.string,
        .bool => {
            const result = try env.allocator.dupe(u8, if (val.bool) "true" else "false");
            try ctx.trackString(result);
            return result;
        },
        .float => {
            var buf = std.ArrayList(u8).init(env.allocator);
            try buf.writer().print("{}", .{val.float});
            const result = try buf.toOwnedSlice();
            try ctx.trackString(result);
            return result;
        },
        else => return error.InvalidMapKey,
    }
}

fn goRoutineEntry(_: *scheduler.Goroutine, user_data: ?*anyopaque) void {
    const ctx: *GoCtx = @ptrCast(@alignCast(user_data orelse return));
    var local_env = ctx.env_copy;
    defer local_env.deinit();
    const allocator = local_env.allocator;
    var inner_threads = std.ArrayList(std.Thread).init(allocator);
    defer inner_threads.deinit();
    execute_statement(&local_env, ctx.ctx_copy, ctx.body_copy, &inner_threads) catch {};
    for (inner_threads.items) |t| t.join();
    allocator.destroy(ctx);
}

fn printValue(val: Value, newline: bool) !void {
    switch (val) {
        .int => if (newline) std.debug.print("{}\n", .{val.int}) else std.debug.print("{}", .{val.int}),
        .string => if (newline) std.debug.print("{s}\n", .{val.string}) else std.debug.print("{s}", .{val.string}),
        .bool => if (newline) std.debug.print("{}\n", .{val.bool}) else std.debug.print("{}", .{val.bool}),
        .float => if (newline) std.debug.print("{}\n", .{val.float}) else std.debug.print("{}", .{val.float}),
        .array => {
            std.debug.print("[", .{});
            for (val.array.items.items, 0..) |item, i| {
                if (i > 0) std.debug.print(", ", .{});
                try printValue(item, false);
            }
            if (newline) std.debug.print("]\n", .{}) else std.debug.print("]", .{});
        },
        .chan => if (newline) std.debug.print("<chan>\n", .{}) else std.debug.print("<chan>", .{}),
        .map => {
            std.debug.print("{{", .{});
            var i: usize = 0;
            var iter = val.map.entries.iterator();
            while (iter.next()) |entry| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}: ", .{entry.key_ptr.*});
                try printValue(entry.value_ptr.*, false);
                i += 1;
            }
            if (newline) std.debug.print("}}\n", .{}) else std.debug.print("}}", .{});
        },
        .object => if (newline) std.debug.print("<{s} object>\n", .{val.object.class_name}) else std.debug.print("<{s} object>", .{val.object.class_name}),
        .closure => if (newline) std.debug.print("<closure>\n", .{}) else std.debug.print("<closure>", .{}),
        .ref_cell => {
            // Dereference and print the inner value
            try printValue(val.ref_cell.value, newline);
        },
        .null_val => if (newline) std.debug.print("null\n", .{}) else std.debug.print("null", .{}),
        .void => {},
    }
}

fn execute_statement(env: *Environment, ctx: *RuntimeCtx, stmt: ast.Statement, threads: *std.ArrayList(std.Thread)) anyerror!void {
    switch (stmt) {
        .var_decl => |vd| {
            const val = try eval_expression(env, ctx, vd.init.?);
            try env.set(vd.name, val);
        },
        .assign => |a| {
            const val = try eval_expression(env, ctx, a.value);
            try env.set(a.name, val);
        },
        .this_assign => |ta| {
            const this_val = env.get("this") orelse return error.NoThisContext;
            if (this_val != .object) return error.NoThisContext;
            const val = try eval_expression(env, ctx, ta.value);
            try this_val.object.fields.put(ta.field, val);
        },
        .array_assign => |aa| {
            const arr_val = env.get(aa.array) orelse return error.UndefinedVariable;
            if (arr_val != .array) return error.NotAnArray;
            const idx_val = try eval_expression(env, ctx, aa.index);
            const idx: usize = @intCast(idx_val.int);
            const val = try eval_expression(env, ctx, aa.value);
            if (idx >= arr_val.array.items.items.len) return error.ArrayIndexOutOfBounds;
            arr_val.array.items.items[idx] = val;
        },
        .expr_stmt => |e| {
            _ = try eval_expression(env, ctx, e);
        },
        .block => |stmts| {
            for (stmts) |s| {
                try execute_statement(env, ctx, s, threads);
            }
        },
        .go_stmt => |body| {
            if (scheduler.tls_scheduler) |sched| {
                // Scheduler mode: spawn as lightweight goroutine
                const env_clone = try env.clone();
                const go_ctx = try env.allocator.create(GoCtx);
                go_ctx.* = .{ .env_copy = env_clone, .ctx_copy = ctx, .body_copy = body.* };

                const g = sched.spawn(goRoutineEntry, @ptrCast(@alignCast(go_ctx))) catch return;
                _ = g;
            } else {
                // Fallback: OS thread mode (original behavior)
                const env_clone = try env.clone();
                const thread = try std.Thread.spawn(.{}, struct {
                    fn run(env_copy: Environment, ctx_copy: *RuntimeCtx, b: ast.Statement) !void {
                        var local_env = env_copy;
                        defer local_env.deinit();
                        var inner_threads = std.ArrayList(std.Thread).init(local_env.allocator);
                        defer inner_threads.deinit();
                        try execute_statement(&local_env, ctx_copy, b, &inner_threads);
                        for (inner_threads.items) |t| t.join();
                    }
                }.run, .{ env_clone, ctx, body.* });
                try threads.append(thread);
            }
        },
        .for_loop => |fl| {
            if (fl.init) |init| try execute_statement(env, ctx, init.*, threads);
            while (true) {
                var cond_val: bool = true;
                if (fl.cond) |cond| {
                    const v = try eval_expression(env, ctx, cond);
                    cond_val = v.bool;
                }
                if (!cond_val) break;
                const body_result = execute_statement(env, ctx, fl.body.*, threads);
                if (body_result) |_| {} else |err| switch (err) {
                    error.BreakSignal => break,
                    error.ContinueSignal => {},
                    error.ReturnSignal => return err,
                    else => return err,
                }
                if (fl.inc) |inc| try execute_statement(env, ctx, inc.*, threads);
            }
        },
        .while_loop => |wl| {
            while (true) {
                const v = try eval_expression(env, ctx, wl.cond);
                if (v != .bool or !v.bool) break;
                const body_result = execute_statement(env, ctx, wl.body.*, threads);
                if (body_result) |_| {} else |err| switch (err) {
                    error.BreakSignal => break,
                    error.ContinueSignal => {},
                    error.ReturnSignal => return err,
                    else => return err,
                }
            }
        },
        .for_each => |fe| {
            const iterable = try eval_expression(env, ctx, fe.iterable);
            if (iterable != .array) return error.NotAnArray;
            for (iterable.array.items.items) |item| {
                try env.set(fe.elem_name, item);
                const body_result = execute_statement(env, ctx, fe.body.*, threads);
                if (body_result) |_| {} else |err| switch (err) {
                    error.BreakSignal => break,
                    error.ContinueSignal => {},
                    error.ReturnSignal => return err,
                    else => return err,
                }
            }
        },
        .if_stmt => |is| {
            const cond_val = try eval_expression(env, ctx, is.cond);
            if (cond_val == .bool and cond_val.bool) {
                try execute_statement(env, ctx, is.then_branch.*, threads);
            } else if (is.else_branch) |else_br| {
                try execute_statement(env, ctx, else_br.*, threads);
            }
        },
        .return_stmt => |ret_expr| {
            if (ret_expr) |expr| {
                ctx.return_value = try eval_expression(env, ctx, expr);
            } else {
                ctx.return_value = Value.void;
            }
            return error.ReturnSignal;
        },
        .break_stmt => return error.BreakSignal,
        .continue_stmt => return error.ContinueSignal,
        .throw_stmt => |expr| {
            const val = try eval_expression(env, ctx, expr);
            ctx.thrown_value = val;
            return error.ThrowSignal;
        },
        .try_stmt => |ts| {
            // Execute try block
            const try_result = execute_statement(env, ctx, ts.try_block.*, threads);
            if (try_result) |_| {
                // try block succeeded — run finally if present
                if (ts.finally_block) |fb| {
                    try execute_statement(env, ctx, fb.*, threads);
                }
            } else |err| switch (err) {
                error.ThrowSignal => {
                    // Caught! Execute catch block with the thrown value bound to catch_var
                    const thrown = ctx.thrown_value orelse Value{ .null_val = {} };
                    ctx.thrown_value = null;
                    try env.set(ts.catch_var, thrown);
                    const catch_result = execute_statement(env, ctx, ts.catch_block.*, threads);
                    if (ts.finally_block) |fb| {
                        try execute_statement(env, ctx, fb.*, threads);
                    }
                    // If catch block threw or returned, propagate that
                    _ = catch_result catch |catch_err| switch (catch_err) {
                        error.ThrowSignal, error.ReturnSignal, error.BreakSignal, error.ContinueSignal => return catch_err,
                        else => return catch_err,
                    };
                },
                else => {
                    // Not a ThrowSignal — still run finally, then propagate the original error
                    if (ts.finally_block) |fb| {
                        try execute_statement(env, ctx, fb.*, threads);
                    }
                    return err;
                },
            }
        },
        .print_stmt => |ps| {
            const val = try eval_expression(env, ctx, ps.expr);
            try printValue(val, ps.newline);
        },
    }
}

pub fn run(allocator: std.mem.Allocator, program: ast.Program) !void {
    var main_method: ?ast.Method = null;
    for (program.classes) |class| {
        if (std.mem.eql(u8, class.name, "Main")) {
            for (class.methods) |method| {
                if (std.mem.eql(u8, method.name, "main")) {
                    main_method = method;
                    break;
                }
            }
        }
    }

    if (main_method == null) return error.MainMethodNotFound;

    // Wrap allocator with thread-safe mutex for concurrent go-threads
    var ts_alloc = ThreadSafeAlloc.init(allocator);
    const safe_alloc = ts_alloc.allocator();

    // Try scheduler mode
    const cpu_count = std.Thread.getCpuCount() catch 4;
    const sched = scheduler.Scheduler.init(safe_alloc, cpu_count) catch null;
    if (sched) |s| {
        // Create main goroutine that executes main()
        const main_body = main_method.?.body;
        const MainCtx = struct {
            env: Environment,
            ctx: RuntimeCtx,
            body: ast.Statement,
        };
        const main_ctx = try safe_alloc.create(MainCtx);
        main_ctx.* = .{
            .env = Environment.init(safe_alloc),
            .ctx = RuntimeCtx.init(safe_alloc),
            .body = main_body,
        };
        main_ctx.ctx.program = &program;

        _ = try s.spawn(struct {
            fn run(_: *scheduler.Goroutine, user_data: ?*anyopaque) void {
                const mc: *MainCtx = @ptrCast(@alignCast(user_data orelse return));
                var threads = std.ArrayList(std.Thread).init(mc.env.allocator);
                defer threads.deinit();
                execute_statement(&mc.env, &mc.ctx, mc.body, &threads) catch {};
                for (threads.items) |t| t.join();
                mc.env.deinit();
                mc.ctx.deinit();
                mc.env.allocator.destroy(mc);
            }
        }.run, @ptrCast(@alignCast(main_ctx)));

        try scheduler.run(s);
        s.deinit();
        return;
    }

    // Fallback: original OS thread mode
    var env = Environment.init(safe_alloc);
    defer env.deinit();

    var ctx = RuntimeCtx.init(safe_alloc);
    ctx.program = &program;
    defer ctx.deinit();

    var threads = std.ArrayList(std.Thread).init(safe_alloc);
    defer threads.deinit();

    const main_result = execute_statement(&env, &ctx, main_method.?.body, &threads);
    _ = main_result catch |err| switch (err) {
        error.ReturnSignal => {},
        else => return err,
    };

    for (threads.items) |t| {
        t.join();
    }
}
