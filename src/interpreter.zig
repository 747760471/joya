const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

pub const Value = union(enum) {
    int: i64,
    string: []const u8,
    bool: bool,
    float: f64,
    chan: *Chan,
    void,
};

pub const Chan = struct {
    elem_type: ast.Type,
    capacity: usize,
    queue: std.ArrayList(Value),
    mutex: std.Thread.Mutex,
    send_cond: std.Thread.Condition,
    recv_cond: std.Thread.Condition,
    closed: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, elem_type: ast.Type, capacity: usize) !*Chan {
        const ch = try allocator.create(Chan);
        ch.* = .{
            .elem_type = elem_type,
            .capacity = capacity,
            .queue = std.ArrayList(Value).init(allocator),
            .mutex = .{},
            .send_cond = .{},
            .recv_cond = .{},
            .allocator = allocator,
        };
        return ch;
    }

    pub fn deinit(self: *Chan) void {
        self.queue.deinit();
        self.allocator.destroy(self);
    }

    pub fn send(self: *Chan, val: Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.queue.items.len >= self.capacity and !self.closed) {
            self.send_cond.wait(&self.mutex);
        }

        if (self.closed) return error.ChannelClosed;

        try self.queue.append(val);
        self.recv_cond.signal();
    }

    pub fn receive(self: *Chan) !?Value {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.queue.items.len == 0 and !self.closed) {
            self.recv_cond.wait(&self.mutex);
        }

        if (self.closed and self.queue.items.len == 0) return null;

        const val = self.queue.orderedRemove(0);
        self.send_cond.signal();
        return val;
    }

    pub fn close(self: *Chan) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
        self.send_cond.broadcast();
        self.recv_cond.broadcast();
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

    pub fn set(self: *Environment, name: []const u8, val: Value) !void {
        try self.vars.put(name, val);
    }

    pub fn get(self: *Environment, name: []const u8) ?Value {
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
    heap_strings: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) RuntimeCtx {
        return .{
            .allocator = allocator,
            .mutex = .{},
            .channels = std.ArrayList(*Chan).init(allocator),
            .heap_strings = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *RuntimeCtx) void {
        for (self.channels.items) |ch| ch.deinit();
        self.channels.deinit();
        for (self.heap_strings.items) |s| self.allocator.free(s);
        self.heap_strings.deinit();
    }

    pub fn trackChan(self: *RuntimeCtx, ch: *Chan) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.channels.append(ch);
    }

    pub fn trackString(self: *RuntimeCtx, s: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.heap_strings.append(s);
    }
};

fn eval_expression(env: *Environment, ctx: *RuntimeCtx, expr: ast.Expression) !Value {
    switch (expr) {
        .int_literal => |v| return Value{ .int = v },
        .float_literal => |v| return Value{ .float = v },
        .string_literal => |v| return Value{ .string = v },
        .bool_literal => |v| return Value{ .bool = v },
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
                    } else if (left == .string or right == .string) {
                        var buf = std.ArrayList(u8).init(env.allocator);
                        if (left == .string) try buf.appendSlice(left.string);
                        if (left == .int) try buf.writer().print("{}", .{left.int});
                        if (left == .float) try buf.writer().print("{}", .{left.float});
                        if (left == .bool) try buf.writer().print("{}", .{left.bool});
                        if (right == .string) try buf.appendSlice(right.string);
                        if (right == .int) try buf.writer().print("{}", .{right.int});
                        if (right == .float) try buf.writer().print("{}", .{right.float});
                        if (right == .bool) try buf.writer().print("{}", .{right.bool});
                        const s = try buf.toOwnedSlice();
                        try ctx.trackString(s);
                        return Value{ .string = s };
                    }
                    return error.InvalidOperation;
                },
                .minus => return Value{ .int = left.int - right.int },
                .star => return Value{ .int = left.int * right.int },
                .slash => return Value{ .int = @divTrunc(left.int, right.int) },
                .percent => return Value{ .int = @rem(left.int, right.int) },
                .lt => return Value{ .bool = left.int < right.int },
                .gt => return Value{ .bool = left.int > right.int },
                .lt_eq => return Value{ .bool = left.int <= right.int },
                .gt_eq => return Value{ .bool = left.int >= right.int },
                .eq_eq => return Value{ .bool = left.int == right.int },
                .not_eq => return Value{ .bool = left.int != right.int },
                else => return error.UnsupportedOperator,
            }
        },
        .new_chan => |nc| {
            const ch = try Chan.init(env.allocator, nc.elem_type, @intCast(nc.capacity));
            try ctx.trackChan(ch);
            return Value{ .chan = ch };
        },
        .unary_not => |operand| {
            const val = try eval_expression(env, ctx, operand.*);
            if (val == .bool) return Value{ .bool = !val.bool };
            return error.InvalidOperation;
        },
        .field_access => |fa| {
            return try eval_expression(env, ctx, fa.object.*);
        },
        .call => |c| {
            if (std.mem.eql(u8, c.name, "send")) {
                if (c.args.len >= 2) {
                    const ch_val = try eval_expression(env, ctx, c.args[0]);
                    const val = try eval_expression(env, ctx, c.args[1]);
                    try ch_val.chan.send(val);
                    return .void;
                }
            } else if (std.mem.eql(u8, c.name, "receive")) {
                if (c.args.len >= 1) {
                    const ch_val = try eval_expression(env, ctx, c.args[0]);
                    const val = try ch_val.chan.receive();
                    return val orelse .void;
                }
            } else if (std.mem.eql(u8, c.name, "close")) {
                if (c.args.len >= 1) {
                    const ch_val = try eval_expression(env, ctx, c.args[0]);
                    ch_val.chan.close();
                    return .void;
                }
            } else if (std.mem.eql(u8, c.name, "print")) {
                if (c.args.len >= 1) {
                    const val = try eval_expression(env, ctx, c.args[0]);
                    switch (val) {
                        .int => std.debug.print("{}", .{val.int}),
                        .string => std.debug.print("{s}", .{val.string}),
                        .bool => std.debug.print("{}", .{val.bool}),
                        .float => std.debug.print("{}", .{val.float}),
                        else => {},
                    }
                    return .void;
                }
            } else if (std.mem.eql(u8, c.name, "println")) {
                if (c.args.len >= 1) {
                    const val = try eval_expression(env, ctx, c.args[0]);
                    switch (val) {
                        .int => std.debug.print("{}\n", .{val.int}),
                        .string => std.debug.print("{s}\n", .{val.string}),
                        .bool => std.debug.print("{}\n", .{val.bool}),
                        .float => std.debug.print("{}\n", .{val.float}),
                        else => {},
                    }
                    return .void;
                }
            }
            return error.UndefinedFunction;
        },
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
        .expr_stmt => |e| {
            _ = try eval_expression(env, ctx, e);
        },
        .block => |stmts| {
            for (stmts) |s| {
                try execute_statement(env, ctx, s, threads);
            }
        },
        .go_stmt => |body| {
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
                try execute_statement(env, ctx, fl.body.*, threads);
                if (fl.inc) |inc| try execute_statement(env, ctx, inc.*, threads);
            }
        },
        .while_loop => |wl| {
            while (true) {
                const v = try eval_expression(env, ctx, wl.cond);
                if (v != .bool or !v.bool) break;
                try execute_statement(env, ctx, wl.body.*, threads);
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
        .return_stmt => {
            return;
        },
        .print_stmt => |ps| {
            const val = try eval_expression(env, ctx, ps.expr);
            switch (val) {
                .int => if (ps.newline) std.debug.print("{}\n", .{val.int}) else std.debug.print("{}", .{val.int}),
                .string => if (ps.newline) std.debug.print("{s}\n", .{val.string}) else std.debug.print("{s}", .{val.string}),
                .bool => if (ps.newline) std.debug.print("{}\n", .{val.bool}) else std.debug.print("{}", .{val.bool}),
                .float => if (ps.newline) std.debug.print("{}\n", .{val.float}) else std.debug.print("{}", .{val.float}),
                else => {},
            }
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

    var env = Environment.init(safe_alloc);
    defer env.deinit();

    var ctx = RuntimeCtx.init(safe_alloc);
    defer ctx.deinit();

    var threads = std.ArrayList(std.Thread).init(safe_alloc);
    defer threads.deinit();

    try execute_statement(&env, &ctx, main_method.?.body, &threads);

    for (threads.items) |t| {
        t.join();
    }
}
