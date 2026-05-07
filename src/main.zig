const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const interpreter = @import("interpreter.zig");
const compiler = @import("compiler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: joya <file.joya> [--compile <output.o>] [--emit-ir <output.ll>] [--target <triple>]\n", .{});
        return;
    }

    const file_path = args[1];

    // Parse CLI flags
    var compile_output: ?[]const u8 = null;
    var emit_ir_output: ?[]const u8 = null;
    var target_triple: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--compile")) {
            i += 1;
            if (i < args.len) compile_output = args[i];
        } else if (std.mem.eql(u8, args[i], "--emit-ir")) {
            i += 1;
            if (i < args.len) emit_ir_output = args[i];
        } else if (std.mem.eql(u8, args[i], "--target")) {
            i += 1;
            if (i < args.len) target_triple = args[i];
        }
        i += 1;
    }

    std.debug.print("=== Joya: reading {s} ===\n", .{file_path});

    // Parse arena — freed after program runs
    var parser_arena = std.heap.ArenaAllocator.init(allocator);
    defer parser_arena.deinit();
    const arena = parser_arena.allocator();

    // Collect all classes from the main file and its imports
    var all_classes = std.ArrayList(ast.Class).init(arena);
    defer all_classes.deinit();

    // Track which files have been imported to avoid cycles
    var imported = std.StringHashMap(void).init(arena);
    defer imported.deinit();

    // Collect imported source buffers — freed after program runs
    var import_sources = std.ArrayList([]const u8).init(allocator);
    defer {
        for (import_sources.items) |src| allocator.free(src);
        import_sources.deinit();
    }

    // Parse the main file and collect imports
    const main_source = try readFile(allocator, file_path);
    defer allocator.free(main_source);

    var main_lex = try lexer.Lexer.init(allocator, main_source);
    defer main_lex.deinit();
    try main_lex.tokenize();
    std.debug.print("Lexed {} tokens\n", .{main_lex.tokens.items.len});

    // Scan for import statements before parsing
    var import_names = std.ArrayList([]const u8).init(arena);
    defer import_names.deinit();

    var ti: usize = 0;
    const tokens = main_lex.tokens.items;
    while (ti < tokens.len) {
        if (tokens[ti].typ == .keyword_import) {
            ti += 1;
            if (ti < tokens.len and tokens[ti].typ == .identifier) {
                try import_names.append(tokens[ti].value);
                ti += 1;
                if (ti < tokens.len and tokens[ti].typ == .semicolon) {
                    ti += 1;
                }
            }
        } else {
            ti += 1;
        }
    }

    // Parse imports first
    const base_dir = try extractDirectory(allocator, file_path);
    defer allocator.free(base_dir);

    var search_paths = std.ArrayList([]const u8).init(arena);
    try search_paths.append(base_dir);
    const lib_dir = try std.fmt.allocPrint(arena, "{s}lib/", .{base_dir});
    try search_paths.append(lib_dir);

    for (import_names.items) |name| {
        try processImport(allocator, arena, name, search_paths.items, &all_classes, &imported, &import_sources);
    }

    // Parse the main file
    var main_parse = try parser.Parser.init(arena, main_lex.tokens.items);
    defer main_parse.deinit();
    const main_ast = try main_parse.parse();

    for (main_ast.classes) |class| {
        try all_classes.append(class);
    }

    const program = ast.Program{ .classes = try all_classes.toOwnedSlice() };

    // Compile mode
    if (compile_output) |output| {
        std.debug.print("Compiling to object file: {s}\n", .{output});
        try compiler.compileToObject(allocator, &program, output, target_triple);
        std.debug.print("Compilation successful!\n", .{});
        return;
    }

    if (emit_ir_output) |output| {
        std.debug.print("Emitting LLVM IR to: {s}\n", .{output});
        try compiler.compileToIR(allocator, &program, output, target_triple);
        std.debug.print("IR emission successful!\n", .{});
        return;
    }

    // Default: interpret mode
    std.debug.print("Parsed {} classes (from {} files), running interpreter...\n", .{ all_classes.items.len, 1 + imported.count() });
    try interpreter.run(allocator, program);
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 1024 * 1024);
}

fn extractDirectory(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    // Find the last '/' or '\' to get the directory
    var idx: ?usize = null;
    for (file_path, 0..) |ch, i| {
        if (ch == '/' or ch == '\\') idx = i;
    }
    if (idx) |end| {
        const dir = file_path[0 .. end + 1];
        return try allocator.dupe(u8, dir);
    }
    return try allocator.dupe(u8, "./");
}

fn processImport(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    module_name: []const u8,
    search_paths: []const []const u8,
    all_classes: *std.ArrayList(ast.Class),
    imported: *std.StringHashMap(void),
    import_sources: *std.ArrayList([]const u8),
) !void {
    // Avoid duplicate imports and cycles
    if (imported.get(module_name) != null) return;
    try imported.put(module_name, {});

    // Construct file path: search_path + module_name + ".joya"
    const suffix = ".joya";
    var source: ?[]const u8 = null;
    var found_path: ?[]const u8 = null;

    for (search_paths) |sp| {
        const path_len = sp.len + module_name.len + suffix.len;
        const path = try allocator.alloc(u8, path_len);
        @memcpy(path[0..sp.len], sp);
        @memcpy(path[sp.len .. sp.len + module_name.len], module_name);
        @memcpy(path[sp.len + module_name.len ..], suffix);

        if (readFile(allocator, path)) |src| {
            source = src;
            found_path = path;
            break;
        } else |_| {
            allocator.free(path);
        }
    }

    if (source == null) {
        std.debug.print("Error: cannot import '{s}' — file not found in search paths\n", .{module_name});
        return error.FileNotFound;
    }

    const path = found_path.?;
    defer allocator.free(path);

    // Track source buffer — will be freed in main() after interpreter runs
    const src = source.?;
    try import_sources.append(src);

    std.debug.print("  Importing: {s}\n", .{path});

    var lex = try lexer.Lexer.init(allocator, src);
    defer lex.deinit();
    try lex.tokenize();

    // Scan for nested imports in this file
    var nested_imports = std.ArrayList([]const u8).init(arena);
    defer nested_imports.deinit();

    var i: usize = 0;
    const tokens = lex.tokens.items;
    while (i < tokens.len) {
        if (tokens[i].typ == .keyword_import) {
            i += 1;
            if (i < tokens.len and tokens[i].typ == .identifier) {
                try nested_imports.append(tokens[i].value);
                i += 1;
                if (i < tokens.len and tokens[i].typ == .semicolon) {
                    i += 1;
                }
            }
        } else {
            i += 1;
        }
    }

    // Process nested imports first
    for (nested_imports.items) |nested| {
        try processImport(allocator, arena, nested, search_paths, all_classes, imported, import_sources);
    }

    // Parse this imported file
    var parse = try parser.Parser.init(arena, lex.tokens.items);
    defer parse.deinit();
    const ast_tree = try parse.parse();

    for (ast_tree.classes) |class| {
        try all_classes.append(class);
    }
}
