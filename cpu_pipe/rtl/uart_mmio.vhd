-- uart_mmio.vhd
-- MMIO UART：0xFF00 DATA，0xFF04 STATUS（bit0=TX ready，恒 1）
library ieee;
use ieee.std_logic_1164.all;

entity uart_mmio is
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

    uart_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity uart_mmio;

architecture rtl of uart_mmio is
  constant ADDR_DATA   : std_logic_vector(15 downto 0) := x"FF00";
  constant ADDR_STATUS : std_logic_vector(15 downto 0) := x"FF04";

  signal data_reg : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  uart_data <= data_reg;

  reg_proc : process (clk, rst)
  begin
    if rst = '0' then
      data_reg <= (others => '0');
    elsif rising_edge(clk) then
      if sel = '1' and write_en = '1' and addr = ADDR_DATA then
        data_reg <= wdata;
      end if;
    end if;
  end process reg_proc;

  rdata <= data_reg
           when sel = '1' and read_en = '1' and addr = ADDR_DATA else
           x"0001"
           when sel = '1' and read_en = '1' and addr = ADDR_STATUS else
           (others => '0');
end architecture rtl;
