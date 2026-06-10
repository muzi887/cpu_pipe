# i_cache / d_cache 构成逻辑与 main_memory 对比

> 对应 RTL：`cpu_pipe/rtl/i_cache.vhd`、`d_cache.vhd`、`main_memory.vhd`、`cache_control.vhd`、`soc_top.vhd`

---

## 1. 整体连接关系

```text
                    ┌──────────────┐
  IF: PC ──────────►│   i_cache    │──mem_req/read──┐
                    └──────────────┘                │
                                                    ▼
                    ┌──────────────┐         ┌─────────────┐
  MEM: ALU地址 ────►│   d_cache    │────────►│ main_memory │（唯一物理 RAM）
                    └──────────────┘         └─────────────┘
                           │                        ▲
                           │                        │
                    i_miss / cpu_ready              │
                           ▼                        │
                    ┌──────────────┐                │
                    │cache_control │──stall────────►│ cpu_top
                    └──────────────┘   (冻结流水)    │
```

**要点：**

- CPU 前端仍是**哈佛接口**：取指走 `i_cache`，访存走 `d_cache`，两路独立。
- 后端只有**一块** `main_memory`：miss 或写直达时，两个 Cache 通过 `soc_top` 仲裁后访问同一 RAM。
- `cache_control` 不直接连主存，只根据 `i_miss` 和 `cpu_ready` 产生 `stall`，冻结流水线。

### 1.1 soc_top 互联代码

```vhdl
-- cpu_pipe/rtl/soc_top.vhd（节选）

-- CPU ↔ Cache
u_icache : i_cache
  port map (
    addr        => instr_addr,    -- PC
    data        => instr_data,    -- 指令字 → IF
    i_miss      => i_miss,
    mem_rdata   => mm_rdata       -- 共享主存读数据
  );

u_dcache : d_cache
  port map (
    addr         => mem_addr,     -- ALU 有效地址
    wdata        => mem_wdata,
    write_en     => mem_write_en,
    read_en      => mem_read_en,
    rdata        => mem_rdata,    -- Load 数据 → MEM
    cpu_ready    => cpu_ready,
    mem_rdata    => mm_rdata
  );

-- 总线授权：仅对方在读主存时暂停本侧 refill
i_mem_grant <= '0' when d_mem_read_en = '1' else '1';
d_mem_grant <= '0' when i_mem_read_en = '1' else '1';

-- 主存仲裁：I-Cache 读优先；D-Cache 写可在 I-Cache 不读时进行
mm_addr     <= i_mem_addr     when i_mem_read_en = '1' else d_mem_addr;
mm_read_en  <= i_mem_read_en  when i_mem_read_en = '1' else d_mem_read_en;
mm_write_en <= d_mem_write_en when d_mem_write_en = '1' and i_mem_read_en = '0' else '0';

u_main_memory : main_memory
  port map (addr => mm_addr, rdata => mm_rdata, ...);

u_cache_control : cache_control
  port map (i_miss => i_miss, cpu_ready => cpu_ready, stall => cache_stall);

u_cpu : cpu_top
  port map (..., cache_stall => cache_stall);
```

main_memory 只有一个读写口，但 i_cache 和 d_cache 在 miss 或写直达时都可能同时要访问主存，所以需要 **仲裁**（这一拍主存给谁）和 **mem_grant**（refill 是否允许采样 `mem_rdata`）。

当前策略（详见 [`Cache主存争用与mem_grant修复.md`](./Cache主存争用与mem_grant修复.md)）：

| 机制 | 规则 |
|------|------|
| **mem_grant** | 仅当对方在读主存（`mem_read_en=1`）时，本侧 refill 暂停采样 |
| **仲裁** | I-Cache 读优先；D-Cache 写仅在 I-Cache 不读时进行（可延后一拍） |
| **为何 I 读优先** | `i_miss=1` 会全局 stall，refill 不完流水线动不了；写直达可晚一拍 |

> 早期 RTL 曾用「d_cache 固定优先 + `i_mem_grant <= not d_mem_req`」，会引发 PC=8 读错 `0000` 与 PC=7 死锁，已废弃。

---

## 2. main_memory 的构成逻辑

`main_memory` 是最底层的**统一物理存储**，逻辑极简：

| 组成 | 说明 |
|------|------|
| `memory[]` | 深度 `2^16` 的 16 bit 字数组 |
| `INIT_MEM` | 上电初值：地址 0～11 为斐波那契指令，12 为数据初值 |
| 读路径 | **组合读**：`read_en='1'` 时 `rdata <= memory(addr)`，0 延迟 |
| 写路径 | **同步写**：时钟上升沿且 `write_en='1'` 时写入 |

```text
addr ──► to_integer ──► memory[addr_i]
                              │
              read_en=1 ──────┴──► rdata（组合）
              write_en=1 ──────────► 下一拍写入（时序）
```

**特点：**

- 不区分"指令区"和"数据区"，只靠**地址**区分内容。
- 没有 hit/miss、没有 valid/tag，每次读都直接返回主存内容。
- 只暴露**一个端口**，同一时刻只能服务一个访问者（由 `soc_top` 仲裁）。

### 2.1 端口与存储阵列

```vhdl
-- cpu_pipe/rtl/main_memory.vhd

entity main_memory is
  port (
    clk       : in  std_logic;
    addr      : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    wdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    write_en  : in  std_logic;
    read_en   : in  std_logic;
    rdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity main_memory;

constant INIT_MEM : mem_array_t := (
  0  => x"0041",   -- ADDI x1, x0, 1
  1  => x"0081",   -- ADDI x2, x0, 1
  ...
  11 => x"F000",   -- HALT
  12 => x"0001",   -- f2 初值
  others => (others => '0')
);
signal memory : mem_array_t := INIT_MEM;
```

### 2.2 读（组合）+ 写（时序）

```vhdl
-- cpu_pipe/rtl/main_memory.vhd

addr_i <= to_integer(unsigned(addr));

-- 组合读：read_en=1 时当拍出数
rdata <= memory(addr_i) when read_en = '1' else (others => '0');

-- 同步写：上升沿写入
write_proc : process (clk)
begin
  if rising_edge(clk) then
    if write_en = '1' then
      memory(addr_i) <= wdata;
    end if;
  end if;
end process write_proc;
```

与 Cache 对比：主存**没有** `valid`/`tag`，`addr` 直接索引 `memory[]`。

---

## 3. i_cache 的构成逻辑

### 3.1 内部存储结构

直接映射 Cache，参数如下：

| 参数 | 值 | 含义 |
|------|-----|------|
| 行数 `NUM_LINES` | 16 | 4 bit index，共 16 行 |
| 行宽 `LINE_WORDS` | 4 | 每行 4 个 16 bit 字 |
| 地址划分 | tag(15:6) \| index(5:2) \| offset(1:0) | 10 + 4 + 2 = 16 bit |

每行由三部分描述：

```text
cache_lines[index][0..3]   ← 4 个数据字（数据体）
valid_bits[index]          ← 该行是否有效（元数据）
tag_bits[index]            ← 10 bit 行标签（元数据）
```

总容量：16 行 × 4 word × 16 bit = **128 B**（仅存数据副本；valid/tag 另计）。

### 3.1.1 地址三字段：tag / index / offset

16 位地址**拆成三个字段**，各干各的事：

```text
 15        6 5    2 1  0
┌──────────┬──────┬────┐
│   tag    │index │off │   共 16 bit
│  10 bit  │4 bit │2bit│
└──────────┴──────┴────┘
```

| 字段 | 位 | 长度 | 作用 |
|------|-----|------|------|
| **offset** | `addr(1:0)` | 2 bit | 在这一行里选**第几个字**（0～3） |
| **index** | `addr(5:2)` | 4 bit | 选 Cache 的**第几行**（0～15，共 16 个槽位） |
| **tag** | `addr(15:6)` | 10 bit | 与 `tag_bits[index]` 比较，**确认这一行是不是当前地址对应的主存块** |

- **index** → 选哪一行（槽位）
- **tag** → 这一行装的是不是你要的那块主存
- **offset** → 这一行 4 个字里的哪一个

### 3.1.2 valid / tag 在 64 bit 数据之外

一行里的 **4×16 bit = 64 bit 只是数据部分**；`valid` 和 `tag` 是**行外的元数据**，不编进这 64 bit 里。

RTL 里是**三套独立存储**（`d_cache` 结构相同）：

```vhdl
signal cache_lines : cache_t;       -- 数据体：16 行 × 每行 4 个 16 bit 字
signal valid_bits  : std_logic_vector(0 to NUM_LINES - 1);  -- 每行 1 bit
signal tag_bits    : array (...) of std_logic_vector(9 downto 0);  -- 每行 10 bit
```

逻辑上一条 cache line 记录可画成：

```text
Cache 第 index 行
┌─────────────────────────────────────┐
│ valid_bits[index]     1 bit         │  ← 元数据（在 64 bit 之外）
│ tag_bits[index]       10 bit        │  ← 元数据（在 64 bit 之外）
│ cache_lines[index][0] 16 bit        │  ← 数据
│ cache_lines[index][1] 16 bit        │
│ cache_lines[index][2] 16 bit        │
│ cache_lines[index][3] 16 bit        │
└─────────────────────────────────────┘
  元数据 11 bit + 数据 64 bit ≈ 75 bit / 行（概念上）
```

| 字段 | 位数 | 作用 |
|------|------|------|
| `valid_bits[index]` | 1 | 该行是否已被 refill 填过；复位后全 0，refill 完成置 1 |
| `tag_bits[index]` | 10 | 该行对应主存哪一段；与 `addr(15:6)` 比较 |
| `cache_lines[index][0..3]` | 4×16 | 从主存搬来的 4 个**连续**字 |

命中先用**元数据**判断，再从**数据体**取字：

```vhdl
hit  <= valid_bits(index) and (tag_bits(index) = req_tag);
data <= cache_lines(index)(offset);   -- 命中后才读 4 个字之一
```

主存里没有 valid/tag 字段；它们是 Cache 自己维护的，用来回答“这一行能不能用、是不是我要的那一行”。

### 3.1.3 举例：地址 5（`0x0005`）

```text
addr = 5 = 0000_0000_0000_0101

offset = 01  →  行内第 1 个字（4 个字里的第 2 个，从 0 数）
index  = 0001 →  Cache 第 1 行
tag    = 全 0
```

该行对应主存**连续 4 个字**（行首地址 = `{tag, index, "00"}` = 4）：

| offset | 主存地址 | 存在 Cache 里 |
|--------|----------|---------------|
| `00` | 4 | `cache_lines[1][0]` |
| `01` | **5** | `cache_lines[1][1]` ← 本次请求 |
| `10` | 6 | `cache_lines[1][2]` |
| `11` | 7 | `cache_lines[1][3]` |

miss 时从主存依次读 4、5、6、7，**整行**填入 `cache_lines[1][0..3]`，不是只搬地址 5 一个字。

```text
16 位地址
    │
    ├─ index(5:2) ──► 选 cache 第几行
    ├─ tag(15:6)  ──► 与 tag_bits[index] 比较（命中条件）
    └─ offset(1:0) ──► 在该行 4 个字中选一个 → cache_lines[index][offset]
```

**一句话**：一行 = 1 bit valid + 10 bit tag + 4 个 16 bit 数据字；64 bit 是数据，valid/tag 在数据之外。

### 3.2 类型定义与三路存储

```vhdl
-- cpu_pipe/rtl/i_cache.vhd

constant INDEX_BITS  : integer := 4;   -- 16 行
constant OFFSET_BITS : integer := 2;   -- 每行 4 word
constant TAG_BITS    : integer := 10;  -- 16-4-2

type line_t is array (0 to LINE_WORDS - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
type cache_t is array (0 to NUM_LINES - 1) of line_t;

signal cache_lines : cache_t;                          -- 数据体
signal valid_bits  : std_logic_vector(0 to NUM_LINES - 1);  -- 有效位
signal tag_bits    : array (0 to NUM_LINES - 1) of std_logic_vector(TAG_BITS - 1 downto 0);
```

### 3.3 地址拆分与命中判定

```vhdl
-- cpu_pipe/rtl/i_cache.vhd

-- 16 位地址拆分
req_index  <= unsigned(addr(5 downto 2));   -- 选哪一行
req_offset <= unsigned(addr(1 downto 0));   -- 行内哪个字
req_tag    <= addr(15 downto 6);          -- 行标签

-- 命中 = valid=1 且 tag 匹配
hit <= valid_bits(to_integer(req_index)) and
       (tag_bits(to_integer(req_index)) = req_tag);
```

对比 main_memory：`addr` 不直接当数组下标，而是先拆成 tag/index/offset，用 index 选行、offset 选字。

### 3.4 命中输出与 miss 信号

```vhdl
-- cpu_pipe/rtl/i_cache.vhd

-- 命中：组合读 cache 行内一个字
data <= cache_lines(to_integer(req_index))(to_integer(req_offset))
        when state = S_IDLE and hit = '1' else
        (others => '0');

-- 未命中或正在 refill 时拉高
i_miss <= '1' when state = S_REFILL or (state = S_IDLE and hit = '0') else '0';
```

### 3.5 状态机与 refill

```text
        ┌──────────────────────────────────────┐
        │              S_IDLE                   │
        │  hit=1 → 输出 data，保持空闲          │
        │  hit=0 → 锁存 tag/index，进入 REFILL  │
        └───────────────┬──────────────────────┘
                        │ miss
                        ▼
        ┌──────────────────────────────────────┐
        │             S_REFILL                  │
        │  从 main_memory 读一行（最多 4 word）：  │
        │  mem_addr = line_base + 0,1,2,3       │
        │  仅 mem_grant=1 时采样 mem_rdata 写入   │
        │  完成后：valid=1, 更新 tag, 回 IDLE   │
        └──────────────────────────────────────┘
```

**访问主存（refill 时）：**

```vhdl
-- cpu_pipe/rtl/i_cache.vhd

-- 行首地址 = {tag, index, "00"}
refill_base <= refill_tag &
               std_logic_vector(refill_line) &
               (OFFSET_BITS - 1 downto 0 => '0');

mem_req     <= '1' when state = S_REFILL else '0';
mem_read_en <= '1' when state = S_REFILL and mem_grant = '1' else '0';
mem_addr    <= std_logic_vector(unsigned(refill_base) + resize(refill_cnt, ADDR_WIDTH))
               when state = S_REFILL else (others => '0');
```

**状态机主体：**

```vhdl
-- cpu_pipe/rtl/i_cache.vhd

case state is
  when S_IDLE =>
    if hit = '0' then
      refill_line  <= req_index;  -- 锁存，refill 期间 addr 不变（stall 冻结 PC）
      refill_tag   <= req_tag;
      refill_index <= req_index;
      refill_cnt   <= (others => '0'); -- 行内字计数器归零：从第 0 个字开始填
      state        <= S_REFILL;
    end if;

  when S_REFILL =>
    if mem_grant = '1' then
      cache_lines(idx)(to_integer(refill_cnt)) <= mem_rdata;  -- 仅授权拍采样
      if refill_cnt = LINE_WORDS - 1 then
        valid_bits(idx) <= '1';
        tag_bits(idx)   <= refill_tag;
        state           <= S_IDLE;
      else
        refill_cnt <= refill_cnt + 1;
      end if;
    end if;
    -- mem_grant=0：本拍不采样、不计数，下一拍重试
end case;
```

### 3.6 与 CPU 的接口

| 信号 | 方向 | 作用 |
|------|------|------|
| `addr` | in | PC（取指地址） |
| `data` | out | 取到的指令字 |
| `i_miss` | out | 未命中或正在 refill |
| `mem_*` | out/in | miss 时访问 `main_memory` |
| `mem_grant` | in | 主存读授权；`0` 时暂停 refill 采样 |

**只读**：I-Cache 无 `mem_write_en`，不向主存写数据。

---

## 4. d_cache 的构成逻辑

### 4.1 内部存储结构

与 `i_cache` **对称**：同样是 16 行 × 4 word 直接映射，地址划分相同，也有 `valid_bits`、`tag_bits`、`cache_lines`。

差异在于：D-Cache 还要处理 **Load/Store 的写操作**，并多出 `cpu_ready` 握手。

### 4.2 读路径代码

```vhdl
-- cpu_pipe/rtl/d_cache.vhd

read_hit <= hit when read_en = '1' else '0';

rdata <= cache_lines(to_integer(req_index))(to_integer(req_offset))
         when read_hit = '1' else
         (others => '0');

d_miss    <= '1' when state = S_REFILL
                  or (read_en = '1' and state = S_IDLE and hit = '0') else '0';
cpu_ready <= '0' when state = S_REFILL
                  or (read_en = '1' and state = S_IDLE and hit = '0') else '1';
```

| 条件 | 行为 |
|------|------|
| `read_en=1` 且 hit | 组合读 cache，`cpu_ready='1'` |
| `read_en=1` 且 miss | 进入 `S_REFILL`，`d_miss='1'`，`cpu_ready='0'` |
| 无读请求 | `cpu_ready='1'`（不阻塞流水线） |

### 4.3 写路径（写直达 Write-Through）

| 场景 | Cache 行为 | 主存行为 |
|------|-----------|----------|
| 写命中 | 更新 `cache_lines(index)(offset)` | 同步写 `main_memory[addr]` |
| 写缺失 | **不分配行**（no-write-allocate） | 只写主存，Cache 不变 |

```vhdl
-- cpu_pipe/rtl/d_cache.vhd

-- 写命中：时钟沿更新 cache 行
if state = S_IDLE and write_en = '1' and hit = '1' then
  cache_lines(idx)(to_integer(req_offset)) <= wdata;
end if;

-- 写直达主存（命中/缺失都写）
mem_req      <= '1' when state = S_REFILL or write_en = '1' else '0';
mem_write_en <= write_en when state = S_IDLE else '0';
mem_addr     <= addr when state = S_IDLE else refill_base + refill_cnt;
mem_wdata    <= wdata;
```

写操作不进入 `S_REFILL`，`cpu_ready` 保持 `'1'`。

### 4.4 读 miss 状态机

与 I-Cache 相同的两状态机，但**仅 `read_en=1` 且 miss 时**才 refill：

```vhdl
-- cpu_pipe/rtl/d_cache.vhd

when S_IDLE =>
  if read_en = '1' and hit = '0' then
    refill_line  <= req_index;
    refill_tag   <= req_tag;
    state        <= S_REFILL;
  end if;

when S_REFILL =>
  if mem_grant = '1' then
    cache_lines(idx)(to_integer(refill_cnt)) <= mem_rdata;
    -- 填完 4 word → valid=1, tag 更新, 回 IDLE
  end if;
```

读 miss refill 与 I-Cache 对称，同样受 `mem_grant` 门控；写直达路径不受 `mem_grant` 影响。

### 4.5 与 CPU 的接口

| 信号 | 方向 | 作用 |
|------|------|------|
| `addr` | in | ALU 算出的有效地址 |
| `wdata` / `write_en` / `read_en` | in | Store / Load 控制 |
| `rdata` | out | Load 读出的数据 |
| `d_miss` | out | 读 miss 或正在 refill |
| `cpu_ready` | out | `'0'` 表示 MEM 级需等待 |
| `mem_*` | out/in | refill 或写直达时访问主存 |
| `mem_grant` | in | 主存读授权；`0` 时暂停 refill 采样 |

---

## 5. 三者逻辑对比总表

| 对比项 | main_memory | i_cache | d_cache |
|--------|-------------|---------|---------|
| **层次** | 最底层物理 RAM | IF 与主存之间的缓冲 | MEM 与主存之间的缓冲 |
| **存储内容** | 指令 + 数据（全集） | 指令副本（热点子集） | 数据副本（热点子集） |
| **容量** | 2^16 word（64 KW） | 16 行 × 4 word = 64 word | 16 行 × 4 word = 64 word |
| **地址解析** | 直接 `addr → memory[addr]` | tag + index + offset 查表 | 同左 |
| **读延迟** | 组合读（0 拍，需 `read_en`） | 命中：组合读；miss：4+ 拍 refill | 命中：组合读；miss：4+ 拍 refill |
| **写操作** | 同步写 | 无（只读） | 写直达主存；命中时同时更新 Cache |
| **miss 信号** | 无 | `i_miss` | `d_miss` |
| **握手机制** | 无 | 无（靠 `i_miss` + stall） | `cpu_ready` |
| **背后是否还有存储** | 无（就是最终存储） | 有，连 `main_memory` | 有，连 `main_memory` |

### 5.1 核心读逻辑并排对比

```vhdl
-- main_memory：addr 直接索引，无命中判断
rdata <= memory(addr_i) when read_en = '1' else (others => '0');

-- i_cache：先判 hit，命中读 cache，miss 走 refill
hit  <= valid_bits(index) and (tag_bits(index) = tag);
data <= cache_lines(index)(offset) when state = S_IDLE and hit = '1' else (others => '0');

-- d_cache：仅 read_en=1 时判 hit
read_hit <= hit when read_en = '1' else '0';
rdata    <= cache_lines(index)(offset) when read_hit = '1' else (others => '0');
```

---

## 6. 与旧版 memory 的演进对比

### 6.1 早期：instr_memory + data_memory（两块独立 RAM）

```text
cpu_top
  IF  ──► instr_memory（内嵌指令数组，组合读）
  MEM ──► data_memory（内嵌数据数组，同步读写）
```

**instr_memory — 永远命中，无 Cache 结构：**

```vhdl
-- cpu_pipe/rtl/instr_memory.vhd

entity instr_memory is
  port (
    addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

addr_i <= to_integer(unsigned(addr));
data   <= memory(addr_i);   -- 组合读，每拍直接出指令
```

**data_memory — 同步读写，无 miss：**

```vhdl
-- cpu_pipe/rtl/data_memory.vhd

mem_proc : process (clk)
begin
  if rising_edge(clk) then
    if write_en = '1' then
      memory(addr_i) <= wdata;
    end if;
    if read_en = '1' then
      rdata <= memory(addr_i);
    end if;
  end if;
end process;
```

两块 RAM **物理分离、内容分离**，指令和数据各一份 `memory[]`。

### 6.2 中期占位：i_cache / d_cache 内嵌 RAM

每个 Cache 自己带一份 `memory[]`，`i_miss`/`d_miss` 恒为 0，行为等同直连存储器，只是换了名字。

### 6.3 当前：i_cache + d_cache + 共享 main_memory

```text
cpu_top
  IF  ──► i_cache ──miss──┐
  MEM ──► d_cache ──miss──┼──► main_memory（唯一 RAM）
```

| 变化 | 说明 |
|------|------|
| 存储合并 | 指令和数据在同一块 `main_memory`，靠地址区分 |
| 前端仍分离 | `i_cache` 只服务取指，`d_cache` 只服务访存 |
| 增加 Cache 行 | valid / tag / data 三级结构，支持 hit/miss |
| 增加 stall | `cache_control` 在 miss 时冻结流水线 |
| 写策略 | 仅 D-Cache 有写；写直达主存，保证一致性 |

---

## 7. 一次取指 vs 一次访存的时序对比

### 7.1 取指（经 i_cache）

```text
拍 1  PC=0, index=0, valid=0  →  miss, stall=1, 进入 REFILL
拍 2  mem_read addr=0, rdata→cache_line[0][0]
拍 3  mem_read addr=1, rdata→cache_line[0][1]
拍 4  mem_read addr=2, rdata→cache_line[0][2]
拍 5  mem_read addr=3, rdata→cache_line[0][3], valid=1
拍 6  PC=0, hit=1, data=cache_line[0][0], stall=0  →  指令进入 IF/ID
拍 7  PC=1, 同行 hit, 1 拍取指
...
```

同一行内 PC=1,2,3 均命中，不再访问主存。

对应代码路径：

```vhdl
-- 拍 1：hit='0' → i_miss='1' → cache_stall='1'
-- 拍 2~5：state=S_REFILL，mem_addr=0,1,2,3，填入 cache_lines(0)
-- 拍 6：hit='1' → data <= cache_lines(0)(0) = memory[0] 的副本
```

### 7.2 访存（经 d_cache，以 ST 为例）

```text
ST x3, 0(x4)   →  write_en=1
  写命中：cache 行更新 + main_memory 同步写，cpu_ready=1，1 拍完成
  写缺失：只写 main_memory，不分配 Cache 行
```

对应代码：

```vhdl
-- 写命中
if write_en = '1' and hit = '1' then
  cache_lines(idx)(offset) <= wdata;   -- 更新 cache
end if;
mem_write_en <= write_en;              -- 同时写 main_memory
mem_addr     <= addr;
```

### 7.3 若直连 main_memory（无 Cache）

```vhdl
-- 取指每拍都碰主存
rdata <= memory(pc);

-- 访存每拍都碰主存
rdata <= memory(alu_addr) when read_en else ...;
```

0 miss、0 stall，但没有局部性加速。

---

## 8. soc_top 中的仲裁与 stall

### 8.1 总线授权（mem_grant）

I-Cache 与 D-Cache 的 refill 都只在获得读授权时才采样 `mem_rdata`、推进 `refill_cnt`：

```vhdl
-- cpu_pipe/rtl/soc_top.vhd

i_mem_grant <= '0' when d_mem_read_en = '1' else '1';
d_mem_grant <= '0' when i_mem_read_en = '1' else '1';
```

| 信号 | 含义 |
|------|------|
| `i_mem_grant` | 接到 `i_cache.mem_grant` |
| `d_mem_grant` | 接到 `d_cache.mem_grant` |

**注意：** 授权只看对方是否在**读**主存（`mem_read_en`），**写**（ST 写直达）不拉低 `i_mem_grant`。否则 stall 冻住 ST 时会与 I-Cache refill 形成死锁（见修复文档问题二）。

### 8.2 主存端口仲裁

```vhdl
-- cpu_pipe/rtl/soc_top.vhd

-- I-Cache 读优先；D-Cache 写仅在 I-Cache 不读时进行
mm_addr     <= i_mem_addr     when i_mem_read_en = '1' else d_mem_addr;
mm_wdata    <= d_mem_wdata;
mm_read_en  <= i_mem_read_en  when i_mem_read_en = '1' else d_mem_read_en;
mm_write_en <= d_mem_write_en when d_mem_write_en = '1' and i_mem_read_en = '0' else '0';
```

| 场景 | 主存行为 |
|------|----------|
| 仅 I-Cache refill | 读指令行 |
| 仅 D-Cache 写（ST） | 写数据 |
| 仅 D-Cache 读 miss refill | 读数据行 |
| I-Cache 读 ∩ D-Cache 写 | **先读**（I 优先），写延后一拍 |
| I-Cache 读 ∩ D-Cache 读 | I 优先（`d_mem_grant=0`，D refill 暂停） |

仿真争用案例与修复过程见 [`Cache主存争用与mem_grant修复.md`](./Cache主存争用与mem_grant修复.md)。

### 8.3 cache_control

```vhdl
-- cpu_pipe/rtl/cache_control.vhd

stall <= i_miss or (not cpu_ready);
```

| 条件 | 效果 |
|------|------|
| `i_miss='1'` | 取指未就绪，冻结 PC、IF/ID、ID/EX、EX/MEM、MEM/WB |
| `cpu_ready='0'` | Load 读 miss 或正在 refill，同上 |
| 两者都为 0 | 流水线正常运行 |

### 8.4 cpu_top 中的 stall 响应

```vhdl
-- cpu_pipe/rtl/cpu_top.vhd

-- 冻结 PC
pc_en <= '0' when cache_stall = '1' else hz_pc_en;

-- 冻结 IF/ID
if hz_ifid_en = '1' and cache_stall = '0' then
  if_id_pc    <= if_pc;
  if_id_instr <= if_id_instr_in;
end if;

-- 冻结 ID/EX、EX/MEM、MEM/WB（hold，不插入 bubble）
if cache_stall = '0' then
  -- 正常推进或 BNE bubble
end if;
```

Cache stall 是 **hold**（保持），与 BNE 的 **bubble**（插 NOP）不同。

---

## 9. Cache 可扩展方向

> 当前 RTL 基线：**直接映射**、**16 行 × 4 word**、**写直达**、**写不分配**、miss 时 **全局 stall**、**单端口 main_memory** + **mem_grant 授权** + **I-Cache 读优先仲裁**。以下按课设计划与常见体系结构实践列出可扩展项。

### 9.1 映射与替换策略

| 方向 | 当前 | 可扩展为 | 改动要点 |
|------|------|----------|----------|
| 相联度 | 直接映射（1 路） | **2 路组相联** / 全相联 | `cache_lines` 改为 `[ways][lines][words]`；命中需比较多路 tag |
| 替换算法 | 无（miss 即覆盖） | **LRU** / FIFO / 随机 | 每 set 增加 `use_bit` 或 `lru_counter`；miss 时选牺牲行 |
| 行大小 | 4 word/行 | 8 / 16 word | 调整 `OFFSET_BITS`、`LINE_WORDS`；refill 状态机计数加长 |

直接映射扩到组相联时，地址划分通常变为：

```text
tag | index | offset        （直接映射，当前）
tag | index | way（可选）| offset   （组相联）
```

冲突 miss 减少，但 hit 判断与替换逻辑更复杂。

### 9.2 写策略

| 方向 | 当前 | 可扩展为 | 改动要点 |
|------|------|----------|----------|
| 写分配 | 写缺失 **不分配**（no-write-allocate） | **写分配**（write-allocate） | 写 miss 也触发 refill，再写入 cache 行 |
| 写策略 | **写直达**（write-through） | **写回**（write-back） | 行增加 `dirty_bit`；写命中只改 cache；替换/evict 时若 dirty 再写主存 |
| 一致性 | 单核、无多主 | 总线嗅探 / 软件维护 | 课设一般不做，可写报告分析 |

写回示例（行结构扩展）：

```vhdl
signal dirty_bits : std_logic_vector(0 to NUM_LINES - 1);  -- 新增
-- evict/refill 前：if dirty_bits(idx)='1' then 写回 main_memory
```

### 9.3 性能统计与验证

当前未实现计数器，可在 `i_cache` / `d_cache` 内增加：

```vhdl
signal hit_count  : unsigned(31 downto 0);
signal miss_count : unsigned(31 downto 0);
-- 每次访问：hit_count++ 或 miss_count++
-- hit_rate = hit_count / (hit_count + miss_count)
```

| 统计项 | 用途 |
|--------|------|
| `hit_count` / `miss_count` | 命中率、miss penalty |
| `refill_cycles` | 平均 refill 拍数 |
| 对比无 Cache CPI | 斐波那契 / 顺序访问 / 冲突访问三组程序 |

课设报告可给出：**有 Cache vs 无 Cache** 的总周期数、CPI、加速比。

### 9.4 与流水线 / 控制集成

| 方向 | 当前 | 可扩展为 |
|------|------|----------|
| stall 范围 | `cache_stall` 冻结全部流水线寄存器 | 仅冻 IF/ID/EX，MEM 保持请求（精细 stall） |
| 与 hazard 优先级 | `cache_stall` 与 BNE bubble 分开处理 | 统一优先级表：CALL > cache stall > load-use > BNE |
| I-Cache | 已实现基本 refill | 预取下一行、与分支目标协同 |
| 握手 | `cpu_ready` 仅 D-Cache | I-Cache 也可输出 `cpu_ready`，统一接口 |

`cache_control` 可扩展为：

```vhdl
stall <= i_miss or (mem_access and not cpu_ready);
-- 仅在 MEM 级真有访存时才等 d_cache，减少无效 stall
```

### 9.5 SoC 与主存接口

| 方向 | 当前 | 可扩展为 | 说明 |
|------|------|----------|------|
| 主存端口 | 单端口 RAM，组合读 | 同步读 / 双端口 | 更接近真实 SRAM 时序 |
| 仲裁 | I-Cache 读优先 + mem_grant | 轮询 / 固定优先级表 / 独立 I、D 主存端口 | 哈佛物理主存可消除仲裁与 grant 等待 |
| MMIO 旁路 | 未实现 | 地址 `0xFFxx` 绕过 D-Cache | `d_cache` 内判断：`if addr(15:8)=x"FF" then 直访外设` |
| 外设 | 仅 main_memory | UART / GPIO / Timer | MMIO 区不进入 cache，避免脏数据 |

MMIO 旁路示意：

```text
addr(15:8) = 0xFF  →  不查 tag/valid，直接 MMIO 读写
addr(15:8) ≠ 0xFF  →  正常走 d_cache
```

### 9.6 存储容量与参数化

通过 generic 参数化，便于仿真对比：

```vhdl
generic (
  NUM_LINES  : integer := 16;   -- 可改为 32、64
  LINE_WORDS : integer := 4;    -- 可改为 8
  ADDR_WIDTH : integer := 16
);
```

| 参数增大 | 效果 | 代价 |
|----------|------|------|
| `NUM_LINES` ↑ | index 位数增加，冲突减少 | 更多 valid/tag 存储 |
| `LINE_WORDS` ↑ | 空间局部性更好，顺序取指/访存 hit 更高 | refill 更长、stall 更多 |

### 9.7 建议实施优先级（课设）

```text
P0（已完成）  直接映射 I/D Cache + main_memory + cache_control stall
P1（建议）    命中率计数器 + 斐波那契性能对比表
P2（建议）    MMIO 旁路（0xFFxx）+ 与 soc_top 地址译码
P3（可选）    写分配 / 写回 + dirty 位
P4（可选）    2 路组相联 + LRU
P5（报告）    向量/阵列访问模式分析（可只写不写 RTL）
```

扩展时建议**每次只改一层**：先加统计，再加 MMIO 旁路，最后才改相联度或写回，避免同时动映射、写策略和 stall 逻辑导致难以调试。

---

## 10. 一句话总结

| 模块 | 本质 |
|------|------|
| **main_memory** | 存放完整程序与数据的"仓库"，`addr` 直接读写 `memory[]` |
| **i_cache** | 指令的"快取窗口"：valid/tag/行数组判 hit，miss 时 refill 4 word |
| **d_cache** | 数据的"快取窗口"：读同 i_cache；写直达主存，命中时同步更新行 |

三者关系：**Cache 是主存前面的缓冲层；主存是最终真相来源（source of truth），Cache 只是热点副本。**

---

## 附 A：文件索引

| 文件 | 路径 |
|------|------|
| 统一主存 | `cpu_pipe/rtl/main_memory.vhd` |
| 指令 Cache | `cpu_pipe/rtl/i_cache.vhd` |
| 数据 Cache | `cpu_pipe/rtl/d_cache.vhd` |
| stall 控制 | `cpu_pipe/rtl/cache_control.vhd` |
| 顶层互联 | `cpu_pipe/rtl/soc_top.vhd` |
| 旧版指令 RAM | `cpu_pipe/rtl/instr_memory.vhd` |
| 旧版数据 RAM | `cpu_pipe/rtl/data_memory.vhd` |
