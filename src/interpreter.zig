const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

pub const Value = union(enum) {
    int: i64,
    string: []const u8,
    bool: bool,
    float: f64,
    chan: *Chan,
    array: *JoyaArray,
    null_val,
    void,
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
            else => Value.void,
        };
    }
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
    arrays: std.ArrayList(*JoyaArray),
    heap_strings: std.ArrayList([]const u8),
    program: ?*const ast.Program,
    return_value: ?Value,

    pub fn init(allocator: std.mem.Allocator) RuntimeCtx {
        return .{
            .allocator = allocator,
            .mutex = .{},
            .channels = std.ArrayList(*Chan).init(allocator),
            .arrays = std.ArrayList(*JoyaArray).init(allocator),
            .heap_strings = std.ArrayList([]const u8).init(allocator),
            .program = null,
            .return_value = null,
        };
    }

    pub fn deinit(self: *RuntimeCtx) void {
        for (self.channels.items) |ch| ch.deinit();
        self.channels.deinit();
        for (self.arrays.items) |arr| arr.deinit();
        self.arrays.deinit();
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
                .lt => return Value{ .bool = left.int < right.int },
                .gt => return Value{ .bool = left.int > right.int },
                .lt_eq => return Value{ .bool = left.int <= right.int },
                .gt_eq => return Value{ .bool = left.int >= right.int },
                .eq_eq => {
                    if (left == .int and right == .int) return Value{ .bool = left.int == right.int };
                    if (left == .string and right == .string) return Value{ .bool = std.mem.eql(u8, left.string, right.string) };
                    if (left == .bool and right == .bool) return Value{ .bool = left.bool == right.bool };
                    if (left == .float and right == .float) return Value{ .bool = left.float == right.float };
                    if (left == .null_val and right == .null_val) return Value{ .bool = true };
                    if (left == .null_val or right == .null_val) return Value{ .bool = false };
                    return Value{ .bool = false };
                },
                .not_eq => {
                    if (left == .int and right == .int) return Value{ .bool = left.int != right.int };
                    if (left == .string and right == .string) return Value{ .bool = !std.mem.eql(u8, left.string, right.string) };
                    if (left == .bool and right == .bool) return Value{ .bool = left.bool != right.bool };
                    if (left == .float and right == .float) return Value{ .bool = left.float != right.float };
                    if (left == .null_val and right == .null_val) return Value{ .bool = false };
                    if (left == .null_val or right == .null_val) return Value{ .bool = true };
                    return Value{ .bool = true };
                },
                else => return error.UnsupportedOperator,
            }
        },
        .new_chan => |nc| {
            const ch = try Chan.init(env.allocator, nc.elem_type, @intCast(nc.capacity));
            try ctx.trackChan(ch);
            return Value{ .chan = ch };
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
        .unary_not => |operand| {
            const val = try eval_expression(env, ctx, operand.*);
            if (val == .bool) return Value{ .bool = !val.bool };
            return error.InvalidOperation;
        },
        .field_access => |fa| {
            // .length on arrays and strings
            if (std.mem.eql(u8, fa.field, "length")) {
                const obj = try eval_expression(env, ctx, fa.object.*);
                if (obj == .array) return Value{ .int = @intCast(obj.array.items.items.len) };
                if (obj == .string) return Value{ .int = @intCast(obj.string.len) };
            }
            return try eval_expression(env, ctx, fa.object.*);
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
            // User-defined method call
            if (ctx.program) |prog| {
                // Evaluate arguments
                var arg_vals = std.ArrayList(Value).init(env.allocator);
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
                            arg_vals.deinit();
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
                arg_vals.deinit();
            }
            return error.UndefinedFunction;
        },
    }
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
        .for_each => |fe| {
            const iterable = try eval_expression(env, ctx, fe.iterable);
            if (iterable != .array) return error.NotAnArray;
            for (iterable.array.items.items) |item| {
                try env.set(fe.elem_name, item);
                try execute_statement(env, ctx, fe.body.*, threads);
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
