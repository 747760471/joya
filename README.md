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

A fully working tree-walking interpreter that validates Joya's syntax and concurrency semantics.

| Feature | Status |
|---------|--------|
| Lexer (25+ keywords, operators, comments) | ✅ |
| Recursive descent parser (precedence climbing) | ✅ |
| AST (Expression, Statement, Method, Class, Program) | ✅ |
| Tree-walking interpreter | ✅ |
| `go {}` goroutines (OS threads, deep-copied environment) | ✅ |
| `chan<T>` buffered channels (mutex + condvar) | ✅ |
| Control flow: `for`, `while`, `if/else if/else`, `return` | ✅ |
| Boolean logic: `&&`, `\|\|`, `!` (short-circuit) | ✅ |
| Comments: `//` line, `/* */` nested block | ✅ |
| Memory management: Arena + ThreadSafeAlloc, zero leaks | ✅ |

### Roadmap

| Phase | Goal | Status |
|-------|------|--------|
| **1** | Interpreter prototype — validate syntax & semantics | ✅ Complete |
| **2** | User-space goroutine scheduler (M:N, work-stealing) | 🔜 Next |
| **3** | LLVM backend — compile to native executables | 📋 Planned |
| **4** | Self-hosting — rewrite compiler in Joya | 📋 Planned |

---

## 💻 Example

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

### Language Features at a Glance

```java
public class Main {
    public static void main() {
        // Variables & types
        int x = 15;
        string name = "Joya";
        bool ready = true;
        float pi = 3.14;
        chan<int> ch = new chan<int>(10);

        // Control flow
        if (x > 20) {
            println("big");
        } else if (x > 10) {
            println("medium");
        } else {
            println("small");
        }

        // Boolean logic with short-circuit
        if (ready && x > 0) {
            println("ready and positive");
        }

        // Loops
        for (int i = 0; i < 5; i++) {
            println("for: " + i);
        }
        while (x > 10) {
            x = x - 1;
        }

        // Modulo
        println("17 % 5 = " + 17 % 5);  // 2
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
├── src/
│   ├── main.zig           # Entry point
│   ├── lexer.zig          # Lexer
│   ├── ast.zig            # AST definitions
│   ├── parser.zig         # Recursive descent parser
│   └── interpreter.zig    # Interpreter (concurrency/channels/thread-safe)
└── examples/
    ├── hello.joya         # Goroutines & channels
    ├── features.joya      # Feature showcase
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
