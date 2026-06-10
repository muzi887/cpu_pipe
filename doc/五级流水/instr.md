# 取指通路与 debug 观测信号

## 1. 信号分层

```text
if_pc (= instr_addr)
  │
  ├──组合读──> instr_data ──> if_instruction     （IF 组合通路，本拍有效）
  │
  └──时钟沿锁存 IF/ID──> if_id_pc, if_id_instr   （ID 阶段入口，上一拍 IF 的结果）
```

| 信号 | 阶段 | 更新时机 | 含义 |
|------|------|----------|------|
| `if_pc` | IF | 每拍（受 `pc_en` / `halt` 控制） | 当前正在用来取指的 PC |
| `if_instruction` | IF | 组合，随 `if_pc` 变化 | 当前 PC 对应的指令（= `instr_data`） |
| `if_id_pc` | IF/ID | 时钟沿锁存 | 上一拍取指时的 PC |
| `if_id_instr` | IF/ID | 时钟沿锁存 | 上一拍取到的指令，现由 ID 译码 |

指令存储器为**组合读**（`instr_memory`），因此 `if_instruction` 与 `instr_data` 在同一拍内对应当前 `if_pc`，无额外延迟。

`if_id_pc` / `if_id_instr` 比 `if_pc` / `if_instruction` **慢 1 个时钟周期**——它们是上一拍 IF 输出在上升沿锁进 IF/ID 寄存器后的值。

## 2. debug 端口分配（定稿）

RTL（`cpu_top.vhd`）：

```vhdl
debug_pc    <= if_id_pc;
debug_instr <= if_id_instr;
```

**设计意图**：`debug_pc` 与 `debug_instr` 均来自 **IF/ID 流水线寄存器**，二者**同拍配对**，表示「ID 阶段正在译码的那条指令及其取指地址」。

### 为何不用 `if_pc` + `if_id_instr`

旧接法将「本拍 PC」与「上一拍指令」混在一起，波形上会出现错位：

```text
时刻 T（上升沿之后）：
  if_pc        = 0x0005   ← 本拍 IF 正在取地址 5
  if_id_instr  = 0x1298   ← 上一拍取到的指令（地址 4）
```

用 `debug_pc` 去查表时，无法与 `debug_instr` 对应，容易误判。

### 备选接法（仅作对比，未采用）

| 观察目标 | `debug_pc` | `debug_instr` |
|----------|------------|---------------|
| 当前取指（IF 组合通路） | `if_pc` | `if_instruction` |
| **ID 阶段译码（定稿）** | **`if_id_pc`** | **`if_id_instr`** |

课设仿真以 **ID 阶段配对** 为准：`debug_pc` 与 `debug_instr` 可直接对照 `instr_memory` 中的地址—指令表。

## 3. 时序示例

假设无 stall、无 flush，时钟周期为 T0、T1、T2…

| 时刻 | `if_pc` | `if_instruction` | `if_id_pc` / `debug_pc` | `if_id_instr` / `debug_instr` |
|------|---------|------------------|---------------------------|--------------------------------|
| T1 后 | 1 | `instr[1]` | 0 | `instr[0]` |
| T2 后 | 2 | `instr[2]` | 1 | `instr[1]` |
| T3 后 | 3 | `instr[3]` | 2 | `instr[2]` |

在同一时刻看 `debug_pc` 与 `debug_instr`，得到的是**同一条**已进入 ID 的指令及其 PC，而不是 IF 本拍正在预取的下一条。

## 4. 与流水线其余阶段的关系

```text
IF（if_pc, if_instruction）
  │ 时钟沿
  ▼
IF/ID（if_id_pc, if_id_instr）  ← debug_pc, debug_instr
  │ 时钟沿
  ▼
ID/EX → EX → MEM → WB
```

五级流水有级间延迟：某条指令的写回、访存效果需等其流到 WB / MEM 才能在波形上看到，不能指望 `debug_instr` 变化当拍就写寄存器。

## 5. 仿真建议

推荐观测：

```text
/tb_soc_top/debug_pc
/tb_soc_top/debug_instr
```

或深入 CPU 内部：

```text
/tb_soc_top/u_dut/u_cpu/debug_pc
/tb_soc_top/u_dut/u_cpu/debug_instr
```

判读要点：

- `debug_pc = N`、`debug_instr = instr[N]` → ID 正在译码地址 N 处的指令
- 需要看「本拍 IF 预取」时，另加 `if_pc`、`if_instruction`（或 `instr_data`），勿与 `debug_*` 混读
