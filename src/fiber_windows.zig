//! Windows Fiber backend for Joya scheduler
//!
//! Direct mapping to Win32 Fiber API:
//!   CreateFiber     → createFiber
//!   SwitchToFiber   → switchToFiber
//!   DeleteFiber     → deleteFiber
//!   ConvertThreadToFiber → convertThreadToFiber
//!   ConvertFiberToThread → convertFiberToThread

const std = @import("std");
const windows = std.os.windows;
const WINAPI = windows.WINAPI;
const LPVOID = windows.LPVOID;
const SIZE_T = windows.SIZE_T;

const PFIBER_START_ROUTINE = *const fn (?LPVOID) callconv(WINAPI) void;

extern "kernel32" fn CreateFiber(SIZE_T, PFIBER_START_ROUTINE, ?LPVOID) callconv(WINAPI) ?LPVOID;
extern "kernel32" fn SwitchToFiber(LPVOID) callconv(WINAPI) void;
extern "kernel32" fn DeleteFiber(LPVOID) callconv(WINAPI) void;
extern "kernel32" fn ConvertThreadToFiber(?LPVOID) callconv(WINAPI) ?LPVOID;
extern "kernel32" fn ConvertFiberToThread() callconv(WINAPI) i32;

/// Opaque fiber handle — on Windows, this is the LPVOID returned by CreateFiber/ConvertThreadToFiber
pub const FiberHandle = LPVOID;

/// Thread-local: the master fiber (scheduler fiber) for this worker thread
threadlocal var master_fiber: FiberHandle = undefined;
threadlocal var master_fiber_set: bool = false;

pub fn createFiber(stack_size: usize, entry: *const fn (?*anyopaque) callconv(.C) void, param: ?*anyopaque) !FiberHandle {
    const fiber = CreateFiber(@intCast(stack_size), @ptrCast(entry), param);
    if (fiber == null) return error.FiberCreationFailed;
    return fiber.?;
}

pub fn switchToFiber(handle: FiberHandle) void {
    SwitchToFiber(handle);
}

pub fn deleteFiber(handle: FiberHandle) void {
    DeleteFiber(handle);
}

pub fn convertThreadToFiber() !FiberHandle {
    const fiber = ConvertThreadToFiber(null);
    if (fiber == null) return error.FiberConversionFailed;
    master_fiber = fiber.?;
    master_fiber_set = true;
    return fiber.?;
}

pub fn convertFiberToThread() void {
    _ = ConvertFiberToThread();
}

pub fn getMasterFiber() FiberHandle {
    if (!master_fiber_set) unreachable;
    return master_fiber;
}
