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
| Performance | JVM overhead | Native, fast | **Native (LLVM backend ✅)** |
| Scheduler | OS threads (~1MB stack each) | M:N goroutines | **M:N goroutines (Fiber-based)** |
| Platforms | JVM (cross-platform) | Native (cross-platform) | **Windows / Linux / macOS** |
| Error handling | try/catch/finally | defer + errors | **try/catch/finally + throw** |
| Modules | packages | packages | **import + lib/ convention** |
| Learning curve | — | New paradigm | **Zero for Java devs** |

Java developers shouldn't have to learn a completely new syntax just to get goroutines and channels. Joya gives you the best of both worlds — the structure you're productive in, with the concurrency model Go popularized.

### Design Goals

- **Familiar** — Classes, methods, braces, semicolons. If you know Java, you know Joya.
- **Concurrent by default** — `go {}` spawns a goroutine. `chan<T>` connects them. No locks, no thread pools.
- **Lightweight scheduling** — M:N user-space goroutine scheduler. Thousands of goroutines on a handful of OS threads.
- **Cross-platform** — Runs on Windows, Linux, and macOS. The scheduler adapts to each platform automatically.
- **Rich standard operations** — String methods, array methods, maps, error handling, compound assignment operators.
- **Modular** — `import` splits code across files. `lib/` directory convention for reusable modules.
- **Fast** — Compiles to standalone native executables via LLVM. No runtime, no VM.
- **Safe** — Memory-safe with garbage collection. No use-after-free, no data races.
- **Simple** — Minimal boilerplate. `public static void main()` is all you need to start.

---

## ✅ Current Progress

### Phase 1: Interpreter Prototype — Complete

| Feature | Status |
|---------|--------|
| **Lexer** (32+ keywords, operators, comments) | ✅ |
| **Recursive descent parser** (precedence climbing) | ✅ |
| **AST** (Expression, Statement, Method, Class, Program) | ✅ |
| **Tree-walking interpreter** | ✅ |
| **Data types**: int, string, bool, float, arrays, objects, chan, map | ✅ |
| **Arrays**: `new int[5]`, `[1,2,3]` literals, `arr[i]`, `arr.length`, 8 built-in methods | ✅ |
| **Strings**: `s.length`, `s[0]`, comparison, concatenation, 10 built-in methods | ✅ |
| **Maps**: `map<K,V>`, `new map<K,V>()`, 9 built-in methods | ✅ |
| **For-each**: `for (int x : arr) { ... }` | ✅ |
| **Methods**: parameters, return values, nested calls | ✅ |
| **Classes**: fields, constructors, `this`, `new ClassName(args)` | ✅ |
| **Static methods**: `ClassName.method(args)` without instantiation | ✅ |
| **null value**: `null` literal, `== null` comparison | ✅ |
| **Control flow**: `for`, `while`, `for-each`, `if/else if/else`, `return`, `break`, `continue` | ✅ |
| **Error handling**: `throw`, `try/catch(string e)/finally` | ✅ |
| **Boolean logic**: `&&`, `\|\|`, `!` (short-circuit) | ✅ |
| **Arithmetic**: int/float mixed ops, `%` modulo, `+= -= *= /= %=` | ✅ |
| **`go {}` goroutines** (user-space M:N scheduler) | ✅ |
| **`chan<T>` buffered channels** (yield on block, re-enqueue on unblock) | ✅ |
| **Modules**: `import ModuleName;`, multi-file programs, `lib/` search path | ✅ |
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

### Phase 3: LLVM Backend — In Progress

Compile Joya programs to native executables via LLVM C API (LLVM 20.1.0, opaque pointers).

| Feature | Status |
|---------|--------|
| **LLVM environment** — LLVM 20.1.0 install, C API headers, build.zig linking | ✅ |
| **CLI flags** — `--compile <output.o>`, `--emit-ir <output.ll>`, `--target <triple>` | ✅ |
| **C runtime** — `main()` entry, `__chkstk` stub (Windows) | ✅ |
| **Type mapping** — int→i64, float→f64, bool→i1, string→ptr, void→void | ✅ |
| **Literals** — int, float, bool, string, null | ✅ |
| **Arithmetic** — +, -, *, /, % (integer) | ✅ |
| **Comparison** — <, >, <=, >=, ==, != (ICmp) | ✅ |
| **Boolean logic** — &&, \|\| (short-circuit + phi), ! (Not) | ✅ |
| **Control flow** — if/else, while, for, return, print/println | ✅ |
| **Variables** — var_decl, assign, alloca + store/load | ✅ |
| **Methods** — static & instance, name mangling, parameter binding | ✅ |
| **Method calls** — static `ClassName.method()`, instance `obj.method()` | ✅ |
| **Classes** — LLVM struct types, `new ClassName()`, malloc + zero-init | ✅ |
| **Fields** — `this.field` read/write via GEP, `obj.field` read | ✅ |
| **Constructors** — `void ClassName(args)` called after malloc | ✅ |
| **Float arithmetic** — FAdd/FSub/FMul/FDiv/FCmp, int↔float casts | 📋 Planned |
| **String concatenation** — runtime `strcat`/`sprintf` | 📋 Planned |
| **Arrays & strings** — C runtime for JoyaArray/JoyaString | 📋 Planned |
| **Map + Chan + goroutines** — runtime hash table, mutex+queue, threads | 📋 Planned |
| **Closures + error handling** — closure struct, setjmp/longjmp | 📋 Planned |
| **Import + multi-file** — cross-module linking | 📋 Planned |

#### LLVM Backend Architecture

```
.joya source → Lexer → Parser → AST → Compiler (LLVM C API) → LLVM IR → .o → .exe
                                                         ↓
                                              TargetMachine (native/x86_64/aarch64)
```

- **Compiler** (`src/compiler.zig`): ~1360 lines, manual extern declarations for ~80 LLVM C API functions
- **Memory**: ArenaAllocator for all compiler temps — zero leaks
- **Class compilation**: `declareClassTypes()` creates named struct types; `current_class_name` tracks compilation context
- **LLVM 20 opaque pointers**: All object pointers use `ptr`; struct types used only for GEP field access
- **Linking**: `zig cc output.o src/joya_runtime.c -o output.exe`

#### Compilation Example

```bash
# Compile to native executable
joya program.joya --compile output.o
zig cc output.o src/joya_runtime.c -o program.exe
./program.exe

# Emit LLVM IR for debugging
joya program.joya --emit-ir output.ll
```

#### Generated IR Example (Point class)

```llvm
%Point = type { i64, i64 }

define void @Point_Point(ptr %0, i64 %1, i64 %2) {
  store ptr %0, ptr %this
  %field_ptr = getelementptr %Point, ptr %this_val, i32 0, i32 0
  store i64 %1, ptr %field_ptr
  %field_ptr4 = getelementptr %Point, ptr %this_val, i32 0, i32 1
  store i64 %2, ptr %field_ptr4
  ret void
}

define i64 @Point_getX(ptr %0) {
  %field_ptr = getelementptr %Point, ptr %this1, i32 0, i32 0
  %x = load i64, ptr %field_ptr
  ret i64 %x
}
```

### Roadmap

| Phase | Goal | Status |
|-------|------|--------|
| **1** | Interpreter prototype — validate syntax & semantics | ✅ Complete |
| **2** | User-space goroutine scheduler (M:N, Fiber-based) | ✅ Complete |
| **2.5** | Cross-platform Fiber abstraction (Windows/Linux/macOS) | ✅ Complete |
| **2.6** | Language features: maps, error handling, import, compound ops | ✅ Complete |
| **3** | LLVM backend — compile to native executables | 🔄 In Progress |
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
            total += val;
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

### Error Handling

```java
try {
    throw "something went wrong";
} catch(string e) {
    println("Caught: " + e);
} finally {
    println("This always runs");
}

// Method with error handling
static int divide(int a, int b) {
    if (b == 0) throw "division by zero";
    return a / b;
}

try {
    int result = divide(10, 0);
} catch(string e) {
    println("Error: " + e);  // Error: division by zero
}
```

### Maps

```java
map<string, int> scores = new map<string, int>();
scores.put("Alice", 95);
scores.put("Bob", 87);

println(scores.get("Alice"));       // 95
println(scores.containsKey("Bob")); // true
println(scores.size());             // 2

string[] keys = scores.keys();
int[] vals = scores.values();
```

### String & Array Methods

```java
string s = "Hello World";
println(s.substring(0, 5));       // Hello
println(s.indexOf("World"));      // 6
println(s.contains("World"));     // true
println(s.toUpperCase());         // HELLO WORLD
println(s.trim());                // Hello World (if padded)
println(s.replace("World", "Joya")); // Hello Joya

string[] parts = "a,b,c".split(",");  // ["a", "b", "c"]

int[] arr = [5, 3, 1, 4, 2];
arr.sort();                       // [1, 2, 3, 4, 5]
arr.reverse();                    // [5, 4, 3, 2, 1]
arr.push(6);
println(arr.join(", "));          // 5, 4, 3, 2, 1, 6
```

### Import & Modules

```java
// In examples/lib/Math.joya
class Math {
    static int max(int a, int b) {
        if (a > b) return a;
        return b;
    }
}

// In your main file
import Math;

public class Main {
    public static void main() {
        println(Math.max(10, 20));  // 20
    }
}
```

Import searches the main file's directory and `lib/` subdirectory. Nested imports and cycle detection are supported.

### Classes & Objects

```java
class Calculator {
    int value;

    void Calculator(int v) {
        this.value = v;
    }

    int add(int x) {
        this.value += x;     // compound assignment
        return this.value;
    }
}

Calculator calc = new Calculator(10);
println(calc.add(5));      // 15
println(calc.value);       // 15
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
        map<string, int> scores = new map<string, int>();

        // Compound assignment
        x += 5;          // x = 20
        x -= 3;          // x = 17
        string s = "Hello";
        s += " World";   // s = "Hello World"

        // Comparison (int, float, string)
        println(3.14 > 2.71);       // true
        println("abc" < "abd");     // true

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

        // Error handling
        try {
            if (x < 0) throw "negative value";
        } catch(string e) {
            println("Error: " + e);
        }

        // null value
        int val = null;
        println(val == null);  // true
    }
}
```

---

## 🛠️ Build & Run

### Interpreter Mode

```bash
zig build
zig-out\bin\joya.exe examples\hello.joya    # Windows
./zig-out/bin/joya examples/hello.joya       # Linux/macOS
```

### LLVM Compile Mode (Native Executable)

> **Requirements:** LLVM 20+ installed (for `LLVM-C.dll`/`libLLVM-C.so` at runtime, and `LLVM-C.lib` at link time)

```bash
zig build

# Step 1: Compile .joya → .o (requires LLVM-C.dll in PATH)
set PATH=C:\Program Files\LLVM\bin;%PATH%     # Windows
zig-out\bin\joya.exe examples/class_test.joya --compile output.o

# Step 2: Link .o + runtime → .exe
zig cc output.o src/joya_runtime.c -o output.exe

# Step 3: Run
output.exe
```

#### CLI Flags

```
joya <file.joya> [--compile <output.o>] [--emit-ir <output.ll>] [--target <triple>]
```

| Flag | Description |
|------|-------------|
| `--compile <path>` | Compile to native object file (.o) |
| `--emit-ir <path>` | Emit LLVM IR text (.ll) for debugging |
| `--target <triple>` | Target triple (default: host native) |

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
├── build.zig              # Zig build config (LLVM linking + conditional C compilation)
├── README.md              # English readme
├── README_CN.md           # Chinese readme
├── joya.md                # Language specification
├── 修改记录.md             # Development changelog
├── llvm-c/                # LLVM C API headers (27 .h files from LLVM 20.1.0)
├── src/
│   ├── main.zig           # Entry point + import system + CLI flags
│   ├── lexer.zig          # Lexer (32+ keywords)
│   ├── ast.zig            # AST definitions
│   ├── parser.zig         # Recursive descent parser (precedence climbing)
│   ├── compiler.zig       # LLVM backend compiler (~1360 lines, ~80 extern decls)
│   ├── joya_runtime.c     # C runtime (main entry, __chkstk for Windows)
│   ├── fiber.zig          # Cross-platform Fiber abstraction (comptime backend selection)
│   ├── fiber_windows.zig  # Windows Fiber backend (Win32 API)
│   ├── fiber_ucontext.zig # Linux/macOS Fiber backend (asm context switching)
│   ├── fiber_ucontext.c   # C shim for asm context switching (x86_64 / aarch64)
│   ├── fiber_fallback.zig # Fallback backend (stub, auto-fallback to OS threads)
│   ├── scheduler.zig      # M:N goroutine scheduler (platform-agnostic)
│   └── interpreter.zig    # Interpreter (objects, arrays, channels, maps, error handling)
└── examples/
    ├── hello.joya         # Goroutines & channels
    ├── compiler_test.joya # LLVM backend test (int arithmetic + if/else + while + print)
    ├── class_test.joya    # LLVM backend class test (Point class + fields + methods)
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
    ├── test_if.joya       # if/else test
    ├── test_compare.joya  # Float/string comparison tests
    ├── test_string_methods.joya # String method tests
    ├── test_map.joya      # Map/dict tests
    ├── test_error.joya    # Error handling tests
    ├── test_compound.joya # Compound assignment tests
    ├── test_import.joya   # Import/module tests
    └── lib/
        ├── Math.joya      # Math utility class
        └── Utils.joya     # General utility class
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
