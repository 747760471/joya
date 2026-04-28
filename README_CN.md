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
| 学习成本 | — | 新范式 | **Java 开发者零成本** |

Java 开发者不应该为了获得 goroutine 和 channel 而去学一套全新的语法。Joya 让你在最熟悉的结构里，用 Go 风格的并发模型写出高效并发程序。

### 设计目标

- **熟悉** — 类、方法、大括号、分号。会 Java 就会 Joya。
- **天生并发** — `go {}` 启动协程，`chan<T>` 连接协程。无需手动管锁和线程池。
- **轻量调度** — M:N 用户态协程调度器。数万协程运行在少数 OS 线程上。
- **高性能** — 通过 LLVM 编译为独立原生可执行文件（计划中）。无运行时，无虚拟机。
- **安全** — 垃圾回收保证内存安全。无悬垂指针，无数据竞争。
- **简洁** — 最少样板代码。`public static void main()` 即可开始。

---

## ✅ 当前进度

### 阶段一：解释器原型 — 已完成

完整可运行的树遍历式解释器，支持数组、对象、方法调用和并发。

| 功能 | 状态 |
|------|------|
| **词法分析器**（28+ 关键字、运算符、注释） | ✅ |
| **递归下降解析器**（优先级爬升法） | ✅ |
| **AST**（Expression、Statement、Method、Class、Program） | ✅ |
| **树遍历式解释器** | ✅ |
| **数据类型**：int、string、bool、float、数组、对象、chan | ✅ |
| **数组**：`new int[5]`、`[1,2,3]` 字面量、`arr[i]`、`arr.length` | ✅ |
| **for-each**：`for (int x : arr) { ... }` | ✅ |
| **字符串操作**：`s.length`、`s[0]`、字符串比较、拼接 | ✅ |
| **方法**：参数传递、返回值、嵌套调用 | ✅ |
| **类**：字段、构造函数、`this`、`new ClassName(args)` | ✅ |
| **方法调用**：`obj.method(args)`，自动绑定 `this` | ✅ |
| **null 值**：`null` 字面量、`== null` 比较 | ✅ |
| **控制流**：`for`、`while`、`for-each`、`if/else if/else`、`return`、`break`、`continue` | ✅ |
| **布尔逻辑**：`&&`、`\|\|`、`!`（短路求值） | ✅ |
| **算术运算**：int/float 混合运算、`%` 取模 | ✅ |
| **`go {}` 协程**（用户态 M:N 调度器） | ✅ |
| **`chan<T>` 带缓冲通道**（阻塞时让出 CPU，唤醒时重新入队） | ✅ |
| **注释**：`//` 行注释、`/* */` 嵌套块注释 | ✅ |
| **内存管理**：Arena + ThreadSafeAlloc，零泄漏 | ✅ |

### 阶段二：用户态协程调度器 — 已完成

基于 Windows Fiber 的 M:N 协程调度器，实现轻量级并发。

| 功能 | 状态 |
|------|------|
| **M:N 调度模型** — N 个协程运行在 M 个 OS 线程上（M = CPU 核心数） | ✅ |
| **Windows Fiber 上下文切换** — 纳秒级切换 | ✅ |
| **全局运行队列** — 锁保护，工作线程竞争获取协程 | ✅ |
| **`go {}` 创建轻量级协程** — 不再为每个 go 创建 OS 线程 | ✅ |
| **Chan 集成** — `send`/`receive` 阻塞 → 让出 CPU；数据就绪 → 重新入队 | ✅ |
| **压力测试** — 1000+ 并发协程 + 通道通信，零泄漏 | ✅ |

#### 调度器 vs OS 线程

| | OS 线程（阶段一） | Fiber 调度器（阶段二） |
|---|---|---|
| 栈开销 | ~1MB/线程 | ~64KB/Fiber |
| 上下文切换 | ~1μs（内核） | ~100ns（用户态） |
| 最大并发 | ~1,000 | ~100,000+ |
| Chan 阻塞 | condvar（内核等待） | yield（用户态让出） |

### 路线图

| 阶段 | 目标 | 状态 |
|------|------|------|
| **1** | 解释器原型 — 验证语法与并发语义 | ✅ 已完成 |
| **2** | 用户态协程调度器（M:N，Fiber 实现） | ✅ 已完成 |
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
            total = total + val;
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

### 协程 + 通道

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

### 数组与 for-each

```java
int[] nums = [10, 20, 30, 40, 50];
for (int n : nums) {
    println(n);
}
println("长度: " + nums.length);
```

### 类与对象

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

### 并发排序

```java
public class Main {
    public static void main() {
        int[] data = [64, 34, 25, 12, 22, 11, 90, 45, 78, 33];

        // 通过协程 + 通道并行求和
        chan<int> ch = new chan<int>(2);
        go {
            send(ch, partialSum(data, 0, 5));
        };
        go {
            send(ch, partialSum(data, 5, 10));
        };
        println("总和: " + (receive(ch) + receive(ch)));

        bubbleSort(data);
    }

    static int partialSum(int[] arr, int start, int end) { ... }
    static void bubbleSort(int[] arr) { ... }
}
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

        // 控制流
        if (x > 20) {
            println("大");
        } else if (x > 10) {
            println("中");
        } else {
            println("小");
        }

        // 循环与 break/continue
        for (int i = 0; i < 10; i++) {
            if (i % 2 == 0) continue;
            if (i > 7) break;
            println(i);  // 1 3 5 7
        }

        // for-each
        string[] names = ["Alice", "Bob"];
        for (string n : names) {
            println(n);
        }

        // 字符串操作
        string s = "hello";
        println(s.length);   // 5
        println(s[0]);       // h

        // null 值
        int val = null;
        println(val == null);  // true
    }
}
```

---

## 🛠️ 构建与运行

```bash
zig build
zig-out\bin\joya.exe examples\hello.joya
```

**依赖：** Zig 0.12.0 LTS（0.13+ 开发版 API 不兼容）

## 📁 项目结构

```
joya/
├── build.zig              # Zig 构建配置
├── README.md              # 英文说明
├── README_CN.md           # 中文说明
├── joya.md                # 语言规范文档
├── 修改记录.md             # 开发修改记录
├── src/
│   ├── main.zig           # 程序入口
│   ├── lexer.zig          # 词法分析器（28+ 关键字）
│   ├── ast.zig            # AST 结构定义
│   ├── parser.zig         # 递归下降解析器（优先级爬升法）
│   ├── scheduler.zig      # M:N 协程调度器（Windows Fiber）
│   └── interpreter.zig    # 解释器核心（对象、数组、通道、调度器集成）
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
    └── test_if.joya       # if/else 测试
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
