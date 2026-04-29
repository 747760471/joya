//! Fallback Fiber backend for unsupported platforms
//!
//! This backend provides compile-time stubs. At runtime, all operations
//! will fail with an error. The scheduler will detect this and fall back
//! to OS thread mode.

pub const FiberHandle = *opaque {};

pub fn createFiber(_: usize, _: *const fn (?*anyopaque) callconv(.C) void, _: ?*anyopaque) !FiberHandle {
    return error.FiberNotSupported;
}

pub fn switchToFiber(_: FiberHandle) void {}

pub fn deleteFiber(_: FiberHandle) void {}

pub fn convertThreadToFiber() !FiberHandle {
    return error.FiberNotSupported;
}

pub fn convertFiberToThread() void {}

pub fn getMasterFiber() FiberHandle {
    unreachable;
}
