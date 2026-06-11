# HALT 停机逻辑

本文说明本课设五级流水 CPU 中 `**HALT` 指令如何停止 PC**、与 flush/stall 的区别，以及 `cpu_pipe/rtl/` 中的实现。

对应 RTL：`id_stage.vhd`（译码）、`cpu_top.vhd`（停机控制）、`if_stage.vhd`（PC 保持与中断覆盖）。

演示程序见 `main_memory.vhd`：地址 `0x0C` 为 `HALT`（`0xF000`），前一条 `0x0B` 为 `EI`。

---

## 1. HALT 做什么

**HALT**（OpCode `1111`）表示程序结束：**不再顺序取新指令**，CPU 停在当前程序流。

与 flush 不同：HALT **不是要改走另一条路**，而是 **永久冻结 PC**（直到复位，或被中断/IRET 的 `flush_all` 打断后跳转）。


| 项目   | HALT           | Flush（分支/中断）    |
| ---- | -------------- | --------------- |
| 目的   | 程序结束，停取指       | 作废误取指，改 PC      |
| PC   | **保持**         | **更新**到新目标      |
| 流水线  | 已有指令继续流到 WB    | 误取指变 NOP/bubble |
| 典型场景 | 斐波那契算完后 `HALT` | BNE 跳转、进 ISR    |


---

## 2. 信号一览


| 信号                 | 位置                     | 含义                        |
| ------------------ | ---------------------- | ------------------------- |
| `**id_halt`**      | ID 组合                  | 当前 IF/ID 中指令译码为 HALT      |
| `**id_ex_halt**`   | ID/EX 寄存器              | **EX 级**指令的 halt 标志       |
| `**halt_latched`** | `cpu_top` 寄存器          | HALT 进入 EX 后锁存，**永久停 PC** |
| `**cpu_halt`**     | `cpu_top` → `if_stage` | 最终送给 IF 的停机请求             |
| `**instr_addr**`   | `if_stage`             | 当前 PC（停机后不再递增）            |


```text
id_stage: opcode=1111 → id_halt=1
              ↓ 锁入 ID/EX
         id_ex_halt=1（HALT 在 EX）
              ↓ 上升沿
         halt_latched←1（永久停机）
              ↓
         cpu_halt → if_stage 冻结 pc_reg
```

---

## 3. 为何需要三层逻辑

原先仅用 `cpu_halt <= id_ex_halt` 有两个问题：

### 3.1 进入 EX 时晚一拍

`id_ex_halt` 在 HALT **锁入 EX 的上升沿**才变 1。上升沿之前 `cpu_halt=0`，PC 仍会 `+1`，多取 `0x0D`、`0x0E`…

**处理**：HALT 在 **ID** 时 `id_halt=1`，提前拉停 PC，保证 **进入 EX 的那一拍不再递增**。

### 3.2 离开 EX 后信号消失

HALT 进入 MEM/WB 后 `id_ex_halt=0`，若未锁存，PC 可能再次递增。

**处理**：HALT 进入 EX 时置 **`halt_latched←1`**；**`irq_take` 清 0**（ISR 要能取 IRET）；**`iret_commit` 再置 1**（回主程序后再停）。

---

## 4. RTL 实现

### 4.1 译码（`id_stage.vhd`）

```vhdl
when "1111" => -- HALT
  halt <= '1';
```

`halt` 随控制信号锁入 ID/EX，在 EX 级体现为 `**id_ex_halt**`。

### 4.2 停机控制（`cpu_top.vhd`）

```vhdl
halt_reg : process (clk, rst)
begin
  if rst = '0' then
    halt_latched <= '0';
  elsif rising_edge(clk) then
    if irq_take = '1' then
      halt_latched <= '0';
    elsif iret_commit = '1' then
      halt_latched <= '1';
    elsif cache_stall = '0' and id_ex_halt = '1' and id_ex_valid = '1' then
      halt_latched <= '1';
    end if;
  end if;
end process halt_reg;

cpu_halt <= halt_latched or id_halt or id_ex_halt;
```


| 项 | 说明 |
| --- | --- |
| **`id_halt`** | HALT 在 ID，提前停 PC |
| **`id_ex_halt`** | HALT 在 EX 期间停 PC |
| **`halt_latched`** | HALT 进 EX 置 1；**`irq_take` 清 0**；**`iret_commit` 再置 1** |
| **`pc_src=11`** | 中断/IRET 改 PC 时优先于 halt（见 `if_stage`） |


### 4.3 PC 保持与中断优先（`if_stage.vhd`）

```vhdl
if pc_en = '1' and (halt = '0' or pc_src = "11") then
  pc_reg <= pc_next;
end if;
```


| 条件                     | 行为                      |
| ---------------------- | ----------------------- |
| `halt=1` 且 `pc_src≠11` | **PC 不变**               |
| `halt=1` 且 `pc_src=11` | **允许更新**（中断/IRET 重定向优先） |
| `halt=0`               | 正常 `pc_en` 控制           |


避免 HALT 停机后 `**irq_take` 无法把 PC 跳到 `0x0100`**。

---

## 5. 五级流水时序（EI → HALT）

主程序末尾：`0x0B EI` → `0x0C HALT`。

```text
拍号   IF          ID          EX          MEM         WB        cpu_halt / PC
──────────────────────────────────────────────────────────────────────────────
T0   EI@0x0B     …           …           …           …         0 / PC 递增
T1   HALT@0x0C   EI          …           …           …         0
T2   HALT@0x0C   HALT        EI          …           …         id_halt=1，PC 将停
T3   HALT@0x0C   …           HALT        EI          …         id_ex_halt=1
T4   …           …           HALT        HALT        EI        halt_latched←1
T5+  …           …           …           …           …         1，PC 冻结
```

说明：

- HALT 在 **ID（T2）** 时 `id_halt=1`，阻止后续 PC 再递增。
- HALT 在 **EX（T3）** 时 `id_ex_halt=1`；**T4 上升沿** `halt_latched←1`。
- PC 通常停在 `**0x0D`**（HALT 在 ID 时多取的一条）；`instr_addr` 不再变为 `0x0E`、`0x0F`…
- **EI 在 T4 WB 提交** → `IE←1`；若 `pending=1`，后续 `irq_take` 经 `pc_src=11` 跳 ISR。
- **irq_take** → `halt_latched←0`，ISR 内 PC 可 `0x0100→0x0101`。
- **IRET 回主程序** → `PC←EPC`（常为 `0x0D`），`iret_commit` 使 `halt_latched←1`，**PC 再次冻结**。

---

## 6. HALT 与中断的配合

### 6.1 EPC 为什么是 `0x0D`（13）

`irq_take` 时 **`EPC ← if_pc`**；HALT 停机前 PC 已多取一条，故为 HALT 的**下一条**地址，不是 `0x0C`。

### 6.2 卡在 `0x0100`、x6 一直加（常见波形）

若 **`irq_take` 后 `halt_latched` 仍为 1**：

```text
irq_take：pc_src=11 可跳到 0x0100（仅这一拍改 PC）
之后：cpu_halt=1，pc_src=00 → PC 无法 +1
      → 每拍重复取 0x0100 的 ADDI x6,x6,1
      → ex_alu_result / x6 每拍递增，永远取不到 0x0101 的 IRET
```

**修复**：`irq_take` 时 **`halt_latched←0`**，ISR 内 PC 正常递增；`iret_commit` 时再 **`halt_latched←1`**。

### 6.3 IRET 后 PC 应停住

```text
主程序: … → EI@0x0B → HALT@0x0C，PC 停在 0x0D，halt_latched=1
         → irq_take：EPC←0x0D，跳 0x0100，halt_latched←0
         → ISR：0x0100 ADDI → 0x0101 IRET
         → iret_commit：PC←0x0D，halt_latched←1，PC 不再递增
```

### 6.4 仿真时序（IRET 与 I-Cache）

| 时刻 | 事件 |
|------|------|
| **935–945ns** | ADDI WB / IRET MEM |
| **945–985ns** | ISR 预取 miss → stall + refill；IRET 卡在 MEM |
| **985–995ns** | stall 解除，IRET MEM→WB |
| **995–1005ns** | `iret_commit=1`；≈1005ns `PC←0x0D` |

详见 **[ISR-IRET与I-Cache时序.md](../中断/ISR-IRET与I-Cache时序.md)** §3（RTL 因果说明）。

---

## 7. 与 Stall、Flush 的对比


| 机制        | PC    | 流水线             | 何时恢复                      |
| --------- | ----- | --------------- | ------------------------- |
| **Stall** | 冻结    | 各级冻结            | Cache 就绪后继续               |
| **Flush** | 改向新地址 | 废指令变 bubble     | 立即从新 PC 取指                |
| **HALT**  | 冻结    | 已在流水中的指令继续流到 WB | `irq_take` 暂解除；`iret_commit` 恢复 |


HALT **不冲刷**已在流水中的指令（如 EI 仍会提交）；只阻止 **新的顺序取指**。

---

## 8. 仿真观察

建议波形信号（`run.do` 可手动添加）：

```tcl
add wave sim:/tb_soc_top/u_dut/u_cpu/cpu_halt
add wave sim:/tb_soc_top/u_dut/u_cpu/halt_latched
add wave sim:/tb_soc_top/u_dut/u_cpu/id_halt
add wave sim:/tb_soc_top/u_dut/u_cpu/id_ex_halt
add wave sim:/tb_soc_top/u_dut/u_cpu/id_ex_valid
add wave sim:/tb_soc_top/u_dut/u_if/instr_addr
```

验收要点：

- HALT 进入 **EX** 后 `instr_addr` 不再递增
- `halt_latched` 在 HALT 进 EX 后置 1 并保持
- `EI` 仍能在 WB 提交（`debug_status_ie` 变 1）
- `irq_take` 后 PC 能跳到 `0x0100`（`pc_src=11` 覆盖 halt）
- `irq_take` 后 `halt_latched` 清 0，PC 能从 `0x0100` 取到 `0x0101`（IRET）
- `IRET` 后 PC 回到 EPC（`0x0D`）且 **不再递增**

---

## 9. 相关文档


| 文档                                     | 内容                                          |
| -------------------------------------- | ------------------------------------------- |
| [flush.md](./flush.md)                 | Flush 与 Stall；中断 `pc_src=11` 与 halt 配合   |
| [Timer精确中断实现.md](../中断/Timer精确中断实现.md) | EI / HALT 后主程序与 ISR 时序                      |
| [中断相关名词解释.md](../中断/中断相关名词解释.md)       | `wb_commit`、`flush_all`、`IE`                |
| [五级流水数据通路.md](../五级流水/五级流水数据通路.md)     | 流水级划分                                       |


---

## 10. 相关 RTL 文件


| 文件                             | 作用                           |
| ------------------------------ | ---------------------------- |
| `cpu_pipe/rtl/id_stage.vhd`    | HALT 译码，`halt` 控制信号          |
| `cpu_pipe/rtl/cpu_top.vhd`     | `halt_latched`、`cpu_halt` 生成 |
| `cpu_pipe/rtl/if_stage.vhd`    | PC 保持；`pc_src=11` 优先于 halt   |
| `cpu_pipe/rtl/main_memory.vhd` | 演示程序 `EI` + `HALT`           |


