const std = @import("std");

pub const TokenType = enum {
    keyword_public,
    keyword_class,
    keyword_static,
    keyword_void,
    keyword_main,
    keyword_int,
    keyword_string,
    keyword_bool,
    keyword_float,
    keyword_chan,
    keyword_go,
    keyword_for,
    keyword_if,
    keyword_else,
    keyword_return,
    keyword_new,
    keyword_send,
    keyword_receive,
    keyword_close,
    keyword_print,
    keyword_println,
    keyword_true,
    keyword_false,
    keyword_while,
    keyword_null,
    keyword_break,
    keyword_continue,
    keyword_this,
    keyword_map,
    keyword_try,
    keyword_catch,
    keyword_finally,
    keyword_throw,
    keyword_import,

    plus,
    minus,
    star,
    slash,
    percent,
    plus_eq,
    minus_eq,
    star_eq,
    slash_eq,
    percent_eq,
    eq,
    eq_eq,
    not_eq,
    bang,
    lt,
    gt,
    lt_eq,
    gt_eq,
    amp_amp,
    pipe_pipe,
    semicolon,
    l_brace,
    r_brace,
    l_paren,
    r_paren,
    l_bracket,
    r_bracket,
    comma,
    dot,
    colon,

    identifier,
    int_literal,
    float_literal,
    string_literal,

    eof,
};

pub const Token = struct {
    typ: TokenType,
    value: []const u8,
    line: usize,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    tokens: std.ArrayList(Token),

    const keywords = std.ComptimeStringMap(TokenType, .{
        .{ "public", .keyword_public },
        .{ "class", .keyword_class },
        .{ "static", .keyword_static },
        .{ "void", .keyword_void },
        .{ "main", .keyword_main },
        .{ "int", .keyword_int },
        .{ "string", .keyword_string },
        .{ "bool", .keyword_bool },
        .{ "float", .keyword_float },
        .{ "chan", .keyword_chan },
        .{ "go", .keyword_go },
        .{ "for", .keyword_for },
        .{ "if", .keyword_if },
        .{ "else", .keyword_else },
        .{ "return", .keyword_return },
        .{ "new", .keyword_new },
        .{ "send", .keyword_send },
        .{ "receive", .keyword_receive },
        .{ "close", .keyword_close },
        .{ "print", .keyword_print },
        .{ "println", .keyword_println },
        .{ "true", .keyword_true },
        .{ "false", .keyword_false },
        .{ "while", .keyword_while },
        .{ "null", .keyword_null },
        .{ "break", .keyword_break },
        .{ "continue", .keyword_continue },
        .{ "this", .keyword_this },
        .{ "map", .keyword_map },
        .{ "try", .keyword_try },
        .{ "catch", .keyword_catch },
        .{ "finally", .keyword_finally },
        .{ "throw", .keyword_throw },
        .{ "import", .keyword_import },
    });

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Lexer {
        return Lexer{
            .allocator = allocator,
            .source = source,
            .tokens = std.ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn next(self: *Lexer) ?u8 {
        const c = self.peek();
        if (c) |ch| {
            self.pos += 1;
            if (ch == '\n') self.line += 1;
            return ch;
        }
        return null;
    }

    fn skip_whitespace(self: *Lexer) void {
        while (self.peek()) |c| {
            if (std.ascii.isWhitespace(c)) {
                _ = self.next();
            } else {
                break;
            }
        }
    }

    fn read_identifier(self: *Lexer) []const u8 {
        const start = self.pos;
        while (self.peek()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                _ = self.next();
            } else {
                break;
            }
        }
        return self.source[start..self.pos];
    }

    fn read_number(self: *Lexer) TokenType {
        const start = self.pos;
        var is_float = false;
        while (self.peek()) |c| {
            if (std.ascii.isDigit(c)) {
                _ = self.next();
            } else if (c == '.' and !is_float) {
                is_float = true;
                _ = self.next();
            } else {
                break;
            }
        }
        _ = start;
        return if (is_float) .float_literal else .int_literal;
    }

    fn read_string(self: *Lexer) ![]const u8 {
        _ = self.next();
        const start = self.pos;
        while (self.peek()) |c| {
            if (c == '"') {
                const str = self.source[start..self.pos];
                _ = self.next();
                return str;
            } else if (c == '\\') {
                _ = self.next();
                _ = self.next();
            } else {
                _ = self.next();
            }
        }
        return error.UnterminatedString;
    }

    pub fn tokenize(self: *Lexer) !void {
        while (self.peek()) |_| {
            self.skip_whitespace();
            const c = self.peek() orelse break;

            if (std.ascii.isAlphabetic(c) or c == '_') {
                const ident = self.read_identifier();
                if (keywords.get(ident)) |typ| {
                    try self.tokens.append(.{
                        .typ = typ,
                        .value = ident,
                        .line = self.line,
                    });
                } else {
                    try self.tokens.append(.{
                        .typ = .identifier,
                        .value = ident,
                        .line = self.line,
                    });
                }
            } else if (std.ascii.isDigit(c)) {
                const start = self.pos;
                const typ = self.read_number();
                const value = self.source[start..self.pos];
                try self.tokens.append(.{
                    .typ = typ,
                    .value = value,
                    .line = self.line,
                });
            } else switch (c) {
                '"' => {
                    const str = try self.read_string();
                    try self.tokens.append(.{
                        .typ = .string_literal,
                        .value = str,
                        .line = self.line,
                    });
                },
                '+' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .plus_eq, .value = "+=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .plus, .value = "+", .line = self.line });
                    }
                },
                '-' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .minus_eq, .value = "-=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .minus, .value = "-", .line = self.line });
                    }
                },
                '*' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .star_eq, .value = "*=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .star, .value = "*", .line = self.line });
                    }
                },
                '/' => {
                    _ = self.next();
                    // Line comment //
                    if (self.peek() == '/') {
                        _ = self.next();
                        while (self.peek()) |ch| {
                            if (ch == '\n') break;
                            _ = self.next();
                        }
                    }
                    // Block comment /* ... */
                    else if (self.peek() == '*') {
                        _ = self.next();
                        var depth: usize = 1;
                        while (depth > 0) {
                            const ch = self.peek() orelse return error.UnterminatedComment;
                            if (ch == '/') {
                                _ = self.next();
                                if (self.peek() == '*') {
                                    _ = self.next();
                                    depth += 1;
                                }
                            } else if (ch == '*') {
                                _ = self.next();
                                if (self.peek() == '/') {
                                    _ = self.next();
                                    depth -= 1;
                                }
                            } else {
                                _ = self.next();
                            }
                        }
                    }
                    // Division assign /=
                    else if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .slash_eq, .value = "/=", .line = self.line });
                    }
                    // Division operator
                    else {
                        try self.tokens.append(.{ .typ = .slash, .value = "/", .line = self.line });
                    }
                },
                '=' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .eq_eq, .value = "==", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .eq, .value = "=", .line = self.line });
                    }
                },
                '!' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .not_eq, .value = "!=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .bang, .value = "!", .line = self.line });
                    }
                },
                '<' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .lt_eq, .value = "<=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .lt, .value = "<", .line = self.line });
                    }
                },
                '>' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .gt_eq, .value = ">=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .gt, .value = ">", .line = self.line });
                    }
                },
                ';' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .semicolon, .value = ";", .line = self.line });
                },
                '{' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .l_brace, .value = "{", .line = self.line });
                },
                '}' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .r_brace, .value = "}", .line = self.line });
                },
                '(' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .l_paren, .value = "(", .line = self.line });
                },
                ')' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .r_paren, .value = ")", .line = self.line });
                },
                '[' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .l_bracket, .value = "[", .line = self.line });
                },
                ']' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .r_bracket, .value = "]", .line = self.line });
                },
                ',' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .comma, .value = ",", .line = self.line });
                },
                '.' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .dot, .value = ".", .line = self.line });
                },
                ':' => {
                    _ = self.next();
                    try self.tokens.append(.{ .typ = .colon, .value = ":", .line = self.line });
                },
                '%' => {
                    _ = self.next();
                    if (self.peek() == '=') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .percent_eq, .value = "%=", .line = self.line });
                    } else {
                        try self.tokens.append(.{ .typ = .percent, .value = "%", .line = self.line });
                    }
                },
                '&' => {
                    _ = self.next();
                    if (self.peek() == '&') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .amp_amp, .value = "&&", .line = self.line });
                    } else {
                        std.debug.print("Invalid character: '&' (single & not supported, use &&) at line {}\n", .{self.line});
                        return error.InvalidCharacter;
                    }
                },
                '|' => {
                    _ = self.next();
                    if (self.peek() == '|') {
                        _ = self.next();
                        try self.tokens.append(.{ .typ = .pipe_pipe, .value = "||", .line = self.line });
                    } else {
                        std.debug.print("Invalid character: '|' (single | not supported, use ||) at line {}\n", .{self.line});
                        return error.InvalidCharacter;
                    }
                },
                else => {
                    std.debug.print("Invalid character: '{}' (0x{x}) at line {}\n", .{c, c, self.line});
                    return error.InvalidCharacter;
                },
            }
        }
        try self.tokens.append(.{ .typ = .eof, .value = "", .line = self.line });
    }
};
