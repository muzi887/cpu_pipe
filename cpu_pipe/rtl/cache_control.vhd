-- cache_control.vhd
-- 汇总 i_miss / d_cache 未就绪，产生全局 stall
library ieee;
use ieee.std_logic_1164.all;

entity cache_control is
  port (
    i_miss    : in  std_logic;
    cpu_ready : in  std_logic;
    stall     : out std_logic
  );
end entity cache_control;

architecture rtl of cache_control is
begin
  stall <= i_miss or (not cpu_ready);
end architecture rtl;
