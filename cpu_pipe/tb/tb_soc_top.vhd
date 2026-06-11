-- tb_soc_top.vhd
-- 斐波那契 + Timer 中断功能仿真
library ieee;
use ieee.std_logic_1164.all;

entity tb_soc_top is
end entity tb_soc_top;

architecture sim of tb_soc_top is
  constant CLK_PERIOD : time := 10 ns;

  signal clk               : std_logic := '0';
  signal rst               : std_logic := '0';
  signal debug_pc          : std_logic_vector(15 downto 0);
  signal debug_instr       : std_logic_vector(15 downto 0);
  signal debug_epc         : std_logic_vector(15 downto 0);
  signal debug_irq_pending : std_logic;
  signal debug_status_ie   : std_logic;

  component soc_top is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk               : in  std_logic;
      rst               : in  std_logic;
      debug_pc          : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      debug_instr       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      debug_epc         : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      debug_irq_pending : out std_logic;
      debug_status_ie   : out std_logic;
      debug_uart_data   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      debug_led         : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

begin
  u_dut : soc_top
    port map (
      clk               => clk,
      rst               => rst,
      debug_pc          => debug_pc,
      debug_instr       => debug_instr,
      debug_epc         => debug_epc,
      debug_irq_pending => debug_irq_pending,
      debug_status_ie   => debug_status_ie,
      debug_uart_data   => open,
      debug_led         => open
    );

  clk <= not clk after CLK_PERIOD / 2;

  stim : process
  begin
    rst <= '0';
    wait for CLK_PERIOD * 2;
    rst <= '1';
    wait for CLK_PERIOD * 800;
    report "Simulation finished";
    wait;
  end process stim;

end architecture sim;
