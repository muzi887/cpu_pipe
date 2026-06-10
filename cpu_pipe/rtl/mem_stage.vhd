-- mem_stage.vhd
-- MEM 访存阶段：生成主存接口信号，透传写回所需数据
library ieee;
use ieee.std_logic_1164.all;

entity mem_stage is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    alu_result_in : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_val_in     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_in         : in  std_logic_vector(3 downto 0);
    branch_taken_in  : in  std_logic;
    branch_target_in : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);

    reg_write_in  : in  std_logic;
    mem_read_in   : in  std_logic;
    mem_write_in  : in  std_logic;
    mem_to_reg_in : in  std_logic;
    rd_src_in     : in  std_logic;
    alu_op_in     : in  std_logic_vector(2 downto 0);
    branch_in     : in  std_logic;
    jump_in       : in  std_logic;
    halt_in       : in  std_logic;

    -- d_cache interface
    mem_rdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_addr      : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    mem_wdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_read_en   : out std_logic;
    mem_write_en  : out std_logic;

    -- to MEM/WB pipeline register
    mem_data_out  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    alu_result_out : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_out        : out std_logic_vector(3 downto 0);
    branch_taken_out  : out std_logic;
    branch_target_out : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

    reg_write_out  : out std_logic;
    mem_read_out   : out std_logic;
    mem_write_out  : out std_logic;
    mem_to_reg_out : out std_logic;
    rd_src_out     : out std_logic;
    alu_op_out     : out std_logic_vector(2 downto 0);
    branch_out     : out std_logic;
    jump_out       : out std_logic;
    halt_out       : out std_logic
  );
end entity mem_stage;

architecture rtl of mem_stage is
begin
  mem_addr     <= alu_result_in;
  mem_wdata    <= rd_val_in;
  mem_read_en  <= mem_read_in;
  mem_write_en <= mem_write_in;

  mem_data_out       <= mem_rdata;
  alu_result_out     <= alu_result_in;
  rd_out             <= rd_in;
  branch_taken_out   <= branch_taken_in;
  branch_target_out  <= branch_target_in;

  reg_write_out  <= reg_write_in;
  mem_read_out   <= mem_read_in;
  mem_write_out  <= mem_write_in;
  mem_to_reg_out <= mem_to_reg_in;
  rd_src_out     <= rd_src_in;
  alu_op_out     <= alu_op_in;
  branch_out     <= branch_in;
  jump_out       <= jump_in;
  halt_out       <= halt_in;
end architecture rtl;
