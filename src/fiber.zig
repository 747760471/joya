//! Cross-platform Fiber abstraction for Joya scheduler
//!
//! Selects the backend at comptime based on target OS:
//!   Windows → fiber_windows.zig (Win32 Fiber API)
//!   Linux   → fiber_ucontext.zig (ucontext_t)
//!   macOS   → fiber_ucontext.zig (ucontext_t, with quirks handled in C)
//!   Other   → fiber_fallback.zig (stub, compile error at link time)
//!
//! Public API (same across all backends):
//!   FiberHandle  — opaque handle to a fiber
//!   createFiber(stack_size, entry, param) → FiberHandle
//!   switchToFiber(handle)                 — switch execution to target fiber
//!   deleteFiber(handle)                   — destroy a fiber
//!   convertThreadToFiber()                → FiberHandle  (Windows only, no-op elsewhere)
//!   convertFiberToThread()                — (Windows only, no-op elsewhere)
//!   getMasterFiber()                      → FiberHandle  (main/scheduler fiber handle)

const std = @import("std");

pub const backend = switch (@import("builtin").os.tag) {
    .windows => @import("fiber_windows.zig"),
    .linux, .macos => @import("fiber_ucontext.zig"),
    else => @import("fiber_fallback.zig"),
};

/// Opaque handle to a fiber context
pub const FiberHandle = backend.FiberHandle;

/// Entry function signature: receives the user parameter
pub const FiberEntry = *const fn (?*anyopaque) callconv(.C) void;

/// Create a new fiber with the given stack size, entry function, and user parameter.
/// Returns a handle to the fiber.
pub fn createFiber(stack_size: usize, entry: FiberEntry, param: ?*anyopaque) !FiberHandle {
    return backend.createFiber(stack_size, entry, param);
}

/// Switch execution to the target fiber.
pub fn switchToFiber(handle: FiberHandle) void {
    backend.switchToFiber(handle);
}

/// Delete (destroy) a fiber and free its resources.
pub fn deleteFiber(handle: FiberHandle) void {
    backend.deleteFiber(handle);
}

/// Convert the current OS thread into a fiber (Windows-specific).
/// On non-Windows platforms, this is a no-op that returns a dummy handle.
pub fn convertThreadToFiber() !FiberHandle {
    return backend.convertThreadToFiber();
}

/// Convert the current fiber back to a normal OS thread (Windows-specific).
/// On non-Windows platforms, this is a no-op.
pub fn convertFiberToThread() void {
    backend.convertFiberToThread();
}

/// Get the handle for the current thread's "master" fiber.
/// On Windows, this is the fiber returned by ConvertThreadToFiber.
/// On ucontext platforms, this returns the main context handle.
pub fn getMasterFiber() FiberHandle {
    return backend.getMasterFiber();
}
