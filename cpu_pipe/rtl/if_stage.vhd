-- if_stage.vhd
-- IF 取指阶段：PC、Next-PC MUX、指令存储器接口
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity if_stage is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;

    -- hazard / control
    pc_en          : in  std_logic;                    -- 1: 允许更新 PC
    pc_src         : in  std_logic_vector(1 downto 0); -- 00: PC+1, 01: branch, 10: jump
    branch_target  : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    jump_target    : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    halt           : in  std_logic;                    -- 1: PC 保持

    -- instruction memory interface (代替 i_cache)
    instr_data     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- to IF/ID pipeline register
    pc_out         : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    pc_plus1_out   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    instruction    : out std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- to instruction memory
    instr_addr     : out std_logic_vector(ADDR_WIDTH - 1 downto 0)
  );
end entity if_stage;

architecture rtl of if_stage is
  signal pc_reg     : unsigned(ADDR_WIDTH - 1 downto 0);
  signal pc_plus1   : unsigned(ADDR_WIDTH - 1 downto 0);
  signal pc_next    : unsigned(ADDR_WIDTH - 1 downto 0);
begin
  pc_plus1 <= pc_reg + 1;

  with pc_src select
    pc_next <= unsigned(branch_target) when "01",
               unsigned(jump_target)   when "10",
               pc_plus1                when others;

  pc_reg_proc : process (clk, rst)
  begin
    if rst = '0' then
      pc_reg <= (others => '0');
    elsif rising_edge(clk) then
      if halt = '0' and pc_en = '1' then
        pc_reg <= pc_next;
      end if;
    end if;
  end process pc_reg_proc;

  instr_addr   <= std_logic_vector(pc_reg);
  pc_out       <= std_logic_vector(pc_reg);
  pc_plus1_out <= std_logic_vector(pc_plus1);
  instruction  <= instr_data;
end architecture rtl;
