const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

// ============================================================================
// LLVM C API Bindings — manually declared externs for the functions we use
// ============================================================================

pub const LLVMBool = c_int;
pub const LLVMOpcode = c_uint;
pub const LLVMIntPredicate = c_uint;
pub const LLVMRealPredicate = c_uint;
pub const LLVMCodeGenOptLevel = c_uint;
pub const LLVMRelocMode = c_uint;
pub const LLVMCodeModel = c_uint;
pub const LLVMCodeGenFileType = c_uint;
pub const LLVMLinkage = c_uint;
pub const LLVMVisibility = c_uint;

pub const LLVMContextRef = ?*anyopaque;
pub const LLVMModuleRef = ?*anyopaque;
pub const LLVMTypeRef = ?*anyopaque;
pub const LLVMValueRef = ?*anyopaque;
pub const LLVMBasicBlockRef = ?*anyopaque;
pub const LLVMBuilderRef = ?*anyopaque;
pub const LLVMTargetMachineRef = ?*anyopaque;
pub const LLVMTargetDataRef = ?*anyopaque;
pub const LLVMTargetRef = ?*anyopaque;
pub const LLVMMemoryBufferRef = ?*anyopaque;
pub const LLVMAttributeRef = ?*anyopaque;

// ---- Context ----
pub extern fn LLVMContextCreate() LLVMContextRef;
pub extern fn LLVMContextDispose(C: LLVMContextRef) void;
pub extern fn LLVMGetGlobalContext() LLVMContextRef;

// ---- Module ----
pub extern fn LLVMModuleCreateWithName(ModuleID: [*:0]const u8) LLVMModuleRef;
pub extern fn LLVMModuleCreateWithNameInContext(ModuleID: [*:0]const u8, C: LLVMContextRef) LLVMModuleRef;
pub extern fn LLVMDisposeModule(M: LLVMModuleRef) void;
pub extern fn LLVMSetDataLayout(M: LLVMModuleRef, DataLayoutStr: [*:0]const u8) void;
pub extern fn LLVMSetTarget(M: LLVMModuleRef, Triple: [*:0]const u8) void;
pub extern fn LLVMDumpModule(M: LLVMModuleRef) void;
pub extern fn LLVMPrintModuleToFile(M: LLVMModuleRef, Filename: [*:0]const u8, ErrorMessage: *[*:0]u8) LLVMBool;
pub extern fn LLVMGetModuleContext(M: LLVMModuleRef) LLVMContextRef;

// ---- Types ----
pub extern fn LLVMVoidTypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMInt1TypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMInt8TypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMInt32TypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMInt64TypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMIntTypeInContext(C: LLVMContextRef, NumBits: c_uint) LLVMTypeRef;
pub extern fn LLVMFloatTypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMDoubleTypeInContext(C: LLVMContextRef) LLVMTypeRef;
pub extern fn LLVMPointerTypeInContext(C: LLVMContextRef, AddressSpace: c_uint) LLVMTypeRef;
pub extern fn LLVMPointerType(ElementType: LLVMTypeRef, AddressSpace: c_uint) LLVMTypeRef;
pub extern fn LLVMFunctionType(ReturnType: LLVMTypeRef, ParamTypes: [*]LLVMTypeRef, ParamCount: c_uint, IsVarArg: LLVMBool) LLVMTypeRef;
pub extern fn LLVMStructTypeInContext(C: LLVMContextRef, ElementTypes: [*]LLVMTypeRef, ElementCount: c_uint, Packed: LLVMBool) LLVMTypeRef;
pub extern fn LLVMStructCreateNamed(C: LLVMContextRef, Name: [*:0]const u8) LLVMTypeRef;
pub extern fn LLVMStructSetBody(StructTy: LLVMTypeRef, ElementTypes: [*]LLVMTypeRef, ElementCount: c_uint, Packed: LLVMBool) void;
pub extern fn LLVMArrayType2(ElementType: LLVMTypeRef, ElementCount: u64) LLVMTypeRef;

// ---- Constants ----
pub extern fn LLVMConstInt(IntTy: LLVMTypeRef, N: c_ulonglong, SignExtend: LLVMBool) LLVMValueRef;
pub extern fn LLVMConstReal(RealTy: LLVMTypeRef, N: f64) LLVMValueRef;
pub extern fn LLVMConstStringInContext2(C: LLVMContextRef, Str: [*]const u8, Length: usize, DontNullTerminate: LLVMBool) LLVMValueRef;
pub extern fn LLVMConstNull(Ty: LLVMTypeRef) LLVMValueRef;
pub extern fn LLVMConstPointerNull(Ty: LLVMTypeRef) LLVMValueRef;

// ---- Global Variables ----
pub extern fn LLVMAddGlobal(M: LLVMModuleRef, Ty: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMAddGlobalInAddressSpace(M: LLVMModuleRef, Ty: LLVMTypeRef, Name: [*:0]const u8, AddressSpace: c_uint) LLVMValueRef;
pub extern fn LLVMGetNamedGlobal(M: LLVMModuleRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMSetInitializer(GlobalVar: LLVMValueRef, ConstantVal: LLVMValueRef) void;
pub extern fn LLVMSetLinkage(GlobalVar: LLVMValueRef, Linkage: LLVMLinkage) void;
pub extern fn LLVMSetGlobalConstant(GlobalVar: LLVMValueRef, IsConstant: LLVMBool) void;

// ---- Functions ----
pub extern fn LLVMAddFunction(M: LLVMModuleRef, Name: [*:0]const u8, FunctionTy: LLVMTypeRef) LLVMValueRef;
pub extern fn LLVMGetNamedFunction(M: LLVMModuleRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMGetParam(Fn: LLVMValueRef, Index: c_uint) LLVMValueRef;
pub extern fn LLVMCountParams(Fn: LLVMValueRef) c_uint;
pub extern fn LLVMCountParamTypes(FunctionTy: LLVMTypeRef) c_uint;
pub extern fn LLVMGetParamTypes(FunctionTy: LLVMTypeRef, Dest: [*]LLVMTypeRef) void;
pub extern fn LLVMGetReturnType(FunctionTy: LLVMTypeRef) LLVMTypeRef;
pub extern fn LLVMDeleteFunction(Fn: LLVMValueRef) void;
pub extern fn LLVMGetEntryBasicBlock(Fn: LLVMValueRef) LLVMBasicBlockRef;

// ---- Basic Blocks ----
pub extern fn LLVMAppendBasicBlockInContext(C: LLVMContextRef, Fn: LLVMValueRef, Name: [*:0]const u8) LLVMBasicBlockRef;
pub extern fn LLVMCreateBasicBlockInContext(C: LLVMContextRef, Name: [*:0]const u8) LLVMBasicBlockRef;
pub extern fn LLVMDeleteBasicBlock(BB: LLVMBasicBlockRef) void;

// ---- Builder ----
pub extern fn LLVMCreateBuilderInContext(C: LLVMContextRef) LLVMBuilderRef;
pub extern fn LLVMDisposeBuilder(Builder: LLVMBuilderRef) void;
pub extern fn LLVMPositionBuilderAtEnd(Builder: LLVMBuilderRef, Block: LLVMBasicBlockRef) void;
pub extern fn LLVMGetInsertBlock(Builder: LLVMBuilderRef) LLVMBasicBlockRef;

// ---- Builder: Terminators ----
pub extern fn LLVMBuildRetVoid(Builder: LLVMBuilderRef) LLVMValueRef;
pub extern fn LLVMBuildRet(Builder: LLVMBuilderRef, V: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMBuildBr(Builder: LLVMBuilderRef, Dest: LLVMBasicBlockRef) LLVMValueRef;
pub extern fn LLVMBuildCondBr(Builder: LLVMBuilderRef, If: LLVMValueRef, Then: LLVMBasicBlockRef, Else: LLVMBasicBlockRef) LLVMValueRef;

// ---- Builder: Arithmetic ----
pub extern fn LLVMBuildAdd(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildFAdd(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildSub(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildFSub(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildMul(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildFMul(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildSDiv(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildFDiv(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildSRem(Builder: LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;

// ---- Builder: Comparisons ----
pub extern fn LLVMBuildICmp(Builder: LLVMBuilderRef, Op: LLVMIntPredicate, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildFCmp(Builder: LLVMBuilderRef, Op: LLVMRealPredicate, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;

// ---- Builder: Memory ----
pub extern fn LLVMBuildAlloca(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildStore(Builder: LLVMBuilderRef, Val: LLVMValueRef, Ptr: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMBuildLoad2(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Ptr: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildGEP2(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Ptr: LLVMValueRef, Indices: [*]LLVMValueRef, NumIndices: c_uint, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildStructGEP2(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Ptr: LLVMValueRef, Idx: c_uint, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildGlobalString(Builder: LLVMBuilderRef, Str: [*:0]const u8, Name: [*:0]const u8) LLVMValueRef;

// ---- Builder: Calls ----
pub extern fn LLVMBuildCall2(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Fn: LLVMValueRef, Args: [*]LLVMValueRef, NumArgs: c_uint, Name: [*:0]const u8) LLVMValueRef;

// ---- Builder: Casts ----
pub extern fn LLVMBuildSIToFP(Builder: LLVMBuilderRef, Val: LLVMValueRef, DestTy: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildFPToSI(Builder: LLVMBuilderRef, Val: LLVMValueRef, DestTy: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildZExt(Builder: LLVMBuilderRef, Val: LLVMValueRef, DestTy: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildTrunc(Builder: LLVMBuilderRef, Val: LLVMValueRef, DestTy: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildBitCast(Builder: LLVMBuilderRef, Val: LLVMValueRef, DestTy: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;

// ---- Builder: Other ----
pub extern fn LLVMBuildNot(Builder: LLVMBuilderRef, V: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildSelect(Builder: LLVMBuilderRef, If: LLVMValueRef, Then: LLVMValueRef, Else: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildPhi(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMAddIncoming(PhiNode: LLVMValueRef, IncomingValues: [*]LLVMValueRef, IncomingBlocks: [*]LLVMBasicBlockRef, Count: c_uint) void;

// ---- Target/TargetMachine ----
pub extern fn LLVMGetDefaultTargetTriple() [*:0]u8;
pub extern fn LLVMGetHostCPUName() [*:0]u8;
pub extern fn LLVMGetHostCPUFeatures() [*:0]u8;
pub extern fn LLVMGetTargetFromTriple(Triple: [*:0]const u8, T: *LLVMTargetRef, ErrorMessage: *[*:0]u8) LLVMBool;
pub extern fn LLVMCreateTargetMachine(T: LLVMTargetRef, Triple: [*:0]const u8, CPU: [*:0]const u8, Features: [*:0]const u8, Level: LLVMCodeGenOptLevel, Reloc: LLVMRelocMode, CodeModel: LLVMCodeModel) LLVMTargetMachineRef;
pub extern fn LLVMDisposeTargetMachine(T: LLVMTargetMachineRef) void;
pub extern fn LLVMCreateTargetDataLayout(T: LLVMTargetMachineRef) LLVMTargetDataRef;
pub extern fn LLVMTargetMachineEmitToFile(T: LLVMTargetMachineRef, M: LLVMModuleRef, Filename: [*:0]const u8, CodeGen: LLVMCodeGenFileType, ErrorMessage: *[*:0]u8) LLVMBool;
pub extern fn LLVMDisposeTargetData(TD: LLVMTargetDataRef) void;

// ---- Initialization (must call for each target backend) ----
pub extern fn LLVMInitializeX86TargetInfo() void;
pub extern fn LLVMInitializeX86Target() void;
pub extern fn LLVMInitializeX86TargetMC() void;
pub extern fn LLVMInitializeX86AsmPrinter() void;
pub extern fn LLVMInitializeX86AsmParser() void;
pub extern fn LLVMInitializeAArch64TargetInfo() void;
pub extern fn LLVMInitializeAArch64Target() void;
pub extern fn LLVMInitializeAArch64TargetMC() void;
pub extern fn LLVMInitializeAArch64AsmPrinter() void;

// ---- Utility ----
pub extern fn LLVMShutdown() void;
pub extern fn LLVMDisposeMessage(Message: [*:0]u8) void;
pub extern fn LLVMTypeOf(Val: LLVMValueRef) LLVMTypeRef;

// ---- Linkage constants ----
pub const LLVMExternalLinkage: LLVMLinkage = 0;
pub const LLVMPrivateLinkage: LLVMLinkage = 3;
pub const LLVMInternalLinkage: LLVMLinkage = 4;

// ---- CodeGenFileType constants ----
pub const LLVMAssemblyFile: LLVMCodeGenFileType = 0;
pub const LLVMObjectFile: LLVMCodeGenFileType = 1;

// ---- CodeGenOptLevel ----
pub const LLVMCodeGenLevelNone: LLVMCodeGenOptLevel = 0;
pub const LLVMCodeGenLevelLess: LLVMCodeGenOptLevel = 1;
pub const LLVMCodeGenLevelDefault: LLVMCodeGenOptLevel = 2;
pub const LLVMCodeGenLevelAggressive: LLVMCodeGenOptLevel = 3;

// ---- RelocMode ----
pub const LLVMRelocDefault: LLVMRelocMode = 0;
pub const LLVMRelocStatic: LLVMRelocMode = 1;
pub const LLVMRelocPIC: LLVMRelocMode = 2;
pub const LLVMRelocDynamicNoPic: LLVMRelocMode = 3;

// ---- CodeModel ----
pub const LLVMCodeModelDefault: LLVMCodeModel = 0;
pub const LLVMCodeModelJITDefault: LLVMCodeModel = 1;
pub const LLVMCodeModelSmall: LLVMCodeModel = 2;
pub const LLVMCodeModelKernel: LLVMCodeModel = 3;
pub const LLVMCodeModelMedium: LLVMCodeModel = 4;
pub const LLVMCodeModelLarge: LLVMCodeModel = 5;

// ---- IntPredicate ----
pub const LLVMIntEQ: LLVMIntPredicate = 32;
pub const LLVMIntNE: LLVMIntPredicate = 33;
pub const LLVMIntUGT: LLVMIntPredicate = 34;
pub const LLVMIntUGE: LLVMIntPredicate = 35;
pub const LLVMIntULT: LLVMIntPredicate = 36;
pub const LLVMIntULE: LLVMIntPredicate = 37;
pub const LLVMIntSGT: LLVMIntPredicate = 38;
pub const LLVMIntSGE: LLVMIntPredicate = 39;
pub const LLVMIntSLT: LLVMIntPredicate = 40;
pub const LLVMIntSLE: LLVMIntPredicate = 41;

// ---- RealPredicate ----
pub const LLVMRealOEQ: LLVMRealPredicate = 16;
pub const LLVMRealONE: LLVMRealPredicate = 17;
pub const LLVMRealOLT: LLVMRealPredicate = 18;
pub const LLVMRealOLE: LLVMRealPredicate = 19;
pub const LLVMRealOGT: LLVMRealPredicate = 20;
pub const LLVMRealOGE: LLVMRealPredicate = 21;

// ============================================================================
// Compiler — compiles Joya AST to native code via LLVM
// ============================================================================

pub const CompileError = error{
    LLMInitFailed,
    TargetNotFound,
    TargetMachineCreateFailed,
    EmitFailed,
    FileWriteFailed,
    UnexpectedType,
    UndefinedVariable,
    InvalidOperation,
    NoThisContext,
    UnsupportedFeature,
};

/// Helper: duplicate a []const u8 slice with a null terminator for C interop
fn dupeZAlloc(allocator: std.mem.Allocator, s: []const u8) ![:0]const u8 {
    const buf = try allocator.alloc(u8, s.len + 1);
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

/// Initialize LLVM target backends — must be called before compilation
pub fn initTargetBackends() void {
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeX86AsmParser();
    LLVMInitializeAArch64TargetInfo();
    LLVMInitializeAArch64Target();
    LLVMInitializeAArch64TargetMC();
    LLVMInitializeAArch64AsmPrinter();
}

/// Compile a Joya program to an object file
pub fn compileToObject(
    allocator: std.mem.Allocator,
    program: *const ast.Program,
    output_path: []const u8,
    target_triple: ?[]const u8,
) !void {
    // Arena for all compiler temporary allocations — freed as a batch after compilation
    var compiler_arena = std.heap.ArenaAllocator.init(allocator);
    defer compiler_arena.deinit();
    const comp_alloc = compiler_arena.allocator();

    initTargetBackends();

    const ctx = LLVMContextCreate() orelse return CompileError.LLMInitFailed;
    defer LLVMContextDispose(ctx);

    const module = LLVMModuleCreateWithNameInContext("joya_module", ctx) orelse return CompileError.LLMInitFailed;
    defer LLVMDisposeModule(module);

    // Set target triple
    var own_triple: ?[:0]const u8 = null;
    var llvm_triple: ?[*:0]u8 = null;

    if (target_triple) |tt| {
        own_triple = try dupeZAlloc(comp_alloc, tt);
    } else {
        llvm_triple = LLVMGetDefaultTargetTriple();
    }
    defer {
        if (llvm_triple) |lt| LLVMDisposeMessage(lt);
    }

    const triple_z: [*:0]const u8 = if (own_triple) |ot| ot.ptr else llvm_triple.?;
    LLVMSetTarget(module, triple_z);

    // Get target
    var err_msg: [*:0]u8 = undefined;
    var target: LLVMTargetRef = null;

    if (LLVMGetTargetFromTriple(triple_z, &target, &err_msg) != 0) {
        std.debug.print("LLVM Error: Failed to get target for triple '{s}': {s}\n", .{ triple_z, err_msg });
        return CompileError.TargetNotFound;
    }

    // Create target machine
    const cpu_name = LLVMGetHostCPUName();
    defer LLVMDisposeMessage(cpu_name);
    const cpu_features = LLVMGetHostCPUFeatures();
    defer LLVMDisposeMessage(cpu_features);

    const target_machine = LLVMCreateTargetMachine(
        target,
        triple_z,
        cpu_name,
        cpu_features,
        LLVMCodeGenLevelDefault,
        LLVMRelocPIC,
        LLVMCodeModelDefault,
    ) orelse return CompileError.TargetMachineCreateFailed;
    defer LLVMDisposeTargetMachine(target_machine);

    // Set data layout from target machine
    const data_layout = LLVMCreateTargetDataLayout(target_machine);
    defer LLVMDisposeTargetData(data_layout);
    const dl_str = LLVMCopyStringRepOfTargetData(data_layout);
    defer LLVMDisposeMessage(dl_str);
    LLVMSetDataLayout(module, dl_str);

    // ---- Compile the program ----
    var compiler = Compiler{
        .allocator = comp_alloc,
        .ctx = ctx,
        .module = module,
        .builder = null,
        .variables = std.StringHashMap(LLVMValueRef).init(comp_alloc),
        .variable_types = std.StringHashMap(LLVMTypeRef).init(comp_alloc),
        .class_struct_types = std.StringHashMap(LLVMTypeRef).init(comp_alloc),
        .class_field_indices = std.StringHashMap(std.StringHashMap(u32)).init(comp_alloc),
    };
    defer compiler.variables.deinit();
    defer compiler.variable_types.deinit();
    defer compiler.class_struct_types.deinit();
    defer {
        var it = compiler.class_field_indices.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit();
        compiler.class_field_indices.deinit();
    }

    try compiler.compileProgram(program);

    // Emit to object file
    const output_z = try dupeZAlloc(comp_alloc, output_path);

    if (LLVMTargetMachineEmitToFile(target_machine, module, output_z.ptr, LLVMObjectFile, &err_msg) != 0) {
        std.debug.print("LLVM Error: Failed to emit object file: {s}\n", .{err_msg});
        return CompileError.EmitFailed;
    }
}

/// Compile a Joya program to LLVM IR text and write to file
pub fn compileToIR(
    allocator: std.mem.Allocator,
    program: *const ast.Program,
    output_path: []const u8,
    target_triple: ?[]const u8,
) !void {
    var compiler_arena = std.heap.ArenaAllocator.init(allocator);
    defer compiler_arena.deinit();
    const comp_alloc = compiler_arena.allocator();

    initTargetBackends();

    const ctx = LLVMContextCreate() orelse return CompileError.LLMInitFailed;
    defer LLVMContextDispose(ctx);

    const module = LLVMModuleCreateWithNameInContext("joya_module", ctx) orelse return CompileError.LLMInitFailed;
    defer LLVMDisposeModule(module);

    // Set target triple
    if (target_triple) |tt| {
        const z_tt = try dupeZAlloc(comp_alloc, tt);
        LLVMSetTarget(module, z_tt);
    } else {
        const triple = LLVMGetDefaultTargetTriple();
        LLVMSetTarget(module, triple);
        LLVMDisposeMessage(triple);
    }

    var compiler = Compiler{
        .allocator = comp_alloc,
        .ctx = ctx,
        .module = module,
        .builder = null,
        .variables = std.StringHashMap(LLVMValueRef).init(comp_alloc),
        .variable_types = std.StringHashMap(LLVMTypeRef).init(comp_alloc),
        .class_struct_types = std.StringHashMap(LLVMTypeRef).init(comp_alloc),
        .class_field_indices = std.StringHashMap(std.StringHashMap(u32)).init(comp_alloc),
    };
    defer compiler.variables.deinit();
    defer compiler.variable_types.deinit();
    defer compiler.class_struct_types.deinit();
    defer {
        var it = compiler.class_field_indices.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit();
        compiler.class_field_indices.deinit();
    }

    try compiler.compileProgram(program);

    // Print IR to file
    const output_z = try dupeZAlloc(comp_alloc, output_path);

    var err_msg: [*:0]u8 = undefined;
    if (LLVMPrintModuleToFile(module, output_z.ptr, &err_msg) != 0) {
        std.debug.print("LLVM Error: Failed to write IR: {s}\n", .{err_msg});
        return CompileError.FileWriteFailed;
    }
}

/// Dump LLVM IR to stdout (for debugging)
pub fn dumpIR(
    allocator: std.mem.Allocator,
    program: *const ast.Program,
    target_triple: ?[]const u8,
) !void {
    var compiler_arena = std.heap.ArenaAllocator.init(allocator);
    defer compiler_arena.deinit();
    const comp_alloc = compiler_arena.allocator();

    initTargetBackends();

    const ctx = LLVMContextCreate() orelse return CompileError.LLMInitFailed;
    defer LLVMContextDispose(ctx);

    const module = LLVMModuleCreateWithNameInContext("joya_module", ctx) orelse return CompileError.LLMInitFailed;
    defer LLVMDisposeModule(module);

    if (target_triple) |tt| {
        const z_tt = try dupeZAlloc(comp_alloc, tt);
        LLVMSetTarget(module, z_tt);
    } else {
        const triple = LLVMGetDefaultTargetTriple();
        LLVMSetTarget(module, triple);
        LLVMDisposeMessage(triple);
    }

    var compiler = Compiler{
        .allocator = comp_alloc,
        .ctx = ctx,
        .module = module,
        .builder = null,
        .variables = std.StringHashMap(LLVMValueRef).init(comp_alloc),
        .variable_types = std.StringHashMap(LLVMTypeRef).init(comp_alloc),
        .class_struct_types = std.StringHashMap(LLVMTypeRef).init(comp_alloc),
        .class_field_indices = std.StringHashMap(std.StringHashMap(u32)).init(comp_alloc),
    };
    defer compiler.variables.deinit();
    defer compiler.variable_types.deinit();
    defer compiler.class_struct_types.deinit();
    defer {
        var it = compiler.class_field_indices.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit();
        compiler.class_field_indices.deinit();
    }

    try compiler.compileProgram(program);
    LLVMDumpModule(module);
}

// ---- External function from llvm-c/Target.h ----
pub extern fn LLVMCopyStringRepOfTargetData(TD: LLVMTargetDataRef) [*:0]u8;

/// The core compiler struct
const Compiler = struct {
    allocator: std.mem.Allocator,
    ctx: LLVMContextRef,
    module: LLVMModuleRef,
    builder: LLVMBuilderRef,
    variables: std.StringHashMap(LLVMValueRef),
    variable_types: std.StringHashMap(LLVMTypeRef),
    current_function: LLVMValueRef = null,
    current_class_name: ?[]const u8 = null, // tracks which class we're compiling

    // LLVM types cached for convenience
    i1: LLVMTypeRef = null,
    i8: LLVMTypeRef = null,
    i8_ptr: LLVMTypeRef = null,
    i32: LLVMTypeRef = null,
    i64: LLVMTypeRef = null,
    f64: LLVMTypeRef = null,
    void_type: LLVMTypeRef = null,

    // Runtime function declarations (lazy-initialized)
    printf_type: LLVMTypeRef = null,
    printf_func: LLVMValueRef = null,
    malloc_type: LLVMTypeRef = null,
    malloc_func: LLVMValueRef = null,

    // Class type info: class_name → LLVM struct body type (not pointer)
    class_struct_types: std.StringHashMap(LLVMTypeRef),
    // Class field indices: class_name → (field_name → struct index)
    class_field_indices: std.StringHashMap(std.StringHashMap(u32)),

    const Self = @This();

    fn initTypes(self: *Self) void {
        self.i1 = LLVMInt1TypeInContext(self.ctx);
        self.i8 = LLVMInt8TypeInContext(self.ctx);
        self.i8_ptr = LLVMPointerTypeInContext(self.ctx, 0);
        self.i32 = LLVMInt32TypeInContext(self.ctx);
        self.i64 = LLVMInt64TypeInContext(self.ctx);
        self.f64 = LLVMDoubleTypeInContext(self.ctx);
        self.void_type = LLVMVoidTypeInContext(self.ctx);
    }

    fn ensurePrintf(self: *Self) LLVMValueRef {
        if (self.printf_func != null) return self.printf_func.?;

        // printf: i32 printf(i8*, ...)
        var printf_params = [_]LLVMTypeRef{self.i8_ptr};
        self.printf_type = LLVMFunctionType(self.i32, &printf_params, 1, 1);
        self.printf_func = LLVMAddFunction(self.module, "printf", self.printf_type.?);
        return self.printf_func.?;
    }

    fn ensureMalloc(self: *Self) LLVMValueRef {
        if (self.malloc_func != null) return self.malloc_func.?;

        // malloc: i8* malloc(i64 size)
        var malloc_params = [_]LLVMTypeRef{self.i64};
        self.malloc_type = LLVMFunctionType(self.i8_ptr, &malloc_params, 1, 0);
        self.malloc_func = LLVMAddFunction(self.module, "malloc", self.malloc_type.?);
        return self.malloc_func.?;
    }

    /// Declare LLVM struct types for all classes and track field indices
    fn declareClassTypes(self: *Self, program: *const ast.Program) !void {
        for (program.classes) |class| {
            if (class.fields.len == 0) continue;

            // Create named struct type for this class
            const class_name_z = try dupeZAlloc(self.allocator, class.name);
            const struct_type = LLVMStructCreateNamed(self.ctx, class_name_z.ptr);

            // Build field types array
            var field_types = std.ArrayList(LLVMTypeRef).init(self.allocator);
            defer field_types.deinit();

            // Build field name → index mapping
            var field_map = std.StringHashMap(u32).init(self.allocator);

            for (class.fields, 0..) |field, idx| {
                try field_types.append(self.joyaTypeToLLVM(field.typ));
                try field_map.put(field.name, @intCast(idx));
            }

            // Set struct body
            LLVMStructSetBody(struct_type, field_types.items.ptr, @intCast(field_types.items.len), 0);

            // Store the struct body type (not a pointer — in LLVM 20, pointers are opaque 'ptr')
            try self.class_struct_types.put(class.name, struct_type);
            try self.class_field_indices.put(class.name, field_map);
        }
    }

    fn compileProgram(self: *Self, program: *const ast.Program) !void {
        self.initTypes();

        // Declare the Joya runtime's print functions
        _ = self.ensurePrintf();
        _ = self.ensureMalloc();

        // First pass: declare LLVM struct types for all classes
        try self.declareClassTypes(program);

        // For each class, declare its methods as LLVM functions
        // First pass: declare all functions (forward declarations)
        for (program.classes) |class| {
            for (class.methods) |method| {
                try self.declareMethod(class.name, &method);
            }
        }

        // Second pass: compile all method bodies
        for (program.classes) |class| {
            for (class.methods) |method| {
                try self.compileMethod(class.name, &method);
            }
        }

        // If no classes/methods, create a simple main
        var has_main = false;
        for (program.classes) |class| {
            for (class.methods) |method| {
                if (std.mem.eql(u8, method.name, "main")) {
                    has_main = true;
                    break;
                }
            }
        }

        if (!has_main) {
            // Generate a trivial main that returns 0
            const main_type = LLVMFunctionType(self.i32, &[_]LLVMTypeRef{}, 0, 0);
            const main_func = LLVMAddFunction(self.module, "main", main_type);
            const entry = LLVMAppendBasicBlockInContext(self.ctx, main_func, "entry");
            const builder = LLVMCreateBuilderInContext(self.ctx);
            LLVMPositionBuilderAtEnd(builder, entry);
            _ = LLVMBuildRet(builder, LLVMConstInt(self.i32, 0, 0));
            LLVMDisposeBuilder(builder);
        }
    }

    fn mangleMethodName(allocator: std.mem.Allocator, class_name: []const u8, method_name: []const u8) ![:0]const u8 {
        // "{class_name}_{method_name}"
        const total_len = class_name.len + 1 + method_name.len;
        const buf = try allocator.alloc(u8, total_len + 1);
        @memcpy(buf[0..class_name.len], class_name);
        buf[class_name.len] = '_';
        @memcpy(buf[class_name.len + 1 .. total_len], method_name);
        buf[total_len] = 0;
        return buf[0..total_len :0];
    }

    fn declareMethod(self: *Self, class_name: []const u8, method: *const ast.Method) !void {
        const mangled = try mangleMethodName(self.allocator, class_name, method.name);

        // Determine if this is a static method (has type_params or is named "main")
        const is_static = method.type_params.len > 0 or std.mem.eql(u8, method.name, "main");

        // Build parameter types
        var param_types = std.ArrayList(LLVMTypeRef).init(self.allocator);
        defer param_types.deinit();

        if (!is_static) {
            // Instance methods get 'this' as first parameter (opaque ptr in LLVM 20)
            try param_types.append(self.i8_ptr);
        }

        for (method.params) |param| {
            try param_types.append(self.joyaTypeToLLVM(param.typ));
        }

        const ret_type = self.joyaTypeToLLVM(method.return_type);
        const func_type = LLVMFunctionType(ret_type, param_types.items.ptr, @intCast(param_types.items.len), 0);
        _ = LLVMAddFunction(self.module, mangled.ptr, func_type);
    }

    fn compileMethod(self: *Self, class_name: []const u8, method: *const ast.Method) !void {
        const mangled = try mangleMethodName(self.allocator, class_name, method.name);

        const func = LLVMGetNamedFunction(self.module, mangled.ptr) orelse return CompileError.UndefinedVariable;

        self.current_function = func;
        self.current_class_name = class_name;
        self.builder = LLVMCreateBuilderInContext(self.ctx);
        defer {
            LLVMDisposeBuilder(self.builder.?);
            self.builder = null;
        }

        const entry = LLVMAppendBasicBlockInContext(self.ctx, func, "entry");
        LLVMPositionBuilderAtEnd(self.builder.?, entry);

        // Clear variables for new scope
        self.variables.clearRetainingCapacity();
        self.variable_types.clearRetainingCapacity();

        const is_static = method.type_params.len > 0 or std.mem.eql(u8, method.name, "main");

        // Bind parameters to alloca
        var param_idx: c_uint = 0;
        if (!is_static) {
            // 'this' parameter (opaque ptr in LLVM 20)
            const this_val = LLVMGetParam(func, 0);
            const this_alloca = LLVMBuildAlloca(self.builder.?, self.i8_ptr, "this");
            _ = LLVMBuildStore(self.builder.?, this_val, this_alloca);
            try self.variables.put("this", this_alloca);
            try self.variable_types.put("this", self.i8_ptr);
            param_idx = 1;
        }

        for (method.params) |param| {
            const param_val = LLVMGetParam(func, param_idx);
            const name_z = try dupeZAlloc(self.allocator, param.name);
            const param_llvm_type = self.joyaTypeToLLVM(param.typ);
            const alloca = LLVMBuildAlloca(self.builder.?, param_llvm_type, name_z.ptr);
            _ = LLVMBuildStore(self.builder.?, param_val, alloca);
            try self.variables.put(param.name, alloca);
            try self.variable_types.put(param.name, param_llvm_type);
            param_idx += 1;
        }

        // Compile method body
        try self.compileStatement(&method.body);

        // Add implicit return if the block doesn't already terminate
        // (LLVM requires every block to end with a terminator)
        const last_block = LLVMGetInsertBlock(self.builder.?);
        const term = LLVMGetBasicBlockTerminator(last_block);
        if (term == null) {
            const ret_type = self.joyaTypeToLLVM(method.return_type);
            if (ret_type == self.void_type) {
                _ = LLVMBuildRetVoid(self.builder.?);
            } else {
                // Return zero/null for the type
                const zero = LLVMConstNull(ret_type);
                _ = LLVMBuildRet(self.builder.?, zero);
            }
        }
    }

    fn compileStatement(self: *Self, stmt: *const ast.Statement) !void {
        switch (stmt.*) {
            .var_decl => |vd| {
                const llvm_type = self.joyaTypeToLLVM(vd.typ);
                const name_z = try dupeZAlloc(self.allocator, vd.name);
                const alloca = LLVMBuildAlloca(self.builder.?, llvm_type, name_z.ptr);

                if (vd.init) |init_expr| {
                    const init_val = try self.compileExpression(init_expr);
                    _ = LLVMBuildStore(self.builder.?, init_val, alloca);
                } else {
                    // Initialize to zero/null
                    const zero = LLVMConstNull(llvm_type);
                    _ = LLVMBuildStore(self.builder.?, zero, alloca);
                }

                try self.variables.put(vd.name, alloca);
                try self.variable_types.put(vd.name, llvm_type);
            },

            .assign => |as| {
                const val = try self.compileExpression(as.value);
                const alloca = self.variables.get(as.name) orelse return CompileError.UndefinedVariable;
                _ = LLVMBuildStore(self.builder.?, val, alloca);
            },

            .this_assign => |ta| {
                const val = try self.compileExpression(ta.value);
                const this_alloca = self.variables.get("this") orelse return CompileError.NoThisContext;
                const this_val = LLVMBuildLoad2(self.builder.?, self.i8_ptr, this_alloca, "this_val");

                // Use current_class_name to find the field
                const cn = self.current_class_name orelse return CompileError.NoThisContext;
                const field_map = self.class_field_indices.get(cn) orelse return CompileError.UnsupportedFeature;
                const field_idx = field_map.get(ta.field) orelse return CompileError.UndefinedVariable;
                const struct_type = self.class_struct_types.get(cn).?;

                var indices = [_]LLVMValueRef{
                    LLVMConstInt(self.i32, 0, 0),
                    LLVMConstInt(self.i32, field_idx, 0),
                };
                const field_ptr = LLVMBuildGEP2(self.builder.?, struct_type, this_val, &indices, 2, "field_ptr");
                _ = LLVMBuildStore(self.builder.?, val, field_ptr);
            },

            .expr_stmt => |expr| {
                _ = try self.compileExpression(expr);
            },

            .block => |block| {
                for (block) |s| {
                    try self.compileStatement(&s);
                }
            },

            .return_stmt => |ret_expr| {
                if (ret_expr) |expr| {
                    const val = try self.compileExpression(expr);
                    _ = LLVMBuildRet(self.builder.?, val);
                } else {
                    _ = LLVMBuildRetVoid(self.builder.?);
                }
            },

            .print_stmt => |ps| {
                const val = try self.compileExpression(ps.expr);
                try self.compilePrint(val, ps.newline);
            },

            .if_stmt => |if_s| {
                const cond = try self.compileExpression(if_s.cond);
                // Convert to i1 if needed (LLVM condbr requires i1)
                const cond_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, cond, LLVMConstInt(self.i1, 0, 0), "ifcond");

                const then_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "then");
                const else_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "else");
                const merge_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "ifmerge");

                _ = LLVMBuildCondBr(self.builder.?, cond_i1, then_bb, else_bb);

                // Then block
                LLVMPositionBuilderAtEnd(self.builder.?, then_bb);
                try self.compileStatement(if_s.then_branch);
                if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(self.builder.?)) == null) {
                    _ = LLVMBuildBr(self.builder.?, merge_bb);
                }

                // Else block
                LLVMPositionBuilderAtEnd(self.builder.?, else_bb);
                if (if_s.else_branch) |else_s| {
                    try self.compileStatement(else_s);
                }
                if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(self.builder.?)) == null) {
                    _ = LLVMBuildBr(self.builder.?, merge_bb);
                }

                // Merge block
                LLVMPositionBuilderAtEnd(self.builder.?, merge_bb);
            },

            .while_loop => |wl| {
                const cond_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "while.cond");
                const body_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "while.body");
                const end_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "while.end");

                _ = LLVMBuildBr(self.builder.?, cond_bb);

                // Condition block
                LLVMPositionBuilderAtEnd(self.builder.?, cond_bb);
                const cond = try self.compileExpression(wl.cond);
                const cond_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, cond, LLVMConstInt(self.i1, 0, 0), "whilecond");
                _ = LLVMBuildCondBr(self.builder.?, cond_i1, body_bb, end_bb);

                // Body block
                LLVMPositionBuilderAtEnd(self.builder.?, body_bb);
                try self.compileStatement(wl.body);
                if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(self.builder.?)) == null) {
                    _ = LLVMBuildBr(self.builder.?, cond_bb);
                }

                // End block
                LLVMPositionBuilderAtEnd(self.builder.?, end_bb);
            },

            .for_loop => |fl| {
                const cond_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "for.cond");
                const body_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "for.body");
                const inc_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "for.inc");
                const end_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "for.end");

                // Init
                if (fl.init) |init_stmt| {
                    try self.compileStatement(init_stmt);
                }
                _ = LLVMBuildBr(self.builder.?, cond_bb);

                // Condition
                LLVMPositionBuilderAtEnd(self.builder.?, cond_bb);
                if (fl.cond) |cond_expr| {
                    const cond = try self.compileExpression(cond_expr);
                    const cond_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, cond, LLVMConstInt(self.i1, 0, 0), "forcond");
                    _ = LLVMBuildCondBr(self.builder.?, cond_i1, body_bb, end_bb);
                } else {
                    _ = LLVMBuildBr(self.builder.?, body_bb);
                }

                // Body
                LLVMPositionBuilderAtEnd(self.builder.?, body_bb);
                try self.compileStatement(fl.body);
                if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(self.builder.?)) == null) {
                    _ = LLVMBuildBr(self.builder.?, inc_bb);
                }

                // Increment
                LLVMPositionBuilderAtEnd(self.builder.?, inc_bb);
                if (fl.inc) |inc_stmt| {
                    try self.compileStatement(inc_stmt);
                }
                if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(self.builder.?)) == null) {
                    _ = LLVMBuildBr(self.builder.?, cond_bb);
                }

                // End
                LLVMPositionBuilderAtEnd(self.builder.?, end_bb);
            },

            .for_each => |fe| {
                // for-each is translated to: index = 0; while (index < len) { elem = arr[index]; body; index++; }
                // For now, we need runtime support — mark as unsupported in this phase
                _ = fe;
                return CompileError.UnsupportedFeature;
            },

            .break_stmt => {
                // TODO: need loop context tracking
                return CompileError.UnsupportedFeature;
            },

            .continue_stmt => {
                // TODO: need loop context tracking
                return CompileError.UnsupportedFeature;
            },

            .go_stmt => {
                // Goroutines require runtime support — will be implemented with thread creation
                return CompileError.UnsupportedFeature;
            },

            .throw_stmt => {
                // Exception handling requires setjmp/longjmp runtime
                return CompileError.UnsupportedFeature;
            },

            .try_stmt => {
                return CompileError.UnsupportedFeature;
            },

            .array_assign => {
                // Requires array runtime
                return CompileError.UnsupportedFeature;
            },
        }
    }

    fn compileExpression(self: *Self, expr: ast.Expression) anyerror!LLVMValueRef {
        switch (expr) {
            .int_literal => |v| {
                return LLVMConstInt(self.i64, @intCast(v), 1);
            },

            .float_literal => |v| {
                return LLVMConstReal(self.f64, v);
            },

            .bool_literal => |v| {
                return LLVMConstInt(self.i1, if (v) 1 else 0, 0);
            },

            .string_literal => |v| {
                // Build a null-terminated copy for LLVM
                const str_z = try dupeZAlloc(self.allocator, v);
                defer self.allocator.free(str_z);
                const str_val = LLVMBuildGlobalString(self.builder.?, str_z.ptr, "str");
                return LLVMBuildBitCast(self.builder.?, str_val, self.i8_ptr, "strptr");
            },

            .null_literal => {
                return LLVMConstNull(self.i8_ptr);
            },

            .identifier => |name| {
                const alloca = self.variables.get(name) orelse return CompileError.UndefinedVariable;
                const llvm_type = self.variable_types.get(name) orelse self.i64;
                const name_z = try dupeZAlloc(self.allocator, name);
                defer self.allocator.free(name_z);
                return LLVMBuildLoad2(self.builder.?, llvm_type, alloca, name_z.ptr);
            },

            .binary_op => |binop| {
                return try self.compileBinaryOp(binop.op, binop.left, binop.right);
            },

            .unary_not => |operand| {
                const val = try self.compileExpression(operand.*);
                return LLVMBuildNot(self.builder.?, val, "not");
            },

            .call => |call_expr| {
                return try self.compileCall(call_expr.name, call_expr.args);
            },

            .method_call => |mc| {
                return try self.compileMethodCall(mc.object, mc.method, mc.args);
            },

            .new_object => |no| {
                const struct_type = self.class_struct_types.get(no.class_name) orelse {
                    return LLVMConstNull(self.i8_ptr);
                };

                // malloc(sizeof(struct))
                const struct_size = LLVMSizeOf(struct_type);
                const size_val = LLVMBuildBitCast(self.builder.?, struct_size, self.i64, "size");
                const malloc_fn = self.ensureMalloc();
                var malloc_args = [_]LLVMValueRef{size_val};
                const obj_ptr = LLVMBuildCall2(self.builder.?, self.malloc_type.?, malloc_fn, &malloc_args, 1, "obj_ptr");

                // Zero-initialize all fields with null/0
                if (self.class_field_indices.get(no.class_name)) |field_map| {
                    var iter = field_map.iterator();
                    while (iter.next()) |entry| {
                        const field_idx = entry.value_ptr.*;
                        var indices = [_]LLVMValueRef{
                            LLVMConstInt(self.i32, 0, 0),
                            LLVMConstInt(self.i32, field_idx, 0),
                        };
                        const field_ptr = LLVMBuildGEP2(self.builder.?, struct_type, obj_ptr, &indices, 2, "field");
                        _ = LLVMBuildStore(self.builder.?, LLVMConstInt(self.i64, 0, 0), field_ptr);
                    }
                }

                // Call constructor if args provided
                if (no.args.len > 0) {
                    const ctor_mangled = try mangleMethodName(self.allocator, no.class_name, no.class_name);
                    if (LLVMGetNamedFunction(self.module, ctor_mangled.ptr)) |ctor| {
                        var call_args = std.ArrayList(LLVMValueRef).init(self.allocator);
                        defer call_args.deinit();
                        try call_args.append(obj_ptr); // pass 'this'
                        for (no.args) |arg| {
                            try call_args.append(try self.compileExpression(arg));
                        }
                        const func_type = LLVMGlobalGetValueType(ctor);
                        _ = LLVMBuildCall2(self.builder.?, func_type, ctor, call_args.items.ptr, @intCast(call_args.items.len), "");
                    }
                }

                return obj_ptr;
            },

            .this_ref => {
                // Load 'this' pointer from the alloca
                const this_alloca = self.variables.get("this") orelse return CompileError.NoThisContext;
                const this_type = self.variable_types.get("this") orelse self.i8_ptr;
                return LLVMBuildLoad2(self.builder.?, this_type, this_alloca, "this");
            },

            .field_access => |fa| {
                // For "this.field", use current_class_name to find the struct type
                // For "obj.field", we need to know the object's class — use current_class_name as hint
                const obj_val = try self.compileExpression(fa.object.*);

                // Find which class this field belongs to
                var cname: ?[]const u8 = null;
                // Check current class first
                if (self.current_class_name) |ccn| {
                    if (self.class_field_indices.get(ccn)) |fm| {
                        if (fm.get(fa.field) != null) {
                            cname = ccn;
                        }
                    }
                }
                // Then check all classes
                if (cname == null) {
                    var class_it = self.class_field_indices.iterator();
                    while (class_it.next()) |entry| {
                        if (entry.value_ptr.get(fa.field) != null) {
                            cname = entry.key_ptr.*;
                            break;
                        }
                    }
                }

                const cn = cname orelse return CompileError.UnsupportedFeature;
                const field_map = self.class_field_indices.get(cn).?;
                const field_idx = field_map.get(fa.field).?;
                const struct_type = self.class_struct_types.get(cn).?;

                var indices = [_]LLVMValueRef{
                    LLVMConstInt(self.i32, 0, 0),
                    LLVMConstInt(self.i32, field_idx, 0),
                };
                const field_ptr = LLVMBuildGEP2(self.builder.?, struct_type, obj_val, &indices, 2, "field_ptr");
                const field_name_z = try dupeZAlloc(self.allocator, fa.field);
                defer self.allocator.free(field_name_z);
                return LLVMBuildLoad2(self.builder.?, self.i64, field_ptr, field_name_z.ptr);
            },

            .new_chan,
            .new_array,
            .array_literal,
            .new_map,
            .array_index,
            .lambda,
            => {
                std.debug.print("Compiler: unsupported expression type: {}\n", .{std.meta.activeTag(expr)});
                return CompileError.UnsupportedFeature;
            },
        }
    }

    fn compileBinaryOp(self: *Self, op: lexer.TokenType, left_expr: *ast.Expression, right_expr: *ast.Expression) anyerror!LLVMValueRef {
        const left = try self.compileExpression(left_expr.*);

        // Short-circuit for && and ||
        switch (op) {
            .amp_amp => {
                // &&: if left is false, result is false; else evaluate right
                const left_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, left, LLVMConstInt(self.i1, 0, 0), "and.lhs");
                const left_bb = LLVMGetInsertBlock(self.builder.?);

                const right_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "and.rhs");
                const merge_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "and.merge");
                _ = LLVMBuildCondBr(self.builder.?, left_i1, right_bb, merge_bb);

                LLVMPositionBuilderAtEnd(self.builder.?, right_bb);
                const right = try self.compileExpression(right_expr.*);
                const right_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, right, LLVMConstInt(self.i1, 0, 0), "and.rhs.val");
                const right_bb_end = LLVMGetInsertBlock(self.builder.?);
                _ = LLVMBuildBr(self.builder.?, merge_bb);

                LLVMPositionBuilderAtEnd(self.builder.?, merge_bb);
                const phi = LLVMBuildPhi(self.builder.?, self.i1, "and.result");
                var incoming_values = [_]LLVMValueRef{ LLVMConstInt(self.i1, 0, 0), right_i1 };
                var incoming_blocks = [_]LLVMBasicBlockRef{ left_bb, right_bb_end };
                LLVMAddIncoming(phi, &incoming_values, &incoming_blocks, 2);
                return phi;
            },
            .pipe_pipe => {
                // ||: if left is true, result is true; else evaluate right
                const left_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, left, LLVMConstInt(self.i1, 0, 0), "or.lhs");
                const left_bb = LLVMGetInsertBlock(self.builder.?);

                const right_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "or.rhs");
                const merge_bb = LLVMAppendBasicBlockInContext(self.ctx, self.current_function.?, "or.merge");
                _ = LLVMBuildCondBr(self.builder.?, left_i1, merge_bb, right_bb);

                LLVMPositionBuilderAtEnd(self.builder.?, right_bb);
                const right = try self.compileExpression(right_expr.*);
                const right_i1 = LLVMBuildICmp(self.builder.?, LLVMIntNE, right, LLVMConstInt(self.i1, 0, 0), "or.rhs.val");
                const right_bb_end = LLVMGetInsertBlock(self.builder.?);
                _ = LLVMBuildBr(self.builder.?, merge_bb);

                LLVMPositionBuilderAtEnd(self.builder.?, merge_bb);
                const phi = LLVMBuildPhi(self.builder.?, self.i1, "or.result");
                var incoming_values = [_]LLVMValueRef{ LLVMConstInt(self.i1, 1, 0), right_i1 };
                var incoming_blocks = [_]LLVMBasicBlockRef{ left_bb, right_bb_end };
                LLVMAddIncoming(phi, &incoming_values, &incoming_blocks, 2);
                return phi;
            },
            else => {},
        }

        const right = try self.compileExpression(right_expr.*);

        switch (op) {
            .plus => {
                // Check types — for now assume int
                return LLVMBuildAdd(self.builder.?, left, right, "add");
            },
            .minus => {
                return LLVMBuildSub(self.builder.?, left, right, "sub");
            },
            .star => {
                return LLVMBuildMul(self.builder.?, left, right, "mul");
            },
            .slash => {
                return LLVMBuildSDiv(self.builder.?, left, right, "div");
            },
            .percent => {
                return LLVMBuildSRem(self.builder.?, left, right, "mod");
            },
            .lt => {
                return LLVMBuildICmp(self.builder.?, LLVMIntSLT, left, right, "lt");
            },
            .gt => {
                return LLVMBuildICmp(self.builder.?, LLVMIntSGT, left, right, "gt");
            },
            .lt_eq => {
                return LLVMBuildICmp(self.builder.?, LLVMIntSLE, left, right, "le");
            },
            .gt_eq => {
                return LLVMBuildICmp(self.builder.?, LLVMIntSGE, left, right, "ge");
            },
            .eq_eq => {
                return LLVMBuildICmp(self.builder.?, LLVMIntEQ, left, right, "eq");
            },
            .not_eq => {
                return LLVMBuildICmp(self.builder.?, LLVMIntNE, left, right, "ne");
            },
            else => {
                std.debug.print("Compiler: unsupported binary op: {}\n", .{op});
                return CompileError.InvalidOperation;
            },
        }
    }

    fn compileCall(self: *Self, name: []const u8, args: []const ast.Expression) anyerror!LLVMValueRef {
        // Look up function by mangled name
        // Try "ClassName_method" patterns — but for a simple call, try direct name
        const name_z = try dupeZAlloc(self.allocator, name);
        defer self.allocator.free(name_z);

        const func = LLVMGetNamedFunction(self.module, name_z.ptr);

        if (func == null) {
            // Try looking for a method with this name across all classes
            // For now, this is a simplification
            std.debug.print("Compiler: undefined function '{s}'\n", .{name});
            return CompileError.UndefinedVariable;
        }

        // Compile arguments
        var llvm_args = std.ArrayList(LLVMValueRef).init(self.allocator);
        defer llvm_args.deinit();

        for (args) |arg| {
            try llvm_args.append(try self.compileExpression(arg));
        }

        const func_type = LLVMGlobalGetValueType(func.?);
        return LLVMBuildCall2(self.builder.?, func_type, func.?, llvm_args.items.ptr, @intCast(llvm_args.items.len), "call");
    }

    fn compileMethodCall(self: *Self, object: *ast.Expression, method: []const u8, args: []const ast.Expression) anyerror!LLVMValueRef {
        // Static method call: ClassName.method(args)
        // Check if the object expression is an identifier that matches a class name
        if (object.* == .identifier) {
            const class_name = object.*.identifier;
            if (self.class_struct_types.get(class_name) != null) {
                const mangled = try mangleMethodName(self.allocator, class_name, method);
                if (LLVMGetNamedFunction(self.module, mangled.ptr)) |func| {
                    var call_args = std.ArrayList(LLVMValueRef).init(self.allocator);
                    defer call_args.deinit();
                    for (args) |arg| {
                        try call_args.append(try self.compileExpression(arg));
                    }
                    const func_type = LLVMGlobalGetValueType(func);
                    return LLVMBuildCall2(self.builder.?, func_type, func, call_args.items.ptr, @intCast(call_args.items.len), "call");
                }
            }
        }

        // Instance method call: obj.method(args)
        const obj_val = try self.compileExpression(object.*);

        // Use current_class_name as hint, then search all classes
        var cname: ?[]const u8 = self.current_class_name;

        // Try to find the method
        var mangled = try mangleMethodName(self.allocator, cname orelse "", method);
        if (cname != null and LLVMGetNamedFunction(self.module, mangled.ptr) != null) {
            // Found in current class
        } else {
            // Search all classes for this method
            cname = null;
            var class_it = self.class_struct_types.iterator();
            while (class_it.next()) |entry| {
                const try_mangled = try mangleMethodName(self.allocator, entry.key_ptr.*, method);
                if (LLVMGetNamedFunction(self.module, try_mangled.ptr)) |func| {
                    cname = entry.key_ptr.*;
                    mangled = try_mangled;
                    _ = func;
                    break;
                }
            }
        }

        if (cname) |cn| {
            mangled = try mangleMethodName(self.allocator, cn, method);
            if (LLVMGetNamedFunction(self.module, mangled.ptr)) |func| {
                var call_args = std.ArrayList(LLVMValueRef).init(self.allocator);
                defer call_args.deinit();
                try call_args.append(obj_val); // pass 'this'
                for (args) |arg| {
                    try call_args.append(try self.compileExpression(arg));
                }
                const func_type = LLVMGlobalGetValueType(func);
                return LLVMBuildCall2(self.builder.?, func_type, func, call_args.items.ptr, @intCast(call_args.items.len), "call");
            }
        }

        std.debug.print("Compiler: unresolved method call '{s}'\n", .{method});
        return CompileError.UnsupportedFeature;
    }

    fn compilePrint(self: *Self, val: LLVMValueRef, newline: bool) anyerror!void {
        const printf = self.ensurePrintf();

        const val_type = LLVMTypeOf(val);

        if (val_type == self.i64) {
            if (newline) {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%lld\n", "fmt_int_nl");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            } else {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%lld", "fmt_int");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            }
        } else if (val_type == self.f64) {
            if (newline) {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%g\n", "fmt_float_nl");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            } else {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%g", "fmt_float");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            }
        } else if (val_type == self.i1) {
            if (newline) {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%s\n", "fmt_bool_nl");
                const true_str = LLVMBuildGlobalString(self.builder.?, "true", "true_str");
                const false_str = LLVMBuildGlobalString(self.builder.?, "false", "false_str");
                const true_ptr = LLVMBuildBitCast(self.builder.?, true_str, self.i8_ptr, "true_ptr");
                const false_ptr = LLVMBuildBitCast(self.builder.?, false_str, self.i8_ptr, "false_ptr");
                const str_val = LLVMBuildSelect(self.builder.?, val, true_ptr, false_ptr, "bool_str");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, str_val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            } else {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%s", "fmt_bool");
                const true_str = LLVMBuildGlobalString(self.builder.?, "true", "true_str");
                const false_str = LLVMBuildGlobalString(self.builder.?, "false", "false_str");
                const true_ptr = LLVMBuildBitCast(self.builder.?, true_str, self.i8_ptr, "true_ptr");
                const false_ptr = LLVMBuildBitCast(self.builder.?, false_str, self.i8_ptr, "false_ptr");
                const str_val = LLVMBuildSelect(self.builder.?, val, true_ptr, false_ptr, "bool_str");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, str_val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            }
        } else if (val_type == self.i8_ptr) {
            // String pointer
            if (newline) {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%s\n", "fmt_str_nl");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            } else {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%s", "fmt_str");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            }
        } else {
            // Fallback: print as integer
            if (newline) {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%lld\n", "fmt_unknown_nl");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            } else {
                const fmt = LLVMBuildGlobalString(self.builder.?, "%lld", "fmt_unknown");
                const fmt_ptr = LLVMBuildBitCast(self.builder.?, fmt, self.i8_ptr, "fmtptr");
                var args = [_]LLVMValueRef{ fmt_ptr, val };
                _ = LLVMBuildCall2(self.builder.?, self.printf_type.?, printf, &args, 2, "");
            }
        }
    }

    fn joyaTypeToLLVM(self: *Self, typ: ast.Type) LLVMTypeRef {
        return switch (typ) {
            .int => self.i64,
            .float => self.f64,
            .bool => self.i1,
            .string => self.i8_ptr,
            .void => self.void_type,
            .fn_ref => self.i8_ptr,
            .chan => self.i8_ptr,
            .array => self.i8_ptr,
            .map => self.i8_ptr,
            .class_ref => self.i8_ptr, // In LLVM 20 opaque pointers, all pointers are 'ptr'
            .type_param => self.i8_ptr,
        };
    }
};

// External function from Core.h (used but not declared above)
pub extern fn LLVMGlobalGetValueType(Global: LLVMValueRef) LLVMTypeRef;
pub extern fn LLVMGetTypeByName2(C: LLVMContextRef, Name: [*:0]const u8) LLVMTypeRef;
pub extern fn LLVMGetElementType(Ty: LLVMTypeRef) LLVMTypeRef;
pub extern fn LLVMSizeOf(Ty: LLVMTypeRef) LLVMValueRef;
pub extern fn LLVMBuildMalloc(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMGetBasicBlockTerminator(BB: LLVMBasicBlockRef) LLVMValueRef;
