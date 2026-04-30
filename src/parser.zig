const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []lexer.Token,
    pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, tokens: []lexer.Token) !Parser {
        return Parser{
            .allocator = allocator,
            .tokens = tokens,
        };
    }

    pub fn deinit(_: *Parser) void {}

    // ---- Helper methods ----

    fn peek(self: *Parser) lexer.Token {
        if (self.pos >= self.tokens.len) return self.tokens[self.tokens.len - 1];
        return self.tokens[self.pos];
    }

    fn advance(self: *Parser) lexer.Token {
        const tok = self.peek();
        if (self.pos < self.tokens.len - 1) self.pos += 1;
        return tok;
    }

    fn check(self: *Parser, typ: lexer.TokenType) bool {
        return self.peek().typ == typ;
    }

    fn match(self: *Parser, typ: lexer.TokenType) ?lexer.Token {
        if (self.check(typ)) return self.advance();
        return null;
    }

    fn expect(self: *Parser, typ: lexer.TokenType) !lexer.Token {
        if (self.check(typ)) return self.advance();
        const tok = self.peek();
        std.debug.print("Parse error: expected {}, got {} ('{s}') at line {}\n", .{ typ, tok.typ, tok.value, tok.line });
        return error.UnexpectedToken;
    }

    fn isAtEnd(self: *Parser) bool {
        return self.peek().typ == .eof;
    }

    /// Parse a name: identifier or keyword that can be used as a name (main, map, etc.)
    fn parseName(self: *Parser) !lexer.Token {
        if (self.check(.identifier)) return self.advance();
        if (self.check(.keyword_main)) return self.advance();
        if (self.check(.keyword_map)) return self.advance();
        if (self.check(.keyword_fn)) return self.advance();
        const tok = self.peek();
        std.debug.print("Parse error: expected name, got {} ('{s}') at line {}\n", .{ tok.typ, tok.value, tok.line });
        return error.ExpectedName;
    }

    // ---- Type parsing ----

    fn isTypeStart(self: *Parser) bool {
        return self.check(.keyword_int) or
            self.check(.keyword_string) or
            self.check(.keyword_bool) or
            self.check(.keyword_float) or
            self.check(.keyword_void) or
            self.check(.keyword_chan) or
            self.check(.keyword_map) or
            self.check(.keyword_fn);
    }

    /// Parse a base type without [] suffix (used by new T[size] and type declarations)
    fn parseBaseType(self: *Parser) anyerror!ast.Type {
        if (self.check(.keyword_int)) { _ = self.advance(); return .int; }
        if (self.check(.keyword_string)) { _ = self.advance(); return .string; }
        if (self.check(.keyword_bool)) { _ = self.advance(); return .bool; }
        if (self.check(.keyword_float)) { _ = self.advance(); return .float; }
        if (self.check(.keyword_void)) { _ = self.advance(); return .void; }
        if (self.check(.keyword_chan)) {
            _ = self.advance();
            _ = try self.expect(.lt);
            const elem_type = try self.parseType();
            _ = try self.expect(.gt);
            const chan_type = try self.allocator.create(ast.Type);
            chan_type.* = elem_type;
            return ast.Type{ .chan = chan_type };
        }
        if (self.check(.keyword_map)) {
            _ = self.advance();
            _ = try self.expect(.lt);
            const key_type = try self.parseType();
            _ = try self.expect(.comma);
            const value_type = try self.parseType();
            _ = try self.expect(.gt);
            const key_ptr = try self.allocator.create(ast.Type);
            key_ptr.* = key_type;
            const val_ptr = try self.allocator.create(ast.Type);
            val_ptr.* = value_type;
            return ast.Type{ .map = .{ .key = key_ptr, .value = val_ptr } };
        }
        // fn type (used as variable/parameter type for closures)
        if (self.check(.keyword_fn)) {
            _ = self.advance();
            return ast.Type{ .fn_ref = {} };
        }
        // Class type: identifier used as type name
        if (self.check(.identifier)) {
            const name_tok = self.advance();
            return ast.Type{ .class_ref = name_tok.value };
        }
        const tok = self.peek();
        std.debug.print("Parse error: expected type, got {} ('{s}') at line {}\n", .{ tok.typ, tok.value, tok.line });
        return error.ExpectedType;
    }

    fn parseType(self: *Parser) anyerror!ast.Type {
        var result = try self.parseBaseType();
        // Array type: T[] (zero or more [] suffixes)
        while (self.check(.l_bracket) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .r_bracket) {
            _ = self.advance(); // [
            _ = self.advance(); // ]
            const inner = try self.allocator.create(ast.Type);
            inner.* = result;
            result = ast.Type{ .array = inner };
        }
        return result;
    }

    // ---- Expression parsing (precedence climbing) ----

    fn parseExpression(self: *Parser) anyerror!ast.Expression {
        return self.parseLogicalOr();
    }

    fn parseLogicalOr(self: *Parser) anyerror!ast.Expression {
        var expr = try self.parseLogicalAnd();
        while (self.check(.pipe_pipe)) {
            const op = self.advance().typ;
            const right = try self.parseLogicalAnd();
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = expr;
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            expr = ast.Expression{
                .binary_op = .{ .op = op, .left = left_ptr, .right = right_ptr },
            };
        }
        return expr;
    }

    fn parseLogicalAnd(self: *Parser) anyerror!ast.Expression {
        var expr = try self.parseComparison();
        while (self.check(.amp_amp)) {
            const op = self.advance().typ;
            const right = try self.parseComparison();
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = expr;
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            expr = ast.Expression{
                .binary_op = .{ .op = op, .left = left_ptr, .right = right_ptr },
            };
        }
        return expr;
    }

    fn parseComparison(self: *Parser) anyerror!ast.Expression {
        var expr = try self.parseAddition();
        while (self.check(.lt) or self.check(.gt) or self.check(.lt_eq) or
            self.check(.gt_eq) or self.check(.eq_eq) or self.check(.not_eq))
        {
            const op = self.advance().typ;
            const right = try self.parseAddition();
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = expr;
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            expr = ast.Expression{
                .binary_op = .{ .op = op, .left = left_ptr, .right = right_ptr },
            };
        }
        return expr;
    }

    fn parseAddition(self: *Parser) anyerror!ast.Expression {
        var expr = try self.parseMultiplication();
        while (self.check(.plus) or self.check(.minus)) {
            const op = self.advance().typ;
            const right = try self.parseMultiplication();
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = expr;
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            expr = ast.Expression{
                .binary_op = .{ .op = op, .left = left_ptr, .right = right_ptr },
            };
        }
        return expr;
    }

    fn parseMultiplication(self: *Parser) anyerror!ast.Expression {
        var expr = try self.parseUnary();
        while (self.check(.star) or self.check(.slash) or self.check(.percent)) {
            const op = self.advance().typ;
            const right = try self.parseUnary();
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = expr;
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            expr = ast.Expression{
                .binary_op = .{ .op = op, .left = left_ptr, .right = right_ptr },
            };
        }
        return expr;
    }

    fn parseUnary(self: *Parser) anyerror!ast.Expression {
        if (self.check(.minus)) {
            _ = self.advance();
            const operand = try self.parseUnary();
            const zero = try self.allocator.create(ast.Expression);
            zero.* = .{ .int_literal = 0 };
            const operand_ptr = try self.allocator.create(ast.Expression);
            operand_ptr.* = operand;
            return ast.Expression{
                .binary_op = .{ .op = .minus, .left = zero, .right = operand_ptr },
            };
        }
        if (self.check(.bang)) {
            _ = self.advance();
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(ast.Expression);
            operand_ptr.* = operand;
            return ast.Expression{
                .unary_not = operand_ptr,
            };
        }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *Parser) anyerror!ast.Expression {
        // Integer literal
        if (self.check(.int_literal)) {
            const tok = self.advance();
            const val = std.fmt.parseInt(i64, tok.value, 10) catch return error.InvalidIntLiteral;
            return ast.Expression{ .int_literal = val };
        }
        // Float literal
        if (self.check(.float_literal)) {
            const tok = self.advance();
            const val = std.fmt.parseFloat(f64, tok.value) catch return error.InvalidFloatLiteral;
            return ast.Expression{ .float_literal = val };
        }
        // String literal
        if (self.check(.string_literal)) {
            const tok = self.advance();
            return ast.Expression{ .string_literal = tok.value };
        }
        // Bool literals
        if (self.check(.keyword_true)) { _ = self.advance(); return ast.Expression{ .bool_literal = true }; }
        if (self.check(.keyword_false)) { _ = self.advance(); return ast.Expression{ .bool_literal = false }; }

        // Null literal
        if (self.check(.keyword_null)) { _ = self.advance(); return ast.Expression{ .null_literal = {} }; }

        // this reference
        if (self.check(.keyword_this)) {
            _ = self.advance();
            var expr = ast.Expression{ .this_ref = {} };
            expr = try self.parsePostfix(expr);
            return expr;
        }

        // Lambda expression: fn(Type name, ...) { body }
        if (self.check(.keyword_fn)) {
            // Lookahead: fn followed by ( means lambda expression
            if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .l_paren) {
                _ = self.advance(); // consume 'fn'
                _ = try self.expect(.l_paren);
                var params = std.ArrayList(ast.Param).init(self.allocator);
                if (!self.check(.r_paren)) {
                    const param_type = try self.parseType();
                    const param_name = try self.parseName();
                    try params.append(.{ .typ = param_type, .name = param_name.value });
                    while (self.check(.comma)) {
                        _ = self.advance();
                        const pt = try self.parseType();
                        const pn = try self.parseName();
                        try params.append(.{ .typ = pt, .name = pn.value });
                    }
                }
                _ = try self.expect(.r_paren);
                const body = try self.parseBlock();
                const body_ptr = try self.allocator.create(ast.Statement);
                body_ptr.* = body;
                var expr = ast.Expression{
                    .lambda = .{ .params = try params.toOwnedSlice(), .body = body_ptr },
                };
                expr = try self.parsePostfix(expr);
                return expr;
            }
        }

        // new chan<T>(capacity)
        if (self.check(.keyword_new)) {
            _ = self.advance();
            // new chan<T>(capacity)
            if (self.check(.keyword_chan)) {
                _ = self.advance();
                _ = try self.expect(.lt);
                const elem_type = try self.parseType();
                _ = try self.expect(.gt);
                _ = try self.expect(.l_paren);
                const cap_tok = try self.expect(.int_literal);
                const capacity = std.fmt.parseInt(i64, cap_tok.value, 10) catch return error.InvalidIntLiteral;
                _ = try self.expect(.r_paren);
                return ast.Expression{
                    .new_chan = .{ .elem_type = elem_type, .capacity = capacity },
                };
            }
            // new map<K,V>()
            if (self.check(.keyword_map)) {
                _ = self.advance();
                _ = try self.expect(.lt);
                const key_type = try self.parseType();
                _ = try self.expect(.comma);
                const value_type = try self.parseType();
                _ = try self.expect(.gt);
                _ = try self.expect(.l_paren);
                _ = try self.expect(.r_paren);
                return ast.Expression{
                    .new_map = .{ .key_type = key_type, .value_type = value_type },
                };
            }
            // new ClassName(args) — object creation (identifier followed by `(`)
            if (self.check(.identifier)) {
                // Lookahead: is next token `(` (object) or `[` (array of class type)?
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .l_paren) {
                    const class_name = self.advance();
                    _ = try self.expect(.l_paren);
                    var args = std.ArrayList(ast.Expression).init(self.allocator);
                    if (!self.check(.r_paren)) {
                        try args.append(try self.parseExpression());
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try args.append(try self.parseExpression());
                        }
                    }
                    _ = try self.expect(.r_paren);
                    return ast.Expression{
                        .new_object = .{ .class_name = class_name.value, .args = try args.toOwnedSlice() },
                    };
                }
            }
            // new T[size] — array creation
            const elem_type = try self.parseBaseType();
            _ = try self.expect(.l_bracket);
            const size_expr = try self.parseExpression();
            _ = try self.expect(.r_bracket);
            const size_ptr = try self.allocator.create(ast.Expression);
            size_ptr.* = size_expr;
            return ast.Expression{
                .new_array = .{ .elem_type = elem_type, .size = size_ptr },
            };
        }

        // Array literal: [expr, expr, ...]
        if (self.check(.l_bracket)) {
            _ = self.advance();
            var elements = std.ArrayList(ast.Expression).init(self.allocator);
            if (!self.check(.r_bracket)) {
                const first = try self.parseExpression();
                try elements.append(first);
                while (self.check(.comma)) {
                    _ = self.advance();
                    try elements.append(try self.parseExpression());
                }
            }
            _ = try self.expect(.r_bracket);
            // Infer element type from first element
            const inferred_type: ast.Type = if (elements.items.len > 0) blk: {
                break :blk switch (elements.items[0]) {
                    .int_literal => ast.Type.int,
                    .float_literal => ast.Type.float,
                    .string_literal => ast.Type.string,
                    .bool_literal => ast.Type.bool,
                    else => ast.Type.void,
                };
            } else ast.Type.void;
            return ast.Expression{
                .array_literal = .{ .elem_type = inferred_type, .elements = try elements.toOwnedSlice() },
            };
        }

        // Built-in function calls: send/receive/close/print/println
        if (self.check(.keyword_send) or self.check(.keyword_receive) or
            self.check(.keyword_close) or self.check(.keyword_print) or
            self.check(.keyword_println))
        {
            const name_tok = self.advance();
            _ = try self.expect(.l_paren);
            var args = std.ArrayList(ast.Expression).init(self.allocator);
            if (!self.check(.r_paren)) {
                try args.append(try self.parseExpression());
                while (self.check(.comma)) {
                    _ = self.advance();
                    try args.append(try self.parseExpression());
                }
            }
            _ = try self.expect(.r_paren);
            return ast.Expression{
                .call = .{ .name = name_tok.value, .args = try args.toOwnedSlice() },
            };
        }

        // Identifier (possibly function call, array index, or field access)
        if (self.check(.identifier) or self.check(.keyword_main)) {
            const name_tok = self.advance();
            // Function call: name(args)
            if (self.check(.l_paren)) {
                _ = self.advance();
                var args = std.ArrayList(ast.Expression).init(self.allocator);
                if (!self.check(.r_paren)) {
                    try args.append(try self.parseExpression());
                    while (self.check(.comma)) {
                        _ = self.advance();
                        try args.append(try self.parseExpression());
                    }
                }
                _ = try self.expect(.r_paren);
                var expr = ast.Expression{
                    .call = .{ .name = name_tok.value, .args = try args.toOwnedSlice() },
                };
                expr = try self.parsePostfix(expr);
                return expr;
            }
            var expr = ast.Expression{ .identifier = name_tok.value };
            expr = try self.parsePostfix(expr);
            return expr;
        }

        // Parenthesized expression
        if (self.check(.l_paren)) {
            _ = self.advance();
            const expr = try self.parseExpression();
            _ = try self.expect(.r_paren);
            return expr;
        }

        const tok = self.peek();
        std.debug.print("Parse error: unexpected token in expression {} ('{s}') at line {}\n", .{ tok.typ, tok.value, tok.line });
        return error.UnexpectedToken;
    }

    // ---- Postfix operators: array index, field access ----

    fn parsePostfix(self: *Parser, expr: ast.Expression) anyerror!ast.Expression {
        var result = expr;
        while (true) {
            // Direct invocation: expr(args) — used for IIFE or calling a closure returned by expression
            if (self.check(.l_paren)) {
                _ = self.advance();
                var args = std.ArrayList(ast.Expression).init(self.allocator);
                if (!self.check(.r_paren)) {
                    try args.append(try self.parseExpression());
                    while (self.check(.comma)) {
                        _ = self.advance();
                        try args.append(try self.parseExpression());
                    }
                }
                _ = try self.expect(.r_paren);
                const obj = try self.allocator.create(ast.Expression);
                obj.* = result;
                result = ast.Expression{
                    .method_call = .{ .object = obj, .method = "", .args = try args.toOwnedSlice() },
                };
            }
            // Array index: expr[index]
            else if (self.check(.l_bracket)) {
                _ = self.advance();
                const index = try self.parseExpression();
                _ = try self.expect(.r_bracket);
                const arr_ptr = try self.allocator.create(ast.Expression);
                arr_ptr.* = result;
                const idx_ptr = try self.allocator.create(ast.Expression);
                idx_ptr.* = index;
                result = ast.Expression{ .array_index = .{ .array = arr_ptr, .index = idx_ptr } };
            }
            // Method call or field access: expr.name(args) or expr.name
            else if (self.check(.dot)) {
                _ = self.advance();
                const field = try self.parseName();
                // Method call: expr.method(args)
                if (self.check(.l_paren)) {
                    _ = self.advance();
                    var args = std.ArrayList(ast.Expression).init(self.allocator);
                    if (!self.check(.r_paren)) {
                        try args.append(try self.parseExpression());
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try args.append(try self.parseExpression());
                        }
                    }
                    _ = try self.expect(.r_paren);
                    const obj = try self.allocator.create(ast.Expression);
                    obj.* = result;
                    result = ast.Expression{
                        .method_call = .{ .object = obj, .method = field.value, .args = try args.toOwnedSlice() },
                    };
                }
                // Field access: expr.field
                else {
                    const obj = try self.allocator.create(ast.Expression);
                    obj.* = result;
                    result = ast.Expression{ .field_access = .{ .object = obj, .field = field.value } };
                }
            }
            else {
                break;
            }
        }
        return result;
    }

    // ---- Statement parsing ----

    fn parseStatement(self: *Parser) anyerror!ast.Statement {
        if (self.check(.l_brace)) return self.parseBlock();
        if (self.check(.keyword_go)) return self.parseGoStmt();
        if (self.check(.keyword_for)) return self.parseForLoop();
        if (self.check(.keyword_while)) return self.parseWhileLoop();
        if (self.check(.keyword_if)) return self.parseIfStmt();
        if (self.check(.keyword_return)) return self.parseReturnStmt();
        if (self.check(.keyword_break)) return self.parseBreakStmt();
        if (self.check(.keyword_continue)) return self.parseContinueStmt();
        if (self.check(.keyword_throw)) return self.parseThrowStmt();
        if (self.check(.keyword_try)) return self.parseTryStmt();
        if (self.check(.keyword_print) or self.check(.keyword_println)) return self.parsePrintStmt();
        if (self.check(.keyword_this)) return self.parseThisAssignOrExpr();
        // Lambda expression as statement: fn(params) { body }(args);
        if (self.check(.keyword_fn) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .l_paren) {
            const expr = try self.parseExpression();
            _ = try self.expect(.semicolon);
            return ast.Statement{ .expr_stmt = expr };
        }
        if (self.isTypeStart()) return self.parseVarDecl();
        // Class-typed variable declaration: ClassName name = ...;
        // Lookahead: identifier followed by another identifier
        if (self.check(.identifier) and self.pos + 1 < self.tokens.len and
            (self.tokens[self.pos + 1].typ == .identifier or self.tokens[self.pos + 1].typ == .keyword_main))
        {
            return self.parseVarDecl();
        }
        if (self.check(.identifier)) return self.parseAssignOrExprStmt();
        // Built-in function calls as expression statements
        if (self.check(.keyword_send) or self.check(.keyword_receive) or self.check(.keyword_close)) {
            const expr = try self.parseExpression();
            _ = try self.expect(.semicolon);
            return ast.Statement{ .expr_stmt = expr };
        }
        const tok = self.peek();
        std.debug.print("Parse error: unexpected token in statement {} ('{s}') at line {}\n", .{ tok.typ, tok.value, tok.line });
        return error.UnexpectedToken;
    }

    fn parseBlock(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.l_brace);
        var stmts = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.check(.r_brace) and !self.isAtEnd()) {
            try stmts.append(try self.parseStatement());
        }
        _ = try self.expect(.r_brace);
        return ast.Statement{ .block = try stmts.toOwnedSlice() };
    }

    fn parseVarDecl(self: *Parser) anyerror!ast.Statement {
        const typ = try self.parseType();
        const name_tok = try self.parseName();

        // If type is fn_ref and name is followed by '(', this is a named lambda declaration
        // fn methodName(params) { body } → var_decl with lambda init
        if (typ == .fn_ref and self.check(.l_paren)) {
            _ = try self.expect(.l_paren);
            var params = std.ArrayList(ast.Param).init(self.allocator);
            if (!self.check(.r_paren)) {
                const param_type = try self.parseType();
                const param_name = try self.parseName();
                try params.append(.{ .typ = param_type, .name = param_name.value });
                while (self.check(.comma)) {
                    _ = self.advance();
                    const pt = try self.parseType();
                    const pn = try self.parseName();
                    try params.append(.{ .typ = pt, .name = pn.value });
                }
            }
            _ = try self.expect(.r_paren);
            const body = try self.parseBlock();
            _ = self.match(.semicolon); // optional semicolon after method body

            const body_ptr = try self.allocator.create(ast.Statement);
            body_ptr.* = body;

            return ast.Statement{
                .var_decl = .{
                    .typ = typ,
                    .name = name_tok.value,
                    .init = ast.Expression{
                        .lambda = .{ .params = try params.toOwnedSlice(), .body = body_ptr },
                    },
                },
            };
        }

        var init_expr: ?ast.Expression = null;
        if (self.check(.eq)) {
            _ = self.advance();
            init_expr = try self.parseExpression();
        }
        _ = try self.expect(.semicolon);
        return ast.Statement{
            .var_decl = .{ .typ = typ, .name = name_tok.value, .init = init_expr },
        };
    }

    fn parseAssignOrExprStmt(self: *Parser) anyerror!ast.Statement {
        const name_tok = self.advance();

        // Array index assignment: name[index] = expr;
        if (self.check(.l_bracket)) {
            _ = self.advance();
            const index = try self.parseExpression();
            _ = try self.expect(.r_bracket);
            if (self.check(.eq)) {
                _ = self.advance();
                const value = try self.parseExpression();
                _ = try self.expect(.semicolon);
                return ast.Statement{
                    .array_assign = .{ .array = name_tok.value, .index = index, .value = value },
                };
            }
            // arr[i] as expression statement (e.g. side-effect via function result)
            const arr_ptr = try self.allocator.create(ast.Expression);
            arr_ptr.* = .{ .identifier = name_tok.value };
            const idx_ptr = try self.allocator.create(ast.Expression);
            idx_ptr.* = index;
            var expr = ast.Expression{ .array_index = .{ .array = arr_ptr, .index = idx_ptr } };
            expr = try self.parsePostfix(expr);
            _ = try self.expect(.semicolon);
            return ast.Statement{ .expr_stmt = expr };
        }

        // Assignment: name = expr;
        if (self.check(.eq)) {
            _ = self.advance();
            const value = try self.parseExpression();
            _ = try self.expect(.semicolon);
            return ast.Statement{
                .assign = .{ .name = name_tok.value, .value = value },
            };
        }

        // Compound assignment: name += expr; name -= expr; etc.
        if (self.check(.plus_eq) or self.check(.minus_eq) or
            self.check(.star_eq) or self.check(.slash_eq) or self.check(.percent_eq))
        {
            const tok = self.advance();
            const op: lexer.TokenType = switch (tok.typ) {
                .plus_eq => .plus,
                .minus_eq => .minus,
                .star_eq => .star,
                .slash_eq => .slash,
                .percent_eq => .percent,
                else => unreachable,
            };
            const value = try self.parseExpression();
            _ = try self.expect(.semicolon);
            const left = try self.allocator.create(ast.Expression);
            left.* = .{ .identifier = name_tok.value };
            const right = try self.allocator.create(ast.Expression);
            right.* = value;
            return ast.Statement{
                .assign = .{
                    .name = name_tok.value,
                    .value = ast.Expression{ .binary_op = .{ .op = op, .left = left, .right = right } },
                },
            };
        }

        // Increment: name++ (tokenized as identifier, plus, plus)
        if (self.check(.plus) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .plus) {
            _ = self.advance();
            _ = self.advance();
            _ = try self.expect(.semicolon);
            const left = try self.allocator.create(ast.Expression);
            left.* = .{ .identifier = name_tok.value };
            const right = try self.allocator.create(ast.Expression);
            right.* = .{ .int_literal = 1 };
            return ast.Statement{
                .assign = .{
                    .name = name_tok.value,
                    .value = ast.Expression{ .binary_op = .{ .op = .plus, .left = left, .right = right } },
                },
            };
        }

        // Decrement: name-- (tokenized as identifier, minus, minus)
        if (self.check(.minus) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .minus) {
            _ = self.advance();
            _ = self.advance();
            _ = try self.expect(.semicolon);
            const left = try self.allocator.create(ast.Expression);
            left.* = .{ .identifier = name_tok.value };
            const right = try self.allocator.create(ast.Expression);
            right.* = .{ .int_literal = 1 };
            return ast.Statement{
                .assign = .{
                    .name = name_tok.value,
                    .value = ast.Expression{ .binary_op = .{ .op = .minus, .left = left, .right = right } },
                },
            };
        }

        // Function call: name(args);
        if (self.check(.l_paren)) {
            _ = self.advance();
            var args = std.ArrayList(ast.Expression).init(self.allocator);
            if (!self.check(.r_paren)) {
                try args.append(try self.parseExpression());
                while (self.check(.comma)) {
                    _ = self.advance();
                    try args.append(try self.parseExpression());
                }
            }
            _ = try self.expect(.r_paren);
            var expr = ast.Expression{
                .call = .{ .name = name_tok.value, .args = try args.toOwnedSlice() },
            };
            expr = try self.parsePostfix(expr);
            _ = try self.expect(.semicolon);
            return ast.Statement{ .expr_stmt = expr };
        }

        // Field access, array index, or plain identifier expression statement
        var expr = ast.Expression{ .identifier = name_tok.value };
        expr = try self.parsePostfix(expr);
        _ = try self.expect(.semicolon);
        return ast.Statement{ .expr_stmt = expr };
    }

    fn parseGoStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_go);
        const body = try self.parseBlock();
        _ = self.match(.semicolon); // optional semicolon after go block
        const body_ptr = try self.allocator.create(ast.Statement);
        body_ptr.* = body;
        return ast.Statement{ .go_stmt = body_ptr };
    }

    fn parseForLoop(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_for);
        _ = try self.expect(.l_paren);

        // Detect for-each: for (Type name : iterable) { ... }
        // Lookahead: type keyword, then identifier, then colon
        if (self.isTypeStart() and self.pos + 2 < self.tokens.len and
            (self.tokens[self.pos + 1].typ == .identifier or self.tokens[self.pos + 1].typ == .keyword_main) and
            self.tokens[self.pos + 2].typ == .colon)
        {
            const elem_type = try self.parseType();
            const name_tok = try self.parseName();
            _ = try self.expect(.colon);
            const iterable = try self.parseExpression();
            _ = try self.expect(.r_paren);
            const body = try self.parseBlock();
            const body_ptr = try self.allocator.create(ast.Statement);
            body_ptr.* = body;
            return ast.Statement{
                .for_each = .{ .elem_type = elem_type, .elem_name = name_tok.value, .iterable = iterable, .body = body_ptr },
            };
        }

        // Traditional for loop: for (init; cond; inc) { ... }
        // Parse init
        var loop_init: ?*ast.Statement = null;
        if (!self.check(.semicolon)) {
            if (self.isTypeStart()) {
                const typ = try self.parseType();
                const name_tok = try self.parseName();
                _ = try self.expect(.eq);
                const value = try self.parseExpression();
                const init_stmt = try self.allocator.create(ast.Statement);
                init_stmt.* = ast.Statement{
                    .var_decl = .{ .typ = typ, .name = name_tok.value, .init = value },
                };
                loop_init = init_stmt;
            } else if (self.check(.identifier)) {
                const name_tok = self.advance();
                _ = try self.expect(.eq);
                const value = try self.parseExpression();
                const init_stmt = try self.allocator.create(ast.Statement);
                init_stmt.* = ast.Statement{
                    .assign = .{ .name = name_tok.value, .value = value },
                };
                loop_init = init_stmt;
            }
        }
        _ = try self.expect(.semicolon);

        // Parse condition
        var cond: ?ast.Expression = null;
        if (!self.check(.semicolon)) {
            cond = try self.parseExpression();
        }
        _ = try self.expect(.semicolon);

        // Parse increment
        var inc: ?*ast.Statement = null;
        if (!self.check(.r_paren)) {
            if (self.check(.identifier)) {
                const name_tok = self.advance();
                // i++
                if (self.check(.plus) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .plus) {
                    _ = self.advance();
                    _ = self.advance();
                    const left = try self.allocator.create(ast.Expression);
                    left.* = .{ .identifier = name_tok.value };
                    const right = try self.allocator.create(ast.Expression);
                    right.* = .{ .int_literal = 1 };
                    const inc_stmt = try self.allocator.create(ast.Statement);
                    inc_stmt.* = ast.Statement{
                        .assign = .{
                            .name = name_tok.value,
                            .value = ast.Expression{ .binary_op = .{ .op = .plus, .left = left, .right = right } },
                        },
                    };
                    inc = inc_stmt;
                }
                // i--
                else if (self.check(.minus) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].typ == .minus) {
                    _ = self.advance();
                    _ = self.advance();
                    const left = try self.allocator.create(ast.Expression);
                    left.* = .{ .identifier = name_tok.value };
                    const right = try self.allocator.create(ast.Expression);
                    right.* = .{ .int_literal = 1 };
                    const inc_stmt = try self.allocator.create(ast.Statement);
                    inc_stmt.* = ast.Statement{
                        .assign = .{
                            .name = name_tok.value,
                            .value = ast.Expression{ .binary_op = .{ .op = .minus, .left = left, .right = right } },
                        },
                    };
                    inc = inc_stmt;
                }
                // i = expr
                else if (self.check(.eq)) {
                    _ = self.advance();
                    const value = try self.parseExpression();
                    const inc_stmt = try self.allocator.create(ast.Statement);
                    inc_stmt.* = ast.Statement{
                        .assign = .{ .name = name_tok.value, .value = value },
                    };
                    inc = inc_stmt;
                }
            }
        }
        _ = try self.expect(.r_paren);

        // Parse body
        const body = try self.parseBlock();
        const body_ptr = try self.allocator.create(ast.Statement);
        body_ptr.* = body;

        return ast.Statement{
            .for_loop = .{ .init = loop_init, .cond = cond, .inc = inc, .body = body_ptr },
        };
    }

    fn parseWhileLoop(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_while);
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);

        const body = try self.parseBlock();
        const body_ptr = try self.allocator.create(ast.Statement);
        body_ptr.* = body;

        return ast.Statement{
            .while_loop = .{ .cond = cond, .body = body_ptr },
        };
    }

    fn parseIfStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_if);
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);

        const then_branch = try self.parseBlock();
        const then_ptr = try self.allocator.create(ast.Statement);
        then_ptr.* = then_branch;

        var else_br: ?*ast.Statement = null;
        if (self.check(.keyword_else)) {
            _ = self.advance();
            if (self.check(.keyword_if)) {
                const else_stmt = try self.parseIfStmt();
                const else_ptr = try self.allocator.create(ast.Statement);
                else_ptr.* = else_stmt;
                else_br = else_ptr;
            } else {
                const else_stmt = try self.parseBlock();
                const else_ptr = try self.allocator.create(ast.Statement);
                else_ptr.* = else_stmt;
                else_br = else_ptr;
            }
        }

        return ast.Statement{
            .if_stmt = .{ .cond = cond, .then_branch = then_ptr, .else_branch = else_br },
        };
    }

    fn parseReturnStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_return);
        var expr: ?ast.Expression = null;
        if (!self.check(.semicolon)) {
            expr = try self.parseExpression();
        }
        _ = try self.expect(.semicolon);
        return ast.Statement{ .return_stmt = expr };
    }

    fn parseBreakStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_break);
        _ = try self.expect(.semicolon);
        return ast.Statement{ .break_stmt = {} };
    }

    fn parseContinueStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_continue);
        _ = try self.expect(.semicolon);
        return ast.Statement{ .continue_stmt = {} };
    }

    fn parseThrowStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_throw);
        const expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        return ast.Statement{ .throw_stmt = expr };
    }

    fn parseTryStmt(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_try);
        const try_block = try self.parseBlock();
        const try_ptr = try self.allocator.create(ast.Statement);
        try_ptr.* = try_block;

        // catch(string e) { ... }
        _ = try self.expect(.keyword_catch);
        _ = try self.expect(.l_paren);
        _ = try self.expect(.keyword_string);
        const catch_var_tok = try self.expect(.identifier);
        _ = try self.expect(.r_paren);
        const catch_block = try self.parseBlock();
        const catch_ptr = try self.allocator.create(ast.Statement);
        catch_ptr.* = catch_block;

        // finally { ... } (optional)
        var finally_ptr: ?*ast.Statement = null;
        if (self.check(.keyword_finally)) {
            _ = self.advance();
            const finally_block = try self.parseBlock();
            finally_ptr = try self.allocator.create(ast.Statement);
            finally_ptr.?.* = finally_block;
        }

        return ast.Statement{
            .try_stmt = .{
                .try_block = try_ptr,
                .catch_var = catch_var_tok.value,
                .catch_block = catch_ptr,
                .finally_block = finally_ptr,
            },
        };
    }

    fn parseThisAssignOrExpr(self: *Parser) anyerror!ast.Statement {
        _ = try self.expect(.keyword_this);
        _ = try self.expect(.dot);
        const field = try self.parseName();
        // this.field = expr;
        if (self.check(.eq)) {
            _ = self.advance();
            const value = try self.parseExpression();
            _ = try self.expect(.semicolon);
            return ast.Statement{ .this_assign = .{ .field = field.value, .value = value } };
        }
        // this.field as expression (or this.field.method() etc.)
        var expr = ast.Expression{ .this_ref = {} };
        const obj = try self.allocator.create(ast.Expression);
        obj.* = expr;
        expr = ast.Expression{ .field_access = .{ .object = obj, .field = field.value } };
        expr = try self.parsePostfix(expr);
        _ = try self.expect(.semicolon);
        return ast.Statement{ .expr_stmt = expr };
    }

    fn parsePrintStmt(self: *Parser) anyerror!ast.Statement {
        const is_newline = self.check(.keyword_println);
        _ = self.advance();
        _ = try self.expect(.l_paren);
        const expr = try self.parseExpression();
        _ = try self.expect(.r_paren);
        _ = try self.expect(.semicolon);
        return ast.Statement{
            .print_stmt = .{ .expr = expr, .newline = is_newline },
        };
    }

    // ---- Method / Class / Program parsing ----

    fn parseMethod(self: *Parser) anyerror!ast.Method {
        // Skip modifiers (public, static)
        while (self.check(.keyword_public) or self.check(.keyword_static)) {
            _ = self.advance();
        }
        const return_type = try self.parseType();
        const name_tok = try self.parseName();

        _ = try self.expect(.l_paren);
        var params = std.ArrayList(ast.Param).init(self.allocator);
        if (!self.check(.r_paren)) {
            const param_type = try self.parseType();
            const param_name = try self.parseName();
            try params.append(.{ .typ = param_type, .name = param_name.value });
            while (self.check(.comma)) {
                _ = self.advance();
                const pt = try self.parseType();
                const pn = try self.parseName();
                try params.append(.{ .typ = pt, .name = pn.value });
            }
        }
        _ = try self.expect(.r_paren);

        const body = try self.parseBlock();

        return ast.Method{
            .name = name_tok.value,
            .return_type = return_type,
            .params = try params.toOwnedSlice(),
            .body = body,
        };
    }

    fn parseClass(self: *Parser) anyerror!ast.Class {
        // Skip modifiers before class
        while (self.check(.keyword_public) or self.check(.keyword_static)) {
            _ = self.advance();
        }
        _ = try self.expect(.keyword_class);
        const name_tok = try self.parseName();
        _ = try self.expect(.l_brace);

        var fields = std.ArrayList(ast.FieldDecl).init(self.allocator);
        var methods = std.ArrayList(ast.Method).init(self.allocator);
        while (!self.check(.r_brace) and !self.isAtEnd()) {
            // Field declaration: type name; (no `(` after name)
            // Method declaration: type name( (has `(` after name/modifiers)
            // We need lookahead to distinguish fields from methods
            // Save position for backtracking
            const saved_pos = self.pos;
            // Skip modifiers
            while (self.check(.keyword_public) or self.check(.keyword_static)) {
                _ = self.advance();
            }
            if (self.isTypeStart() or self.check(.identifier)) {
                _ = try self.parseType(); // consume type
                if (self.check(.identifier) or self.check(.keyword_main)) {
                    _ = self.advance(); // consume name
                    if (self.check(.l_paren)) {
                        // It's a method — restore position and parse as method
                        self.pos = saved_pos;
                        try methods.append(try self.parseMethod());
                    } else {
                        // It's a field — restore position and parse field
                        self.pos = saved_pos;
                        // Skip modifiers again
                        while (self.check(.keyword_public) or self.check(.keyword_static)) {
                            _ = self.advance();
                        }
                        const field_type = try self.parseType();
                        const field_name = try self.parseName();
                        _ = try self.expect(.semicolon);
                        try fields.append(.{ .typ = field_type, .name = field_name.value });
                    }
                } else {
                    self.pos = saved_pos;
                    try methods.append(try self.parseMethod());
                }
            } else {
                self.pos = saved_pos;
                try methods.append(try self.parseMethod());
            }
        }
        _ = try self.expect(.r_brace);

        return ast.Class{
            .name = name_tok.value,
            .fields = try fields.toOwnedSlice(),
            .methods = try methods.toOwnedSlice(),
        };
    }

    /// Entry point: parse the entire program into an AST
    pub fn parse(self: *Parser) anyerror!ast.Program {
        var classes = std.ArrayList(ast.Class).init(self.allocator);
        while (!self.isAtEnd()) {
            // Skip import statements — they're handled by main.zig before parsing
            if (self.check(.keyword_import)) {
                _ = self.advance(); // skip 'import'
                if (self.check(.identifier)) _ = self.advance(); // skip module name
                if (self.check(.semicolon)) _ = self.advance(); // skip ;
                continue;
            }
            try classes.append(try self.parseClass());
        }
        return ast.Program{
            .classes = try classes.toOwnedSlice(),
        };
    }
};
