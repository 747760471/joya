//! Assembly-based Fiber backend for Linux and macOS
//!
//! Uses the C shim in fiber_ucontext.c which implements context switching
//! via inline assembly (x86_64 / aarch64) — no dependency on the deprecated
//! POSIX ucontext API. This makes it work with musl libc and cross-compilation.
//!
//! Architecture:
//!   - Each fiber is a JoyaFiberContext (C struct) containing stack + saved regs
//!   - switchToFiber saves current callee-saved regs and swaps to target
//!   - The "master fiber" is the worker thread's scheduler context
//!   - convertThreadToFiber allocates a context slot for save/restore

const std = @import("std");

/// C-side opaque context
pub const JoyaFiberContext = opaque {};

pub const FiberHandle = *JoyaFiberContext;

extern fn joya_create_fiber(stack_size: usize, entry: ?*const fn (?*anyopaque) callconv(.C) void, param: ?*anyopaque) ?FiberHandle;
extern fn joya_alloc_master_context() ?FiberHandle;
extern fn joya_switch_fiber(from: FiberHandle, to: FiberHandle) c_int;
extern fn joya_delete_fiber(fc: FiberHandle) void;

/// Thread-local: current running fiber on this OS thread
threadlocal var current_fiber: FiberHandle = undefined;
threadlocal var current_fiber_set: bool = false;

pub fn createFiber(stack_size: usize, entry: *const fn (?*anyopaque) callconv(.C) void, param: ?*anyopaque) !FiberHandle {
    const handle = joya_create_fiber(stack_size, entry, param);
    if (handle == null) return error.FiberCreationFailed;
    return handle.?;
}

pub fn switchToFiber(handle: FiberHandle) void {
    const from = if (current_fiber_set) current_fiber else {
        // This should never happen — switchToFiber called before convertThreadToFiber
        return;
    };
    current_fiber = handle;
    _ = joya_switch_fiber(from, handle);
}

pub fn deleteFiber(handle: FiberHandle) void {
    joya_delete_fiber(handle);
}

/// On non-Windows platforms, "converting a thread to a fiber" means
/// allocating a context slot for the scheduler/main context.
pub fn convertThreadToFiber() !FiberHandle {
    const ctx = joya_alloc_master_context();
    if (ctx == null) return error.FiberConversionFailed;
    current_fiber = ctx.?;
    current_fiber_set = true;
    return ctx.?;
}

pub fn convertFiberToThread() void {
    if (current_fiber_set) {
        joya_delete_fiber(current_fiber);
        current_fiber_set = false;
    }
}

pub fn getMasterFiber() FiberHandle {
    if (!current_fiber_set) unreachable;
    return current_fiber;
}
