-- wb_stage.vhd
-- WB 写回阶段：将数据写回寄存器文件
library ieee;
use ieee.std_logic_1164.all;

entity wb_stage is
  generic (
    DATA_WIDTH : integer := 16
  );
  port (
    mem_data_in    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    alu_result_in  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_in          : in  std_logic_vector(3 downto 0);
    reg_write_in   : in  std_logic;
    mem_to_reg_in  : in  std_logic;

    -- register file write interface
    wb_addr        : out std_logic_vector(3 downto 0);
    wb_data        : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    wb_en          : out std_logic
  );
end entity wb_stage;

architecture rtl of wb_stage is
begin
  wb_data <= mem_data_in when mem_to_reg_in = '1' else alu_result_in;
  wb_addr <= rd_in;
  wb_en   <= reg_write_in;
end architecture rtl;