## 五级流水_mine
### IF/ID
`IF/ID` 读作 “从 IF 到 ID 的寄存器”：数据从 IF 流入，在 ID 被读出。

1. 分段：IF 取到的指令在本拍末尾锁进 `IF/ID`，ID 下一拍再译码
2. 并行：同一时刻 IF 取 i+3，ID 译 i+2，互不串扰
3. 冒险处理：分支误取、stall 时，可对 `IF/ID` 清 NOP 或冻结

### 1. IF（Instruction Fetch，取指）

IR←MEM[PC]

PC←PC+1

**是什么**：流水线的第 1 级，负责从存储器取出下一条要执行的指令。

**包含器件**：
- **PC（Program Counter，程序计数器）**：保存当前指令地址。
- **PC+1 加法器**：计算顺序下一条地址 `pc_plus1 = PC + 1`。
- **指令存储器 / main_memory**：以 PC 为地址读出 16 位指令（对应原来的 `MAR←PC`、`MemR`、`MDR←RAM` 取指微序列，在 IF 级一次完成）。

**本阶段做什么**：
1. 用 PC 作为地址访问存储器，读出 `instruction`；
2. 计算 `pc_plus1`；
3. 将 `{ pc, pc_plus1, instr }` 送入 **IF/ID** 流水线寄存器；
4. 若无 stall/分支，下一拍 PC 更新为 `pc_plus1`（顺序执行）。

**对应原模型机**：原来的取指微程序（地址 0–3：`LoadMAR`、`MemR`、`LoadMDR`、`LoadIR`）合并为 IF 级一个时钟周期。


```text
PC ──Addr──> i_cache ──Inst──> IF/ID ──> ID 阶段
  ↑
PC+1
```

- **输入 `Addr`**：来自 **PC**，即当前要取的指令地址  
- **输出 `Inst`**：读出的 **16 位指令**，送入 **IF/ID** 流水线寄存器  

作用等价于“**按 PC 读指令的存储器**”。在你原来的微程序模型机里，这对应取指微序列里的 **`MemR` 读 RAM**；只是这里单独画成 **`i_cache`**，表示指令从**指令侧高速存储**读出，而不是每次都慢速访问主存。

### 2. ID（Instruction Decode，译码 / 读寄存器）

RD←REGS[IR7..4]

RS←REGS[IR3..0]

IMM←REGS[IR7..4]

IMM←IR7..0

**是什么**：第 2 级，解析指令含义，读出运算所需的操作数，并产生控制信号。

**包含器件**：
- **指令字段拆分器**：从 `instr` 中拆出 `opcode、rs1、rs2、rd、imm/offset`。
- **立即数扩展器**：将 6/12 位立即数零扩展或符号扩展到 16 位（对应原来的 `IR_Operand_Ext`）。
- **reg_file（寄存器堆）读端口**：按 `rs1、rs2` 读出 `rs1_val、rs2_val`（对应原来的 AX/BX/CX/AC 分散寄存器，现统一为 x0–x15）。
- **control_unit（硬布线控制器）**：根据 `opcode` 产生 `RegWrite、MemRead、MemWrite、MemToReg、ALUSrc、ALUOp、Branch、Jump` 等控制信号（替代原来的 `microController` + CM_ROM 微程序 Map）。

**本阶段做什么**：
1. 识别指令类型（ADD、ADDI、LD、ST、BNE 等）；
2. 从寄存器堆读出源操作数；
3. 扩展立即数；
4. 产生控制信号，与操作数、地址字段一起锁入 **ID/EX**。

**对应原模型机**：原来 IR 送入微程序控制器做 Map 跳转；现在 ID 阶段一次性硬布线译码，不再走微指令序列。


---

#### 指令格式

本次设计的指令为16位，其中高8位为操作码，低8位为操作数。都是单字指令，采用固定长度编码格式

```
| 15 ─────────── 8 | 7 ── 4 | 3 ── 0 |
| opcode（操作码） | rd | rs |
| 8 bit | 4 bit | 4 bit |
```

- 高 8 位 `[15:8]`：操作码，Control 单元据此判断指令类型
- 低 8 位 `[7:0]`：操作数区，再拆成：
    - `rd` = `[7:4]`：目标寄存器编号（4 位 → 最多 16 个寄存器）
    - `rs` = `[3:0]`：源寄存器编号（4 位）

### 寻址方式

指令集中，共有三种寻址方式：立即数寻址，寄存器直接寻址，寄存器间接寻址。

---

|器件|作用|
|---|---|
|Control|读 `Ins[15:8]`（opcode），产生控制信号|
|Registers|用 `Ins[3:0]`、`Ins[7:4]` 读寄存器，得到 RS、RD|
|Unsigned extend|把 `Ins[3:0]` 零扩展成 16 位立即数|

所以：左是 IF/ID，右是 ID/EX，中间整块就是 ID 阶段。

ID/EX 寄存器内容：

```
┌─────────────────────────────────┐
│ WB  段：给写回阶段用的控制信号    │  ← 如 Reg_w（是否写寄存器）
│ MEM 段：给访存阶段用的控制信号    │  ← 如 MemRead、MemWrite
│ EX  段：给执行阶段用的控制信号    │  ← 如 ALUOp、ALUSrc
├─────────────────────────────────┤
│ RS、RD 数据，扩展后的立即数等     │
└─────────────────────────────────┘
```


### 3. EX（Execute，执行）

**是什么**：第 3 级，做算术逻辑运算、计算访存地址、判断分支是否成立。

**包含器件**：
- **Forward MUX A / B（数据转发多路选择器）**：为 ALU 选择正确操作数来源（见下文 forwarding_unit）。
- **ALUSrc MUX**：选 ALU 第二输入是 `rs2_val` 还是 `imm`。
- **ALU（算术逻辑单元）**：执行 ADD/SUB/AND 等，输出 `alu_result`（对应原来的 `AC + bus → ALU`）。
- **分支目标计算**：`branch_target = pc + imm`。
- **分支比较逻辑**：`branch_taken = Branch ∧ (rs1 ≠ rs2)`（对应原来的 `PSW_Z_flag` + `JNZ`）。

**本阶段做什么**：
1. ALU 完成运算或地址计算（如 `rd = rs1 + rs2`，或 `addr = rs1 + offset`）；
2. 对 BNE 等分支指令比较 rs1、rs2，决定是否跳转；
3. 将 `{ alu_result, rs2_val, rd, branch_taken, branch_target, control }` 锁入 **EX/MEM**。

**对应原模型机**：原来的 `LoadAC`、`ALU_op`、`AC_Sel←ALU` 在这一级完成；分支判断从微程序末尾提前到 EX。

### 4. MEM（Memory Access，访存）

**是什么**：第 4 级，对数据存储器进行读或写（Load/Store 指令在此生效，非访存指令此级可视为“空操作/pass-through”）。

**包含器件**：
- **访存地址**：直接使用 EX 级输出的 `alu_result` 作为地址（对应原来的 `MAR ← bus`）。
- **WriteData**：Store 时用 EX/MEM 中的 `rs2_val` 作为写入数据（对应原来的 `MDR → RAM`）。
- **main_memory / D-Cache**：根据 `MemRead/MemWrite` 读写存储器（对应原来的 `MemR/MemW`）。

**本阶段做什么**：
1. **LD**：`mem_data ← Mem[alu_result]`；
2. **ST**：`Mem[alu_result] ← rs2_val`；
3. **ADD/ADDI/BNE 等**：不访存，只把 `alu_result` 等信号传下去；
4. 将 `{ mem_data, alu_result, rd, control }` 锁入 **MEM/WB**。

**对应原模型机**：原来的 `MOVE AC,[BX]`、`STORE AC,[AX]` 中的 MAR+MDR+RAM 操作在这一级完成。

### 5. WB（Write Back，写回）

**是什么**：第 5 级，把运算或 Load 的结果写回寄存器堆，完成指令对通用寄存器的更新。

**包含器件**：
- **MemToReg MUX**：选择写回数据来源——`alu_result`（算术结果）或 `mem_data`（Load 结果）（对应原来的 `AC_Sel` 选 ALU 或总线）。
- **reg_file 写端口**：在 `RegWrite=1` 时，将 `WriteData` 写入 `rd`（对应原来的 `LoadAC/LoadAX/LoadBX/LoadCX`）。

**本阶段做什么**：
1. 根据 `MemToReg` 选择写回值；
2. 若 `RegWrite=1`，写入目标寄存器 `rd`；
3. 指令执行完毕。

**对应原模型机**：原来通过 `LoadAC`、`LoadAX`、`IncBX`、`DecCX` 等微命令更新寄存器；现在统一为 WB 级一次写回。

|信号|常见名字|含义|
|---|---|---|
|Reg_w|RegWrite|写使能。为 1 时允许写入；为 0 时不写，寄存器保持原值|
|Wr_addr|Write_addr / rd|写地址，要写入的寄存器编号（目标寄存器 rd）|
|writedata|Write_data|写数据，要写入该寄存器的 16 位值|

