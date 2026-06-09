-- data_memory.vhd
-- 数据存储器（哈佛结构，同步读写）
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_memory is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    clk       : in  std_logic;
    addr      : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    wdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    write_en  : in  std_logic;
    read_en   : in  std_logic;
    rdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity data_memory;

architecture rtl of data_memory is
  constant MEM_DEPTH : integer := 2**ADDR_WIDTH;
  type mem_array_t is array (0 to MEM_DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal memory : mem_array_t := (
    11 => x"0001",
    12 => x"0001",
    others => (others => '0')
  );
  signal addr_i : integer range 0 to MEM_DEPTH - 1;
begin
  addr_i <= to_integer(unsigned(addr));

  mem_proc : process (clk)
  begin
    if rising_edge(clk) then
      if write_en = '1' then
        memory(addr_i) <= wdata;
      end if;

      if read_en = '1' then
        rdata <= memory(addr_i);
      else
        rdata <= (others => '0');
      end if;
    end if;
  end process mem_proc;

end architecture rtl;
