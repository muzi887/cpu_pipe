-- forward_unit.vhd
-- 转发控制单元：比较寄存器编号，输出 forward_rs / forward_rd 选择信号
--
-- 01：EX/MEM → EX（优先；LD 时 MemRead=1 不转发地址）
-- 10：MEM/WB → EX
-- 00：不转发，使用 ID/EX 锁存值
library ieee;
use ieee.std_logic_1164.all;

entity forward_unit is
  port (
    -- ID/EX：当前 EX 指令源寄存器编号
    id_ex_rs  : in  std_logic_vector(3 downto 0);
    id_ex_rs2 : in  std_logic_vector(3 downto 0);

    -- EX/MEM：上一条指令写回信息
    ex_mem_rd : in  std_logic_vector(3 downto 0);
    ex_mem_we : in  std_logic;
    ex_mem_mr : in  std_logic;

    -- MEM/WB：再前一条指令写回信息
    mem_wb_rd : in  std_logic_vector(3 downto 0);
    mem_wb_we : in  std_logic;

    -- 转发选择：forward_a = forward_rs，forward_b = forward_rd
    forward_a : out std_logic_vector(1 downto 0);
    forward_b : out std_logic_vector(1 downto 0)
  );
end entity forward_unit;

architecture rtl of forward_unit is
  function forward_sel (
    src_reg   : std_logic_vector(3 downto 0);
    ex_mem_rd : std_logic_vector(3 downto 0);
    ex_mem_we : std_logic;
    ex_mem_mr : std_logic;
    mem_wb_rd : std_logic_vector(3 downto 0);
    mem_wb_we : std_logic
  ) return std_logic_vector is
  begin
    if ex_mem_we = '1' and ex_mem_mr = '0' and ex_mem_rd /= "0000" and ex_mem_rd = src_reg then
      return "01";
    elsif mem_wb_we = '1' and mem_wb_rd /= "0000" and mem_wb_rd = src_reg then
      return "10";
    else
      return "00";
    end if;
  end function forward_sel;
begin
  -- RS 路径（ALU A、BNE rs1）
  forward_a <= forward_sel(
    id_ex_rs, ex_mem_rd, ex_mem_we, ex_mem_mr,
    mem_wb_rd, mem_wb_we
  );

  -- RS2 路径（ALU B、ST 写数据、BNE rs2）
  forward_b <= forward_sel(
    id_ex_rs2, ex_mem_rd, ex_mem_we, ex_mem_mr,
    mem_wb_rd, mem_wb_we
  );
end architecture rtl;
