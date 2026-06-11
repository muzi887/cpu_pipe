## Hazard Unit 是什么？

**Hazard Unit（冒险处理单元）** 是五级流水线 CPU 里的一块**组合逻辑控制电路**，专门监视流水线里有没有 **冒险（hazard）**，并在需要时发出 **stall（停顿）**、**flush（冲刷）** 等信号，让多条指令并行执行时结果仍然正确。

你们课设里对应模块名是 `hazard_unit.vhd`，和 `forwarding_unit.vhd` 一起构成“冒险处理”部分。

---

### 为什么需要它？

单周期/多周期模型机一次只执行一条指令，**不存在**“下一条已经取指、上一条还没写回”的问题。

五级流水后，IF～WB 里**同时有多条指令**，就会出现：

| 冒险类型 | 典型情况 | 危险 |
|----------|----------|------|
| **数据冒险（RAW）** | 上一条写 R2，下一条马上读 R2 | 读到旧值 |
| **Load-use** | `LW` 后一条立刻用加载结果 | MEM 末才有数据，EX 太早 |
| **控制冒险** | 分支在 EX 才确定，IF/ID 已取了错误路径 | 误执行 |

**Forwarding Unit** 解决一部分数据冒险（旁路到 ALU）。  
**Hazard Unit** 负责 Forward 解决不了、以及控制/结构冲突时的 **停一拍** 或 **作废已取指令**。

---

### 它具体做什么

```text
forwarding_unit  → 发 ForwardA/B，选 EX/MEM 或 MEM/WB 的结果
hazard_unit      → 发 stall / flush，冻结 PC、插 bubble、清 NOP
```

**1. Load-use stall（数据冒险，必须停顿）**

```text
检测：ID/EX 是 Load，且 rd = 下一条（IF/ID）的 rs1 或 rs2
动作：PC_hold、IF/ID_hold、向 ID/EX 插入 bubble（控制置 0）
```

就是你前面问的 **Bubble**：由 Hazard Unit 触发，不是改汇编。

**2. 分支 flush（控制冒险）**

```text
检测：EX 级分支成立（如 BNE 条件满足）
动作：PC ← 分支目标；IF/ID、ID/EX 清成 NOP（作废误取的 1～2 条）
```

**3. 结构冒险（若 IF 与 MEM 争用同一存储器）**

有的设计里 Hazard Unit 还会在 MEM 忙时让 IF 停顿（`PCWrite=0`），你们初期报告里提到可用哈佛结构或 MEM 忙时 stall IF。

---

### 它连在数据通路的哪里？

Hazard Unit **不执行运算**，只**看**各级流水线寄存器里的字段（控制位、寄存器号、分支结果），**输出**控制信号给：

- PC 更新逻辑（是否 `Pc_en` / `PC_hold`）
- IF/ID、ID/EX 流水线寄存器的写使能 / flush
- 有时还和 Cache `cpu_ready` 等配合（miss 时整流水线冻结）

和 **control_unit（译码）**、**forwarding_unit（转发）** 分工不同：

| 模块 | 职责 |
|------|------|
| `control_unit` | 根据 opcode 产生 RegWrite、MemRead、ALUOp 等 |
| `forwarding_unit` | 数据相关时选 ALU 输入来源（旁路） |
| `hazard_unit` | 何时停、何时冲，保证时序正确 |

---

### 一句话

**Hazard Unit = 流水线的“交通警察”**：发现 Load 后立刻用、分支猜错、存储器冲突等情况时，自动 **freeze（停）** 或 **flush（冲掉错误指令）**，程序员不必在汇编里插 NOP；课设里用 VHDL 实现 `hazard_unit.vhd` 即可。

### 延伸阅读

| 文档 | 内容 |
|------|------|
| [flush.md](../flush.md) | Flush 原理、三种场景、信号优先级与波形观察 |
| [stall.md](./stall.md) | Stall 与 Flush 的区别 |