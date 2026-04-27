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
| 学习成本 | — | 新范式 | **Java 开发者零成本** |

Java 开发者不应该为了获得 goroutine 和 channel 而去学一套全新的语法。Joya 让你在最熟悉的结构里，用 Go 风格的并发模型写出高效并发程序。

### 设计目标

- **熟悉** — 类、方法、大括号、分号。会 Java 就会 Joya。
- **天生并发** — `go {}` 启动协程，`chan<T>` 连接协程。无需手动管锁和线程池。
- **高性能** — 通过 LLVM 编译为独立原生可执行文件（计划中）。无运行时，无虚拟机。
- **安全** — 垃圾回收保证内存安全。无悬垂指针，无数据竞争。
- **简洁** — 最少样板代码。`public static void main()` 即可开始。

---

## ✅ 当前进度

### 阶段一：解释器原型 — 已完成

完整可运行的树遍历式解释器，验证了 Joya 的语法设计和并发语义。

| 功能 | 状态 |
|------|------|
| 词法分析器（25+ 关键字、运算符、注释） | ✅ |
| 递归下降解析器（优先级爬升法） | ✅ |
| AST（Expression、Statement、Method、Class、Program） | ✅ |
| 树遍历式解释器 | ✅ |
| `go {}` 协程（OS 线程，环境深拷贝） | ✅ |
| `chan<T>` 带缓冲通道（mutex + condvar） | ✅ |
| 控制流：`for`、`while`、`if/else if/else`、`return` | ✅ |
| 布尔逻辑：`&&`、`\|\|`、`!`（短路求值） | ✅ |
| 注释：`//` 行注释、`/* */` 嵌套块注释 | ✅ |
| 内存管理：Arena + ThreadSafeAlloc，零泄漏 | ✅ |

### 路线图

| 阶段 | 目标 | 状态 |
|------|------|------|
| **1** | 解释器原型 — 验证语法与并发语义 | ✅ 已完成 |
| **2** | 用户态协程调度器（M:N 模型，工作窃取） | 🔜 下一阶段 |
| **3** | LLVM 后端 — 编译为原生可执行文件 | 📋 计划中 |
| **4** | 自举 — 用 Joya 重写编译器 | 📋 计划中 |

---

## 💻 示例

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

### 语法一览

```java
public class Main {
    public static void main() {
        // 变量与类型
        int x = 15;
        string name = "Joya";
        bool ready = true;
        float pi = 3.14;
        chan<int> ch = new chan<int>(10);

        // 控制流
        if (x > 20) {
            println("大");
        } else if (x > 10) {
            println("中");
        } else {
            println("小");
        }

        // 布尔逻辑（短路求值）
        if (ready && x > 0) {
            println("就绪且为正数");
        }

        // 循环
        for (int i = 0; i < 5; i++) {
            println("for: " + i);
        }
        while (x > 10) {
            x = x - 1;
        }

        // 取模
        println("17 % 5 = " + 17 % 5);  // 2
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
│   ├── lexer.zig          # 词法分析器
│   ├── ast.zig            # AST 结构定义
│   ├── parser.zig         # 递归下降解析器
│   └── interpreter.zig    # 解释器核心（并发/通道/线程安全）
└── examples/
    ├── hello.joya         # 协程与通道示例
    ├── features.joya      # 特性展示
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
