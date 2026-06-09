# 五级流水 CPU 寄存器堆

> RTL：`cpu_pipe/rtl/id_stage.vhd`（寄存器堆嵌在 ID 阶段，未单独拆模块）  
> 写回：`wb_stage.vhd` 产生 `wb_en / wb_addr / wb_data`，经 `cpu_top.vhd` 接入 ID

---

## 1. 总体结构

五级流水 CPU 的寄存器堆由 **一块存储阵列** + **一个写端口** + **三个读端口** + **读地址译码** 组成。

```text
                    ┌──────────────────────────────────────────┐
  WB ──wr_en/addr/data──►│  reg_file_write (同步写 regs)        │
                         │                                        │
  instruction ──────────►│  地址译码 → rs_field / rs2 / rd_field  │
                         │       │         │            │         │
                         │       ▼         ▼            ▼         │
                         │   读口 RS    读口 RS2     读口 RD      │
                         │       │         │            │         │
                         │       └──── op2_data MUX ─────┘         │
                         │                 │                        │
                         │            rs_val / rd_val ──► ID/EX     │
                         └──────────────────────────────────────────┘
```

| 参数 | 规格 |
|------|------|
| 寄存器数量 | 16（x0～x15） |
| 数据位宽 | 16 bit |
| 地址位宽 | 4 bit |
| 写端口 | 1（WB 写回） |
| 读端口 | 3（rs1、rs2、rd/第二源，组合读） |
| x0 | 恒为 0，禁止写入 |

---

## 2. 存储阵列

类型定义与内部信号：

```vhdl
type reg_array_t is array (0 to 15) of std_logic_vector(DATA_WIDTH - 1 downto 0);
signal regs : reg_array_t;
```

`regs` 是寄存器堆的本体，16 个 16 位寄存器。对外不直接暴露，只通过读写端口访问。

---

## 3. 写端口实现

### 3.1 写回控制信号来源

WB 阶段根据 `MemToReg` 选择写回数据，并输出写控制：

```vhdl
-- wb_stage.vhd
wb_data <= mem_data_in when mem_to_reg_in = '1' else alu_result_in;
wb_addr <= rd_in;
wb_en   <= reg_write_in;
```

| 信号 | 含义 |
|------|------|
| `wb_en` | 本拍是否写寄存器（= 该指令 `RegWrite`） |
| `wb_addr` | 目的寄存器编号（4 bit） |
| `wb_data` | 写回数据（ALU 结果或 Load 数据） |

### 3.2 同步写入 process

```vhdl
reg_file_write : process (clk, rst)
begin
  if rst = '0' then
    regs <= (others => (others => '0'));
  elsif rising_edge(clk) then
    if wr_en = '1' and wr_addr /= "0000" then
      regs(to_integer(unsigned(wr_addr))) <= wr_data;
    end if;
  end if;
end process reg_file_write;
```

要点：

- **同步写**：仅在时钟上升沿更新 `regs`
- **x0 不可写**：`wr_addr = 0` 时跳过写入
- 复位低有效：`rst = '0'` 时清零全部寄存器

---

## 4. 读地址译码

读地址不由独立端口给出，而是由 **ID 阶段对 instruction 字段拆分** 得到。指令内寄存器编号为 3 bit，扩展为 4 bit（高位补 0）。

```vhdl
-- rs1：I/R/S/B 型均有
rs_field <= '0' & instruction(11 downto 9)
            when opcode = "0000" or opcode = "0001" or opcode = "0010" or
                 opcode = "0011" or opcode = "0100" or opcode = "1110" else
            (others => '0');

-- rs2：R / S / B 型
rs2_field <= '0' & instruction(8 downto 6)
             when opcode = "0001" or opcode = "0011" or opcode = "0100" else
             (others => '0');

-- rd 字段（写回目的）或 I 型第二读地址
rd_field <= '0' & instruction(8 downto 6)
            when opcode = "0000" or opcode = "0010" else
            '0' & instruction(5 downto 3)
            when opcode = "0001" else
            (others => '0');
```

| 指令格式 | rs_field | rs2_field | rd_field |
|----------|----------|-----------|----------|
| I 型 ADDI/LD | rs1 `[11:9]` | 0 | rd `[8:6]` |
| R 型 ADD | rs1 `[11:9]` | rs2 `[8:6]` | rd `[5:3]` |
| S 型 ST | rs1（基址） | rs2（存数） | 0 |
| B 型 BNE | rs1 | rs2 | 0 |

---

## 5. 读端口实现

### 5.1 三个组合读口

读口是组合逻辑，同拍完成。每个读口通过 `reg_read_write_first` 从 `regs` 取值，并支持写优先（第 9 节说明原因与作用）。

```vhdl
function reg_read_write_first (
  addr      : std_logic_vector(3 downto 0);
  wr_en_i   : std_logic;
  wr_addr_i : std_logic_vector(3 downto 0);
  wr_data_i : std_logic_vector(DATA_WIDTH - 1 downto 0);
  regs_i    : reg_array_t
) return std_logic_vector is
begin
  if addr = "0000" then
    return (others => '0');
  elsif wr_en_i = '1' and wr_addr_i /= "0000" and wr_addr_i = addr then
    return wr_data_i;   -- 写优先：同拍 WB 写、ID 读同一寄存器
  else
    return regs_i(to_integer(unsigned(addr)));
  end if;
end function reg_read_write_first;

rs_data  <= reg_read_write_first(rs_field,  wr_en, wr_addr, wr_data, regs);
rs2_data <= reg_read_write_first(rs2_field, wr_en, wr_addr, wr_data, regs);
rd_data  <= reg_read_write_first(rd_field,  wr_en, wr_addr, wr_data, regs);
```

| 内部信号 | 读地址 | 说明 |
|----------|--------|------|
| `rs_data` | `rs_field` | 第一源寄存器 rs1 的值 |
| `rs2_data` | `rs2_field` | 第二源寄存器 rs2 的值 |
| `rd_data` | `rd_field` | I 型目的寄存器 / R 型 rd 字段对应单元 |

读为 **组合逻辑**，ID 阶段同拍完成，供本拍末锁入 ID/EX。

### 5.2 第二操作数复用（`op2_data`）

R/S/B 型的第二源来自 rs2；I 型来自 rd 字段对应单元：

```vhdl
op2_data <= rs2_data when opcode = "0001" or opcode = "0011" or opcode = "0100" else
            rd_data;
```

### 5.3 输出到流水线

```vhdl
rs_val  <= rs_data;   -- 锁入 ID/EX 后成为 rs_val_in（EX 的 RS 路径）
rd_val  <= op2_data;  -- 锁入 ID/EX 后成为 rd_val_in（EX 的 RD/RS2 路径）

rs_out  <= rs_field;  -- 源寄存器编号，供转发比较
rs2_out <= rs2_field;
rd_out  <= rd_field;  -- 写回目的寄存器编号
```

命名说明：`rd_val` 在 **R 型 ADD** 下实际是 **rs2 的值**。

---

## 6. x0 硬连线

x0 在五级流水 CPU 中恒为 0，读写均有保护：

```vhdl
-- 读：地址为 0 时直接返回 0，不访问 regs
if addr = "0000" then
  return (others => '0');

-- 写：wr_addr = 0 时不写入
if wr_en = '1' and wr_addr /= "0000" then
  ...
```

---

## 7. 端口一览

### 7.1 写端口（来自 WB）

```vhdl
wr_en   : in  std_logic;
wr_addr : in  std_logic_vector(3 downto 0);
wr_data : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
```

### 7.2 读结果（到 ID/EX）

```vhdl
rs_val : out std_logic_vector(DATA_WIDTH - 1 downto 0);  -- rs1 数据
rd_val : out std_logic_vector(DATA_WIDTH - 1 downto 0);  -- rs2 或 I 型 rd 数据
rs_out : out std_logic_vector(3 downto 0);               -- rs1 编号
rs2_out: out std_logic_vector(3 downto 0);               -- rs2 编号
rd_out : out std_logic_vector(3 downto 0);               -- 写回目的编号
```

### 7.3 调试观测

```vhdl
rs_addr, rd_addr : out std_logic_vector(3 downto 0);
rs, rd           : out std_logic_vector(DATA_WIDTH - 1 downto 0);
```

---

## 8. 结构总图

```text
         wb_en ────────┐
         wb_addr ──────┤
         wb_data ──────┤
                       ▼
              ┌─────────────────┐
instruction ─►│ 地址译码         │
              │ rs/rs2/rd_field │
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
    ┌─────────┐  ┌─────────┐  ┌─────────┐
    │ 读口 RS │  │读口 RS2 │  │ 读口 RD │
    └────┬────┘  └────┬────┘  └────┬────┘
         │            │            │
         │     ┌──────┴──────┐     │
         │     ▼             │     │
         │  op2_data MUX    │     │
         │     │             │     │
         ▼     ▼             ▼     │
      rs_val  rd_val ◄─────────────┘
         │       │
         └───┬───┘
             ▼
        ID/EX 流水寄存器
             │
             ▼
    （EX 阶段使用锁存值，不再读 regs）
```

---

## 9. 写优先读的作用

第 3 节是「时钟沿写」，第 5 节是「组合读」。分开看各自正确，同拍叠加会出现冲突。

### 9.1 冲突从哪来

写用 `regs <= wr_data`，读用 `rs2_data <= regs(2)`。同一上升沿：

- 写：`regs(2)` 要到该沿之后才真正更新
- 读：组合逻辑读到的仍是**旧值**

若这一拍 WB 写 x2，ID 同时读 x2 并锁进 ID/EX，就会把旧值锁进去。五级流水 CPU 的 EX 阶段只用 ID/EX 锁存值，不再读寄存器堆——**锁错则 EX 转发无法纠正**。

若只改 `reg_file_write` 的 process，在内部「先写后读」，无法解决：读是并发语句 `<= regs(...)`，不在同一 process 里。写优先必须加在**读口**：同地址冲突时直接返回 `wb_data`。

### 9.2 与 EX 阶段转发的分工

该 CPU 的数据转发 MUX 集中在 EX 阶段（见 `doc/竞争冒险/转发技术/Forward.md`），不在 ID 另设转发通路。二者分工如下：

| 情况 | 处理方式 |
|------|----------|
| 结果还在 EX/MEM | EX 转发 `forward = 01` |
| 结果还在 MEM/WB | EX 转发 `forward = 10` |
| 同拍 WB 写、ID 读同一寄存器 | 寄存器堆写优先读 |
| 结果已稳定写入 regs | 正常读 `regs` |

写优先不是 EX 外的第四路转发，而是寄存器堆读口在冲突时应具备的行为。

### 9.3 波形示例：斐波那契程序

```text
1: ADDI x2, x0, 1
2: ADDI x4, x0, 13
3: ADDI x5, x0, 5
4: ADD  x3, x1, x2
```

`ADD` 进入 EX（约 75–85ns）时，`ADDI x2` 已离开 MEM/WB 流水寄存器，`forward_b` 无法匹配 x2，EX 只能使用 ID/EX 中的 `id_ex_rd_val`。

无写优先：

```text
75ns：WB 写 x2=1，读口仍从 regs 读到 0 → id_ex_rd_val = 0
EX：  1 + 0 = 1  （错误，应为 2）
```

有写优先：

```text
75ns：wr_addr=2，读口返回 wb_data=1 → id_ex_rd_val = 1
EX：  1 + 1 = 2  （正确）
```

若 `ADDI x2` 与 `ADD` 紧邻（中间无其它指令），`ADD` 进 EX 时 `ADDI` 仍在 EX/MEM，由 `forward_b = 01` 解决，不依赖写优先。

### 9.4 归纳

- 写优先 = 读口旁路，复用 `wr_en / wr_addr / wb_data`
- 作用：保证锁入 ID/EX 的操作数正确
- EX 转发覆盖 EX/MEM、MEM/WB 中的生产者；写优先覆盖 WB 与 ID 同拍冲突
- load-use stall 需单独处理，写优先不能替代

---

## 相关代码

| 文件 | 内容 |
|------|------|
| `cpu_pipe/rtl/id_stage.vhd` | 寄存器堆实现 |
| `cpu_pipe/rtl/wb_stage.vhd` | 写回数据与控制 |
| `cpu_pipe/rtl/cpu_top.vhd` | WB ↔ ID 连线 |
