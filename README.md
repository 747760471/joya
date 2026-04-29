# Joya Language

**[中文](./README_CN.md)** | English

---

> **Java syntax you already know. Go concurrency you always wanted.**

Joya is a systems programming language that bridges the gap between Java's familiar object-oriented syntax and Go's elegant concurrency model (CSP). Write code that reads like Java, runs concurrent like Go, and compiles to native machine code with near-Go performance.

### Why Joya?

| | Java | Go | **Joya** |
|---|---|---|---|
| Syntax | Verbose, OOP-heavy | Simple, C-like | **Java-style classes & methods** |
| Concurrency | Threads, locks, CompletableFuture | goroutines + channels | **go {} + chan\<T\>** |
| Performance | JVM overhead | Native, fast | **Native (LLVM, planned)** |
| Scheduler | OS threads (~1MB stack each) | M:N goroutines | **M:N goroutines (Fiber-based)** |
| Platforms | JVM (cross-platform) | Native (cross-platform) | **Windows / Linux / macOS** |
| Learning curve | — | New paradigm | **Zero for Java devs** |

Java developers shouldn't have to learn a completely new syntax just to get goroutines and channels. Joya gives you the best of both worlds — the structure you're productive in, with the concurrency model Go popularized.

### Design Goals

- **Familiar** — Classes, methods, braces, semicolons. If you know Java, you know Joya.
- **Concurrent by default** — `go {}` spawns a goroutine. `chan<T>` connects them. No locks, no thread pools.
- **Lightweight scheduling** — M:N user-space goroutine scheduler. Thousands of goroutines on a handful of OS threads.
- **Cross-platform** — Runs on Windows, Linux, and macOS. The scheduler adapts to each platform automatically.
- **Fast** — Compiles to standalone native executables via LLVM (planned). No runtime, no VM.
- **Safe** — Memory-safe with garbage collection. No use-after-free, no data races.
- **Simple** — Minimal boilerplate. `public static void main()` is all you need to start.

---

## ✅ Current Progress

### Phase 1: Interpreter Prototype — Complete

A fully working tree-walking interpreter with arrays, objects, method calls, and concurrency.

| Feature | Status |
|---------|--------|
| **Lexer** (28+ keywords, operators, comments) | ✅ |
| **Recursive descent parser** (precedence climbing) | ✅ |
| **AST** (Expression, Statement, Method, Class, Program) | ✅ |
| **Tree-walking interpreter** | ✅ |
| **Data types**: int, string, bool, float, arrays, objects, chan | ✅ |
| **Arrays**: `new int[5]`, `[1,2,3]` literals, `arr[i]`, `arr.length` | ✅ |
| **For-each**: `for (int x : arr) { ... }` | ✅ |
| **String ops**: `s.length`, `s[0]`, string comparison, concatenation | ✅ |
| **Methods**: parameters, return values, nested calls | ✅ |
| **Classes**: fields, constructors, `this`, `new ClassName(args)` | ✅ |
| **Method calls**: `obj.method(args)` with `this` binding | ✅ |
| **null value**: `null` literal, `== null` comparison | ✅ |
| **Control flow**: `for`, `while`, `for-each`, `if/else if/else`, `return`, `break`, `continue` | ✅ |
| **Boolean logic**: `&&`, `\|\|`, `!` (short-circuit) | ✅ |
| **Arithmetic**: int/float mixed ops, `%` modulo | ✅ |
| **`go {}` goroutines** (user-space M:N scheduler) | ✅ |
| **`chan<T>` buffered channels** (yield on block, re-enqueue on unblock) | ✅ |
| **Comments**: `//` line, `/* */` nested block | ✅ |
| **Memory management**: Arena + ThreadSafeAlloc, zero leaks | ✅ |

### Phase 2: User-Space Goroutine Scheduler — Complete

M:N goroutine scheduler with cross-platform fiber context switching.

| Feature | Status |
|---------|--------|
| **M:N scheduling model** — N goroutines on M OS threads (M = CPU count) | ✅ |
| **Cross-platform context switching** — Windows Fiber / Linux & macOS asm | ✅ |
| **Global run queue** — lock-protected, worker threads compete for goroutines | ✅ |
| **`go {}` spawns lightweight goroutine** — no OS thread per goroutine | ✅ |
| **Chan integration** — `send`/`receive` block → yield CPU; data ready → re-enqueue | ✅ |
| **Stress tested** — 1000+ concurrent goroutines with channels, zero leaks | ✅ |

#### Platform Support

| Platform | Backend | Context Switch Mechanism |
|----------|---------|------------------------|
| **Windows** | `fiber_windows.zig` | Win32 Fiber API (`CreateFiber` / `SwitchToFiber`) |
| **Linux (x86_64)** | `fiber_ucontext.zig` + C shim | Inline assembly (System V ABI callee-saved regs) |
| **Linux (aarch64)** | `fiber_ucontext.zig` + C shim | Inline assembly (AAPCS64 callee-saved regs) |
| **macOS (x86_64)** | `fiber_ucontext.zig` + C shim | Inline assembly (System V ABI + macOS symbol prefix) |
| **macOS (aarch64)** | `fiber_ucontext.zig` + C shim | Inline assembly (AAPCS64 callee-saved regs) |
| **Other** | `fiber_fallback.zig` | Stub → auto-fallback to OS thread mode |

The cross-platform abstraction is achieved via `fiber.zig`, which selects the backend at **comptime** using `@import("builtin").os.tag`. The scheduler code (`scheduler.zig`) is fully platform-agnostic — no `#ifdef` or platform-specific code.

#### Scheduler vs OS Threads

| | OS Threads (Phase 1) | Fiber Scheduler (Phase 2) |
|---|---|---|
| Stack overhead | ~1MB per thread | ~64KB per Fiber |
| Context switch | ~1μs (kernel) | ~100ns (user-space) |
| Max concurrency | ~1,000 | ~100,000+ |
| Chan blocking | condvar (kernel wait) | yield (user-space) |
| Platform support | All (OS-provided) | Windows / Linux / macOS |

### Roadmap

| Phase | Goal | Status |
|-------|------|--------|
| **1** | Interpreter prototype — validate syntax & semantics | ✅ Complete |
| **2** | User-space goroutine scheduler (M:N, Fiber-based) | ✅ Complete |
| **2.5** | Cross-platform Fiber abstraction (Windows/Linux/macOS) | ✅ Complete |
| **3** | LLVM backend — compile to native executables | 🔜 Next |
| **4** | Self-hosting — rewrite compiler in Joya | 📋 Planned |

---

## 💻 Examples

### 1000 Goroutines Stress Test

```java
public class Main {
    public static void main() {
        chan<int> ch = new chan<int>(1000);

        // Launch 1000 goroutines — impossible with OS threads
        for (int i = 0; i < 1000; i++) {
            go {
                send(ch, i);
            };
        }

        // Receive and sum all values
        int total = 0;
        for (int i = 0; i < 1000; i++) {
            int val = receive(ch);
            total = total + val;
        }
        // total = 0+1+2+...+999 = 499500
        println("Total from 1000 goroutines: " + total);
    }
}
```

```
Total from 1000 goroutines: 499500
PASSED!
```

### Goroutines + Channels

```java
public class Main {
    public static void main() {
        chan<int> ch = new chan<int>(2);

        go {
            for (int i = 0; i < 3; i++) {
                send(ch, i * 10);
                println("sent: " + (i * 10));
            }
            close(ch);
        };

        for (int i = 0; i < 3; i++) {
            int val = receive(ch);
            println("received: " + val);
        }
    }
}
```

```
sent: 0      received: 0
sent: 10     received: 10
sent: 20     received: 20
```

### Arrays & For-Each

```java
int[] nums = [10, 20, 30, 40, 50];
for (int n : nums) {
    println(n);
}
println("length: " + nums.length);
```

### Classes & Objects

```java
class Calculator {
    int value;

    void Calculator(int v) {
        this.value = v;
    }

    int add(int x) {
        this.value = this.value + x;
        return this.value;
    }
}

Calculator calc = new Calculator(10);
println(calc.add(5));      // 15
println(calc.value);       // 15
```

### Concurrent Sorting

```java
public class Main {
    public static void main() {
        int[] data = [64, 34, 25, 12, 22, 11, 90, 45, 78, 33];

        // Parallel partial sum via goroutines + channels
        chan<int> ch = new chan<int>(2);
        go {
            send(ch, partialSum(data, 0, 5));
        };
        go {
            send(ch, partialSum(data, 5, 10));
        };
        println("Sum: " + (receive(ch) + receive(ch)));

        bubbleSort(data);
    }

    static int partialSum(int[] arr, int start, int end) { ... }
    static void bubbleSort(int[] arr) { ... }
}
```

### Language Features at a Glance

```java
public class Main {
    public static void main() {
        // Variables & types
        int x = 15;
        string name = "Joya";
        bool ready = true;
        float pi = 3.14;
        int[] arr = new int[5];
        chan<int> ch = new chan<int>(10);

        // Control flow
        if (x > 20) {
            println("big");
        } else if (x > 10) {
            println("medium");
        } else {
            println("small");
        }

        // Loops with break/continue
        for (int i = 0; i < 10; i++) {
            if (i % 2 == 0) continue;
            if (i > 7) break;
            println(i);  // 1 3 5 7
        }

        // For-each
        string[] names = ["Alice", "Bob"];
        for (string n : names) {
            println(n);
        }

        // String operations
        string s = "hello";
        println(s.length);   // 5
        println(s[0]);       // h

        // null value
        int val = null;
        println(val == null);  // true
    }
}
```

---

## 🛠️ Build & Run

### Windows

```bash
zig build
zig-out\bin\joya.exe examples\hello.joya
```

### Linux / macOS

```bash
zig build
./zig-out/bin/joya examples/hello.joya
```

### Cross-Compilation

Zig supports cross-compilation out of the box. All targets compile successfully:

```bash
zig build -Dtarget=x86_64-linux     # Linux x86_64
zig build -Dtarget=aarch64-linux    # Linux ARM64
zig build -Dtarget=x86_64-macos     # macOS Intel
zig build -Dtarget=aarch64-macos    # macOS Apple Silicon
```

**Requirements:** Zig 0.12.0 LTS (0.13+ dev builds have incompatible API)

## 📁 Project Structure

```
joya/
├── build.zig              # Zig build config (conditional C compilation)
├── README.md              # English readme
├── README_CN.md           # Chinese readme
├── joya.md                # Language specification
├── 修改记录.md             # Development changelog
├── src/
│   ├── main.zig           # Entry point
│   ├── lexer.zig          # Lexer (28+ keywords)
│   ├── ast.zig            # AST definitions
│   ├── parser.zig         # Recursive descent parser (precedence climbing)
│   ├── fiber.zig          # Cross-platform Fiber abstraction (comptime backend selection)
│   ├── fiber_windows.zig  # Windows Fiber backend (Win32 API)
│   ├── fiber_ucontext.zig # Linux/macOS Fiber backend (asm context switching)
│   ├── fiber_ucontext.c   # C shim for asm context switching (x86_64 / aarch64)
│   ├── fiber_fallback.zig # Fallback backend (stub, auto-fallback to OS threads)
│   ├── scheduler.zig      # M:N goroutine scheduler (platform-agnostic)
│   └── interpreter.zig    # Interpreter (objects, arrays, channels, scheduler integration)
└── examples/
    ├── hello.joya         # Goroutines & channels
    ├── features.joya      # Feature showcase
    ├── demo_sort.joya     # Concurrent sorting demo
    ├── stress_test.joya   # 1000 goroutine stress test
    ├── test_array.joya    # Array tests
    ├── test_string.joya   # String tests
    ├── test_method.joya   # Method call tests
    ├── test_null.joya     # Null value tests
    ├── test_break.joya    # break/continue tests
    ├── test_class.joya    # Object & multi-class tests
    ├── test_class_min.joya # Minimal this.field test
    └── test_if.joya       # if/else test
```

## 📄 License

- **Learning**: Free for learning, research, and modification
- **Commercial**: Contact the author for authorization
- **All rights reserved**

## 📬 Contact

- Email: 747760471@qq.com
- GitHub: https://github.com/747760471/joya
- Gitee：https://gitee.com/txd747760471/joya

---

*Joya — Java syntax, Go concurrency, native performance.*
