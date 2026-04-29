# Joya 语言

中文 | **[English](./README.md)**

---

> **你熟悉的 Java 语法，你想要的 Go 并发。**

Joya 是一门系统级编程语言，旨在融合 Java 熟悉的面向对象语法和 Go 优雅的 CSP 并发模型。用 Java 的写法，享受 Go 的并发能力，最终编译为接近 Go 性能的原生可执行文件。

### 为什么是 Joya？

| | Java | Go | **Joya** |
|---|---|---|---|
| 语法 | 繁琐，强 OOP | 简洁，类 C | **Java 风格的类与方法** |
| 并发 | 线程、锁、CompletableFuture | goroutine + channel | **go {} + chan\<T\>** |
| 性能 | JVM 开销 | 原生，快 | **原生执行（LLVM，计划中）** |
| 调度器 | OS 线程（每个 ~1MB 栈） | M:N 协程 | **M:N 协程（Fiber 实现）** |
| 跨平台 | JVM（跨平台） | 原生（跨平台） | **Windows / Linux / macOS** |
| 错误处理 | try/catch/finally | defer + errors | **try/catch/finally + throw** |
| 模块 | packages | packages | **import + lib/ 约定** |
| 学习成本 | — | 新范式 | **Java 开发者零成本** |

Java 开发者不应该为了获得 goroutine 和 channel 而去学一套全新的语法。Joya 让你在最熟悉的结构里，用 Go 风格的并发模型写出高效并发程序。

### 设计目标

- **熟悉** — 类、方法、大括号、分号。会 Java 就会 Joya。
- **天生并发** — `go {}` 启动协程，`chan<T>` 连接协程。无需手动管锁和线程池。
- **轻量调度** — M:N 用户态协程调度器。数万协程运行在少数 OS 线程上。
- **跨平台** — 运行于 Windows、Linux、macOS。调度器自动适配各平台。
- **丰富的标准操作** — 字符串方法、数组方法、字典、错误处理、复合赋值运算符。
- **模块化** — `import` 跨文件组织代码，`lib/` 目录约定存放可复用模块。
- **高性能** — 通过 LLVM 编译为独立原生可执行文件（计划中）。无运行时，无虚拟机。
- **安全** — 垃圾回收保证内存安全。无悬垂指针，无数据竞争。
- **简洁** — 最少样板代码。`public static void main()` 即可开始。

---

## ✅ 当前进度

### 阶段一：解释器原型 — 已完成

| 功能 | 状态 |
|------|------|
| **词法分析器**（32+ 关键字、运算符、注释） | ✅ |
| **递归下降解析器**（优先级爬升法） | ✅ |
| **AST**（Expression、Statement、Method、Class、Program） | ✅ |
| **树遍历式解释器** | ✅ |
| **数据类型**：int、string、bool、float、数组、对象、chan、map | ✅ |
| **数组**：`new int[5]`、`[1,2,3]` 字面量、`arr[i]`、`arr.length`、8 个内置方法 | ✅ |
| **字符串**：`s.length`、`s[0]`、比较、拼接、10 个内置方法 | ✅ |
| **字典**：`map<K,V>`、`new map<K,V>()`、9 个内置方法 | ✅ |
| **for-each**：`for (int x : arr) { ... }` | ✅ |
| **方法**：参数传递、返回值、嵌套调用 | ✅ |
| **类**：字段、构造函数、`this`、`new ClassName(args)` | ✅ |
| **静态方法**：`ClassName.method(args)` 无需创建对象 | ✅ |
| **null 值**：`null` 字面量、`== null` 比较 | ✅ |
| **控制流**：`for`、`while`、`for-each`、`if/else if/else`、`return`、`break`、`continue` | ✅ |
| **错误处理**：`throw`、`try/catch(string e)/finally` | ✅ |
| **布尔逻辑**：`&&`、`\|\|`、`!`（短路求值） | ✅ |
| **算术运算**：int/float 混合运算、`%` 取模、`+= -= *= /= %=` | ✅ |
| **`go {}` 协程**（用户态 M:N 调度器） | ✅ |
| **`chan<T>` 带缓冲通道**（阻塞时让出 CPU，唤醒时重新入队） | ✅ |
| **模块**：`import ModuleName;`、多文件程序、`lib/` 搜索路径 | ✅ |
| **注释**：`//` 行注释、`/* */` 嵌套块注释 | ✅ |
| **内存管理**：Arena + ThreadSafeAlloc，零泄漏 | ✅ |

### 阶段二：用户态协程调度器 — 已完成

M:N 协程调度器，支持跨平台 Fiber 上下文切换。

| 功能 | 状态 |
|------|------|
| **M:N 调度模型** — N 个协程运行在 M 个 OS 线程上（M = CPU 核心数） | ✅ |
| **跨平台上下文切换** — Windows Fiber / Linux & macOS 内联汇编 | ✅ |
| **全局运行队列** — 锁保护，工作线程竞争获取协程 | ✅ |
| **`go {}` 创建轻量级协程** — 不再为每个 go 创建 OS 线程 | ✅ |
| **Chan 集成** — `send`/`receive` 阻塞 → 让出 CPU；数据就绪 → 重新入队 | ✅ |
| **压力测试** — 1000+ 并发协程 + 通道通信，零泄漏 | ✅ |

#### 平台支持

| 平台 | 后端 | 上下文切换机制 |
|------|------|--------------|
| **Windows** | `fiber_windows.zig` | Win32 Fiber API（`CreateFiber` / `SwitchToFiber`） |
| **Linux (x86_64)** | `fiber_ucontext.zig` + C shim | 内联汇编（System V ABI callee-saved 寄存器） |
| **Linux (aarch64)** | `fiber_ucontext.zig` + C shim | 内联汇编（AAPCS64 callee-saved 寄存器） |
| **macOS (x86_64)** | `fiber_ucontext.zig` + C shim | 内联汇编（System V ABI + macOS 符号前缀） |
| **macOS (aarch64)** | `fiber_ucontext.zig` + C shim | 内联汇编（AAPCS64 callee-saved 寄存器） |
| **其他** | `fiber_fallback.zig` | 占位 → 自动回退到 OS 线程模式 |

跨平台抽象通过 `fiber.zig` 实现，使用 `@import("builtin").os.tag` 在 **comptime** 选择后端。调度器代码（`scheduler.zig`）完全平台无关 — 无 `#ifdef` 或平台特定代码。

#### 调度器 vs OS 线程

| | OS 线程（阶段一） | Fiber 调度器（阶段二） |
|---|---|---|
| 栈开销 | ~1MB/线程 | ~64KB/Fiber |
| 上下文切换 | ~1μs（内核） | ~100ns（用户态） |
| 最大并发 | ~1,000 | ~100,000+ |
| Chan 阻塞 | condvar（内核等待） | yield（用户态让出） |
| 跨平台 | 全平台（OS 提供） | Windows / Linux / macOS |

### 路线图

| 阶段 | 目标 | 状态 |
|------|------|------|
| **1** | 解释器原型 — 验证语法与并发语义 | ✅ 已完成 |
| **2** | 用户态协程调度器（M:N，Fiber 实现） | ✅ 已完成 |
| **2.5** | 跨平台 Fiber 抽象层（Windows/Linux/macOS） | ✅ 已完成 |
| **2.6** | 语言特性：字典、错误处理、import、复合赋值 | ✅ 已完成 |
| **3** | LLVM 后端 — 编译为原生可执行文件 | 🔜 下一阶段 |
| **4** | 自举 — 用 Joya 重写编译器 | 📋 计划中 |

---

## 💻 示例

### 1000 协程压力测试

```java
public class Main {
    public static void main() {
        chan<int> ch = new chan<int>(1000);

        // 启动 1000 个协程 — OS 线程模式不可能做到
        for (int i = 0; i < 1000; i++) {
            go {
                send(ch, i);
            };
        }

        // 接收并求和
        int total = 0;
        for (int i = 0; i < 1000; i++) {
            int val = receive(ch);
            total += val;
        }
        // total = 0+1+2+...+999 = 499500
        println("1000 协程总和: " + total);
    }
}
```

```
1000 协程总和: 499500
PASSED!
```

### 错误处理

```java
try {
    throw "something went wrong";
} catch(string e) {
    println("捕获异常: " + e);
} finally {
    println("无论如何都会执行");
}

// 带错误处理的方法
static int divide(int a, int b) {
    if (b == 0) throw "division by zero";
    return a / b;
}

try {
    int result = divide(10, 0);
} catch(string e) {
    println("错误: " + e);  // 错误: division by zero
}
```

### 字典

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

### 字符串与数组方法

```java
string s = "Hello World";
println(s.substring(0, 5));       // Hello
println(s.indexOf("World"));      // 6
println(s.contains("World"));     // true
println(s.toUpperCase());         // HELLO WORLD
println(s.trim());                // Hello World（去除首尾空白）
println(s.replace("World", "Joya")); // Hello Joya

string[] parts = "a,b,c".split(",");  // ["a", "b", "c"]

int[] arr = [5, 3, 1, 4, 2];
arr.sort();                       // [1, 2, 3, 4, 5]
arr.reverse();                    // [5, 4, 3, 2, 1]
arr.push(6);
println(arr.join(", "));          // 5, 4, 3, 2, 1, 6
```

### 模块/Import

```java
// 在 examples/lib/Math.joya 中
class Math {
    static int max(int a, int b) {
        if (a > b) return a;
        return b;
    }
}

// 在主文件中
import Math;

public class Main {
    public static void main() {
        println(Math.max(10, 20));  // 20
    }
}
```

import 搜索主文件所在目录和 `lib/` 子目录。支持嵌套导入和循环检测。

### 类与对象

```java
class Calculator {
    int value;

    void Calculator(int v) {
        this.value = v;
    }

    int add(int x) {
        this.value += x;     // 复合赋值
        return this.value;
    }
}

Calculator calc = new Calculator(10);
println(calc.add(5));      // 15
println(calc.value);       // 15
```

### 语法一览

```java
public class Main {
    public static void main() {
        // 变量与类型
        int x = 15;
        string name = "Joya";
        bool ready = true;
        float pi = 3.14;
        int[] arr = new int[5];
        chan<int> ch = new chan<int>(10);
        map<string, int> scores = new map<string, int>();

        // 复合赋值
        x += 5;          // x = 20
        x -= 3;          // x = 17
        string s = "Hello";
        s += " World";   // s = "Hello World"

        // 比较（int、float、string）
        println(3.14 > 2.71);       // true
        println("abc" < "abd");     // true

        // 控制流
        if (x > 20) {
            println("大");
        } else if (x > 10) {
            println("中");
        } else {
            println("小");
        }

        // 错误处理
        try {
            if (x < 0) throw "负数值";
        } catch(string e) {
            println("错误: " + e);
        }

        // null 值
        int val = null;
        println(val == null);  // true
    }
}
```

---

## 🛠️ 构建与运行

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

### 交叉编译

Zig 开箱即支持交叉编译，所有目标编译通过：

```bash
zig build -Dtarget=x86_64-linux     # Linux x86_64
zig build -Dtarget=aarch64-linux    # Linux ARM64
zig build -Dtarget=x86_64-macos     # macOS Intel
zig build -Dtarget=aarch64-macos    # macOS Apple Silicon
```

**依赖：** Zig 0.12.0 LTS（0.13+ 开发版 API 不兼容）

## 📁 项目结构

```
joya/
├── build.zig              # Zig 构建配置（条件编译 C 文件）
├── README.md              # 英文说明
├── README_CN.md           # 中文说明
├── joya.md                # 语言规范文档
├── 修改记录.md             # 开发修改记录
├── src/
│   ├── main.zig           # 程序入口 + import 系统
│   ├── lexer.zig          # 词法分析器（32+ 关键字）
│   ├── ast.zig            # AST 结构定义
│   ├── parser.zig         # 递归下降解析器（优先级爬升法）
│   ├── fiber.zig          # 跨平台 Fiber 抽象层（comptime 选择后端）
│   ├── fiber_windows.zig  # Windows Fiber 后端（Win32 API）
│   ├── fiber_ucontext.zig # Linux/macOS Fiber 后端（汇编上下文切换）
│   ├── fiber_ucontext.c   # 汇编上下文切换 C shim（x86_64 / aarch64）
│   ├── fiber_fallback.zig # 兜底后端（占位，自动回退 OS 线程）
│   ├── scheduler.zig      # M:N 协程调度器（平台无关）
│   └── interpreter.zig    # 解释器核心（对象、数组、通道、字典、错误处理）
└── examples/
    ├── hello.joya         # 协程与通道示例
    ├── features.joya      # 特性展示
    ├── demo_sort.joya     # 并发排序 Demo
    ├── stress_test.joya   # 1000 协程压力测试
    ├── test_array.joya    # 数组测试
    ├── test_string.joya   # 字符串测试
    ├── test_method.joya   # 方法调用测试
    ├── test_null.joya     # null 值测试
    ├── test_break.joya    # break/continue 测试
    ├── test_class.joya    # 对象与多类测试
    ├── test_class_min.joya # 最小 this.field 测试
    ├── test_if.joya       # if/else 测试
    ├── test_compare.joya  # float/string 比较测试
    ├── test_string_methods.joya # 字符串方法测试
    ├── test_map.joya      # 字典测试
    ├── test_error.joya    # 错误处理测试
    ├── test_compound.joya # 复合赋值测试
    ├── test_import.joya   # 模块/import 测试
    └── lib/
        ├── Math.joya      # 数学工具类
        └── Utils.joya     # 通用工具类
```

## 📄 开源协议

- **学习使用**：免费，欢迎学习、研究和修改
- **商业使用**：请联系作者获取授权
- **保留所有权利**

## 📬 联系方式

- 邮箱：747760471@qq.com
- GitHub：https://github.com/747760471/joya
- Gitee：https://gitee.com/txd747760471/joya

---

*Joya — Java 语法，Go 并发，原生性能。*
