--- if_stage.vhd: IF 阶段，负责 PC 更新和指令获取
library ieee;
use ieee.std_logic_1164.all; -- 标准逻辑库
use ieee.numeric_std.all;    -- 数字类型库

entity if_stage is
  generic(
    ADDR_WIDTH : integer := 16; -- 地址宽度
    DATA_WIDTH : integer := 16  -- 数据宽度（指令宽度）
  );
  port(
    clk            : in  std_logic; -- 时钟信号
    rst            : in  std_logic; -- 复位信号

    -- hazard / control signals
    pc_en          : in  std_logic;                    -- 1: 允许更新 PC
    pc_src         : in  std_logic_vector(1 downto 0); -- PC 来源选择：00 = PC+1, 01 = jump with condition target, 10 = jump without condition target, 11 = addr in stack
    branch_target  : in  std_logic_vector(ADDR_WIDTH - 1 downto 0); -- 分支目标地址
    jump_target    : in  std_logic_vector(ADDR_WIDTH - 1 downto 0); -- 跳转目标地址
    halt           : in  std_logic;                    -- 1: PC 保持不变

    -- instruction memory interface (代替 i_cache)
    instr_data     : in  std_logic_vector(DATA_WIDTH - 1 downto 0); -- 从指令内存读取的指令数据

    -- to IF/ID pipeline register
    pc_out         : out std_logic_vector(ADDR_WIDTH - 1 downto 0); -- 当前 PC 输出到 IF/ID 寄存器
    npc_out        : out std_logic_vector(ADDR_WIDTH - 1 downto 0); -- PC + 1 输出到 IF/ID 寄存器
    instruction    : out std_logic_vector(DATA_WIDTH - 1 downto 0); -- 当前指令输出到 IF/ID 寄存器

    -- to instruction memory
    instr_addr     : out std_logic_vector(ADDR_WIDTH - 1 downto 0) -- 输出当前 PC 到指令内存地址线
  );
end entity if_stage;

architecture rtl of if_stage is
  signal pc_reg     : unsigned(ADDR_WIDTH - 1 downto 0); -- PC 寄存器
  signal npc        : unsigned(ADDR_WIDTH - 1 downto 0); -- PC + 1 的值
  signal pc_next    : unsigned(ADDR_WIDTH - 1 downto 0); -- 下一周期的 PC 值

begin
  npc <= pc_reg + 1; -- 计算 PC + 1

  with pc_src select
    pc_next <= unsigned(branch_target) when "01", -- 分支目标地址
               unsigned(jump_target)   when "10", -- 跳转目标地址
               npc                    when others; -- 默认 PC + 1
    
    pc_reg_proc: process(clk, rst)
    begin
      if rst = '0' then 
        pc_reg <= (others => '0');
      elsif rising_edge(clk) then
        if halt = '0' and pc_en = '1' then
          pc_reg <= pc_next; -- 更新 PC 寄存器
        end if;
      end if;
    end process pc_reg_proc;

    instr_addr <= std_logic_vector(pc_reg); -- 输出当前 PC 到指令内存地址线
    pc_out     <= std_logic_vector(pc_reg); -- 输出当前 PC 到 IF/ID 寄存器
    npc_out    <= std_logic_vector(npc);    -- 输出 PC + 1 到 IF/ID 寄存器
    instruction <= instr_data;              -- 输出当前指令到 IF/ID 寄存器

end architecture rtl;
