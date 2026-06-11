-- main_memory.vhd
-- 统一主存：指令区 + 数据区，组合读、同步写
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity main_memory is
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
end entity main_memory;

architecture rtl of main_memory is
  constant MEM_DEPTH : integer := 2**ADDR_WIDTH;
  type mem_array_t is array (0 to MEM_DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  constant INIT_MEM : mem_array_t := (
    0  => x"0041", -- ADDI x1, x0, 1
    1  => x"0081", -- ADDI x2, x0, 1
    2  => x"010D", -- ADDI x4, x0, 13
    3  => x"0145", -- ADDI x5, x0, 5
    4  => x"1298", -- ADD  x3, x1, x2
    5  => x"38C0", -- ST   x3, 0(x4)
    6  => x"0440", -- ADDI x1, x2, 0
    7  => x"0680", -- ADDI x2, x3, 0
    8  => x"0901", -- ADDI x4, x4, 1
    9  => x"0B7F", -- ADDI x5, x5, -1
    10 => x"4A3A", -- BNE  x5, x0, LOOP (offset = -6)
    11 => x"E000", -- EI
    12 => x"F000", -- HALT
    31 => x"FF00", -- UART 基址常量（供 LD 预载 x7，可选）
    -- Timer ISR @ 0x0100
    256 => x"0D81", -- ADDI x6, x6, 1
    257 => x"E002", -- IRET
    others => (others => '0')
  );

  signal memory : mem_array_t := INIT_MEM;
  signal addr_i : integer range 0 to MEM_DEPTH - 1;
begin
  addr_i <= to_integer(unsigned(addr));

  rdata <= memory(addr_i) when read_en = '1' else (others => '0');

  write_proc : process (clk)
  begin
    if rising_edge(clk) then
      if write_en = '1' then
        memory(addr_i) <= wdata;
      end if;
    end if;
  end process write_proc;

end architecture rtl;
