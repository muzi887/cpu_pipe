# ISR / IRET 与 I-Cache 仿真时序说明

> 配合波形阅读：`run.do` 中 TB / IF / I-Cache / `cache_stall` / `iret_commit` / `flush_all`  
> 相关：[Timer精确中断实现.md](./Timer精确中断实现.md)、[halt.md](../竞争冒险/halt.md)、[i_cache_d_cache与main_memory.md](../cache/i_cache_d_cache与main_memory.md)

---

## 1. 结论（以实测波形为准）

| 时刻 | 含义 |
|------|------|
| **935–945ns** | **ADDI** 在 **WB** 写回 x6；**IRET** 在 **MEM**（比 ADDI 低一级） |
| **945–985ns** | **`cache_stall=1`**，I-Cache **refill**（ISR 区预取 **0x0102** 一带 miss）；**流水线冻结**，IRET **停在 MEM**，尚未提交 |
| **985–995ns** | stall 结束，IRET **MEM→WB**，`debug_pc` 仍沿 ISR 预取路径（如 `0103`→`0104`） |
| **995–1005ns** | **`iret_commit=1`**（IRET 在 **WB 提交**）；**`flush_all=1`** |
| **≈1005ns** | **`PC ← EPC`（`0x0D`）**；`halt_latched←1`；IF 开始对 **0x0D** 取指（可能再次 **i_miss**） |

> 时钟 **10ns/拍** 时，上表窗口各约 **1 拍**。ns 以波形光标为准。

**要点**：

1. **945–985ns 的 refill 不是 IRET 返回后**，而是 **IRET 还在 MEM、IF 已预取到 0x0102** 时的 **I-Cache miss + stall**。
2. **stall 期间流水不推进**，IRET 被 **推迟** 到 **995–1005ns** 才在 WB 提交。
3. **`iret_commit=1` 在 995–1005ns**；**PC 跳到 `0x0D` 在 ≈1005ns**（提交拍末尾/下一拍 IF 可见）。

---

## 2. ISR 两条指令：流水对齐

`main_memory.vhd` 预载：

| 地址 | 机器码 | 指令 |
|------|--------|------|
| `0x0100` | `0D81` | `ADDI x6, x6, 1` |
| `0x0101` | `E002` | `IRET` |

IRET 比 ADDI **晚 1 拍** 进入流水：

```text
935–945ns   ADDI 在 WB（ex_rs/ex_rd=6，reg_write 写 x6）
            IRET 在 MEM

945–985ns   cache_stall=1，IRET 仍停在 MEM（流水冻结）
            IF 侧 PC 曾预取到 0x0102 等 → 触发 refill

985–995ns   stall 解除，IRET 进入 WB 路径

995–1005ns  IRET 在 WB：iret_commit=1，flush_all=1

≈1005ns     PC ← EPC = 0x0D
```

```vhdl
iret_commit <= mem_wb_valid and mem_wb_sys_iret and (not cache_stall);
flush_all   <= irq_take or iret_commit;
pc_redirect <= epc_reg when iret_commit = '1' else ISR_ADDR;
```

**`iret_commit` 要求 `cache_stall=0`**，故 **945–985ns stall 期间 IRET 不可能提交**——这与波形一致。

---

## 3. 两段 refill 不要混

| 时段 | 原因 | 与 IRET 关系 |
|------|------|----------------|
| **945–985ns** | ISR 内 IF 预取 **0x0102/0x0104** 等 → **miss** | IRET 还在 MEM，**未返回** |
| **≈1005ns 之后** | **PC←0x0D** 后取主程序行 → 可能 **再次 miss** | **IRET 提交之后** |

`main_memory` 的 `256/257` 只是保证 **refill 时主存有 ADDI/IRET 机器码**，**不能避免 miss**。

---

## 4. 为何 EPC 是 13（`0x0D`）

| 地址 | 内容 |
|------|------|
| `0x0C` | `HALT` |
| `0x0D` | 停机时 `if_pc`（HALT 在 ID 时 PC 已 +1） |

`irq_take` 时 **`EPC ← if_pc = 0x0D`**。IRET 回到 **0x0D** 后 **`halt_latched←1`**，PC 再冻住——不是继续跑主程序。

---

## 5. 仿真时间轴（与波形对照）

```text
时间        流水 / 事件                      debug_pc   iret_commit   cache_stall
──────────────────────────────────────────────────────────────────────────────────
935–945     ADDI WB，IRET MEM                0101       0             0
945–985     ISR 预取 miss → refill；IRET 卡在 MEM   0102       0             1
985–995     stall 结束，IRET→WB              0103–0104  0             0
995–1005    IRET WB 提交                     0104       1             0
≈1005       PC←EPC=0x0D；取 0x0D            000D       0             0/1?
之后        halt 冻住 PC                     000D       0             …
```

`debug_pc` 为 **IF/ID 中的 PC**，比 **`if_pc`/`instr_addr`** 晚 1～2 级；**1005ns 看到 `000D`** 正常。

---

## 6. 推荐波形信号

```tcl
add wave sim:/tb_soc_top/clk
add wave sim:/tb_soc_top/u_dut/u_cpu/cache_stall
add wave sim:/tb_soc_top/u_dut/u_cpu/iret_commit
add wave sim:/tb_soc_top/u_dut/u_cpu/flush_all
add wave sim:/tb_soc_top/u_dut/u_cpu/halt_latched
add wave sim:/tb_soc_top/debug_epc
add wave sim:/tb_soc_top/debug_pc
add wave sim:/tb_soc_top/u_dut/u_if/instr_addr
add wave sim:/tb_soc_top/u_dut/u_cpu/if_pc
add wave sim:/tb_soc_top/u_dut/u_icache/state
add wave sim:/tb_soc_top/u_dut/u_icache/hit
add wave sim:/tb_soc_top/u_dut/u_icache/i_miss
```

---

## 7. 相关文档

| 文档 | 内容 |
|------|------|
| [halt.md](../竞争冒险/halt.md) | `halt_latched` 与 `irq_take` / `iret_commit` |
| [Timer精确中断实现.md](./Timer精确中断实现.md) | `iret_commit`、`wb_commit` |
| [i_cache_d_cache与main_memory.md](../cache/i_cache_d_cache与main_memory.md) | miss/refill、stall |
