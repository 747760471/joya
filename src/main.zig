const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const interpreter = @import("interpreter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: joya <file.joya>\n", .{});
        return;
    }

    const file_path = args[1];
    std.debug.print("=== Joya: reading {s} ===\n", .{file_path});

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    // 词法分析
    var lex = try lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    try lex.tokenize();

    std.debug.print("Lexed {} tokens\n", .{lex.tokens.items.len});

    // 语法分析 - 使用 ArenaAllocator，程序结束时一次性释放所有 AST 节点
    var parser_arena = std.heap.ArenaAllocator.init(allocator);
    defer parser_arena.deinit();

    var parse = try parser.Parser.init(parser_arena.allocator(), lex.tokens.items);
    defer parse.deinit();
    const ast_tree = try parse.parse();

    std.debug.print("Parsed {} classes, running interpreter...\n", .{ast_tree.classes.len});

    // 解释执行
    try interpreter.run(allocator, ast_tree);
}
