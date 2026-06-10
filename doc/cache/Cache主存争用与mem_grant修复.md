# Cache 主存争用与 mem_grant 修复

> 本文档由 `Cache仿真异常分析.md` 重构而来，**原文件保留不动**。  
> 面向斐波那契程序 + ModelSim 波形调试，记录单端口 `main_memory` 上 I/D Cache 争用的两个仿真问题及 RTL 修复。  
> 架构背景见 [`i_cache_d_cache与main_memory.md`](./i_cache_d_cache与main_memory.md)。

---

## 0. 快速导航

| 问题 | 现象 | 状态 |
|------|------|------|
| [问题一](#1-问题一pc8-指令变成-0000) | PC=8 时 `debug_instr=0000`，x4 写回失败 | 已修复（`mem_grant` v1） |
| [问题二](#2-问题二pc7-程序卡死) | PC=7 停住，`cache_stall` 一直为 1 | 已修复（仲裁 + `mem_grant` v2） |

**涉及文件：** `i_cache.vhd`、`d_cache.vhd`、`soc_top.vhd`、`cache_control.vhd`、`main_memory.vhd`

---

## 背景：为什么容易出问题？

CPU 采用哈佛接口（取指、访存两路），但 **I-Cache 与 D-Cache 共用一块 `main_memory`**。  
Miss 时两边都可能访问主存，必须仲裁。仲裁或授权写错，就会出现：

1. **读错**：I-Cache refill 采到 `0000`，错指令进流水线  
2. **卡死**：I-Cache 永远 refill 不完，流水线永久 stall

```text
cpu_top
  IF  ──► i_cache ──┐
                    ├──► main_memory（单端口）
  MEM ──► d_cache ──┘
         ▲
    cache_control：stall <= i_miss or (not cpu_ready)
```

**调试信号含义：**

| 信号 | 来源 | 含义 |
|------|------|------|
| `debug_pc` / `debug_instr` | IF/ID 寄存器 | 进入 ID 阶段的 PC 与指令，**不是 WB 级** |
| `i_miss` | I-Cache | 取指 miss 或正在 refill |
| `d_miss` / `cpu_ready` | D-Cache | 读 miss / refill；`cpu_ready=0` 等价于 D 侧未就绪 |
| `cache_stall` | cache_control | `i_miss=1` 或 `cpu_ready=0` 时冻结整条流水线 |

**斐波那契相关指令：**

| PC | 机器码 | 指令 | 备注 |
|----|--------|------|------|
| 5 | `38C0` | ST x3, 0(x4) | 写主存地址 13，与 I-Cache refill 易冲突 |
| 7 | `0680` | ADDI x2, x3, 0 | 卡死时 IF/ID 常停在这里 |
| 8 | `0901` | ADDI x4, x4, 1 | 应在行 2 refill 后正确取指 |

**Cache 行划分（index = PC[5:2]）：**

```text
PC 0～3  → 行 0
PC 4～7  → 行 1
PC 8～11 → 行 2   ← ADDI x4,x4,1 所在行，首次与 ST 写主存重叠
```

---

## 1. 问题一：PC=8 指令变成 `0000`

### 1.1 现象

| 观测点 | 预期 | 实际 |
|--------|------|------|
| PC=8 时 IF/ID 指令 | `0901` | `0000` |
| x4 更新 | 13 → 14 | 保持 13 |
| EX 级 rs（~265ns） | rs=4 | rs=3（实为 PC=7 的 `0680` 停在 EX） |

波形约 255～265ns：`debug_pc=8` 且 `debug_instr=0000`。PC 与指令字对齐，说明 **不是流水线错位**，而是 **I-Cache 给了错误数据**。

### 1.2 当时流水线在做什么？

PC=8 触发 I-Cache 行 2 miss，同时 MEM 级在执行 PC=5 的 ST：

```text
IF   : PC=8  →  I-Cache miss，refill 主存 [8,9,10,11]
ID   : PC=7  →  ADDI x2, x3, 0
EX   : PC=6  →  ADDI x1, x2, 0
MEM  : PC=5  →  ST x3, 0(x4)  →  D-Cache 写主存
```

I-Cache 要**读**主存，D-Cache 要**写**主存，共用一根总线。

### 1.3 根因（技术）

**仲裁：D-Cache 优先**

```vhdl
-- soc_top.vhd（修复前）
mm_addr     <= d_mem_addr     when d_mem_req = '1' else i_mem_addr;
mm_read_en  <= d_mem_read_en  when d_mem_req = '1' else i_mem_read_en;
mm_write_en <= d_mem_write_en when d_mem_req = '1' else '0';
```

ST 执行时 `d_mem_req=1`，`mm_read_en=0`。主存写周期不驱动读数据：

```vhdl
-- main_memory.vhd
rdata <= memory(addr_i) when read_en = '1' else (others => '0');
```

故 `mm_rdata = 0000`。而 I-Cache refill **每拍无条件采样**：

```vhdl
-- i_cache.vhd（修复前）
cache_lines(idx)(to_integer(refill_cnt)) <= mem_rdata;
```

**因果链：**

```text
PC=8 miss → I-Cache S_REFILL（行 2）
     ‖ 同拍
PC=5 ST   → d_mem_req=1，mm_read_en=0，mm_rdata=0000
     ↓
I-Cache 仍把 0000 写入 cache_lines[2][*]
     ↓
refill 结束 valid=1 → 对 PC=8 形式上 hit，但内容是 0000
     ↓
stall 解除 → IF/ID 锁存 PC=8, instr=0000 → x4 写回失败
```

### 1.4 根因（通俗）

主存只有一个口。ST 在写的时候，I-Cache 那边读出来全是 0，但 I-Cache **还是把 0 存进了 Cache**。  
stall 结束后命中读 Cache，读到的就是被写坏的 0，**不会自动从主存恢复**（主存里 `0901` 其实还在）。

```text
【容易误以为】stall 结束 → 再读主存 → 得到 0901
【实际情况】  stall 结束 → hit 读 Cache → 得到 0000（refill 时写坏的）
```

### 1.5 修复（mem_grant v1）

**思路：** 只有总线**真正授权**读时，I-Cache 才采样 `mem_rdata`、才推进 refill。

| 文件 | 改动 |
|------|------|
| `i_cache.vhd` | 新增 `mem_grant`（mem_read_en 门控）；`S_REFILL` 仅在 `mem_grant=1` 时写 Cache 行 |
| `soc_top.vhd` | 产生 `i_mem_grant` 并接到 I-Cache |

```vhdl
-- i_cache.vhd
mem_read_en <= '1' when state = S_REFILL and mem_grant = '1' else '0';

when S_REFILL =>
  if mem_grant = '1' then
    cache_lines(idx)(to_integer(refill_cnt)) <= mem_rdata;
    -- 递增 refill_cnt 或结束 refill
  end if;
```

```vhdl
-- soc_top.vhd（v1，后引发问题二）
i_mem_grant <= '0' when d_mem_req = '1' else '1';
```

效果： 主存被 D-Cache 写占用时，I-Cache 暂停 refill，不把 0000 写进 Cache 行。

### 1.6 验证要点

1. PC=8：`debug_instr = 0901`
2. refill 与 ST 重叠时 `refill_cnt` 暂停，不写入 `0000`
3. x4：13 → 14
4. `cache_lines[2][0] = 0901`

---

## 2. 问题二：PC=7 程序卡死

### 2.1 现象

问题一修完后，指令不再读错，但仿真在 **PC=7** 停住：

- `cache_stall` 一直为 1，`debug_pc` 不再前进
- 常见：`mem_write_en=1`，`mem_addr=000D`（ST 写地址 13）
- `i_miss=1` 或 I-Cache refill 无法结束

### 2.2 根因（通俗）

可以想成 **互相等、谁也动不了**：

1. PC=8 要取新一行指令 → I-Cache miss → 全线 stall  
2. ST 被冻在 MEM，`write_en` 每拍都是 1  
3. 旧逻辑里「D-Cache 要用主存」就拉低 `i_mem_grant`，**写也算占用**  
4. I-Cache 每拍都拿不到授权 → refill 永远完不成 → 永远 stall  
5. PC 看起来停在 7（IF/ID 冻住），实际是 **PC=8 的取指卡住了**

```text
I-Cache："我要读指令！"
D-Cache："ST 在写，你先等。"（每拍都说）
CPU：    "全线冻结，谁也不许动。"
→ 死锁
```

### 2.3 根因（技术）

```text
IF/ID : PC=7
MEM   : ST x3, 0(x4)  →  write_en=1，d_mem_req=1（每拍）
IF    : 预取 PC=8    →  I-Cache 行 2 miss，S_REFILL
```

v1 授权逻辑：

```vhdl
i_mem_grant <= '0' when d_mem_req = '1' else '1';
```

`d_mem_req` 在 **写直达** 时也为 1。ST 冻在 MEM 后 **每拍拉低 grant** → **I-Cache 无法 refill → `i_miss` 不释放 → 永久 stall**。

### 2.4 与问题一的关系

| | 问题一 | 问题二 |
|---|--------|--------|
| 授权过宽 | 未检查 grant 就采样 → 读到 0 还写入 | `d_mem_req` 含写 → grant 永远为 0 |
| 表现 | 错指令 `0000` | PC 卡死 |
| 同一根源 | 单端口主存 + I/D 同时访问 + 授权/仲裁不当 | 同左 |

问题一修「采样」，但 v1 的 grant 条件太粗，触发了问题二。

### 2.5 修复（mem_grant v2 + 仲裁）

**三条原则：**

1. **授权只看「读主存」** — 写不阻塞 I-Cache refill  
2. **I-Cache 读优先** — D-Cache 写可延后一拍  
3. **D-Cache refill 对称加 `mem_grant`** — 避免 Load miss 时采错数

```vhdl
-- soc_top.vhd（当前方案）
i_mem_grant <= '0' when d_mem_read_en = '1' else '1';
d_mem_grant <= '0' when i_mem_read_en = '1' else '1';

mm_addr     <= i_mem_addr     when i_mem_read_en = '1' else d_mem_addr;
mm_read_en  <= i_mem_read_en  when i_mem_read_en = '1' else d_mem_read_en;
mm_write_en <= d_mem_write_en when d_mem_write_en = '1' and i_mem_read_en = '0' else '0';
```

| 文件 | 改动 |
|------|------|
| `soc_top.vhd` | 上述授权与仲裁；`d_cache` 组件声明补 `mem_grant` |
| `d_cache.vhd` | 新增 `mem_grant`；REFILL 逻辑与 I-Cache 对称 |

### 2.6 验证要点

1. PC=7 之后能到 PC=8，`debug_instr=0901`
2. `i_miss` 在 PC=8 换行后若干拍内回到 0
3. ST 写 `mem[13]=2` 在 stall 解除后完成
4. 仿真能跑完 BNE 循环

---

## 3. 波形阅读备忘

### 3.1 `debug_pc` 不等于 WB 正在写的指令

`debug_pc` / `debug_instr` 接 IF/ID。例如 `debug_pc=8` 表示 `ADDI x4,x4,1` **刚进 ID**，写回要等约 3～4 拍（有 stall 时更晚）。  
在 255～265ns 看 `reg_write_in=0`，可能是 WB 里恰好是不写寄存器的 ST/BNE，**不一定是 ADDI 写回失败**。

### 3.2 EX 级 rs=3 不代表 PC=8 译码错

`ADDI x4,x4,1` 应 rs=4。若 EX 见 rs=3，多为 **PC=7 的 `0680`（ADDI x2,x3,0）因 stall 停在 EX**，与 PC=8 取指错误是同一时段的不同级。

### 3.3 为何 PC=0～7 写回看起来正常？

| PC 段 | Cache 行 | refill 是否与 ST 写重叠 |
|-------|----------|-------------------------|
| 0～3 | 行 0 | 否 |
| 4～7 | 行 1 | 通常否 |
| **8** | **行 2** | **是（与 PC=5 的 ST 重叠）** |

只有 PC=8 所在行 refill 首次与 ST 撞车，错误才明显暴露。

---

## 4. 最终 RTL 方案汇总

```text
修复演进
  原始实现 ──► 问题一：refill 无条件采样 mem_rdata
       │
       ▼
  mem_grant v1 ──► 问题二：grant 被 d_mem_req（含写）永久拉低
       │
       ▼
  mem_grant v2 + I 读优先仲裁 ──► 当前方案
```

**I-Cache / D-Cache refill 共同规则：**

- `mem_read_en` 仅在 `S_REFILL and mem_grant='1'` 时为 1  
- `S_REFILL` 仅在 `mem_grant='1'` 时采样 `mem_rdata` 并递增 `refill_cnt`  
- `mem_grant=0` 时暂停，下一拍从同一 `refill_cnt` 重试  

**`cache_control.vhd`（未改）：**

```vhdl
stall <= i_miss or (not cpu_ready);
```

斐波那契无 Load，`cpu_ready` 通常保持 1；stall 主要由 `i_miss` 引起。

---

## 5. 仿真检查清单

跑完 `do run.do` 后，按顺序核对：

- [ ] 冷启动：首次 `i_miss` 后 PC 能继续走
- [ ] PC=8：`debug_instr = 0901`（不是 `0000`）
- [ ] PC=7 之后不再永久 stall
- [ ] `mem[13]` 被 ST 写成 x3 的值（第一次循环为 2）
- [ ] x4 能随 `ADDI x4,x4,1` 递增
- [ ] BNE 能跳回 LOOP，多次循环后 HALT

**建议同时观察：**

```text
debug_pc, debug_instr
i_miss, i_mem_grant, i_mem_read_en
d_miss, cpu_ready, d_mem_read_en, d_mem_write_en
cache_stall, mem_write_en, mem_addr
```

---

## 6. 其他可选方案（未采用）

| 方案 | 说明 | 未采用原因 |
|------|------|------------|
| refill 期间推迟 D-Cache 占主存 | `i_miss=1` 时缓冲 ST | 改动大，需写缓冲 |
| 哈佛双主存 | 指令、数据各一块 RAM | 与课设单主存架构不一致 |
| 分级 stall | 仅 Load 时因 `cpu_ready` 冻 WB | 可作后续优化；斐波那契无 Load |

---

## 7. 相关代码索引

| 文件 | 关键点 |
|------|--------|
| `soc_top.vhd` | 主存仲裁、`i_mem_grant` / `d_mem_grant` |
| `i_cache.vhd` | `i_miss`、`S_REFILL`、`mem_grant` |
| `d_cache.vhd` | `d_miss`、`cpu_ready`、`mem_grant` |
| `cache_control.vhd` | 全局 `cache_stall` |
| `main_memory.vhd` | `read_en=0` 时 `rdata=0` |
| `cpu_top.vhd` | `cache_stall` 冻结各级流水线；`debug_pc`/`debug_instr` |

---

## 8. 一句话总结

**单端口主存上，I-Cache refill 与 D-Cache 写撞车时，若未正确授权，会先错存 `0000`（问题一）；若授权把写也当成占线，会死锁在 PC=7（问题二）。当前方案：只在真实读周期互斥授权，且 I-Cache 读优先，写可等一拍。**
