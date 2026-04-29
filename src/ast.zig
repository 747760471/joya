const std = @import("std");
const lexer = @import("lexer.zig");

pub const Type = union(enum) {
    int,
    string,
    bool,
    float,
    chan: *Type,
    array: *Type,
    map: struct {
        key: *Type,
        value: *Type,
    },
    class_ref: []const u8,
    void,
};

pub const Expression = union(enum) {
    int_literal: i64,
    float_literal: f64,
    string_literal: []const u8,
    bool_literal: bool,
    null_literal,
    identifier: []const u8,
    binary_op: struct {
        op: lexer.TokenType,
        left: *Expression,
        right: *Expression,
    },
    unary_not: *Expression,
    call: struct {
        name: []const u8,
        args: []const Expression,
    },
    new_chan: struct {
        elem_type: Type,
        capacity: i64,
    },
    field_access: struct {
        object: *Expression,
        field: []const u8,
    },
    new_array: struct {
        elem_type: Type,
        size: *Expression,
    },
    array_literal: struct {
        elem_type: Type,
        elements: []const Expression,
    },
    array_index: struct {
        array: *Expression,
        index: *Expression,
    },
    new_object: struct {
        class_name: []const u8,
        args: []const Expression,
    },
    new_map: struct {
        key_type: Type,
        value_type: Type,
    },
    method_call: struct {
        object: *Expression,
        method: []const u8,
        args: []const Expression,
    },
    this_ref,
};

pub const Statement = union(enum) {
    var_decl: struct {
        typ: Type,
        name: []const u8,
        init: ?Expression,
    },
    assign: struct {
        name: []const u8,
        value: Expression,
    },
    this_assign: struct {
        field: []const u8,
        value: Expression,
    },
    array_assign: struct {
        array: []const u8,
        index: Expression,
        value: Expression,
    },
    expr_stmt: Expression,
    block: []const Statement,
    go_stmt: *Statement,
    for_loop: struct {
        init: ?*Statement,
        cond: ?Expression,
        inc: ?*Statement,
        body: *Statement,
    },
    while_loop: struct {
        cond: Expression,
        body: *Statement,
    },
    for_each: struct {
        elem_type: Type,
        elem_name: []const u8,
        iterable: Expression,
        body: *Statement,
    },
    break_stmt,
    continue_stmt,
    throw_stmt: Expression,
    try_stmt: struct {
        try_block: *Statement,
        catch_var: []const u8,
        catch_block: *Statement,
        finally_block: ?*Statement,
    },
    if_stmt: struct {
        cond: Expression,
        then_branch: *Statement,
        else_branch: ?*Statement,
    },
    return_stmt: ?Expression,
    print_stmt: struct {
        expr: Expression,
        newline: bool,
    },
};

pub const Param = struct {
    typ: Type,
    name: []const u8,
};

pub const FieldDecl = struct {
    typ: Type,
    name: []const u8,
};

pub const Method = struct {
    name: []const u8,
    return_type: Type,
    params: []const Param,
    body: Statement,
};

pub const Class = struct {
    name: []const u8,
    fields: []const FieldDecl,
    methods: []const Method,
};

pub const Program = struct {
    classes: []const Class,

    pub fn deinit(_: *Program, _: std.mem.Allocator) void {
        // ArenaAllocator handles cleanup
    }
};
