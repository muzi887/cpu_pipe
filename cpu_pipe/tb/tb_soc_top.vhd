-- tb_soc_top.vhd
-- 斐波那契程序功能仿真
library ieee;
use ieee.std_logic_1164.all;

entity tb_soc_top is
end entity tb_soc_top;

architecture sim of tb_soc_top is
  constant CLK_PERIOD : time := 10 ns;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '0';
  signal debug_pc    : std_logic_vector(15 downto 0);
  signal debug_instr : std_logic_vector(15 downto 0);

  component soc_top is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      debug_pc    : out std_logic_vector(15 downto 0);
      debug_instr : out std_logic_vector(15 downto 0)
    );
  end component;

begin
  u_dut : soc_top
    port map (
      clk         => clk,
      rst         => rst,
      debug_pc    => debug_pc,
      debug_instr => debug_instr
    );

  clk <= not clk after CLK_PERIOD / 2;

  stim : process
  begin
    rst <= '0';
    wait for CLK_PERIOD * 2;
    rst <= '1';
    wait for CLK_PERIOD * 400;
    report "Simulation finished";
    wait;
  end process stim;

end architecture sim;
