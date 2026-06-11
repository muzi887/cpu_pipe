-- gpio_mmio.vhd
-- MMIO GPIO LED：0xFF10 写 LED 寄存器
library ieee;
use ieee.std_logic_1164.all;

entity gpio_mmio is
  generic (
    DATA_WIDTH : integer := 16
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    addr     : in  std_logic_vector(15 downto 0);
    wdata    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    write_en : in  std_logic;
    read_en  : in  std_logic;
    rdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    sel      : in  std_logic;

    led_out : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity gpio_mmio;

architecture rtl of gpio_mmio is
  constant ADDR_LED : std_logic_vector(15 downto 0) := x"FF10";

  signal led_reg : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  led_out <= led_reg;

  reg_proc : process (clk, rst)
  begin
    if rst = '0' then
      led_reg <= (others => '0');
    elsif rising_edge(clk) then
      if sel = '1' and write_en = '1' and addr = ADDR_LED then
        led_reg <= wdata;
      end if;
    end if;
  end process reg_proc;

  rdata <= led_reg
           when sel = '1' and read_en = '1' and addr = ADDR_LED else
           (others => '0');
end architecture rtl;
