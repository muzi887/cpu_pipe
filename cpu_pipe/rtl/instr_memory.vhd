-- instr_memory.vhd
-- 指令存储器（哈佛结构，组合读）
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity instr_memory is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity instr_memory;

architecture rtl of instr_memory is
  constant MEM_DEPTH : integer := 2**ADDR_WIDTH;
  type mem_array_t is array (0 to MEM_DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  constant INIT_MEM : mem_array_t := (
    0  => x"0041", -- ADDI x1, x0, 1
    1  => x"0081", -- ADDI x2, x0, 1
    2  => x"012F", -- ADDI x4, x0, 23
    3  => x"0145", -- ADDI x5, x0, 5
    4  => x"1298", -- ADD  x3, x1, x2
    5  => x"38C0", -- ST   x3, 0(x4)
    6  => x"0440", -- ADDI x1, x2, 0
    7  => x"0680", -- ADDI x2, x3, 0
    8  => x"0901", -- ADDI x4, x4, 1
    9  => x"0B7F", -- ADDI x5, x5, -1
    10 => x"4A3A", -- BNE  x5, x0, LOOP (offset = -6)
    11 => x"F000", -- HALT
    others => (others => '0')
  );

  signal memory : mem_array_t := INIT_MEM;
  signal addr_i : integer range 0 to MEM_DEPTH - 1;
begin
  addr_i <= to_integer(unsigned(addr));
  data   <= memory(addr_i);
end architecture rtl;
