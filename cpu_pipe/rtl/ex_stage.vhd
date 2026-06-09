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
    rs_val_in   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_val_in   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_in       : in  std_logic_vector(3 downto 0);
    imm_ext_in  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    addr_target_in : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    reg_write_in  : in  std_logic;
    mem_read_in   : in  std_logic;
    mem_write_in  : in  std_logic;
    mem_to_reg_in : in  std_logic;
    rs_src_in     : in  std_logic;
    alu_op_in     : in  std_logic_vector(2 downto 0);
    branch_in     : in  std_logic;
    jump_in       : in  std_logic;
    halt_in       : in  std_logic;

    -- forwarding interface (中期默认 00，终期由 forwarding_unit 驱动)
    forward_a     : in  std_logic_vector(1 downto 0);
    forward_b     : in  std_logic_vector(1 downto 0);
    ex_mem_alu    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_wb_data   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- to EX/MEM pipeline register
    alu_result    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_val_out    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_out        : out std_logic_vector(3 downto 0);
    branch_taken  : out std_logic;
    branch_target : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

    reg_write_out  : out std_logic;
    mem_read_out   : out std_logic;
    mem_write_out  : out std_logic;
    mem_to_reg_out : out std_logic;
    rs_src_out     : out std_logic;
    alu_op_out     : out std_logic_vector(2 downto 0);
    branch_out     : out std_logic;
    jump_out       : out std_logic;
    forward_rs     : out std_logic_vector(1 downto 0);
    forward_rd     : out std_logic_vector(1 downto 0);
    halt_out       : out std_logic
  );
end entity ex_stage;

architecture rtl of ex_stage is
  signal alu_a      : signed(DATA_WIDTH - 1 downto 0);
  signal alu_b      : signed(DATA_WIDTH - 1 downto 0);
  signal alu_y      : signed(DATA_WIDTH - 1 downto 0);
  signal operand_a  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal operand_b  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_rs_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_rd_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  with forward_a select
    forward_rs_data <= ex_mem_alu  when "01",
                       mem_wb_data when "10",
                       rs_val_in   when others;

  with forward_b select
    forward_rd_data <= ex_mem_alu  when "01",
                       mem_wb_data when "10",
                       rd_val_in   when others;

  operand_a <= forward_rs_data;
  operand_b <= imm_ext_in when rs_src_in = '1' else forward_rd_data;

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

  branch_taken <= branch_in when operand_a /= operand_b else '0';

  rd_val_out <= forward_rd_data;
  rd_out      <= rd_in;

  reg_write_out  <= reg_write_in;
  mem_read_out   <= mem_read_in;
  mem_write_out  <= mem_write_in;
  mem_to_reg_out <= mem_to_reg_in;
  rs_src_out     <= rs_src_in;
  alu_op_out     <= alu_op_in;
  branch_out     <= branch_in;
  jump_out       <= jump_in;
  forward_rs     <= forward_a;
  forward_rd     <= forward_b;
  halt_out       <= halt_in;
end architecture rtl;
