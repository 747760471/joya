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
| Learning curve | — | New paradigm | **Zero for Java devs** |

Java developers shouldn't have to learn a completely new syntax just to get goroutines and channels. Joya gives you the best of both worlds — the structure you're productive in, with the concurrency model Go popularized.

### Design Goals

- **Familiar** — Classes, methods, braces, semicolons. If you know Java, you know Joya.
- **Concurrent by default** — `go {}` spawns a goroutine. `chan<T>` connects them. No locks, no thread pools.
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
| **`go {}` goroutines** (OS threads, deep-copied environment) | ✅ |
| **`chan<T>` buffered channels** (mutex + condvar, send/receive/close) | ✅ |
| **Comments**: `//` line, `/* */` nested block | ✅ |
| **Memory management**: Arena + ThreadSafeAlloc, zero leaks | ✅ |

### Roadmap

| Phase | Goal | Status |
|-------|------|--------|
| **1** | Interpreter prototype — validate syntax & semantics | ✅ Complete |
| **2** | User-space goroutine scheduler (M:N, work-stealing) | 🔜 Next |
| **3** | LLVM backend — compile to native executables | 📋 Planned |
| **4** | Self-hosting — rewrite compiler in Joya | 📋 Planned |

---

## 💻 Examples

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

```bash
zig build
zig-out\bin\joya.exe examples\hello.joya
```

**Requirements:** Zig 0.12.0 LTS (0.13+ dev builds have incompatible API)

## 📁 Project Structure

```
joya/
├── build.zig              # Zig build config
├── README.md              # English readme
├── README_CN.md           # Chinese readme
├── joya.md                # Language specification
├── 修改记录.md             # Development changelog
├── src/
│   ├── main.zig           # Entry point
│   ├── lexer.zig          # Lexer (28+ keywords)
│   ├── ast.zig            # AST definitions
│   ├── parser.zig         # Recursive descent parser (precedence climbing)
│   └── interpreter.zig    # Interpreter (objects, arrays, concurrency, channels)
└── examples/
    ├── hello.joya         # Goroutines & channels
    ├── features.joya      # Feature showcase
    ├── demo_sort.joya     # Concurrent sorting demo
    ├── test_array.joya    # Array tests
    ├── test_string.joya   # String tests
    ├── test_method.joya   # Method call tests
    ├── test_null.joya     # Null value tests
    ├── test_break.joya    # break/continue tests
    ├── test_class.joya    # Object & multi-class tests
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
