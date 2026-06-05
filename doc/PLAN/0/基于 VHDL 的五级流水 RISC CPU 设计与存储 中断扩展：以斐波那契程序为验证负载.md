# 计算机体系结构课设实施指南：五级流水 CPU -> Cache -> 中断 -> 最小嵌入式演示

> 基础工程：`final/doc/reference/cpu_fibo`  
> 现有基础：VHDL 微程序控制、单总线、多周期 CPU，能运行斐波那契程序。  
> 目标课设：把它升级成更符合“计算机体系结构”课程重点的系统：**五级流水 CPU 为核心，加入 D-Cache 性能对比，再加入中断，最后用 UART/GPIO 做最小嵌入式演示**。

---

## 0. 先明确最终成果

这次课设不要做成“很多方向各做一点”。建议包装成一个连续题目：

> **基于 VHDL 的五级流水 RISC CPU 设计与存储/中断扩展：以斐波那契程序为验证负载**

最后交付物应包括：

1. **五级流水 CPU**：IF/ID/EX/MEM/WB，支持斐波那契程序所需指令。
2. **冒险处理**：数据转发、load-use stall、分支 flush。
3. **D-Cache**：直接映射 Cache，对比有无 Cache 的周期数和命中率。
4. **中断机制**：Timer 中断即可，保存 PC，跳转到中断服务程序，返回后继续执行。
5. **最小嵌入式演示**：UART 或 GPIO 输出斐波那契结果 / 中断计数。
6. **报告分析**：时空图、CPI、Cache 命中率、加速比、中断响应时序。

如果时间紧，优先级是：

```text
P0 五级流水 CPU
P1 D-Cache
P2 Timer 中断
P3 UART/GPIO 最小演示
P4 向量/阵列只写报告分析，不做完整 RTL
```

---

## 1. 你现在的参考工程是什么

参考工程核心文件：

| 文件 | 当前作用 | 后续处理 |
|---|---|---|
| `rtl/datapath.vhd` | 单总线数据通路，包含 PC/MAR/MDR/IR/AC/AX/BX/CX/ALU | 不建议硬改成流水线；建议作为“旧版 CPU”参考，重新拆成五级模块 |
| `rtl/microController.vhd` | 微程序控制器，靠 32 位微指令驱动数据通路 | 流水线版改成硬布线控制，不再使用微程序 ROM |
| `rtl/main_memory.vhd` | 统一存放指令和数据的同步 RAM，已加载斐波那契程序 | 可继续复用为主存；后续在 CPU 和 RAM 中间插 Cache |

当前 CPU 是：

```text
PC / IR / AC / AX / BX / CX / MAR / MDR
        |
    internal_bus 单总线
        |
       ALU
        |
   microController 微程序控制
        |
   main_memory 指令 + 数据统一存储
```

它的特点是：

- 一条指令被拆成多个微周期。
- 所有寄存器共享一条内部总线。
- `microController` 通过 `microCommands` 控制每一步。
- 这更像“计算机组成原理”的多周期模型机。

课设升级的关键是：**不要继续堆微指令，而是把执行过程固定拆成 IF/ID/EX/MEM/WB 五个阶段，让多条指令重叠执行。**

---

## 2. 总体架构从哪里改

建议新建一个流水线版目录，例如：

```text
rtl_pipe/
  cpu_top.vhd
  if_stage.vhd
  id_stage.vhd
  ex_stage.vhd
  mem_stage.vhd
  wb_stage.vhd
  reg_file.vhd
  alu.vhd
  control_unit.vhd
  hazard_unit.vhd
  forwarding_unit.vhd
  dcache.vhd
  interrupt_controller.vhd
  timer.vhd
  uart_mmio.vhd
  main_memory.vhd
```

也可以先不拆这么细，第一版合并成 4 个文件：

```text
cpu_pipe.vhd
main_memory.vhd
dcache.vhd
soc_top.vhd
```

但报告里仍然按五级模块讲。

推荐顶层连接：

```text
                +----------------------+
                |      cpu_pipe        |
                | IF ID EX MEM WB      |
                +----------+-----------+
                           |
                      data bus
                           |
                +----------v-----------+
                |    D-Cache / MMIO    |
                +----+-------------+---+
                     |             |
              +------v-----+  +----v-----+
              | main_memory |  | UART/GPIO|
              +------------+  +----------+
                           ^
                           |
                    Timer / IRQ
```

---

## 3. 第一步：把指令系统改成适合流水线的格式

现有指令已经够跑斐波那契，但名字更偏单总线模型机：

| 现有指令 | 语义 |
|---|---|
| `LOAD BX, imm` | BX <- imm |
| `LOAD CX, imm` | CX <- imm |
| `MOVE AC, [BX]` | AC <- Mem[BX] |
| `INC BX` | BX <- BX + 1 |
| `MOVE AX, BX` | AX <- BX |
| `ADD AC, [BX]` | AC <- AC + Mem[BX] |
| `INC AX` | AX <- AX + 1 |
| `STORE AC, [AX]` | Mem[AX] <- AC |
| `DEC CX` | CX <- CX - 1 |
| `JNZ LOOP` | if CX != 0 then PC <- LOOP |

五级流水更适合改成类似 RISC 的指令格式：

| 新指令 | 建议格式 | 作用 |
|---|---|---|
| `ADDI rd, rs, imm` | I 型 | rd <- rs + imm |
| `ADD rd, rs1, rs2` | R 型 | rd <- rs1 + rs2 |
| `LD rd, offset(rs1)` | I 型 | rd <- Mem[rs1 + offset] |
| `ST rs2, offset(rs1)` | S 型 | Mem[rs1 + offset] <- rs2 |
| `BNE rs1, rs2, offset` | B 型 | if rs1 != rs2 then PC <- PC + offset |
| `J target` | J 型 | 无条件跳转，可选 |
| `HALT` | 特殊 | 仿真停止或自循环 |

寄存器建议：

```text
x0 = 0，恒为 0
x1 = a，当前 f[i]
x2 = b，当前 f[i+1]
x3 = tmp，新结果
x4 = ptr，数据写入地址
x5 = cnt，循环次数
x6 = irq_count 或 UART 数据
```

这样斐波那契程序可以写成：

```asm
ADDI x1, x0, 1      ; a = 1
ADDI x2, x0, 1      ; b = 1
ADDI x4, x0, 13     ; ptr = 13
ADDI x5, x0, 5      ; cnt = n - 2

loop:
ADD  x3, x1, x2     ; tmp = a + b
ST   x3, 0(x4)      ; Mem[ptr] = tmp
ADDI x1, x2, 0      ; a = b
ADDI x2, x3, 0      ; b = tmp
ADDI x4, x4, 1      ; ptr++
ADDI x5, x5, -1     ; cnt--
BNE  x5, x0, loop

ST   x3, UART(x0)   ; 嵌入式演示：输出结果，可放到最后再做
HALT
```

如果你想少改程序，也可以保留原助记符，但内部最好仍然设计成“寄存器堆 + ALU + Load/Store”的流水线结构。

---

## 4. 第二步：实现五级流水 CPU

### 4.1 五级分别做什么

| 阶段 | 名称 | 输入 | 输出 |
|---|---|---|---|
| IF | 取指 | PC、指令存储器 | instruction、PC+1 |
| ID | 译码/读寄存器 | instruction、reg_file | rs1_val、rs2_val、imm、控制信号 |
| EX | 执行/地址计算 | ALU 输入、控制信号 | ALU 结果、分支判断 |
| MEM | 访存 | ALU 地址、写数据 | load 数据 / store 完成 |
| WB | 写回 | ALU 结果或 load 数据 | 写回寄存器堆 |

每两级之间必须加流水线寄存器：

```text
IF/ID  : pc, pc_plus1, instr
ID/EX  : pc, rs1_val, rs2_val, rd, rs1, rs2, imm, control
EX/MEM : alu_result, rs2_val, rd, branch_taken, branch_target, control
MEM/WB : mem_data, alu_result, rd, control
```

### 4.2 控制器怎么替代 `microController`

现有 `microController.vhd` 是“微程序控制”，每个周期输出一大串 `microCommands`。

流水线版改成“硬布线译码”：

```text
instruction opcode
      |
      v
control_unit
      |
      +-- RegWrite
      +-- MemRead
      +-- MemWrite
      +-- MemToReg
      +-- ALUSrc
      +-- ALUOp
      +-- Branch
      +-- Jump
```

也就是说：

- 不再用 `uAR_reg`、`uIR_reg`、`CM_ROM`。
- 每条指令在 ID 阶段直接译码出控制信号。
- 控制信号跟着流水线寄存器一路传到后面的阶段。

### 4.3 第一版先跑通的最小指令集

先只做这些：

```text
ADDI
ADD
LD
ST
BNE
HALT
```

这 6 条足够完成斐波那契、Cache 测试、中断服务程序和 UART 输出。

不要一开始就把原 CPU 的所有微指令都搬过来。流水线 CPU 的核心不是指令多，而是 **五级重叠执行 + hazard 处理正确**。

---

## 5. 第三步：处理流水线冒险

### 5.1 数据冒险：先做转发

典型例子：

```asm
ADD  x3, x1, x2
ADDI x2, x3, 0
```

第二条在 EX 阶段需要 `x3`，但第一条可能还没 WB。解决方法是转发：

```text
EX/MEM.alu_result  -> EX 阶段 ALU 输入
MEM/WB.write_data  -> EX 阶段 ALU 输入
```

`forwarding_unit` 输入：

```text
ID/EX.rs1
ID/EX.rs2
EX/MEM.rd
MEM/WB.rd
EX/MEM.RegWrite
MEM/WB.RegWrite
```

输出：

```text
ForwardA
ForwardB
```

### 5.2 load-use 冒险：必须停顿 1 周期

典型例子：

```asm
LD  x3, 0(x4)
ADD x5, x3, x2
```

load 的数据到 MEM 末尾才出来，下一条的 EX 阶段太早，单纯转发不够。做法：

```text
PCWrite = 0
IF_ID_Write = 0
ID_EX_Control = 0   ; 插入 bubble
```

判断条件：

```text
if ID_EX.MemRead = 1 and
   (ID_EX.rd = IF_ID.rs1 or ID_EX.rd = IF_ID.rs2)
then stall
```

### 5.3 控制冒险：分支先在 EX 判断，跳转后 flush

`BNE` 在 EX 阶段比较两个寄存器：

```text
branch_taken = Branch and (rs1_val != rs2_val)
branch_target = ID_EX.pc + imm
```

如果跳转成立：

```text
PC <- branch_target
IF/ID <- NOP
ID/EX <- NOP
```

第一版不要做分支预测。报告里写“采用静态不预测，分支成立时 flush 两级”即可。

---

## 6. 第四步：验证五级流水

### 6.1 必看波形

仿真时至少观察：

```text
clk, rst
pc
IF_ID_instr
ID_EX_rs1_val, ID_EX_rs2_val
EX_MEM_alu_result
MEM_WB_write_data
reg_file(x1..x6)
stall
flush
ForwardA, ForwardB
MemRead, MemWrite, RegWrite
```

### 6.2 验收标准

斐波那契程序跑完后：

```text
x3 = 13
Mem[13] = 2
Mem[14] = 3
Mem[15] = 5
Mem[16] = 8
Mem[17] = 13
```

同时能在波形里指出：

- `ADD x3, x1, x2` 后接 `ADDI x2, x3, 0` 触发 EX/MEM 转发。
- 如果你保留 `LD` 版本程序，`LD` 后接使用者会触发 1 周期 stall。
- `BNE` 跳回 `loop` 时，IF/ID 和 ID/EX 被 flush。

### 6.3 报告里的性能计算

多周期旧 CPU：

```text
总周期 = 每条指令的微周期数之和
```

流水线 CPU：

```text
理想周期 = 指令条数 + 流水级数 - 1
实际周期 = 理想周期 + stall 周期 + flush 周期 + cache miss penalty
CPI = 实际周期 / 指令条数
加速比 = 旧 CPU 总周期 / 新 CPU 总周期
```

---

## 7. 第五步：加入 D-Cache

### 7.1 为什么只做 D-Cache

课设时间有限，建议只做数据 Cache：

```text
CPU MEM 阶段 -> D-Cache -> main_memory
```

指令存储器可以先保持单周期读取，避免 I-Cache 和取指 stall 把复杂度拉太高。报告里说明：“本设计聚焦数据局部性，因此实现 D-Cache；I-Cache 留作扩展。”

### 7.2 推荐 Cache 规格

直接映射，16 行，每行 4 word，16 位数据：

```text
Line count = 16
Block size = 4 words
Data width = 16 bits
Address width = 16 bits
```

地址划分：

```text
offset = 2 bits      ; 4 word / line
index  = 4 bits      ; 16 lines
tag    = 10 bits     ; 16 - 4 - 2
```

每行保存：

```text
valid
dirty              ; 如果做写回才需要
tag
data[0..3]
```

写策略建议：

| 策略 | 难度 | 建议 |
|---|---|---|
| 写直达 write-through | 低 | 推荐第一版 |
| 写回 write-back | 中 | 有时间再做 |
| 写分配 write-allocate | 中 | 可选 |
| 写不分配 no-write-allocate | 低 | 推荐配合写直达 |

第一版最简单：

```text
读命中：1 周期返回
读缺失：从主存读 4 个 word 填入 cache line，再返回目标 word
写命中：写 Cache，同时写主存
写缺失：直接写主存，不分配 cache line
```

### 7.3 Cache 控制状态机

`dcache` 对 CPU 暴露接口：

```text
cpu_addr
cpu_wdata
cpu_read
cpu_write
cpu_rdata
cpu_ready
cache_hit
```

对 RAM 暴露接口：

```text
mem_addr
mem_wdata
mem_read
mem_write
mem_rdata
mem_ready
```

状态机：

```text
IDLE
  |
  +-- read/write request
        |
        +-- HIT  -> RESP
        |
        +-- MISS -> REFILL_0 -> REFILL_1 -> REFILL_2 -> REFILL_3 -> RESP
```

CPU 的 MEM 阶段必须支持等待：

```text
if MemRead or MemWrite:
    等 dcache.cpu_ready = 1
else:
    正常流动
```

Cache miss 时冻结流水线：

```text
PCWrite = 0
IF_ID_Write = 0
ID_EX_Write = 0
EX_MEM_Write = 0
MEM_WB_Write = 0
```

也可以第一版只冻结 IF/ID/EX，让 MEM 保持当前请求，WB 不写错误数据。

### 7.4 Cache 验证程序

用斐波那契就能看到局部性，但最好再加两个小程序：

顺序访问：

```asm
LD x1, 0(x4)
LD x2, 1(x4)
LD x3, 2(x4)
LD x4, 3(x4)
```

预期：第一次 miss，后面 3 次 hit。

冲突访问：

```asm
LD x1, 0(x0)
LD x2, 64(x0)
LD x3, 0(x0)
```

如果 0 和 64 映射到同一 index，会出现冲突 miss。

### 7.5 报告指标

至少统计：

```text
cache_access_count
cache_hit_count
cache_miss_count
hit_rate = hit / access
miss_penalty = refill_cycles
```

对比表：

| 程序 | 无 Cache 周期 | 有 Cache 周期 | Hit rate | 加速比 |
|---|---:|---:|---:|---:|
| Fibonacci | 待仿真填写 | 待仿真填写 | 待仿真填写 | 待仿真填写 |
| 顺序访问 | 待仿真填写 | 待仿真填写 | 待仿真填写 | 待仿真填写 |
| 冲突访问 | 待仿真填写 | 待仿真填写 | 待仿真填写 | 待仿真填写 |

---

## 8. 第六步：加入中断

### 8.1 中断做多大

只做一个 Timer 中断就够：

```text
timer 每 N 个周期产生 irq_timer
CPU 如果 irq_enable=1，则响应中断
保存当前 PC 到 EPC
PC 跳到固定中断入口 ISR_ADDR
ISR 执行几条指令
IRET 返回 EPC
```

可选再加一个外部中断：

```text
irq_ext = 按键 / 仿真输入
```

### 8.2 新增寄存器

```text
EPC        ; Exception Program Counter，保存被中断的返回地址
STATUS     ; bit0 = global interrupt enable
CAUSE      ; 中断原因：timer / external
```

建议地址：

```text
RESET_PC = 0x0000
ISR_ADDR = 0x0100
```

### 8.3 中断响应时机

为了简单可靠，只在“指令提交边界”响应中断：

```text
当 MEM/WB 阶段的当前指令即将提交后，
如果 irq_pending=1 and STATUS.IE=1：
  EPC <- next_pc
  CAUSE <- irq_type
  STATUS.IE <- 0
  PC <- ISR_ADDR
  flush 全部流水线
```

这样避免一条指令执行到一半被打断。

报告里可以写：**本设计采用精确中断思想，保证中断发生时，已提交指令全部完成，未提交指令全部清空。**

### 8.4 新增指令

最少两条：

```text
CSRRS / CSRRW   ; 可选，用来读写 STATUS/CAUSE
IRET            ; PC <- EPC, STATUS.IE <- 1
```

如果不想做通用 CSR 指令，可以做专用伪指令：

```text
EI      ; enable interrupt
DI      ; disable interrupt
IRET
```

### 8.5 ISR 示例

中断服务程序只做最小演示：

```asm
; 0x0100: timer_isr
ADDI x6, x6, 1        ; irq_count++
ST   x6, UART(x0)     ; 可选：输出中断次数
IRET
```

主程序仍然跑斐波那契：

```asm
EI
run_fibonacci:
  ...
```

验收现象：

- 主程序最终仍能得到 `f7 = 13`。
- `x6` 会随着 timer 中断增加。
- 波形中能看到 `irq_pending`、`EPC`、`PC -> ISR_ADDR`、`IRET -> EPC`。

---

## 9. 第七步：最小嵌入式演示

嵌入式不要做大，只做“CPU 通过内存映射 I/O 控制外设”。

### 9.1 地址规划

```text
0x0000 - 0x7FFF : RAM
0xFF00          : UART_DATA
0xFF04          : UART_STATUS
0xFF10          : GPIO_LED
0xFF20          : TIMER_CTRL
0xFF24          : TIMER_COUNT
```

地址译码：

```text
if addr = 0xFF00:
    写 UART
elif addr = 0xFF10:
    写 LED
else:
    访问 RAM / D-Cache
```

注意：**MMIO 地址不要进 Cache**。做法是：

```text
if addr(15 downto 8) = x"FF":
    bypass D-Cache，直接访问外设
else:
    访问 D-Cache
```

### 9.2 UART 最小模型

仿真里 UART 不一定真的串口发送，可以先做成一个寄存器：

```text
uart_data_reg <= cpu_wdata
uart_valid <= 1 个周期脉冲
```

波形看到 `uart_data_reg = 13`，就可以说明“斐波那契结果通过 UART 数据寄存器输出”。

如果上 FPGA，再接真正串口波特率发生器。

### 9.3 GPIO 最小模型

```text
led_reg <= cpu_wdata(7 downto 0)
```

可以让：

```asm
ST x3, GPIO_LED(x0)
```

结果是 LED 显示低 8 位。

---

## 10. 推荐时间安排

### 第 1 周：流水线最小闭环

目标：不带 Cache、不带中断，跑通斐波那契。

| 天数 | 任务 | 验收 |
|---|---|---|
| Day 1 | 定指令格式、写 `reg_file`、`alu`、`control_unit` | 单条 `ADD/ADDI` 仿真正确 |
| Day 2 | 写 IF/ID/EX/MEM/WB 流水线寄存器 | 能看到 5 条指令重叠 |
| Day 3 | 跑通无冒险小程序 | 寄存器结果正确 |
| Day 4 | 加 forwarding | RAW 冒险不出错 |
| Day 5 | 加 load-use stall 和 branch flush | 斐波那契结果为 13 |

### 第 2 周：Cache

目标：D-Cache 能命中/缺失，并能冻结流水线。

| 天数 | 任务 | 验收 |
|---|---|---|
| Day 1 | 写直接映射 Cache 数据结构 | 地址 tag/index/offset 正确 |
| Day 2 | 实现读命中、读缺失 refill | 顺序访问 1 miss + 3 hit |
| Day 3 | 实现写直达 | Store 后主存数据正确 |
| Day 4 | 接入 CPU MEM 阶段 | miss 时流水线等待 |
| Day 5 | 统计 hit/miss/cycles | 完成对比表 |

### 第 3 周：中断 + 最小嵌入式

目标：Timer 打断斐波那契，UART/GPIO 输出结果。

| 天数 | 任务 | 验收 |
|---|---|---|
| Day 1 | 写 timer 和 irq_pending | 周期性产生中断 |
| Day 2 | 加 EPC/STATUS/CAUSE 和 PC 跳转 | PC 能跳到 ISR |
| Day 3 | 加 IRET 和 flush | ISR 后回到主程序 |
| Day 4 | 加 UART/GPIO MMIO | 写 `0xFF00/0xFF10` 有波形 |
| Day 5 | 联调完整 demo | 主程序结果正确，中断计数正确 |

### 第 4 周：整理报告和答辩材料

目标：把“做了什么”变成“体系结构分析”。

必须补齐：

- 总体框图。
- 五级流水时空图。
- 冒险处理表。
- Cache 地址划分图。
- 中断响应时序图。
- 有/无 Cache 周期对比表。
- 仿真波形截图。
- 资源使用与不足。

---

## 11. 报告建议结构

```text
摘要
1. 课设背景与目标
2. 原多周期微程序 CPU 分析
3. 五级流水 CPU 设计
   3.1 指令系统
   3.2 数据通路
   3.3 控制器
   3.4 流水线寄存器
   3.5 数据冒险与控制冒险处理
4. D-Cache 设计
   4.1 Cache 参数
   4.2 地址划分
   4.3 命中/缺失状态机
   4.4 性能对比
5. 中断系统设计
   5.1 Timer 中断
   5.2 EPC/STATUS/CAUSE
   5.3 中断入口与返回
6. 最小嵌入式演示
   6.1 MMIO 地址空间
   6.2 UART/GPIO 输出
7. 仿真验证
8. 性能分析
9. 总结与展望
```

---

## 12. 答辩怎么讲

建议答辩主线：

1. **我原来有一个多周期微程序 CPU**，能跑斐波那契，但每条指令要多个微周期，吞吐率低。
2. **我把它升级成五级流水 CPU**，用 IF/ID/EX/MEM/WB 让多条指令重叠执行。
3. **流水线会带来冒险**，所以实现了 forwarding、load-use stall 和 branch flush。
4. **流水线提高吞吐后，访存成为瓶颈**，所以加入直接映射 D-Cache，并统计 hit rate 和周期数。
5. **为了接近真实系统**，加入 Timer 中断，支持 EPC 保存和 IRET 返回。
6. **最后用 MMIO UART/GPIO 做最小嵌入式演示**，证明 CPU 能和外设交互。

可以准备一句总结：

> 本课设从一个多周期模型机出发，完成了向现代处理器关键机制的递进扩展：时间并行的流水线、空间局部性的 Cache、异步事件处理的中断，以及内存映射 I/O 的最小 SoC 演示。

---

## 13. 常见坑

### 13.1 不要把微程序 CPU 直接“套壳”叫流水线

如果还是 `microCommands` 一步一步控制同一条指令，就不是五级流水。必须有：

```text
IF/ID
ID/EX
EX/MEM
MEM/WB
```

并且波形中能看到不同指令同时处于不同阶段。

### 13.2 分支 flush 不做会算错

`BNE loop` 成立时，后面已经取到的顺序指令必须清掉，否则会执行错路径。

### 13.3 Cache miss 时 CPU 不能继续跑

如果 `dcache_ready = 0`，MEM 阶段还没拿到数据，后面的写回不能发生。否则寄存器会写入旧值或未知值。

### 13.4 MMIO 不能被 Cache 缓存

UART/GPIO/Timer 是外设寄存器，不是普通内存。访问 `0xFFxx` 时必须绕过 Cache。

### 13.5 中断要在指令边界处理

不要在任意流水级中间直接改 PC。建议统一在提交边界响应，并 flush 流水线，这样最好解释，也最不容易错。

---

## 14. 最小验收清单

如果老师只看最终效果，至少保证：

- [ ] 五级流水波形能看出 5 个阶段并行。
- [ ] 斐波那契结果正确：`f7 = 13`。
- [ ] RAW 冒险有转发信号。
- [ ] load-use 冒险有 stall。
- [ ] 分支成立有 flush。
- [ ] D-Cache 有 hit/miss 统计。
- [ ] Cache miss 时流水线等待。
- [ ] Timer 中断能跳到 ISR。
- [ ] `IRET` 后能回主程序。
- [ ] UART/GPIO 能输出结果或中断计数。

---

## 15. 如果只剩两周怎么办

砍到最小：

```text
必做：
1. 五级流水 CPU
2. forwarding + stall + flush
3. 斐波那契仿真
4. 直接映射 D-Cache，只做读 Cache

可选：
1. Timer 中断只做波形演示
2. UART 只做 MMIO 寄存器，不做真实串口

不做：
1. 写回 Cache
2. 复杂优先级中断
3. 完整嵌入式 SoC
4. 完整向量处理器
```

报告里仍然可以写“扩展设计”，但 RTL 只实现核心闭环。

---

## 16. 最终简历描述

可以写成：

> 基于 VHDL/Quartus 设计五级流水 RISC CPU，支持 IF/ID/EX/MEM/WB、数据转发、load-use stall 与分支 flush；集成直接映射 D-Cache 并统计斐波那契程序 CPI/命中率；实现 Timer 中断、EPC/IRET 机制和内存映射 UART/GPIO 最小 SoC 演示。

这比单独写“实现斐波那契 CPU”更能体现体系结构能力。

