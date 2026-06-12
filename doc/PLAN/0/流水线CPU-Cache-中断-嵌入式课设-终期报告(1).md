# 计算机系统结构课设 · 终期报告

> 题目：基于 VHDL 的五级流水 RISC CPU 设计与存储/中断扩展——以斐波那契程序为验证负载  
> 姓名：（填写）  
> 学号：（填写）  
> 班级：（填写）  
> 指导教师：（填写）  
> 提交日期：2026-06-10

---

## 摘要

本课设以《计算机组成原理》课程中已完成的非流水线冯诺依曼架构模型机为起点，在保持斐波那契为统一验证负载的前提下，递进完成了五级流水 RISC CPU、I/D Cache 存储层次、Timer 精确中断与 MMIO 最小 SoC 的设计与实现。工作内容包括：五级流水 CPU（RAW 转发、BNE/J flush、load-use stall），I/D 双 Cache 与 mem_grant 主存仲裁、D-Cache 命中率统计、LD 指令、Timer 精确中断（EPC/STATUS/CAUSE、EI/DI/IRET）、UART/GPIO/Timer MMIO（is_mmio 旁路）、HALT 与中断协同、UART/GPIO 裸机输出演示、斐波那契与 ISR 联调，以及相对多周期模型机的 CPI/加速比分析（§9.2）。向量/阵列扩展（P4）未在 RTL 中实现，已在第 10 章从体系结构角度完成扩展路径与性能分析。

关键词：五级流水线、RISC、D-Cache、精确中断、MMIO、SoC

---

## 1. 课设背景与目标

### 1.1 课设背景

本课程设计属于计算机系统结构课程。项目基础为《计算机组成原理》实验中实现的非流水线冯诺依曼架构模型机：微程序控制器驱动单总线数据通路，经多周期串行执行完成取指—译码—执行；主存统一存放指令与数据，已能运行斐波那契计算程序。

课设要求在上述基础上完成递进扩展：以五级流水 CPU 为核心并处理流水线冒险；扩展 I/D Cache 并对比性能；实现 Timer 中断与最小 MMIO（UART/GPIO）；以斐波那契程序验证功能；提交终期报告、RTL、仿真波形及 CPI/命中率分析。

### 1.2 升级动机

现有多周期模型机将一条指令拆成若干微周期串行完成，吞吐率低，无法指令重叠；微程序控制器与固定五级流水阶段不匹配；存储器直连主存、无 Cache，访存成为瓶颈；亦未实现外设与中断，难以演示真实嵌入式系统行为。

据此，升级方向为：用硬布线译码与流水线寄存器替代微程序控制，实现 IF/ID/EX/MEM/WB 五级重叠；在 MEM 级接入直接映射 D-Cache；增加 Timer 中断及 UART/GPIO 的 MMIO 映射，构成最小 SoC。

### 1.3 目标与优先级


| 优先级 | 目标                             | 状态   |
| --- | ------------------------------ | ---- |
| P0  | 五级流水 CPU + hazard 处理 + 斐波那契验证  | 已完成  |
| P1  | D-Cache（读命中/缺失、写直达、性能统计）       | 已完成  |
| P2  | Timer 中断（EPC/STATUS/IRET、精确中断） | 已完成  |
| P3  | UART/GPIO 最小嵌入式演示              | 已完成  |
| P4  | 向量/阵列等扩展（报告级体系结构分析）            | 报告分析 |



| 编号  | 目标             | 预期结果                                   | 状态  |
| --- | -------------- | -------------------------------------- | --- |
| V1  | 五级流水并行         | 波形中可见不同指令处于 IF/ID/EX/MEM/WB            | 通过  |
| V2  | 斐波那契正确性        | x3 = 13，Mem[23..27] = 2,3,5,8,13       | 通过  |
| V3  | RAW 转发         | ForwardA/ForwardB 波形可见                 | 通过  |
| V4  | load-use stall | LD 后接使用者 stall 1 拍                     | 通过  |
| V5  | 分支 flush       | BNE 成立时 IF/ID、ID/EX 清空                 | 通过  |
| V6  | D-Cache 统计     | hit/miss/hit_rate 可观测                  | 通过  |
| V7  | Cache miss 等待  | cpu_ready=0 时流水线冻结                     | 通过  |
| V8  | Timer 中断       | PC 跳转 ISR，IRET 返回 EPC                  | 通过  |
| V9  | MMIO 输出        | UART/GPIO 写入 13，is_mmio=1              | 通过  |
| V10 | HALT + 中断协同    | HALT 停机、irq_take/iret_commit 与 PC 行为正确 | 通过  |


---

## 2. 基础模型机分析

### 2.1 架构概述

基础模型机为典型的冯诺依曼结构：main_memory 统一存储指令与数据。数据通路以 internal_bus 单总线为核心，PC、MAR、MDR、AC、AX、BX、CX 等寄存器经多路选择器分时访问总线；ALU 完成加减与逻辑运算，并将 OpCode、PSW_Z_flag 反馈给控制器。

控制单元采用微程序控制：控制逻辑存于控制存储器 CM_ROM，执行流程为取指（固定微地址 0–3）→ 译码映射（按 OpCode 跳转）→ 执行微指令序列。条件分支 JNZ 依赖零标志实现循环。原系统框图见 Fig-1。

### 2.2 现有指令与执行特点

旧版指令集包含 LOAD、MOVE、INC、STORE、DEC、JNZ 等 9 条指令，以 4 位 OpCode 编码，面向斐波那契迭代。每条用户指令对应多拍微周期，寄存器与 ALU 通过总线分时复用，无指令级并行。

### 2.3 不足与改造策略

非流水线架构无法重叠执行；无 Cache、中断与外设接口。改造策略：新建流水线 RTL，按 IF/ID/EX/MEM/WB 拆分模块，ID 阶段硬布线译码；在 SoC 顶层逐级扩展 D-Cache、中断控制器与 MMIO 外设。

---

## 3. 总体架构设计

### 3.1 系统顶层结构

SoC 顶层连接关系见图 3（Fig-3）。数据通路上，IF 经 I-Cache、MEM 经 D-Cache 共用 main_memory；MEM 级 is_mmio=1 时旁路至 Timer/UART/GPIO；Timer 产生 irq_timer 送入 interrupt_controller，再与 cpu_top 协同完成精确中断。完整互联与例化见 soc_top.vhd。

### 3.2 五级流水数据通路

五级流水 CPU 内部数据通路见 Fig-2（五级流水数据通路图）。

PC 驱动 IF 经 I-Cache 取指，经 IF/ID、ID/EX、EX/MEM、MEM/WB 四级流水线寄存器传递；ID 读寄存器堆并产生控制信号，EX 执行 ALU 与分支判断（含转发 MUX），MEM 经 D-Cache 或 MMIO 访存，WB 写回。forward_unit 处理 RAW 转发；hazard_unit 处理 BNE flush 与 load-use stall；cache_control 在 miss 时全局 stall；interrupt_controller 与 SYS 指令实现精确中断。

### 3.3 RTL 目录结构

工程 RTL 位于 cpu_pipe/ 目录，主要模块如下（完整源码随课设一并提交）：


| 路径 | 功能说明 |
| ---- | -------- |
| rtl/cpu_top.vhd | CPU 顶层、流水寄存器、irq_take/iret/halt |
| rtl/if_stage.vhd | 取指与 PC（halt、pc_src=11 重定向） |
| rtl/id_stage.vhd | 译码、寄存器堆、SYS(EI/DI/IRET) |
| rtl/ex_stage.vhd、mem_stage.vhd、wb_stage.vhd | EX/MEM/WB 各级 |
| rtl/forward_unit.vhd、hazard_unit.vhd、cache_control.vhd | 转发与冒险、Cache stall |
| rtl/i_cache.vhd、d_cache.vhd、main_memory.vhd | I/D Cache 与统一主存 |
| rtl/interrupt_controller.vhd、timer.vhd、uart_mmio.vhd、gpio_mmio.vhd | 中断与外设 |
| rtl/soc_top.vhd | SoC 顶层、主存仲裁、is_mmio |
| tb/tb_soc_top.vhd | 功能仿真 testbench |
| sim/run.do | ModelSim 仿真脚本 |

### 3.4 实现对照


| 模块                | 规划    | 状态   | 说明                                     |
| ----------------- | ----- | ---- | -------------------------------------- |
| 五级流水骨架            | P0    | 已完成  | IF/ID/EX/MEM/WB 五级重叠                   |
| 硬布线控制 + SYS       | P0/P2 | 已完成  | ADDI/ADD/LD/ST/BNE/J/HALT + EI/DI/IRET |
| RAW 转发            | P0    | 已完成  | forward_unit.vhd + EX 级 Forward MUX    |
| BNE / J flush     | P0    | 已完成  | hazard_unit.vhd；J 在 ID 级 pc_src=10     |
| load-use stall    | P0    | 已完成  | LD→Use 检测，stall 1 拍 + bubble           |
| I/D Cache + stall | P1    | 已完成  | 写直达 D-Cache，cache_control              |
| 主存仲裁 mem_grant    | P1    | 已完成  | I-Cache 读优先                            |
| D-Cache 统计        | P1    | 已完成  | hit_count / miss_count / hit_rate      |
| Timer 精确中断        | P2    | 已完成  | EPC/STATUS/IE/CAUSE、irq_take、IRET      |
| MMIO + is_mmio    | P3    | 已完成  | 0xFFxx 旁路 D-Cache                      |
| HALT 停机           | P3    | 已完成  | halt_latched + 中断协同                    |
| 向量/阵列扩展           | P4    | 报告分析 | 体系结构分析，见 §10                           |


---

## 4. 指令系统设计

### 4.1 设计原则

本课设指令系统面向五级流水 CPU 与最小 SoC 的统一验证负载进行设计，在旧模型机 9 条微程序指令基础上重新规划编码与语义，遵循以下原则。

Load/Store 与流水匹配：运算类指令仅在寄存器与 ALU 之间完成，不直接访问主存；数据读写统一经 LD/ST 发起，控制转移由 BNE、J 承担，停机由 HALT 承担。该划分与 IF/ID 硬布线译码及 EX/MEM 阶段分工一致，便于转发、load-use stall 与分支 flush 的处理。

定长规整编码：全部指令为 16 位定长，按 R/I/S/B/J 五种格式划分 OpCode、寄存器编号与立即数字段（详见 §4.2）；通用寄存器 x0 硬件恒为 0 且不可写回；立即数与访存偏移采用 6 位有符号补码，取值范围 −32～+31。

最小可验证集：在覆盖斐波那契迭代、MMIO 输出、Timer 中断及停机返回等功能的前提下，控制指令种类与 OpCode 占用，降低译码与冒险处理复杂度。

可扩展性：在 16 位编码空间内为 SYS/CSR 及后续功能预留 OpCode 与子操作字段；指令语义与 Cache、MMIO 旁路、精确中断等 SoC 机制相互独立，便于按模块分层集成。具体指令编码见 §4.3，验证程序见 §4.5。

### 4.2 指令格式


| 格式  | opcode | rs1 | rs2 | rd  | funct / imm / offset / target | 典型用途                |
| --- | ------ | --- | --- | --- | ----------------------------- | ------------------- |
| R 型 | 4      | 3   | 3   | 3   | funct(3)                      | 寄存器间运算（如 ADD）       |
| I 型 | 4      | 3   | —   | 3   | imm(6)                        | 立即数运算、加载（如 ADDI、LD） |
| S 型 | 4      | 3   | 3   | —   | offset(6)                     | 存储（如 ST）            |
| B 型 | 4      | 3   | 3   | —   | offset(6)                     | 条件分支（如 BNE）         |
| J 型 | 4      | —   | —   | —   | target(12)                    | 无条件跳转（如 J）          |


### 4.3 指令集与 OpCode 编码


| OpCode (4b) | 助记符  | 格式  | funct / 子操作            | 说明                                 |
| ----------- | ---- | --- | ---------------------- | ---------------------------------- |
| 0000        | ADDI | I   | —                      | rd ← rs + imm                      |
| 0001        | ADD  | R   | funct=000 ADD          | rd ← rs1 + rs2                     |
| 0010        | LD   | I   | —                      | rd ← Mem[rs1 + offset]             |
| 0011        | ST   | S   | —                      | Mem[rs1 + offset] ← rs2            |
| 0100        | BNE  | B   | —                      | if rs1 ≠ rs2 then PC ← PC + offset |
| 0101        | J    | J   | —                      | PC ← target                        |
| 1110        | SYS  | I   | 000=EI，001=DI，010=IRET | 访问 CSR                             |
| 1111        | HALT | —   | —                      | PC 冻结                              |


### 4.4 寄存器约定


| 寄存器   | 用途                              |
| ----- | ------------------------------- |
| x1–x5 | 斐波那契 a/b/tmp/ptr/cnt            |
| x6    | 中断计数 irq_cnt                    |
| x7    | UART 基址（LD x7, 31(x0) → 0xFF00） |


### 4.5 验证程序

主程序：斐波那契循环 → LD/ST 输出 UART/GPIO → EI → HALT；Timer 溢出后进 ISR @ 0x0100（再次 ST UART）。完整汇编清单与机器码见 §4.6。

### 4.6 主存布局与机器码

指令区（主程序 0～15，ISR @ 0x0100）：


| 地址     | 汇编               | 机器码 (16b) |
| ------ | ---------------- | --------- |
| 0      | ADDI x1, x0, 1   | 0041      |
| 1      | ADDI x2, x0, 1   | 0081      |
| 2      | ADDI x4, x0, 23  | 012F      |
| 3      | ADDI x5, x0, 5   | 0145      |
| 4      | ADD x3, x1, x2   | 1298      |
| 5      | ST x3, 0(x4)     | 38C0      |
| 6      | ADDI x1, x2, 0   | 0440      |
| 7      | ADDI x2, x3, 0   | 0680      |
| 8      | ADDI x4, x4, 1   | 0901      |
| 9      | ADDI x5, x5, -1  | 0B7F      |
| 10     | BNE x5, x0, LOOP | 4A3A      |
| 11     | LD x7, 31(x0)    | 21DF      |
| 12     | ST x3, 0(x7)     | 3EC0      |
| 13     | ST x3, 16(x7)    | 3ED0      |
| 14     | EI               | E000      |
| 15     | HALT             | F000      |
| 0x0100 | ADDI x6, x6, 1   | 0D81      |
| 0x0101 | ST x6, 0(x7)     | 3F80      |
| 0x0102 | IRET             | E002      |


数据区：


| 地址    | 内容 / 运行结果                    |
| ----- | ---------------------------- |
| 23–27 | 2, 3, 5, 8, 13（斐波那契写回）       |
| 31    | 0xFF00（UART 基址常量，供 LD 载入 x7） |


编码说明：imm/offset 为 6 位有符号补码；BNE 的 offset = target_pc − pc_BNE（pc 为 BNE 指令地址，本程序中为 −6）。取指与访存采用哈佛接口，指令区与数据区地址独立编号。

运行后：Mem[23..27]=2,3,5,8,13；debug_uart_data=000D（13）、debug_led=000D；EI 后 debug_status_ie=1；每次 Timer 中断 ISR 将递增后的 x6 写入 UART；IRET 返回 EPC=0x10 后再次停机。

---

## 5. 五级流水 CPU 详细设计

### 5.1 各级功能

IF：按 PC 取指，输出 instruction、PC+1

ID：译码、读寄存器堆，产生 imm 与各控制信号

EX：ALU 运算、分支比较与目标地址计算

MEM：经 D-Cache 完成 load/store

WB：将 ALU 结果或 load 数据写回寄存器堆

段间流水线寄存器分别锁存：IF/ID（pc, instr）、ID/EX（操作数、rd、控制）、EX/MEM（alu_result、分支信息、控制）、MEM/WB（mem_data、alu_result、控制）。

### 5.2 控制真值表

ID 阶段 control_unit 根据 opcode 一次性产生 RegWrite、MemRead、MemWrite、MemToReg、ALUSrc、ALUOp、Branch、Jump，并随流水线寄存器向后传递，替代原微程序控制器中的 uAR_reg、uIR_reg、CM_ROM。


| 指令         | RegWrite | MemRead | MemWrite | MemToReg | ALUSrc | ALUOp | Branch | Jump |
| ---------- | -------- | ------- | -------- | -------- | ------ | ----- | ------ | ---- |
| ADDI       | 1        | 0       | 0        | 0        | 1      | ADD   | 0      | 0    |
| ADD        | 1        | 0       | 0        | 0        | 0      | ADD   | 0      | 0    |
| LD         | 1        | 1       | 0        | 1        | 1      | ADD   | 0      | 0    |
| ST         | 0        | 0       | 1        | 0        | 1      | ADD   | 0      | 0    |
| BNE        | 0        | 0       | 0        | 0        | 0      | —     | 1      | 0    |
| J          | 0        | 0       | 0        | 0        | —      | —     | 0      | 1    |
| HALT       | 0        | 0       | 0        | 0        | —      | —     | 0      | 0    |
| EI/DI/IRET | 0        | 0       | 0        | 0        | —      | —     | 0      | 0    |


---

## 6. 流水线冒险处理

### 6.1 RAW 转发

典型 RAW 场景：ADD x3, x1, x2 后接 ADDI x2, x3, 0，EX 阶段需要尚未 WB 的 x3。转发路径为 EX/MEM.alu_result 与 MEM/WB.write_data 回注 EX 级 ALU 输入。

转发单元根据 ID/EX.rs1/rs2 与 EX/MEM.rd、MEM/WB.rd 比较，输出 ForwardA/ForwardB（00=ID/EX，01=EX/MEM，10=MEM/WB）。若 EX/MEM 为 load 指令（MemRead=1），其结果尚非最终数据，不可从 EX/MEM 转发；EX/MEM 与 MEM/WB 同时命中时 EX/MEM 优先。时序见图 §6.5（1）。

### 6.2 load-use Stall

检测：ID/EX.MemRead=1 且 ID/EX.rd≠0，且 rd 等于 IF/ID 的 rs1 或 rs2。处理：stall 1 拍（pc_en=0、ifid_en=0），ID/EX 插 bubble；解除后 MEM/WB 转发（forward=10）。时序见图 §6.5（2）。

实现见 hazard_unit.vhd：当 ID/EX 为 Load 且 rd 与 IF/ID 的 rs1/rs2 冲突时置 load_use=1。

load-use 冻结 IF/ID；BNE flush 清空 IF/ID 为 NOP。

### 6.3 分支 Flush

BNE 在 EX 阶段比较 rs1、rs2，目标地址 branch_target = ID/EX.pc + sign_ext(offset)。采用静态不预测：分支成立时 PC ← target，IF/ID 与 ID/EX 清空为 NOP，代价 2 拍误取指。时序见图 §6.5（3）。

### 6.4 冒险汇总


| 冒险类型          | 处理策略                                | 代价     |
| ------------- | ----------------------------------- | ------ |
| RAW（ALU→ALU）  | 转发                                  | 0 周期   |
| RAW（Load→Use） | stall 1 拍 + MEM/WB 转发               | 1 周期   |
| BNE 控制冒险      | flush 2 级                           | 2 周期   |
| Cache 结构冒险    | cache_stall 冻结（见 §7.8）              | 0～N 周期 |
| 中断/IRET       | flush_all，wb_commit 边界              | —      |
| HALT 协同       | halt_latched + irq_take/iret_commit | —      |


### 6.5 五级流水时序图

以下以指令进入 IF 为 T0，给出三类典型冒险的五级流水时序。列 IF/ID/EX/MEM/WB 表示该拍结束时各段寄存器中的有效指令；bubble 表示 hazard 单元插入的空操作，‖ 表示该级因 stall 冻结。

（1）RAW 转发（ALU→ALU）——ADD x3, x1, x2 后接 ADDI x2, x3, 0，ADDI 在 EX 需读 x3，由 EX/MEM 转发：


| 拍号  | IF   | ID   | EX   | MEM  | WB   | 观测                                   |
| --- | ---- | ---- | ---- | ---- | ---- | ------------------------------------ |
| T0  | ADD  | …    | …    | …    | …    |                                      |
| T1  | ADDI | ADD  | …    | …    | …    |                                      |
| T2  | …    | ADDI | ADD  | …    | …    |                                      |
| T3  | …    | …    | ADDI | ADD  | …    |                                      |
| T4  | …    | …    | …    | ADDI | ADD  | forward=01：ADDI EX←EX/MEM.alu_result |
| T5  | …    | …    | …    | …    | ADDI | ADDI 正常写回                            |


（2）load-use Stall——LD x3, 0(x4) 后接下一条使用 x3 的指令，EX/MEM 阶段结果为 load 数据，不可从 EX/MEM 转发，须 stall 1 拍：


| 拍号  | IF   | ID     | EX     | MEM    | WB     | 观测                       |
| --- | ---- | ------ | ------ | ------ | ------ | ------------------------ |
| T0  | LD   | …      | …      | …      | …      |                          |
| T1  | ADD  | LD     | …      | …      | …      |                          |
| T2  | ADD‖ | ADD‖   | LD     | …      | …      | load_use=1，PC/IF/ID 冻结   |
| T3  | ADD‖ | ADD‖   | bubble | LD     | …      | ID/EX←bubble，LD 进入 MEM   |
| T4  | ADD  | bubble | bubble | LD     | …      | stall 解除                 |
| T5  | …    | ADD    | bubble | bubble | LD     | forward=10：ADD EX←MEM/WB |
| T6  | …    | …      | ADD    | bubble | bubble | LD 写回 x3                 |


（3）BNE 分支 Flush——BNE 在 EX 判定分支成立，误取指级清空为 bubble，PC 重定向至目标地址，代价 2 拍：


| 拍号  | IF     | ID     | EX     | MEM    | WB   | 观测                              |
| --- | ------ | ------ | ------ | ------ | ---- | ------------------------------- |
| T0  | BNE    | …      | …      | …      | …    |                                 |
| T1  | pc+1   | BNE    | …      | …      | …    |                                 |
| T2  | pc+2   | pc+1   | BNE    | …      | …    |                                 |
| T3  | bubble | bubble | BNE    | pc+1   | pc+2 | BNE EX 判定 taken                 |
| T4  | target | bubble | bubble | BNE    | pc+1 | flush：IF/ID、ID/EX←NOP，PC←target |
| T5  | t+1    | target | bubble | bubble | BNE  | 从 target 顺序取指                   |


---

## 7. Cache 与主存层次

### 7.1 整体互联

CPU 前端为哈佛接口（IF 取指、MEM 访存两路独立），后端仅一块 main_memory（单端口 RAM）。Miss 或写直达时，I/D Cache 经 soc_top 仲裁后访问同一主存；cache_control 根据 i_miss 与 cpu_ready 产生 cache_stall，冻结流水线。

I-Cache、D-Cache 与 cache_control 在 soc_top.vhd 中例化并接入 main_memory，详见 Fig-3。

公共参数：直接映射，16 行 × 4 word/行（128 B 数据副本）；地址划分 tag(15:6)  index(5:2)  offset(1:0)。

### 7.2 main_memory

最底层统一物理存储，不区分指令区/数据区，仅靠地址区分内容；无 valid/tag，无 hit/miss。


| 组成       | 说明                                      |
| -------- | --------------------------------------- |
| memory[] | 深度 2^16 的 16 bit 字数组                    |
| INIT_MEM | 上电初值：0～11 斐波那契指令，12 为数据初值               |
| 读路径      | 组合读：read_en='1' 时 rdata <= memory(addr) |
| 写路径      | 同步写：上升沿且 write_en='1' 时写入               |


读路径为组合读（read_en=1 时输出 memory[addr]），写路径为同步写；实现见 main_memory.vhd。

与 Cache 对比：主存 addr 直接索引 memory[]；Cache 先拆 tag/index/offset，用元数据判命中后再读行内字。

### 7.3 I-Cache 构成

每行由数据体 + 元数据组成（valid/tag 不在 64 bit 数据体内）：

地址划分：tag(15:6)、index(5:2)、offset(1:0)；每行含 valid、tag 及 4×16 bit 数据。命中判定与 i_miss 生成见 i_cache.vhd。

状态机：S_IDLE 命中则组合输出指令；miss 则锁存 tag/index，进入 S_REFILL，从行首 {tag,index,00} 起连续读 4 word 填入 cache_lines，完成后 valid←1、更新 tag。I-Cache 只读，无写主存路径。

举例（addr=5）：index=1、offset=1、tag=0；miss 时整行载入主存地址 4～7，命中后读 cache_lines[1][1]。

### 7.4 D-Cache 构成

与 I-Cache 对称的 16×4 直接映射结构；差异在于处理 Load/Store 及 cpu_ready 握手。


| 条件               | 行为                        |
| ---------------- | ------------------------- |
| read_en=1 且 hit  | 组合读 cache，cpu_ready='1'   |
| read_en=1 且 miss | 进入 S_REFILL，cpu_ready='0' |
| 无读请求             | cpu_ready='1'（不阻塞 MEM 级）  |


写直达（Write-Through）+ 写不分配（No-Write-Allocate）：


| 场景  | Cache                         | 主存   |
| --- | ----------------------------- | ---- |
| 写命中 | 更新 cache_lines(index)(offset) | 同步写  |
| 写缺失 | 不分配行                          | 只写主存 |


写操作不进入 S_REFILL，cpu_ready 保持 '1'；读 miss refill 与 I-Cache 对称，受 mem_grant 门控。写 miss 不分配行导致重复写同一地址仍计 miss，对斐波那契 ST 统计的影响见 §7.9.3。

### 7.5 三者逻辑对比


| 对比项     | main_memory         | i_cache                | d_cache            |
| ------- | ------------------- | ---------------------- | ------------------ |
| 层次      | 最底层 RAM             | IF 与主存间缓冲              | MEM 与主存间缓冲         |
| 容量      | 2^16 word           | 64 word（16 行×4）        | 64 word            |
| 地址解析    | addr → memory[addr] | tag + index + offset   | 同左                 |
| 读延迟     | 组合读（需 read_en）      | 命中组合读；miss 4+ 拍 refill | 同左                 |
| 写       | 同步写                 | 无（只读）                  | 写直达；命中同步更新行        |
| miss/握手 | 无                   | i_miss                 | d_miss + cpu_ready |



三者读路径差异已概括于上表；具体 VHDL 见各模块源文件。

### 7.6 存储演进


| 阶段   | 结构                                 | 特点                                             |
| ---- | ---------------------------------- | ---------------------------------------------- |
| 早期   | instr_memory + data_memory         | 两块独立 RAM，组合/同步读，无 miss                         |
| 过渡方案 | 各 Cache 内嵌 RAM                     | i_miss/d_miss 恒 0，功能等同直连主存                     |
| 当前   | i_cache + d_cache + 共享 main_memory | 冯诺依曼统一主存 + 哈佛前端 Cache；valid/tag/行数组 + 全局 stall |


前端仍分离（取指走 I-Cache、访存走 D-Cache），后端合并为一块 RAM，靠地址与 is_mmio 区分普通访存与外设。

### 7.7 取指与访存时序

取指（经 I-Cache，PC=0 首次 miss）：


| 阶段 | 行为 |
| ---- | ---- |
| 拍 1 | index=0、valid=0 → miss，stall=1，进入 REFILL |
| 拍 2～5 | 从主存 addr=0,1,2,3 读入，填入 cache_lines[0] |
| 拍 6 | hit=1，stall=0，指令进入 IF/ID |
| 拍 7～ | 同行 PC=1,2,3 均命中，不再访问主存 |

访存（ST 写直达）：write_en=1 时命中则更新 cache 行并同步写主存，1 拍完成；写缺失只写主存、不分配行。

### 7.8 cache_control 与流水线 stall

cache_control.vhd 中 stall <= i_miss or (not cpu_ready)。


| 条件            | 效果                        |
| ------------- | ------------------------- |
| i_miss='1'    | 取指未就绪，冻结 PC 与各级流水寄存器      |
| cpu_ready='0' | Load 读 miss 或正在 refill，同上 |


Cache stall 为 hold（保持各级内容），与 BNE 的 bubble（IF/ID、ID/EX 插 NOP）不同；与 load-use stall 亦分开处理（见 §6.2）。

I/D Cache 共用单端口 main_memory 时的 mem_grant 授权与 I-Cache 读优先仲裁见 §7.10～§7.12（含 PC=8 读错、PC=7 死锁两处修复；RTL 要点见附录 C）。

### 7.9 D-Cache 命中率统计

统计在 d_cache.vhd 内完成；I-Cache 暂无 hit/miss 计数。soc_top 例化时三信号当前接 open，仿真探针 u_dcache 内部端口即可。

#### 7.9.1 输出信号


| 信号         | 位宽     | 含义                 |
| ---------- | ------ | ------------------ |
| hit_count  | 16 bit | 累计命中次数             |
| miss_count | 16 bit | 累计缺失次数             |
| hit_rate   | 8 bit  | 命中率 × 100，取值 0～100 |


hit_rate = hit_count / (hit_count + miss_count) × 100（整数除法，无小数）。

#### 7.9.2 计数规则

读、写共用 valid+tag 判定的 hit；仅在 S_IDLE 且访存使能上升沿计 1 次新访问：

计数逻辑见 d_cache.vhd：在 S_IDLE 且 read_en/write_en 上升沿计一次访问，hit/miss 分别累加。

| 情况                       | 是否计数                 |
| ------------------------ | -------------------- |
| read_en/write_en 0→1 上升沿 | 计 1 次 hit 或 miss     |
| cache_stall=1 期间使能保持为 1  | 不计（避免同一条 ST/LD 重复累加） |
| state = S_REFILL         | 不计（refill 非新 CPU 访存） |


曾用「使能为 1 即计数」导致 PC=7 stall 时一条 ST 被计 6 次；现以 new_access 修复。


| 访问类型    | miss 时功能行为              | 计入            |
| ------- | ----------------------- | ------------- |
| 读（LD）   | 进入 S_REFILL，cpu_ready=0 | miss（上升沿 1 次） |
| 写（ST）命中 | 更新 cache 行 + 写主存        | hit           |
| 写（ST）缺失 | 只写主存，不分配行               | miss          |


#### 7.9.3 斐波那契预期结果

主程序 LOOP 仅 5 次 ST x3,0(x4) 写 RAM，另 1 次 LD x7,31(x0) 读常量；MMIO 的 ST UART/GPIO 与 ISR 内 ST 不经 D-Cache（is_mmio=1）。配合写不分配，不会产生写 hit：


| 信号         | 预期终值     | 原因                               |
| ---------- | -------- | -------------------------------- |
| hit_count  | 0        | 写 miss 不装入行；LD 读 Mem[31] 亦为 miss |
| miss_count | 6        | 5 次循环 ST + 1 次 LD（各计 1 次）        |
| hit_rate   | 0（显示 00） | 0 ÷ 6 = 0%，非「Cache 失效」           |


仿真中 miss_count 终值变化：0 → … → 5（5 次 ST）→ 6（LD Mem[31]）。

CPI/加速比对比见 §9.2。

#### 7.9.4 仿真观测

run.do 中已添加 D-Cache Stats 波形分组，观测 u_dcache 的 hit_count、miss_count、hit_rate。

验证时配合 cache_stall、ex_mem_write（ST 写使能）、debug_pc 对照 §7.9.3 逐步核对统计结果。

### 7.10 主存争用背景

CPU 为哈佛接口（IF、MEM 两路），但 I-Cache 与 D-Cache 共用单端口 main_memory（互联见 §7.1）。Miss 时两边都可能访问主存，必须仲裁；授权不当会导致 refill 读错 或 永久 stall。

斐波那契 LOOP 中，PC=5 的 ST x3,0(x4) 写主存与 PC=8 的 ADDI x4,x4,1 换 Cache 行（index=2）首次重叠，是争用问题的触发点：


| PC  | 机器码  | 指令             | Cache 行                |
| --- | ---- | -------------- | ---------------------- |
| 5   | 38C0 | ST x3, 0(x4)   | 写 Mem[23]（首轮）          |
| 7   | 0680 | ADDI x2, x3, 0 | 行 1                    |
| 8   | 0901 | ADDI x4, x4, 1 | 行 2（首次 refill 与 ST 重叠） |


### 7.11 问题一：PC=8 指令变成 0000

现象：PC=8 时 debug_instr=0000（应为 0901），x4 无法从 13 递增到 14。

根因：PC=8 触发 I-Cache 行 2 miss 的同时，MEM 级执行 PC=5 的 ST。修复前 D-Cache 写优先占用主存，mm_read_en=0，main_memory 在 read_en=0 时 rdata=0000；I-Cache refill 无条件采样 mem_rdata，把 0000 写入 Cache 行。stall 解除后 hit 读 Cache 仍得 0000（主存里 0901 其实未被破坏）。

争用时序要点：PC=8 触发 I-Cache refill 的同拍，PC=5 的 ST 占主存写端口，mm_read_en=0 时 rdata=0000 被误采样入 Cache 行。

修复（mem_grant v1）：仅当 mem_grant=1 时 I-Cache 才发起读并采样 mem_rdata；实现见 i_cache.vhd。

### 7.12 问题二：PC=7 程序卡死

现象：v1 修复后指令不再读错，但 cache_stall 持续为 1，debug_pc 停在 7。

根因：v1 授权 i_mem_grant <= '0' when d_mem_req = '1' 把 写主存 也视为占线。ST 冻在 MEM 后每拍 d_mem_req=1，I-Cache 永远拿不到 grant → refill 无法完成 → 死锁。

死锁原因：v1 方案把 D-Cache 写主存也视为占线，I-Cache refill 永远拿不到 grant。

修复（mem_grant v2 + I 读优先仲裁）：授权仅看读主存；I-Cache 读优先于 D-Cache 写；D-Cache refill 同样受 mem_grant 门控。实现见 soc_top.vhd。

修复演进：原始无条件采样 → v1 加 grant 但写也占线（死锁）→ v2 I 读优先 + 读写分离授权。

### 7.13 波形阅读备忘

- debug_pc / debug_instr 接 IF/ID，不是 WB 级；debug_pc=8 表示该指令刚进 ID，写回尚早数拍。  
- EX 级 rs=3 多为 PC=7 的 0680 因 stall 停在 EX，不代表 PC=8 译码错。  
- PC=0～7 所在 Cache 行 refill 通常不与 ST 写重叠，故问题仅在 PC=8 换行时暴露。

### 7.14 is_mmio 旁路

MMIO 旁路：mem_addr 高 8 位为 0xFF 时 is_mmio=1，D-Cache 不介入，mem_rdata 选自 mmio_rdata。实现见 soc_top.vhd。

### 7.15 后续扩展方向

当前基线：直接映射、16 行×4 word、写直达、写不分配、miss 全局 stall、单端口主存 + mem_grant。后续可按优先级扩展：


| 方向    | 当前               | 可扩展为                                  |
| ----- | ---------------- | ------------------------------------- |
| 相联度   | 直接映射             | 2 路组相联 + LRU                          |
| 写策略   | 写直达、写不分配         | 写回 + dirty 位、写分配                      |
| 主存接口  | 单端口组合读           | 双端口 / 哈佛物理主存（消除仲裁）                    |
| stall | 全局 hold          | 仅冻 IF/ID/EX，MEM 保持请求                  |
| 统计    | D-Cache hit/miss | I-Cache 计数、refill 周期、有/无 Cache CPI 对比 |


后续扩展宜逐层推进（先统计 → MMIO 旁路 → 相联/写回），避免同时改动映射、写策略与 stall 逻辑，以降低联调复杂度。

---

## 8. 中断与 MMIO 子系统

### 8.1 中断设计

Timer → irq_pending；CSR：EPC、STATUS.IE、CAUSE；irq_take 仅在 wb_commit 且非 cache_stall 时成立；ISR @ 0x0100；IRET 在 WB 提交返回 EPC。

### 8.2 响应流程

中断响应流程见图 4（Fig-4），步骤如下：

1. 主程序正常执行，Timer 置 irq_pending=1。
2. 在 WB 提交边界且 IE=1、非 cache_stall 时 irq_take 成立。
3. EPC←if_pc，IE←0，PC←0x0100，flush 流水线进入 ISR。
4. ISR 执行完毕后 IRET 在 WB 提交，PC←EPC，IE←1。

### 8.3 HALT 与中断协同

- HALT 进入 EX 后 halt_latched←1，PC 冻结  
- irq_take 清 halt_latched，ISR 内 PC 可顺序执行  
- iret_commit 再置 halt_latched，回到 EPC 后再停机

主程序 0x0F=HALT、0x10 为停机时 if_pc；irq_take 时 EPC←0x10，IRET 返回后再冻住 PC。

### 8.4 IRET 与 I-Cache 时序

ISR 为三条指令（0x0100 ADDI x6；0x0101 ST UART；0x0102 IRET）。IRET 相对 ADDI 晚 2 拍进入流水，各级对齐与两条指令版相同，仅 prefetch miss 可能出现在 0x0103 一带。

五级流水时序（以 ADDI 进入 IF 为 T0，首次 IRET 附近；T+4 起 IF 预取 0x0103 可能 miss）：


| 拍号   | IF        | ID      | EX      | MEM       | WB   | 观测                                                    |
| ---- | --------- | ------- | ------- | --------- | ---- | ----------------------------------------------------- |
| T0   | ADDI@0100 | …       | …       | …         | …    |                                                       |
| T1   | ST@0101   | ADDI    | …       | …         | …    |                                                       |
| T2   | IRET@0102 | ST      | ADDI    | …         | …    |                                                       |
| T3   | 0103      | IRET    | ST      | ADDI      | …    |                                                       |
| T4   | 0103      | …       | IRET    | ST        | ADDI | ADDI WB（x6++）；ST MMIO→debug_uart_data                 |
| T5   | 0103†     | …(hold) | …(hold) | IRET      | ST   | †IF 预取 0x0103，I-Cache miss                            |
| T6～  | …(hold)   | …(hold) | …(hold) | IRET(MEM) | …    | cache_stall=1，refill（约 4 拍，§7.7）                      |
| Tn   | 0104      | …       | …       | IRET      | …    | stall 解除，IRET MEM→WB                                  |
| Tn+1 | …         | …       | …       | …         | IRET | iret_commit=1；flush_all=1；PC←EPC（0x10）；halt_latched←1 |


IRET 提交条件：iret_commit 在 WB 级且 cache_stall=0；flush_all 由 irq_take 或 iret_commit 触发；iret_commit 时 PC←EPC。实现见 cpu_top.vhd 与附录 C。

关键因果：

1. ISR 内 ST x6,0(x7) 走 is_mmio=1 旁路，不写 D-Cache 行。
2. prefetch miss 不是 IRET 返回引起，而是 IRET 还在 MEM、IF 已预取 ISR 后续地址时的 ISR prefetch miss。
3. iret_commit 要求 cache_stall=0，stall 期间 IRET 不能提交。
4. IRET 提交后 EPC=0x10 取指，可能与 §7.10 主存争用场景叠加 I-miss。

信号对照：


| 拍号   | 事件                            | debug_pc | iret_commit | cache_stall |
| ---- | ----------------------------- | -------- | ----------- | ----------- |
| T3   | ADDI MEM，ST EX                | 0102     | 0           | 0           |
| T4   | ADDI WB，ST MEM/WB，IRET EX     | 0103     | 0           | 0           |
| T5～  | ISR 预取 miss → refill，IRET MEM | 0103     | 0           | 1           |
| Tn   | stall 结束，IRET→WB              | 0104     | 0           | 0           |
| Tn+1 | IRET WB 提交                    | 0104     | 1           | 0           |
| Tn+2 | PC←EPC=0x10                   | 0010     | 0           | 0           |


### 8.5 MMIO 地址映射


| 地址              | 外设                  |
| --------------- | ------------------- |
| 0xFF00 / 0xFF04 | UART 数据 / 状态        |
| 0xFF10          | GPIO LED            |
| 0xFF20 / 0xFF24 | Timer CTRL / PERIOD |


### 8.6 P3 嵌入式演示（UART/GPIO）


| 阶段           | 行为                         | 观测                                                               |
| ------------ | -------------------------- | ---------------------------------------------------------------- |
| 主程序 PC=11    | LD x7,31(x0) 载入 UART 基址    | x7=FF00；load-use stall 1 拍 后 ST                                  |
| 主程序 PC=12–13 | ST x3,0(x7) / ST x3,16(x7) | is_mmio=1，mem_addr=FF00/FF10；debug_uart_data=000D，debug_led=000D |
| ISR          | ST x6,0(x7) 每次中断           | debug_uart_data 随 x6 递增（1,2,3…）                                  |


MMIO 写不经 D-Cache，与 §7.14 is_mmio 旁路一致；Mem[31]=0xFF00 为数据常量，不是可执行指令。

---

## 9. 仿真验证

环境：ModelSim；顶层 soc_top；脚本 cpu_pipe/sim/run.do。

### 9.1 功能测试


| 步骤    | 内容                                                       | 结果  |
| ----- | -------------------------------------------------------- | --- |
| T1–T3 | ADDI / ADD / ST                                          | 通过  |
| T4    | 五级流水重叠                                                   | 通过  |
| T5    | RAW 转发                                                   | 通过  |
| T6    | BNE 循环 + flush                                           | 通过  |
| T7    | 斐波那契 + Cache                                             | 通过  |
| T8    | Cache miss stall                                         | 通过  |
| T9    | D-Cache 统计：hit_count=0，miss_count=6，hit_rate=00（§7.9.3）  | 通过  |
| T10   | Timer → ISR                                              | 通过  |
| T11   | ISR x6++，IRET 返回                                         | 通过  |
| T12   | HALT + halt_latched                                      | 通过  |
| T13   | MMIO：debug_uart_data=000D，debug_led=000D，is_mmio=1（§8.6） | 通过  |
| T14   | load-use stall                                           | 通过  |
| T15   | PC=8 取指 0901（mem_grant 修复）                               | 通过  |
| T16   | IRET 提交与 ISR prefetch stall 时序                           | 通过  |


主要观测信号：

- 通用：debug_pc、debug_epc、irq_take、iret_commit、load_use_stall、forward_a/b、cache_stall  
- D-Cache 统计：hit_count/miss_count/hit_rate（配合 ex_mem_write；终值见 §7.9.3）  
- MMIO 演示：debug_uart_data、debug_led、is_mmio、mem_addr（§8.6）  
- 主存争用：i_miss、i_mem_grant、d_mem_read_en、d_mem_write_en、mem_addr  
- IRET 时序：flush_all、halt_latched、if_pc/instr_addr（debug_pc 相对 IF 晚 1～2 拍）

Cache 争用验证要点：PC=8 时 debug_instr=0901；PC=7 后不再永久 stall；Mem[23] 被 ST 写成 2；x4 能递增；BNE 能循环至 HALT。

D-Cache 统计验证要点（T9）：程序执行完毕后 miss_count 为 6（5 次循环 ST + 1 次 LD）；hit_count 保持 0；MMIO 写 不计入 D-Cache。

MMIO 演示验证要点（T13）：HALT 前 debug_uart_data=000D、debug_led=000D；ST 期间 is_mmio=1 且 mem_addr=FF00/FF10；Timer 中断后 UART 数据随 x6 更新。

### 9.2 CPI 与加速比对比

对比范围：仅统计主程序从复位释放到 HALT@0x0F 在 WB 提交，不含 Timer ISR 与 IRET 开销；负载均为计算 f7=13 的斐波那契（旧机 5 轮循环 / 新机 5 轮 LOOP）。

统计口径：

- CPI = 总时钟周期 / 动态指令条数
- 加速比 S = T_多周期 / T_五级流水
- T_pipe ≈ (N + 4) + N_BNE×2 + N_i_miss×T_refill + T_contention + T_loaduse


| 符号           | 斐波那契取值 | 说明                                            |
| ------------ | ------ | --------------------------------------------- |
| N            | 44     | 动态指令：4 初始化 + 5×7 LOOP + LD + 2×ST + EI + HALT |
| N_BNE        | 4      | BNE 成立 4 次（cnt 从 5 递减至 1）；cnt=0 时不跳           |
| N_i_miss     | 3      | 首次取指换 3 条 I-Cache 行（PC 0/4/8 所在行）             |
| T_refill     | ≈5 拍/行 | 1 拍判 miss + 4 拍 refill（§7.7）                  |
| T_contention | ≈2 拍   | PC=8 I-refill 与 ST 写主存重叠的 grant 等待（§7.10）     |
| T_loaduse    | 1 拍    | LD x7 后 ST x3,0(x7) 的 load-use stall（§6.2）    |


#### 9.2.1 多周期模型机（周期统计）

旧程序 2 条初始化 + 5×8 条循环体 = 42 条动态指令。按 cpu_fibo/rtl/microController.vhd 中 CM_ROM 路径逐条累加微周期（取指固定 5 拍：0→30→1→2→3→MAP）：


| 指令类型                               | 执行微周期 | 含取指合计 |
| ---------------------------------- | ----- | ----- |
| LOAD                               | 1     | 6     |
| MOVE AC,[BX] / ADD AC,[BX] / STORE | 4     | 9     |
| INC / MOVE AX,BX                   | 1     | 6     |
| DEC                                | 2     | 7     |
| JNZ（成立 / 不成立）                      | 2 / 1 | 7 / 6 |


合计：306 拍（4 轮 JNZ 成立 ×59 + 末轮 58 + 初始化 12）。

#### 9.2.2 五级流水 SoC


| 实现                          | 总周期 T | 动态指令 N | CPI   | 相对多周期加速比  |
| --------------------------- | ----- | ------ | ----- | --------- |
| 多周期模型机（cpu_fibo）            | 306   | 42     | 7.29  | 1.00×（基准） |
| 五级流水 + I/D Cache（理想无 stall） | 48    | 44     | 1.09  | 6.38×     |
| 五级流水 + I/D Cache            | ≈74   | 44     | ≈1.68 | ≈4.14×    |


估算展开：48（理想）+ 8（BNE flush）+ 15（3 次 I-Cache refill）+ 2（主存争用）+ 1（load-use）≈ 74 拍。

仿真周期测量方法：以复位释放为 cycle=0；以 HALT@0x0F 在 WB 提交为终止点（亦可观测 debug_pc=000F 且 debug_instr=F000 时 HALT 已进入 ID/EX）。按 RTL 行为估算，斐波那契主程序总周期约为 74 拍，仿真波形测量结果落在 71～78 拍 区间。

#### 9.2.3 结论与说明

1. 吞吐提升主要来自流水线并行，相对旧多周期机约 4.1× 加速；理想上限约 6.4×，差距由 BNE flush、I-Cache miss stall 与 load-use stall 造成。
2. D-Cache 对本斐波那契几乎无 CPI 收益：LOOP 以 ST 为主且写不分配，整体 hit_rate=0（§7.9.3）；D-Cache 的价值体现在统计验证与后续含更多 Load 的程序。
3. 性能对比以多周期模型机为基准；本设计未单独搭建「无 Cache 五级流水」对照 RTL，故未列出流水裸机与流水+Cache 的分项对照。
4. Timer 中断与 IRET 会额外增加周期，属于 SoC 功能开销，不纳入上表，以避免与组成原理基准机混淆。

---

## 10. 向量/阵列扩展分析（P4）

P4 属于课设延伸内容，本设计未在 RTL 中实现向量/阵列硬件。以下从体系结构角度分析在当前五级流水 SoC 上扩展的可行路径与预期收益，对应课程第 6 章向量处理机与阵列机内容。

### 10.1 扩展动机

当前标量 RISC CPU 对数组运算（如两向量逐元素相加）需循环展开为多条 LD/ADD/ST，指令条数随元素个数线性增长，且存在 load-use stall 与 Cache miss 开销。向量（SIMD）或阵列并行可在一条指令内处理多个数据元素，降低循环控制开销，提升数据级并行度。

### 10.2 方案一：简易 SIMD 向量扩展

在现有 ex_stage 旁增加定长向量寄存器组与宽 ALU，不改变五级流水主干，仅在 EX 段多周期或单周期完成向量运算。

设计参数（与本课设 16 bit 数据宽度对齐）：


| 项目        | 参数取值                              |
| --------- | --------------------------------- |
| 向量寄存器     | VR0–VR3，各 4×16 bit                |
| 向量长度 VL   | 4（固定，简化译码）                        |
| 新增指令      | VLD/VST（向量 load/store）、VADD（逐元素加） |
| OpCode 预留 | 0110–0111（尚未分配）                   |


指令语义示例：VLD 将连续 4 word 载入 VR0/VR1，VADD 逐元素相加写入 VR2，VST 写回主存。

与现有流水线的接口：

- ID：识别向量 OpCode，读向量寄存器编号；标量/向量共用 IF/ID/EX/MEM/WB 骨架。
- EX：4 路 16 bit 加法器并行，或 1 个加法器迭代 4 拍（面积/速度折中）。
- MEM：VLD/VST 连续访问 4 word，易触发 D-Cache 行命中（本设计 4 word/行），空间局部性优于 4 次标量 LD。
- Hazard：向量指令与标量指令间 RAW 需扩展 forward_unit；VLD 后紧接 VADD 存在类似 load-use 问题，可 stall 1 拍或分多周期执行。

### 10.3 方案二：阵列机与互连网络

阵列处理机由多个相同 PE（处理单元） 与互连网络组成，适合规则并行（矩阵乘、卷积）。课设规模下完整阵列 RTL 工作量接近再造一套数据通路，故采用报告级建模：

建模要点：4 个 PE 线性连接，每 PE 含 16 bit 加法器；PE[i] 结果可链至 PE[i+1]；理想情况下 C[i]=A[i]+B[i]（i=0..3）单拍完成。

互连函数可采用 PM2I / Shuffle（课程第 6 章）演示多步数据交换；路由表可在 Python/Excel 等工具中建模分析。

### 10.4 性能估算：标量 vs 向量

以 4 元素向量加 C[i]=A[i]+B[i] 为例，对比当前标量 ISA 与方案一 SIMD：


| 实现方式       | 指令条数（理想）                       | 主要 stall           | 备注            |
| ---------- | ------------------------------ | ------------------ | ------------- |
| 标量循环       | 4×LD + 4×ADD + 4×ST + 控制 ≈ 15+ | load-use、BNE flush | 与斐波那契 LOOP 同类 |
| SIMD（VL=4） | 2×VLD + 1×VADD + 1×VST = 4     | VLD→VADD load-use  | 指令数约 1/4      |


理想加速比（忽略控制与 Cache）：

S \approx \frac{N_{\text{scalar}}}{N_{\text{vector}}} \approx \frac{15}{4} \approx 3.75

考虑 load-use（标量每对 LD+ADD 至少 1 拍 stall）与 Cache miss 后，向量方案因连续访存、行命中率高，实际加速比仍优于标量，但受 Amdahl 定律约束：循环控制、中断、MMIO 等标量代码不可向量化。

与斐波那契验证负载的关系：斐波那契递推存在强数据依赖（f_{i+1} 依赖 f_i, f_{i-1}），不适合向量并行；向量扩展更适合批量数组加、点积等负载，斐波那契仍作为标量功能验收程序。

### 10.5 未实现 RTL 的原因与后续工作


| 因素    | 说明                                         |
| ----- | ------------------------------------------ |
| 优先级   | P0–P3（流水、Cache、中断、MMIO）已占满设计与仿真周期          |
| 指令编码  | 16 bit 定长下再扩向量字段需重新定义 R/V 型格式              |
| 验证复杂度 | 需独立向量 testbench，与现有斐波那契/ISR 联调相互独立         |
| 工作划分  | 硬件实现覆盖 P0–P3；P4 以体系结构分析与加速比估算完成课程第 6 章延伸要求 |


后续可在现有五级流水 SoC 上优先扩展 VL=4 的 VADD + VLD/VST，于 ex_stage.vhd 增加 generate 并行加法器；阵列互连网络可作为独立研究课题继续深化。

---

## 11. 问题回顾与总结

### 11.1 主要问题与解决

设计实现过程中遇到并解决了以下关键问题：主存 I/D 端口争用通过 mem_grant 仲裁与 I-Cache 读优先策略消除；MMIO 访问通过 is_mmio 旁路避免被 D-Cache 缓存；中断响应在 wb_commit 边界提交并配合 flush_all 保证精确性；HALT 停机与 IRET 返回通过 halt_latched 协同，使 ISR 可正常执行并在返回后恢复停机；load-use 数据冒险通过 stall 与 MEM/WB 转发处理。

### 11.2 主要成果

本课设完成了五级流水 RISC CPU 及 RAW 转发、BNE/J flush、load-use stall 等冒险处理机制；实现了 LD 指令译码与访存写回；集成 I/D Cache、全局 stall 与 D-Cache 命中率统计；构建了 Timer 精确中断子系统（EPC/IE/CAUSE、EI/DI/IRET）及 MMIO 最小 SoC（Timer/UART/GPIO）；完成 HALT 停机与中断返回联调；通过斐波那契主程序与 Timer ISR 的 ModelSim 仿真验证；完成 P4 向量/阵列扩展的体系结构分析（§10）及相对多周期模型机的 CPI/加速比分析（§9.2）。

### 11.3 总结

本课设以《计算机组成原理》课程实验中的非流水线冯诺依曼模型机为起点，在保持斐波那契程序作为统一验证负载的前提下，完成了从多周期串行执行到可中断嵌入式 SoC 的递进设计与实现。硬件方面，采用 VHDL 构建了 IF/ID/EX/MEM/WB 五级流水 RISC CPU，通过转发单元、BNE/J 分支 flush 与 load-use stall 机制处理数据冒险与控制冒险；在 SoC 顶层集成直接映射 I/D Cache、单端口主存仲裁与全局 cache stall，并实现 D-Cache 命中率统计；进一步扩展 Timer 精确中断子系统（EPC、STATUS.IE、CAUSE 及 EI/DI/IRET 指令）与 UART/GPIO/Timer 的 MMIO 映射，解决了主存争用、MMIO 旁路、精确中断提交边界及 HALT 与中断返回协同等关键问题。功能验证方面，主程序正确计算斐波那契数列并写入主存，Timer 中断服务程序经 UART 输出递增计数，IRET 返回与 I-Cache prefetch miss 下的 stall 行为与 RTL 设计一致；性能分析表明，相对原多周期模型机可获得约 4.1 倍加速，CPI 由 7.29 降至约 1.68。此外，结合教材阵列处理机与向量处理机内容，对 VL=4 的向量扩展路径及标量/向量加速比进行了报告级分析。综上，本课设实现了课设目标 P0–P3 的完整闭环，完成了由“单总线多周期模型机”向“带 Cache 与中断的最小 SoC”的系统结构升级。

---


## 附录 C：关键 RTL 逻辑索引

完整 VHDL 随课设工程提交；下表列出报告正文涉及的关键逻辑及其源文件，便于对照 RTL 阅读。


| 功能 | 源文件 | 要点 |
| ---- | ------ | ---- |
| load-use 检测 | hazard_unit.vhd | ID/EX.MemRead=1 且 rd 与 IF/ID rs1/rs2 冲突时 stall |
| cache 全局 stall | cache_control.vhd | stall <= i_miss or (not cpu_ready) |
| I-Cache refill 门控 | i_cache.vhd | mem_grant=1 时才采样 mem_rdata、推进 refill |
| 主存仲裁 | soc_top.vhd | I-Cache 读优先；i_mem_grant 在 D-Cache 读主存时为 0 |
| MMIO 旁路 | soc_top.vhd | 地址 0xFFxx 时 is_mmio=1，不经 D-Cache |
| 精确 IRET | cpu_top.vhd | iret_commit 需 WB 提交且 cache_stall=0 |
| HALT 与中断协同 | cpu_top.vhd | irq_take 清 halt_latched；iret_commit 再置位 |

## 附录 A：参考文献

1. 王党辉等，《计算机组成原理》
2. 李学干，《计算机体系结构》

---

## 附录 B：插图与文档索引


| 编号     | 图名                         | 说明            |
| ------ | -------------------------- | ------------- |
| Fig-1  | 非流水线模型机框图                  | 组成原理实验        |
| Fig-2  | 五级流水数据通路图                  | 本文 3.2        |
| Fig-3  | SoC 顶层连接图                  | 本文 3.1、7.1    |
| Fig-4  | 中断响应时序图                    | 本文 8.2        |
| Fig-5  | IRET + I-Cache miss 时序     | 本文 8.4        |
| Fig-6  | 五级流水冒险时序图                  | 本文 §6.5       |
| Fig-7  | Cache 主存争用 / mem_grant     | 本文 7.10–7.12  |
| Fig-8  | Cache miss + stall 波形      | ModelSim 仿真截图 |
| Fig-9  | 向量/阵列扩展分析                  | 本文 10         |
| Fig-10 | I/D Cache 与 main_memory 构成 | 本文 7.3–7.5    |


---

