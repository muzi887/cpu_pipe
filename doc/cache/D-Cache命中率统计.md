# D-Cache 命中率统计说明

> 实现文件：`cpu_pipe/rtl/d_cache.vhd`  
> 仿真观测：`cpu_pipe/sim/run.do` → `D-Cache Stats` 分组  
> 相关架构：`[i_cache_d_cache与main_memory.md](./i_cache_d_cache与main_memory.md)`

---

## 1. 统计什么？

D-Cache 在每次**新的**读/写访存时，根据该行是否在 Cache 中，更新三个输出：


| 信号           | 位宽     | 含义                 |
| ------------ | ------ | ------------------ |
| `hit_count`  | 16 bit | 累计命中次数             |
| `miss_count` | 16 bit | 累计缺失次数             |
| `hit_rate`   | 8 bit  | 命中率 × 100，取值 0～100 |


```text
命中率 = hit_count / (hit_count + miss_count) × 100
```

**注意：** 统计在 **D-Cache** 内完成；**I-Cache 暂无** hit/miss 计数。

---

## 2. 端口定义

```vhdl
-- d_cache.vhd entity 端口（节选）

-- 性能统计：每条读/写仅在使能上升沿计 1 次（stall 保持使能不重复计）
hit_count  : out std_logic_vector(15 downto 0);
miss_count : out std_logic_vector(15 downto 0);
hit_rate   : out std_logic_vector(7 downto 0);   -- 命中率 × 100，0～100
```

`soc_top.vhd` 中 `u_dcache` 的 `hit_count` / `miss_count` / `hit_rate` 当前接 `open`（未引出到顶层）。仿真时直接探针 `u_dcache` 内部信号即可（见 §6）。

---

## 3. 什么叫 hit / miss？

由当前访存地址拆出的 `tag` + `index` 与 Cache 行比对：

```vhdl
-- d_cache.vhd

hit <= '1' when valid_bits(to_integer(req_index)) = '1' and
                tag_bits(to_integer(req_index)) = req_tag else
       '0';
```


| 条件                   | 判定       |
| -------------------- | -------- |
| `valid=1` 且 `tag` 匹配 | **hit**  |
| 行无效或 tag 不匹配         | **miss** |


读、写共用同一套 `hit` 判断；但 **写缺失不分配行**（no-write-allocate），故写 miss 后 Cache 仍无该行，下次写同一地址仍是 miss。

---

## 4. 计数逻辑（核心代码）

### 4.1 内部寄存器与输出

```vhdl
signal hit_cnt_reg  : unsigned(15 downto 0) := (others => '0');
signal miss_cnt_reg : unsigned(15 downto 0) := (others => '0');
signal total_access : unsigned(16 downto 0);

hit_count  <= std_logic_vector(hit_cnt_reg);
miss_count <= std_logic_vector(miss_cnt_reg);
```

### 4.2 上升沿检测：每条访存只计 1 次

`cache_stall=1` 时流水线冻住，MEM 级的 `read_en` / `write_en` 可能**多拍保持为 1**。  
若按“使能为 1 就计数”，同一条 ST/LD 会被重复统计。

**修法：** 记录上一拍使能，仅在 **0→1 上升沿** 计一次新访问：

```vhdl
signal read_en_q  : std_logic := '0';
signal write_en_q : std_logic := '0';
signal new_access : std_logic;

new_access <= (read_en and not read_en_q) or (write_en and not write_en_q);
```

状态机进程内：

```vhdl
elsif rising_edge(clk) then
  read_en_q  <= read_en;
  write_en_q <= write_en;

  if state = S_IDLE and new_access = '1' then
    if hit = '1' then
      hit_cnt_reg <= hit_cnt_reg + 1;
    else
      miss_cnt_reg <= miss_cnt_reg + 1;
    end if;
  end if;
  -- ...
end if;
```


| 时刻         | `write_en` | `write_en_q` | `new_access` | 是否计数      |
| ---------- | ---------- | ------------ | ------------ | --------- |
| ST 刚进入 MEM | 1          | 0            | 1            | **计 1 次** |
| stall 期间   | 1          | 1            | 0            | 不计        |
| ST 离开 MEM  | 0          | 1            | 0            | 不计        |


复位时 `hit_cnt_reg`、`miss_cnt_reg`、`read_en_q`、`write_en_q` 均清零。



后缀 `_q` 在数字电路里常表示 **寄存器输出 / 延迟一拍后的值**（queued / registered）。

### 4.3 何时不计数


| 情况                 | 原因                        |
| ------------------ | ------------------------- |
| `state = S_REFILL` | 正在 refill，本拍不是新的 CPU 访存请求 |
| `new_access = '0'` | 非上升沿，或读写使能均为 0            |
| 复位期间               | 寄存器清零                     |


读 miss 进入 `S_REFILL` 的那一拍：在 `S_IDLE` 且 `read_en` 上升沿时计 1 次 miss，随后转入 refill，不会重复计。

---

## 5. 命中率计算

```vhdl
total_access <= resize(hit_cnt_reg, 17) + resize(miss_cnt_reg, 17);

hit_rate <= std_logic_vector(
  to_unsigned(
    (to_integer(hit_cnt_reg) * 100) / to_integer(total_access),
    8
  )
) when total_access > 0 else (others => '0');
```


| `hit_count` | `miss_count` | `hit_rate`（显示） |
| ----------- | ------------ | -------------- |
| 0           | 0            | `00`（尚无访问）     |
| 0           | 5            | `00`（0%）       |
| 3           | 1            | `75`（75%）      |
| 5           | 5            | `50`（50%）      |


整数除法，无小数；访问次数少时精度有限。

---

## 6. 仿真中如何观测

`run.do` 已添加波形：

```tcl
add wave -divider "D-Cache Stats"
add wave sim:/tb_soc_top/u_dut/u_dcache/hit_count
add wave sim:/tb_soc_top/u_dut/u_dcache/miss_count
add wave sim:/tb_soc_top/u_dut/u_dcache/hit_rate
```

建议配合：

```tcl
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_mem_write   -- ST 写使能
add wave sim:/tb_soc_top/u_dut/cache_stall
add wave sim:/tb_soc_top/debug_pc
```

---

## 7. 斐波那契程序上的预期波形

程序只有 **ST**（写），没有 **LD**（读）；D-Cache 为 **写直达 + 写缺失不分配**。


| 现象                 | 原因                                   |
| ------------------ | ------------------------------------ |
| `hit_count` 一直为 0  | 写 miss 不把行装入 Cache，后续写仍 miss         |
| `miss_count` 最终为 5 | 循环 5 次，每次 1 条 `ST x3, 0(x4)`         |
| `hit_rate` 为 0     | hit ÷ (hit+miss) = 0 ÷ 5 = 0%        |
| 每次 +1 间隔多拍         | 中间有 I-Cache miss stall，但 **不再每拍 +1** |


```text
miss_count:  0 ──► 1 ──────► 2 ──────► 3 ──────► 4 ──────► 5
              ↑      ↑           ↑           ↑           ↑
           第1次ST  第2次ST     第3次ST     第4次ST     第5次ST
           (每轮循环各 1 次，stall 期间保持不计)
```

**不能**把 `hit_rate=0` 解读为“Cache 完全无效”——本程序根本不产生读 hit，且写从不分配行。

---

## 8. 读 / 写 miss 与功能行为的关系

统计用的 `hit` 与功能路径一致，但含义不同：


| 访问类型        | miss 时 Cache 行为             | 是否计入 `miss_count` |
| ----------- | --------------------------- | ----------------- |
| **读**（LD）   | 进入 `S_REFILL`，`cpu_ready=0` | 是（上升沿计 1 次）       |
| **写**（ST）命中 | 更新 Cache 行 + 写主存            | 否（计 hit）          |
| **写**（ST）缺失 | 只写主存，不分配行                   | 是（计 miss）         |


```vhdl
-- 读 miss 会 stall（斐波那契无 LD，通常不触发）
d_miss    <= '1' when state = S_REFILL
                  or (read_en = '1' and state = S_IDLE and hit = '0') else '0';
cpu_ready <= '0' when state = S_REFILL
                  or (read_en = '1' and state = S_IDLE and hit = '0') else '1';

-- 写直达：write_en=1 时 mem_req=1，但不进入 S_REFILL
mem_req      <= '1' when state = S_REFILL or write_en = '1' else '0';
mem_write_en <= write_en when state = S_IDLE else '0';
```

---

## 9. 曾修复的 bug（stall 重复计数）

### 9.1 错误写法（已废弃）

```vhdl
-- 错误：stall 期间 write_en 每拍为 1，miss 被重复累加
if state = S_IDLE and (read_en = '1' or write_en = '1') then
  if hit = '1' then
    hit_cnt_reg <= hit_cnt_reg + 1;
  else
    miss_cnt_reg <= miss_cnt_reg + 1;
  end if;
end if;
```

现象：PC=7 stall 时 `miss_count` 从 1 涨到 6（一条 ST 被数 6 次）。

### 9.2 当前写法

见 §4.2：仅在 `new_access='1'` 时计数。

---

## 10. 可扩展方向


| 方向               | 说明                                      |
| ---------------- | --------------------------------------- |
| 引出到 `soc_top` 顶层 | 将 `hit_count` 等接到调试端口或 MMIO 只读寄存器       |
| I-Cache 统计       | 在 `i_cache.vhd` 增加对称计数器                 |
| 读写分开统计           | `read_hit` / `write_hit` 分开，命中率仅用读访问    |
| 写分配后 hit 变化      | 若改为 write-allocate，重复写同一地址可出现 write hit |


---

## 11. 相关文件索引


| 文件                                         | 内容                          |
| ------------------------------------------ | --------------------------- |
| `cpu_pipe/rtl/d_cache.vhd`                 | 统计实现                        |
| `cpu_pipe/rtl/soc_top.vhd`                 | 例化 `u_dcache`（统计口暂接 `open`） |
| `cpu_pipe/sim/run.do`                      | 波形脚本                        |
| `doc/cache/i_cache_d_cache与main_memory.md` | D-Cache 整体架构                |
| `doc/cache/Cache主存争用与mem_grant修复.md`       | 主存争用与 stall 背景              |


---

## 12. 一句话总结

**D-Cache 在每次读/写使能上升沿根据 `hit` 更新 `hit_count` 或 `miss_count`，`hit_rate = hit×100/(hit+miss)`；上升沿计数以避免 stall 期间重复统计；斐波那契只有写 miss，故 `miss_count=5`、`hit_rate=0` 属预期结果。**