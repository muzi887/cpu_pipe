
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
         （ALU 上端 / RS）         （ALU 下端 / rd_src）
              │                         │
              ├─→ operand_a             ├─→ operand_b
              │   （alu_a）              │   （alu_b）
              │                         └─→ rd_val_out（ST 写数据，Forward_rs2 另路）
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
  ├─ RS 读口 ──> rs_src_data ──> Forward_rs MUX ──> ALU 上端（A / alu_a / operand_a）
  │
  └─ rd_src MUX ──> rd_src_data ──> Forward_rd MUX ──> ALU 下端（B / alu_b / operand_b）
        │ rd_src=1: imm
        │ rd_src=0: rd_val（R 型 rs2 / BNE 第二源）
        │
        └─（ST 写数据另路）rd_val_in(rs2) ──> Forward_rs2 MUX ──> rd_val_out ──> mem_wdata
```

```text
EX/MEM.alu_result  ──> Forward 的 01 输入
MEM/WB.write_data  ──> Forward 的 10 输入
锁存原始值         ──> Forward 的 00 输入（rs_src_data / rd_src_data / rd_val_in）
```

### rd_src MUX（在 Forward_rd 之前）

**立即数与寄存器的选择在 `rd_src_data` 完成**，再送入 `Forward_rd`：

```text
rd_src_data <= imm_ext_in  when rd_src = 1   （ADDI / LD / ST 偏移）
            <= rd_val_in   when rd_src = 0   （ADD / BNE 第二源）
```

### rs_src_data

```text
rs_src_data <= rs_val_in    （RS 读口，锁存自 ID/EX）
             ──> Forward_rs ──> ALU 上端（A）
```

### rd_src=1 时 Forward_rd 的特殊规则

`forward_b` 比较的是 **ID/EX.RS2**（ST 的写数据寄存器 x3），用于 **写数据转发**，  
**不能**覆盖 ALU 下端（B）的 `rd_src_data`（imm 偏移）。

```text
rd_src = 1  →  forward_rd_data（送 ALU）= rd_src_data（恒为 imm，忽略 forward_b 的 01/10）
rd_src = 0  →  forward_rd_data（送 ALU）= Forward_rd(rd_src_data)，可转发
```

ST 写数据走独立一路：`Forward_rs2(forward_b, rd_val_in)` → `rd_val_out`。

### 代码中的操作数连接（ex_stage.vhd）

```vhdl
rs_src_data <= rs_val_in;
rd_src_data <= imm_ext_in when rd_src_in = '1' else rd_val_in;

-- Forward_rs → ALU 上端（A）
with forward_a select
  forward_rs_data <= ex_mem_alu  when "01",
                     mem_wb_data when "10",
                     rs_src_data when others;

-- Forward_rd → ALU 下端（B）；00 输入为 rd_src_data
with forward_b select
  forward_rd_reg <= ex_mem_alu  when "01",
                    mem_wb_data when "10",
                    rd_src_data when others;

forward_rd_data <= rd_src_data when rd_src_in = '1' else forward_rd_reg;

-- ST 写数据：Forward_rs2 只转发 rs2（rd_val_in），与 ALU 下端分离
with forward_b select
  forward_rs2_data <= ex_mem_alu  when "01",
                      mem_wb_data when "10",
                      rd_val_in   when others;

operand_a    <= forward_rs_data;
operand_b    <= forward_rd_data;
rd_val_out   <= forward_rs2_data when mem_write_in = '1' else forward_rd_reg;
branch_taken <= branch_in when forward_rs_data /= forward_rd_reg else '0';
```

**数据流小结**：

| 路径 | 连接 |
|------|------|
| ALU 上端（A） | `rs_src_data → Forward_rs → operand_a` |
| ALU 下端（B） | `rd_src_data → Forward_rd → operand_b`（rd_src=1 时不被 forward_b 覆盖） |
| ST 写数据 | `rd_val_in → Forward_rs2 → rd_val_out` |

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
forward_rs  →  Forward_rs MUX（rs_src_data → ALU 上端 A）
forward_rd  →  Forward_rd MUX（rd_src_data → ALU 下端 B；rd_src=1 时不覆盖 imm）
            +  Forward_rs2 MUX（rd_val_in → rd_val_out，仅 ST 写数据）
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

见第 4 节「代码中的操作数连接」完整 VHDL。

数据来源：

```text
ex_mem_alu  ← ex_mem_alu_result   （EX/MEM）
mem_wb_data ← mem_wb_wdata        （MEM/WB 写回值）
rs_src_data ← id_ex_rs_val
rd_src_data ← imm 或 id_ex_rd_val （由 rd_src 选择）
rd_val_in   ← id_ex_rd_val        （rs2，ST 写数据 + BNE 第二源）
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

### ST x3, 0(x4) 在 EX（斐波那契，ADD 紧前）应看到

```text
id_ex_rs  = x4        （基址）
id_ex_rs2 = x3        （写数据寄存器号）
rd_src    = 1         （ALU 下端 B 取 imm 偏移）

rs_src_data  = 13     （x4）
rd_src_data  = 0      （imm）
forward_a    = 00
forward_b    = 01     （x3 在 EX/MEM，用于写数据转发）

operand_a / ex_rs_val     = 13
operand_b / forward_rd_data = 0   （rd_src=1，不被 forward_b 覆盖）
alu_result   = 13 + 0 = 13
rd_val_out   = 2      （x3=ADD 结果，经 Forward_rs2 / forward_b=01）
```

**常见误判**：

- `forward_b=01` 时以为 ALU 也算 13+2=15 → **错**；`forward_b` 写数据转发与 ALU 下端（B）已分离
- 把 imm 选择放在 `operand_b` 直连、绕过 `rd_src_data → Forward_rd` → **与数据流图不符**

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
