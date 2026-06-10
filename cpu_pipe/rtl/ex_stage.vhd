-- ex_stage.vhd
-- EX 执行阶段：ALU、分支目标计算、分支判断
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ex_stage is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    pc_in       : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    rs_in       : in  std_logic_vector(3 downto 0);
    rs2_in      : in  std_logic_vector(3 downto 0);
    rs_val_in   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_val_in   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_in       : in  std_logic_vector(3 downto 0);
    imm_ext_in  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    addr_target_in : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    reg_write_in  : in  std_logic;
    mem_read_in   : in  std_logic;
    mem_write_in  : in  std_logic;
    mem_to_reg_in : in  std_logic;
    rd_src_in     : in  std_logic;
    alu_op_in     : in  std_logic_vector(2 downto 0);
    branch_in     : in  std_logic;
    jump_in       : in  std_logic;
    halt_in       : in  std_logic;

    forward_a     : in  std_logic_vector(1 downto 0);
    forward_b     : in  std_logic_vector(1 downto 0);
    ex_mem_alu    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_wb_data   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    alu_result    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rs_val_out    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rs_out        : out std_logic_vector(3 downto 0);
    rs2_val_out   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rs2_out       : out std_logic_vector(3 downto 0);
    rd_val_out    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_out        : out std_logic_vector(3 downto 0);
    branch_taken  : out std_logic;
    branch_target : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

    reg_write_out  : out std_logic;
    mem_read_out   : out std_logic;
    mem_write_out  : out std_logic;
    mem_to_reg_out : out std_logic;
    rd_src_out     : out std_logic;
    alu_op_out     : out std_logic_vector(2 downto 0);
    branch_out     : out std_logic;
    jump_out       : out std_logic;
    forward_rs     : out std_logic_vector(1 downto 0);
    forward_rd     : out std_logic_vector(1 downto 0);
    halt_out       : out std_logic
  );
end entity ex_stage;

architecture rtl of ex_stage is
  signal alu_a             : signed(DATA_WIDTH - 1 downto 0);
  signal alu_b             : signed(DATA_WIDTH - 1 downto 0);
  signal alu_y             : signed(DATA_WIDTH - 1 downto 0);
  signal operand_a         : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal operand_b         : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rs_src_data       : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rd_src_data       : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_rs_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_rd_reg    : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_rd_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_rs2_data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  rs_src_data <= rs_val_in;

  -- rd_src MUX → Forward_rd 的 00 输入
  rd_src_data <= imm_ext_in when rd_src_in = '1' else rd_val_in;

  -- rs_src_data → Forward_rs → ALU A
  with forward_a select
    forward_rs_data <= ex_mem_alu  when "01",
                       mem_wb_data when "10",
                       rs_src_data when others;

  -- rd_src_data → Forward_rd → ALU B（rd_src=0 时可转发）
  with forward_b select
    forward_rd_reg <= ex_mem_alu  when "01",
                        mem_wb_data when "10",
                        rd_src_data when others;

  -- rd_src=1：ALU B 恒为 rd_src_data（imm），forward_b 不写数据转发不能覆盖
  forward_rd_data <= rd_src_data when rd_src_in = '1' else forward_rd_reg;

  -- ST 写数据：rs2（rd_val_in）单独转发，与 ALU B 分离
  with forward_b select
    forward_rs2_data <= ex_mem_alu  when "01",
                          mem_wb_data when "10",
                          rd_val_in   when others;

  operand_a <= forward_rs_data;
  operand_b <= forward_rd_data;

  rd_val_out <= forward_rs2_data when mem_write_in = '1' else forward_rd_reg;

  alu_a <= signed(operand_a);
  alu_b <= signed(operand_b);

  alu_core : process (alu_a, alu_b, alu_op_in)
  begin
    case alu_op_in is
      when "000"  => alu_y <= alu_a + alu_b;
      when "001"  => alu_y <= alu_a - alu_b;
      when "010"  => alu_y <= alu_a and alu_b;
      when others => alu_y <= (others => '0');
    end case;
  end process alu_core;

  alu_result <= std_logic_vector(alu_y);

  branch_target <= addr_target_in;

  -- BNE：rs1（Forward_rs）与 rs2（Forward_rd_reg）比较
  branch_taken <= branch_in when forward_rs_data /= forward_rd_reg else '0';

  rs_val_out  <= forward_rs_data;
  rs2_val_out <= forward_rs2_data when mem_write_in = '1' else forward_rd_reg;
  rd_out      <= rd_in;
  rs_out      <= rs_in;
  rs2_out     <= rs2_in;

  reg_write_out  <= reg_write_in;
  mem_read_out   <= mem_read_in;
  mem_write_out  <= mem_write_in;
  mem_to_reg_out <= mem_to_reg_in;
  rd_src_out     <= rd_src_in;
  alu_op_out     <= alu_op_in;
  branch_out     <= branch_in;
  jump_out       <= jump_in;
  forward_rs     <= forward_a;
  forward_rd     <= forward_b;
  halt_out       <= halt_in;
end architecture rtl;
