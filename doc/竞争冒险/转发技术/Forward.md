
![[attachments/Pasted image 20260602171017.png]]

# 转发（Forwarding）技术笔记

> **设计决策（定稿）**：采用 **单一 EX 转发**——所有操作数相关（含 `ADD/ADDI` 运算与 `ST` 写数据）均在 **EX 阶段** 通过 `forward_rs / forward_rd` 解决；**MEM 阶段不做转发**，只透传 EX/MEM 锁存值。  
> 本文档覆盖：转发原理、RTL 实现、LD/ST 与分支地址、仿真判读，以及「单一 EX vs 混合 MEM 旁路」的设计讨论。

---

## 1. 为什么需要转发

流水线中，多条指令同时在不同阶段执行。后一条指令在 EX 读寄存器时，前一条的结果可能：

- 还在 **EX/MEM**（刚算完，尚未写回）
- 还在 **MEM/WB**（即将写回，同拍来不及从寄存器堆读到新值）

**转发（旁路）**：不等待写回，直接把 EX/MEM 或 MEM/WB 里的最新结果送到 EX 的操作数输入端。

---

## 2. Forward 块做什么

Forward 块**只做两件事**：

1. **判断**要不要转发（比较寄存器编号）
2. **输出** `forward_rs`、`forward_rd`，**控制** EX 阶段两个 Forward MUX 选哪一路

**数据不经过 Forward 块**。  
`EX/MEM.alu_result`、`MEM/WB.write_data` 直接连到 MUX 输入；Forward 块只发「选谁」的控制信号。

---

## 3. 数据通路总览（单一 EX）

```text
                    forward_sel（cpu_top）
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
         forward_a                 forward_b
      （= forward_rs）           （= forward_rd）
              │                         │
              ▼                         ▼
         Forward_rs MUX            Forward_rd MUX
         （ALU 下端 / RS）         （ALU 上端 / RS2）
              │                         │
              ├─→ operand_a             ├─→ operand_b（rs_src=0）
              │                         └─→ rd_val_out（ST 写数据）
              ▼
            ALU
              │
              ├─ alu_result  ──→ EX/MEM ──→ MEM.mem_addr
              └─ rd_val_out  ──→ EX/MEM ──→ MEM.mem_wdata
```

**MEM 阶段**：`mem_addr ← alu_result_in`，`mem_wdata ← rd_val_in`，**无转发 MUX**。  
与使用 `main_memory` 还是 `d_cache` **无关**，接口都是 `addr / wdata / rdata`。

---

## 4. EX 阶段 Forward MUX（按数据流图约定）

```text
ID/EX
  │
  ├─ RD/RS2 ───────────────────────────> Forward_rd MUX ──> ALU 上端
  │                                              │
  │                                              └──> rd_val_out（ST Write_Data）
  │
  └─ RS ─────> Rs_src MUX ─────────────> Forward_rs MUX ──> ALU 下端
               (选 RS / imm)

EX/MEM.alu_result  ──> 两个 MUX 的【上输入】  forward = 01
MEM/WB.write_data  ──> 两个 MUX 的【下输入】  forward = 10
ID/EX 原始寄存器值 ──> 两个 MUX 的【中输入】  forward = 00
```

### Rs_src 的作用

**Rs_src 在 Forward_rs 前面**：先决定 ALU 下端用 RS 还是 imm，再决定是否被转发值覆盖。

```text
Rs_src = 0  →  ALU 下端选 ID/EX.RS（经 Forward_rs MUX）
Rs_src = 1  →  ALU 下端选 imm（立即数）
```

对 `ADDI / LD / ST`：`rs_src = 1`，运算为 **RS + imm**（基址 + 偏移）。  
`rs_src` 控制的是 **ALU 下端的 imm 选择**，不是把 imm 接到上端。

### 代码中的操作数连接（ex_stage.vhd）

图中「上/下」是数据流图约定；代码里用 `operand_a/b` 只是变量名：

```text
图中 ALU 下端 ← forward_rs_data ← forward_a
图中 ALU 上端 ← forward_rd_data ← forward_b（rs_src=0 时参与 ALU）

operand_a <= forward_rs_data
operand_b <= imm_ext_in when rs_src_in = '1' else forward_rd_data

alu_result <= alu_y
rd_val_out <= forward_rd_data    ← ST 写数据也走 forward_rd 路径
```

---

## 5. Forward 块的输入与输出

### 输入（只用于比较，不是 ALU 数据）

```text
来自 ID/EX：
  ID/EX.RS    ← 当前指令第一个源寄存器编号（基址 / rs1）
  ID/EX.RS2   ← 当前指令第二个源寄存器编号（rs2，ST 的写数据寄存器）

来自 EX/MEM：
  EX/MEM.RD        ← 上一条指令的目标寄存器
  EX/MEM.REGWrite  ← 上一条是否写寄存器
  EX/MEM.MemRead   ← 上一条是否是 LD

来自 MEM/WB：
  MEM/WB.RD        ← 再前一条的目标寄存器
  MEM/WB.REGWrite  ← 再前一条是否写寄存器
```

### 输出

```text
forward_rs  →  Forward_rs MUX（ALU 下端 / RS 路径）
forward_rd  →  Forward_rd MUX（ALU 上端 / RS2 路径 + ST 写数据）
```

代码对应：

```text
forward_a  ↔  forward_rs  ↔  比较 ID/EX.RS
forward_b  ↔  forward_rd  ↔  比较 ID/EX.RS2
```

---

## 6. 转发条件真值表

### forward = 01（从 EX/MEM 转发，优先）

```text
IF (EX/MEM.REGWrite = 1
    AND EX/MEM.MemRead = 0
    AND EX/MEM.RD != x0
    AND EX/MEM.RD = 当前源寄存器)
   forward = 01
```

- 转发数据 = `EX/MEM.alu_result`
- **LD 例外**：LD 在 EX/MEM 时 `alu_result` 只是地址，不能转发，必须等 MEM/WB 的 load 数据

### forward = 10（从 MEM/WB 转发）

```text
IF (MEM/WB.REGWrite = 1
    AND MEM/WB.RD != x0
    AND MEM/WB.RD = 当前源寄存器)
   forward = 10
```

- 转发数据 = `MEM/WB.write_data`（WB 阶段 MemToReg 的输出，**尚未写回寄存器堆**）

### forward = 00（不转发）

使用 ID/EX 锁存的 `rs_val_in` / `rd_val_in`（ID 阶段从寄存器堆读到的值）。

### 优先级

```text
01（EX/MEM）优先于 10（MEM/WB）
```

---

## 7. 特殊条件说明

### 为什么 `EX/MEM.MemRead = 0`

```text
LD  x1, 4(x0)     -- EX/MEM.alu_result = 4（地址，不是 x1 的值）
ADD x2, x1, x3    -- 不能把 4 当作 x1 转发
```

LD 的结果要到 **MEM/WB** 才能从 `write_data` 转发（`forward = 10`），或触发 load-use stall。

### 为什么 `RD != x0`

`x0` 恒为 0，写 `x0` 无效。读 `x0` 时直接得到 0，不需要转发。

### 信号缩写（RTL）

| 缩写 | 含义 |
|---|---|
| `we` / `ex_mem_we` | Write Enable，是否写寄存器（`reg_write`） |
| `mr` / `ex_mem_mr` | Memory Read，是否 LD（`mem_read`） |

---

## 8. 当前 RTL 实现（cpu_top + ex_stage）

### forward_sel 函数

```vhdl
forward_sel(
  id_ex_rs,    -- 当前 EX 指令要读的寄存器号
  ex_mem_rd,   -- EX/MEM 目标寄存器
  ex_mem_we,   -- EX/MEM 写使能
  ex_mem_mr,   -- EX/MEM 是否 LD
  mem_wb_rd,   -- MEM/WB 目标寄存器
  mem_wb_we    -- MEM/WB 写使能
)
-- 返回 "00" / "01" / "10"
```

调用：

```text
forward_a <= forward_sel(id_ex_rs,  ...)
forward_b <= forward_sel(id_ex_rs2, ...)
```

### EX 阶段 MUX（ex_stage.vhd）

```vhdl
with forward_a select
  forward_rs_data <= ex_mem_alu  when "01",
                     mem_wb_data when "10",
                     rs_val_in   when others;

with forward_b select
  forward_rd_data <= ex_mem_alu  when "01",
                     mem_wb_data when "10",
                     rd_val_in   when others;

operand_a    <= forward_rs_data;
operand_b    <= imm_ext_in when rs_src_in = '1' else forward_rd_data;
rd_val_out   <= forward_rd_data;
alu_result   <= std_logic_vector(alu_y);
```

数据来源：

```text
ex_mem_alu  ← ex_mem_alu_result   （EX/MEM）
mem_wb_data ← mem_wb_wdata        （MEM/WB 写回值，= wb_data）
rs_val_in   ← id_ex_rs_val
rd_val_in   ← id_ex_rd_val
```

### 锁存与 MEM 透传

```text
EX（组合）                时钟沿锁存              MEM（透传）
alu_result  ──→ ex_mem_alu_result  ──→ mem_addr
rd_val_out  ──→ ex_mem_rd_val      ──→ mem_wdata
```

---

## 9. 地址计算与 ID 阶段分工

| 内容 | 计算阶段 |
|---|---|
| `J` 目标地址 | **ID**（`addr_target`） |
| `BNE` 分支目标 | **ID**（`PC + offset`） |
| `LD/ST` 访存地址 | **EX**（`forwarded_rs + imm`） |
| `ADD/ADDI` 运算 | **EX**（ALU） |

```text
ID：只提前计算 J / BNE 的 target
EX：计算 LD/ST 的 address = forwarded_rs + imm
MEM：mem_addr = EX/MEM.alu_result
```

---

## 10. 实例：测试程序与 ST 转发

### 测试序列（instr_memory 当前版本）

```text
0: ADDI x1, x0, 1
1: ADDI x2, x0, 2
2: ADD  x3, x1, x2
3: ST   x3, 0(x0)      ← 实际为 0(x0)，非 0(x4)
4: HALT
```

### ADD → ST 的流水线时序（时钟周期 10ns，20ns 起为时段 1）

```text
时段 5: EX = ADD x3
时段 6: EX = ST,     EX/MEM = ADD x3
时段 7: MEM = ST,    WB = ADD x3
```

### ST x3, 0(x0) 在 EX（时段 6）应看到

```text
id_ex_rs  = x0        （基址）
id_ex_rs2 = x3        （写数据）

forward_a = 00        ← 基址 x0，不需要转发
forward_b = 01        ← x3 = EX/MEM.rd，从 EX/MEM 转发

alu_result = 0 + 0 = 0     （地址）
rd_val_out = 3             （写数据，来自 ex_mem_alu）
```

**常见误判**：

- 看 `forward_a` 以为 x3 在转发 → **错**；x3 走 `forward_b / forward_rd`
- 认为 x3 在 MEM 阶段才从 WB 转发 → **与当前 RTL 不符**（见第 11 节）

若 `forward_a = 01` 且 `alu_result = 3`：说明 RS 路径误用了 ADD 的结果，地址算错。

---

## 11. 设计讨论：单一 EX vs 混合 MEM 旁路

### 两种方案

| | 单一 EX（定稿） | 混合（EX + MEM WB 旁路） |
|---|---|---|
| ALU 操作数 | EX 转发 | EX 转发 |
| ST 写数据 | EX 的 `forward_rd → rd_val_out` | EX 或 MEM 从 WB 旁路 |
| MEM 阶段 | 透传 | 多一套 Write_Data MUX |
| 与当前 RTL | ✅ 一致 | 需改 mem_stage、EX/MEM 带 rs2 |
| 与当前数据流图 | ✅ 一致（Write_Data ← EX/MEM.RS_data） | 需在 MEM 加 MUX |

### 为何选定单一 EX

1. **通用性**：相关距离不固定（EX/MEM 或 MEM/WB），EX 两档转发（01/10）可统一处理 ADD、ADDI、ST。
2. **实现简单**：Forwarding Unit 只驱动 EX，MEM 只访存。
3. **与数据流图一致**：图中 Forward 块只连 EX；Write_Data 来自 EX/MEM.RS_data。
4. **斐波那契够用**：`ADD → ST` 在 ST 处于 EX 时，ADD 在 EX/MEM，`forward_b = 01` 即可。

### 混合方案何时考虑

- 数据流图**强制**画出 MEM 阶段 WB → Write_Data 旁路
- 需在 MEM 的 Write_Data 前加 MUX，EX/MEM 需额外传递 `rs2`

对课设验收与通用程序，**单一 EX 更稳**。

### 「MEM 阶段从 WB 转发」为何不采用

用户的另一种理解：

```text
时段 6 EX：ST 只算地址 x0+0
时段 7 MEM：ST 写内存，此时 ADD 在 WB，从 WB 取 x3
```

这在架构上可行，但**当前 RTL 未实现**：写数据在 EX 末尾锁入 `ex_mem_rd_val`，MEM 不再选 WB。  
这与 mem/cache 无关，是**数据通路设计选择**。

---

## 12. 斐波那契循环中的转发

```asm
LOOP:
  ADD  x3, x1, x2         ; 写 x3
  ST   x3, 0(x4)          ; 读 x3（写数据）、x4（基址）
  ADDI x1, x2, 0
  ADDI x2, x3, 0
  ...
```

| 相关 | 转发信号 | 时机 |
|---|---|---|
| ADD → ST 的 **x3** | `forward_b = 01` | ST 在 EX，ADD 在 EX/MEM |
| ADD → ADDI 的 **x1/x2/x3** | `forward_a/b` = 01 或 10 | ADDI 在 EX |
| ST 的 **x4 基址** | 通常 `forward_a = 00` | x4 在前一轮已写回 |

每轮循环的 `ADD → ST` 是**相邻指令**，ST 写数据在 **EX 阶段**通过 `forward_b` 从 EX/MEM 获取即可。

---

## 13. 仿真建议波形

```text
id_ex_rs, id_ex_rs2
ex_mem_rd, mem_wb_rd
forward_a, forward_b
ex_mem_alu, mem_wb_data
rs_val_in, rd_val_in
ex_alu_result, ex_rd_val
ex_mem_alu_result, ex_mem_rd_val
mem_addr, mem_wdata
```

### 判读要点

| 信号 | 含义 |
|---|---|
| `forward_* = 0` | 00，不转发 |
| `forward_* = 1` | 01，从 EX/MEM（波形 hex 显示） |
| `forward_* = 2` | 10，从 MEM/WB |
| ST 地址 | 看 `forward_a`、`alu_result` |
| ST 写数据 | 看 `forward_b`、`ex_rd_val` |

---

## 14. 无相关示例（复习）

当前 EX 需要 `RS=1, RS2=2`；EX/MEM 要写 `RD=3`：

```text
EX/MEM.RD(3) == ID/EX.RS(1)  ? 否
EX/MEM.RD(3) == ID/EX.RS2(2) ? 否
→ forward_rs = 00, forward_rd = 00
→ 使用寄存器堆读出的旧值
```

---

## 15. 小结

| 项目 | 内容 |
|---|---|
| 设计定稿 | **单一 EX 转发** |
| 转发位置 | 仅 EX 阶段两个 Forward MUX |
| 控制信号 | `forward_rs`（forward_a）、`forward_rd`（forward_b） |
| 转发源 | 01 = EX/MEM.alu_result；10 = MEM/WB.write_data |
| ST | 地址：`forward_rs` + imm；写数据：`forward_rd → rd_val_out` |
| MEM | 透传，不转发 |
| LD | 不能从 EX/MEM 转发；需 10 或 stall |

> **RD 是寄存器编号，转发的是运算结果 alu_result / write_data，不是 RD 本身。**
