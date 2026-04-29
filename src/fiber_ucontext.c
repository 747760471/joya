/*
 * fiber_ucontext.c — Assembly-based fiber context switching
 *
 * Instead of using the deprecated POSIX ucontext API (which is not available
 * in musl libc and has been removed from POSIX.1-2008), we implement context
 * switching directly in assembly. This is what production coroutine libraries
 * (libco, boost::context, libtask) do.
 *
 * Benefits over ucontext:
 *   - Works with musl, glibc, and any C library
 *   - Much faster (no signal mask save/restore)
 *   - Cross-compilation friendly (no system library dependency)
 *   - More portable across Linux distributions
 *
 * Supported architectures:
 *   - x86_64 (System V ABI / macOS)
 *   - aarch64 (ARM64, Linux / macOS)
 */

#ifdef _WIN32
/* This file is not used on Windows — fiber_windows.zig handles it natively */
#else

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* macOS C symbols have an underscore prefix; Linux does not.
 * This macro ensures inline asm references the correct symbol name. */
#ifdef __APPLE__
#define JOYA_SYM(name) "_" #name
#else
#define JOYA_SYM(name) #name
#endif

/* ---- Architecture detection ---- */
#if defined(__x86_64__) || defined(_M_X64)
#define JOYA_ARCH_X86_64 1
#elif defined(__aarch64__) || defined(_M_ARM64)
#define JOYA_ARCH_AARCH64 1
#else
#error "Unsupported architecture for fiber context switching"
#endif

/* ---- Context structure ---- */
typedef struct {
    void** stack_ptr;   /* stack pointer pointing to saved register area */
    void (*entry)(void*);
    void* param;
    char* stack;
    size_t stack_size;
} JoyaFiberContext;

/* ---- Forward declarations ---- */
static void fiber_startup(JoyaFiberContext* fc);

#if JOYA_ARCH_X86_64
__attribute__((naked, no_sanitize("all")))
static void fiber_initial_entry_x86_64(void);
#elif JOYA_ARCH_AARCH64
__attribute__((naked, no_sanitize("all")))
static void fiber_initial_entry_aarch64(void);
#endif

/* ====================================================================
 * Startup functions (called when a new fiber first starts executing)
 * ==================================================================== */

__attribute__((used))
static void fiber_startup(JoyaFiberContext* fc) {
    if (fc && fc->entry) {
        fc->entry(fc->param);
    }
    /* If entry returns, the fiber is done.
       The scheduler handles this — the goroutine marks itself done
       and yields back. If we get here unexpectedly, just spin. */
    while (1) {}
}

#if JOYA_ARCH_X86_64
__attribute__((naked, no_sanitize("all")))
static void fiber_initial_entry_x86_64(void) {
    __asm__ volatile (
        "movq %%r12, %%rdi\n\t"
        "jmp " JOYA_SYM(fiber_startup) "\n\t"
        ::: "memory"
    );
}
#elif JOYA_ARCH_AARCH64
__attribute__((naked, no_sanitize("all")))
static void fiber_initial_entry_aarch64(void) {
    __asm__ volatile (
        "mov x0, x19\n\t"
        "b " JOYA_SYM(fiber_startup) "\n\t"
        ::: "memory"
    );
}
#endif

/* ====================================================================
 * x86_64 context switching
 *
 * System V ABI callee-saved: rbx, rbp, r12-r15
 *
 * Stack layout after switch (from high to low address):
 *   return address    ← popped by ret
 *   rbx
 *   rbp
 *   r12
 *   r13
 *   r14
 *   r15               ← stack_ptr points here
 * ==================================================================== */
#if JOYA_ARCH_X86_64

__attribute__((noinline, no_sanitize("all")))
void joya_switch_fiber(JoyaFiberContext* from, JoyaFiberContext* to) {
    __asm__ volatile (
        "pushq %%rbx\n\t"
        "pushq %%rbp\n\t"
        "pushq %%r12\n\t"
        "pushq %%r13\n\t"
        "pushq %%r14\n\t"
        "pushq %%r15\n\t"
        "movq %%rsp, (%[from])\n\t"
        "movq (%[to]), %%rsp\n\t"
        "popq %%r15\n\t"
        "popq %%r14\n\t"
        "popq %%r13\n\t"
        "popq %%r12\n\t"
        "popq %%rbp\n\t"
        "popq %%rbx\n\t"
        "retq\n\t"
        :
        : [from] "r" (from), [to] "r" (to)
        : "memory"
    );
}

JoyaFiberContext* joya_create_fiber(size_t stack_size, void (*entry)(void*), void* param) {
    JoyaFiberContext* fc = (JoyaFiberContext*)calloc(1, sizeof(JoyaFiberContext));
    if (!fc) return NULL;

    fc->stack_size = stack_size < 65536 ? 65536 : stack_size;
    fc->stack = (char*)malloc(fc->stack_size);
    if (!fc->stack) {
        free(fc);
        return NULL;
    }

    fc->entry = entry;
    fc->param = param;

    /* Set up initial stack frame.
     *
     * When joya_switch_fiber first switches to this fiber:
     *   1. Load rsp from fc->stack_ptr
     *   2. pop r15, r14, r13, r12, rbp, rbx  (6 pops)
     *   3. ret → jumps to return address on stack
     *
     * We set the return address to fiber_initial_entry_x86_64,
     * and store fc in r12 so the stub can move it to rdi (first arg).
     *
     * Stack (from rsp upward):
     *   [rsp+0]  r15 value
     *   [rsp+8]  r14 value
     *   [rsp+16] r13 value
     *   [rsp+24] r12 value
     *   [rsp+32] rbp value
     *   [rsp+40] rbx value
     *   [rsp+48] return address (→ fiber_initial_entry_x86_64)
     */

    uintptr_t sp = (uintptr_t)(fc->stack + fc->stack_size);
    /* Align to 16 bytes (System V ABI requires 16-byte alignment at call sites).
     * After the 6 pops (48 bytes) + ret (8 bytes), sp will be at the
     * original alignment. We need the stack pointer we set to be 16-byte
     * aligned after accounting for the return address that ret pops. */
    sp &= ~0xFUL;

    /* Return address (highest, popped by ret) */
    sp -= sizeof(void*);
    *(void**)sp = (void*)fiber_initial_entry_x86_64;

    /* 6 callee-saved register slots (lowest, popped first) */
    sp -= sizeof(void*) * 6;

    void** regs = (void**)sp;
    regs[0] = 0;              /* r15 */
    regs[1] = 0;              /* r14 */
    regs[2] = 0;              /* r13 */
    regs[3] = (void*)fc;      /* r12 = context pointer (used by entry stub) */
    regs[4] = 0;              /* rbp */
    regs[5] = 0;              /* rbx */

    fc->stack_ptr = (void**)sp;
    return fc;
}

/* ====================================================================
 * aarch64 context switching
 *
 * AAPCS64 callee-saved: x19-x28, x29(fp), x30(lr)
 * ==================================================================== */
#elif JOYA_ARCH_AARCH64

__attribute__((noinline, no_sanitize("all")))
void joya_switch_fiber(JoyaFiberContext* from, JoyaFiberContext* to) {
    __asm__ volatile (
        "stp x19, x20, [sp, #-96]!\n\t"
        "stp x21, x22, [sp, #16]\n\t"
        "stp x23, x24, [sp, #32]\n\t"
        "stp x25, x26, [sp, #48]\n\t"
        "stp x27, x28, [sp, #64]\n\t"
        "stp x29, x30, [sp, #80]\n\t"
        "mov x9, sp\n\t"
        "str x9, [%[from]]\n\t"
        "ldr x9, [%[to]]\n\t"
        "mov sp, x9\n\t"
        "ldp x29, x30, [sp, #80]\n\t"
        "ldp x27, x28, [sp, #64]\n\t"
        "ldp x25, x26, [sp, #48]\n\t"
        "ldp x23, x24, [sp, #32]\n\t"
        "ldp x21, x22, [sp, #16]\n\t"
        "ldp x19, x20, [sp], #96\n\t"
        "ret\n\t"
        :
        : [from] "r" (from), [to] "r" (to)
        : "memory", "x9"
    );
}

JoyaFiberContext* joya_create_fiber(size_t stack_size, void (*entry)(void*), void* param) {
    JoyaFiberContext* fc = (JoyaFiberContext*)calloc(1, sizeof(JoyaFiberContext));
    if (!fc) return NULL;

    fc->stack_size = stack_size < 65536 ? 65536 : stack_size;
    fc->stack = (char*)malloc(fc->stack_size);
    if (!fc->stack) {
        free(fc);
        return NULL;
    }

    fc->entry = entry;
    fc->param = param;

    uintptr_t sp = (uintptr_t)(fc->stack + fc->stack_size);
    sp &= ~0xFUL;

    /* 12 register pairs = 96 bytes (x19/x20 pairs through x29/x30) */
    sp -= 96;

    void** regs = (void**)sp;
    regs[0] = (void*)fc;      /* x19 = context pointer (used by entry stub) */
    regs[1] = 0;              /* x20 */
    regs[2] = 0;              /* x21 */
    regs[3] = 0;              /* x22 */
    regs[4] = 0;              /* x23 */
    regs[5] = 0;              /* x24 */
    regs[6] = 0;              /* x25 */
    regs[7] = 0;              /* x26 */
    regs[8] = 0;              /* x27 */
    regs[9] = 0;              /* x28 */
    regs[10] = 0;             /* x29 (fp) */
    regs[11] = (void*)fiber_initial_entry_aarch64;  /* x30 (lr) */

    fc->stack_ptr = (void**)sp;
    return fc;
}

#endif /* architecture */

/* ---- Common functions ---- */

JoyaFiberContext* joya_alloc_master_context(void) {
    JoyaFiberContext* fc = (JoyaFiberContext*)calloc(1, sizeof(JoyaFiberContext));
    if (!fc) return NULL;

    fc->stack = NULL;
    fc->stack_size = 0;
    fc->entry = NULL;
    fc->param = NULL;
    fc->stack_ptr = NULL;  /* Will be set on first switch */

    return fc;
}

void joya_delete_fiber(JoyaFiberContext* fc) {
    if (!fc) return;
    if (fc->stack) free(fc->stack);
    free(fc);
}

#endif /* !_WIN32 */
