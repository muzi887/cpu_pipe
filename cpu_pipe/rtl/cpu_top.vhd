-- cpu_top.vhd
-- 五级流水 CPU 顶层：五级模块 + 段间流水线寄存器 + 基础 hazard 处理
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu_top is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

    -- 哈佛结构存储器接口
    instr_addr : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    instr_data : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    mem_addr      : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    mem_wdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_rdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_read_en   : out std_logic;
    mem_write_en  : out std_logic;

    -- Cache miss 时全局冻结流水线
    cache_stall : in std_logic;

    -- Timer 中断输入（来自 soc_top）
    irq_timer : in std_logic;

    -- 调试观测
    debug_pc        : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    debug_instr     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_epc       : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    debug_irq_pending : out std_logic;
    debug_status_ie : out std_logic
  );
end entity cpu_top;

architecture rtl of cpu_top is
  constant ISR_ADDR : std_logic_vector(ADDR_WIDTH - 1 downto 0) := x"0100";
  constant CAUSE_TIMER : std_logic_vector(ADDR_WIDTH - 1 downto 0) := x"0001";

  component if_stage is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk           : in  std_logic;
      rst           : in  std_logic;
      pc_en         : in  std_logic;
      pc_src        : in  std_logic_vector(1 downto 0);
      branch_target : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      jump_target   : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      pc_redirect   : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      halt          : in  std_logic;
      instr_data    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      pc_out        : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      pc_plus1_out  : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      instruction   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      instr_addr    : out std_logic_vector(ADDR_WIDTH - 1 downto 0)
    );
  end component;

  component id_stage is
    generic (
      DATA_WIDTH : integer := 16
    );
    port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      instruction : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      pc_in       : in  std_logic_vector(15 downto 0);
      wr_en       : in  std_logic;
      wr_addr     : in  std_logic_vector(3 downto 0);
      wr_data     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      rs_addr     : out std_logic_vector(3 downto 0);
      rd_addr     : out std_logic_vector(3 downto 0);
      rs          : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd          : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      pc_out      : out std_logic_vector(15 downto 0);
      rs_out      : out std_logic_vector(3 downto 0);
      rs2_out     : out std_logic_vector(3 downto 0);
      rd_out      : out std_logic_vector(3 downto 0);
      rs_val      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_val      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      imm_ext     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      addr_target : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      reg_write   : out std_logic;
      mem_read    : out std_logic;
      mem_write   : out std_logic;
      mem_to_reg  : out std_logic;
      rd_src      : out std_logic;
      alu_op      : out std_logic_vector(2 downto 0);
      branch      : out std_logic;
      jump        : out std_logic;
      halt        : out std_logic;
      sys_ei      : out std_logic;
      sys_di      : out std_logic;
      sys_iret    : out std_logic
    );
  end component;

  component interrupt_controller is
    generic (
      ADDR_WIDTH : integer := 16
    );
    port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      irq_timer   : in  std_logic;
      epc_out     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      status_ie   : out std_logic;
      cause_out   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      epc_write   : in  std_logic;
      epc_wdata   : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      ie_set      : in  std_logic;
      ie_clear    : in  std_logic;
      cause_write : in  std_logic;
      cause_wdata : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      irq_ack     : in  std_logic;
      irq_pending : out std_logic
    );
  end component;

  component ex_stage is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      pc_in         : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      rs_in         : in  std_logic_vector(3 downto 0);
      rs2_in        : in  std_logic_vector(3 downto 0);
      rs_val_in     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_val_in     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_in         : in  std_logic_vector(3 downto 0);
      imm_ext_in    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
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
      reg_write_out : out std_logic;
      mem_read_out  : out std_logic;
      mem_write_out : out std_logic;
      mem_to_reg_out : out std_logic;
      rd_src_out    : out std_logic;
      alu_op_out    : out std_logic_vector(2 downto 0);
      branch_out    : out std_logic;
      jump_out      : out std_logic;
      forward_rs    : out std_logic_vector(1 downto 0);
      forward_rd    : out std_logic_vector(1 downto 0);
      halt_out      : out std_logic
    );
  end component;

  component mem_stage is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      alu_result_in    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_val_in        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_in            : in  std_logic_vector(3 downto 0);
      branch_taken_in  : in  std_logic;
      branch_target_in : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      reg_write_in     : in  std_logic;
      mem_read_in      : in  std_logic;
      mem_write_in     : in  std_logic;
      mem_to_reg_in    : in  std_logic;
      rd_src_in        : in  std_logic;
      alu_op_in        : in  std_logic_vector(2 downto 0);
      branch_in        : in  std_logic;
      jump_in          : in  std_logic;
      halt_in          : in  std_logic;
      mem_rdata        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_addr         : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      mem_wdata        : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_read_en      : out std_logic;
      mem_write_en     : out std_logic;
      mem_data_out     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      alu_result_out   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_out           : out std_logic_vector(3 downto 0);
      branch_taken_out : out std_logic;
      branch_target_out : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      reg_write_out    : out std_logic;
      mem_read_out     : out std_logic;
      mem_write_out    : out std_logic;
      mem_to_reg_out   : out std_logic;
      rd_src_out       : out std_logic;
      alu_op_out       : out std_logic_vector(2 downto 0);
      branch_out       : out std_logic;
      jump_out         : out std_logic;
      halt_out         : out std_logic
    );
  end component;

  component wb_stage is
    generic (
      DATA_WIDTH : integer := 16
    );
    port (
      mem_data_in   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      alu_result_in : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      rd_in         : in  std_logic_vector(3 downto 0);
      reg_write_in  : in  std_logic;
      mem_to_reg_in : in  std_logic;
      wb_addr       : out std_logic_vector(3 downto 0);
      wb_data       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      wb_en         : out std_logic
    );
  end component;

  component hazard_unit is
    generic (
      ADDR_WIDTH : integer := 16
    );
    port (
      bne_taken      : in  std_logic;
      id_ex_mem_read : in  std_logic;
      id_ex_rd       : in  std_logic_vector(3 downto 0);
      id_ex_valid    : in  std_logic;
      if_id_rs1      : in  std_logic_vector(3 downto 0);
      if_id_rs2      : in  std_logic_vector(3 downto 0);
      load_use_stall : out std_logic;
      pc_src         : out std_logic_vector(1 downto 0);
      pc_en          : out std_logic;
      ifid_en        : out std_logic;
      ifid_src       : out std_logic;
      control_src    : out std_logic
    );
  end component;

  component forward_unit is
    port (
      id_ex_rs  : in  std_logic_vector(3 downto 0);
      id_ex_rs2 : in  std_logic_vector(3 downto 0);
      ex_mem_rd : in  std_logic_vector(3 downto 0);
      ex_mem_we : in  std_logic;
      ex_mem_mr : in  std_logic;
      mem_wb_rd : in  std_logic_vector(3 downto 0);
      mem_wb_we : in  std_logic;
      forward_a : out std_logic_vector(1 downto 0);
      forward_b : out std_logic_vector(1 downto 0)
    );
  end component;

  -- IF 级输出
  signal if_pc         : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal if_pc_plus1   : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal if_instruction : std_logic_vector(DATA_WIDTH - 1 downto 0);

  -- IF/ID 流水线寄存器
  signal if_id_pc      : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal if_id_instr   : std_logic_vector(DATA_WIDTH - 1 downto 0);

  -- ID 级输出
  signal id_pc         : std_logic_vector(15 downto 0);
  signal id_rs         : std_logic_vector(3 downto 0);
  signal id_rs2        : std_logic_vector(3 downto 0);
  signal id_rd         : std_logic_vector(3 downto 0);
  signal id_rs_val     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_rd_val     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_imm_ext    : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_addr_target : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_reg_write  : std_logic;
  signal id_mem_read   : std_logic;
  signal id_mem_write  : std_logic;
  signal id_mem_to_reg : std_logic;
  signal id_rd_src     : std_logic;
  signal id_alu_op     : std_logic_vector(2 downto 0);
  signal id_branch     : std_logic;
  signal id_jump       : std_logic;
  signal id_halt       : std_logic;
  signal id_sys_ei     : std_logic;
  signal id_sys_di     : std_logic;
  signal id_sys_iret   : std_logic;

  -- ID/EX 流水线寄存器
  signal id_ex_pc         : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal id_ex_rs         : std_logic_vector(3 downto 0);
  signal id_ex_rs2        : std_logic_vector(3 downto 0);
  signal id_ex_rd         : std_logic_vector(3 downto 0);
  signal id_ex_rs_val     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_ex_rd_val     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_ex_imm_ext    : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_ex_addr_target : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_ex_instr      : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal id_ex_reg_write  : std_logic;
  signal id_ex_mem_read   : std_logic;
  signal id_ex_mem_write  : std_logic;
  signal id_ex_mem_to_reg : std_logic;
  signal id_ex_rd_src     : std_logic;
  signal id_ex_alu_op     : std_logic_vector(2 downto 0);
  signal id_ex_branch     : std_logic;
  signal id_ex_jump       : std_logic;
  signal id_ex_halt       : std_logic;
  signal id_ex_sys_ei     : std_logic;
  signal id_ex_sys_di     : std_logic;
  signal id_ex_sys_iret   : std_logic;
  signal id_ex_valid      : std_logic;

  -- EX 级输出
  signal ex_alu_result   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal ex_rs_val       : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal ex_rs           : std_logic_vector(3 downto 0);
  signal ex_rs2_val      : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal ex_rs2          : std_logic_vector(3 downto 0);
  signal ex_rd_val       : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal ex_rd           : std_logic_vector(3 downto 0);
  signal ex_branch_taken : std_logic;
  signal ex_branch_target : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal ex_reg_write    : std_logic;
  signal ex_mem_read     : std_logic;
  signal ex_mem_write    : std_logic;
  signal ex_mem_to_reg   : std_logic;
  signal ex_rd_src       : std_logic;
  signal ex_alu_op       : std_logic_vector(2 downto 0);
  signal ex_branch       : std_logic;
  signal ex_jump         : std_logic;
  signal ex_halt         : std_logic;

  -- EX/MEM 流水线寄存器
  signal ex_mem_alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal ex_mem_rd_val     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal ex_mem_rd         : std_logic_vector(3 downto 0);
  signal ex_mem_branch_taken : std_logic;
  signal ex_mem_branch_target : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal ex_mem_reg_write  : std_logic;
  signal ex_mem_mem_read   : std_logic;
  signal ex_mem_mem_write  : std_logic;
  signal ex_mem_mem_to_reg : std_logic;
  signal ex_mem_rd_src     : std_logic;
  signal ex_mem_alu_op     : std_logic_vector(2 downto 0);
  signal ex_mem_branch     : std_logic;
  signal ex_mem_jump       : std_logic;
  signal ex_mem_halt       : std_logic;
  signal ex_mem_sys_ei     : std_logic;
  signal ex_mem_sys_di     : std_logic;
  signal ex_mem_sys_iret   : std_logic;
  signal ex_mem_valid      : std_logic;

  -- MEM 级输出
  signal mem_data        : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_alu_result  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_rd          : std_logic_vector(3 downto 0);
  signal mem_reg_write   : std_logic;
  signal mem_mem_to_reg  : std_logic;

  -- MEM/WB 流水线寄存器
  signal mem_wb_mem_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_wb_alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_wb_rd         : std_logic_vector(3 downto 0);
  signal mem_wb_reg_write  : std_logic;
  signal mem_wb_mem_to_reg : std_logic;
  signal mem_wb_sys_ei     : std_logic;
  signal mem_wb_sys_di     : std_logic;
  signal mem_wb_sys_iret   : std_logic;
  signal mem_wb_valid      : std_logic;

  -- WB 级输出
  signal wb_addr : std_logic_vector(3 downto 0);
  signal wb_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal wb_en   : std_logic;

  -- hazard / control
  signal pc_en         : std_logic;
  signal pc_src        : std_logic_vector(1 downto 0);
  signal branch_target : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal jump_target   : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal cpu_halt      : std_logic;
  signal halt_latched  : std_logic;
  signal hz_pc_src       : std_logic_vector(1 downto 0);
  signal hz_pc_en        : std_logic;
  signal hz_ifid_en      : std_logic;
  signal hz_ifid_src     : std_logic;
  signal hz_control_src  : std_logic;
  signal load_use_stall  : std_logic;
  signal ifid_src        : std_logic;
  signal control_src     : std_logic;
  signal if_id_instr_in  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal forward_a     : std_logic_vector(1 downto 0);
  signal forward_b     : std_logic_vector(1 downto 0);
  signal ex_forward_rs : std_logic_vector(1 downto 0);
  signal ex_forward_rd : std_logic_vector(1 downto 0);
  signal mem_wb_wdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal status_ie     : std_logic;
  signal epc_reg       : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal irq_pending   : std_logic;
  signal wb_commit     : std_logic;
  signal irq_take      : std_logic;
  signal iret_commit   : std_logic;
  signal flush_all     : std_logic;
  signal pc_redirect   : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal epc_write     : std_logic;
  signal epc_wdata     : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal ie_set        : std_logic;
  signal ie_clear      : std_logic;
  signal cause_write   : std_logic;
  signal cause_wdata   : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal irq_ack       : std_logic;

begin
  u_if : if_stage
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      clk           => clk,
      rst           => rst,
      pc_en         => pc_en,
      pc_src        => pc_src,
      branch_target => branch_target,
      jump_target   => jump_target,
      pc_redirect   => pc_redirect,
      halt          => cpu_halt,
      instr_data    => instr_data,
      pc_out        => if_pc,
      pc_plus1_out  => if_pc_plus1,
      instruction   => if_instruction,
      instr_addr    => instr_addr
    );

  u_id : id_stage
    generic map (DATA_WIDTH => DATA_WIDTH)
    port map (
      clk         => clk,
      rst         => rst,
      instruction => if_id_instr,
      pc_in       => if_id_pc(15 downto 0),
      wr_en       => wb_en,
      wr_addr     => wb_addr,
      wr_data     => wb_data,
      rs_addr     => open,
      rd_addr     => open,
      rs          => open,
      rd          => open,
      pc_out      => id_pc,
      rs_out      => id_rs,
      rs2_out     => id_rs2,
      rd_out      => id_rd,
      rs_val      => id_rs_val,
      rd_val      => id_rd_val,
      imm_ext     => id_imm_ext,
      addr_target => id_addr_target,
      reg_write   => id_reg_write,
      mem_read    => id_mem_read,
      mem_write   => id_mem_write,
      mem_to_reg  => id_mem_to_reg,
      rd_src      => id_rd_src,
      alu_op      => id_alu_op,
      branch      => id_branch,
      jump        => id_jump,
      halt        => id_halt,
      sys_ei      => id_sys_ei,
      sys_di      => id_sys_di,
      sys_iret    => id_sys_iret
    );

  u_ex : ex_stage
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      pc_in         => id_ex_pc,
      rs_in         => id_ex_rs,
      rs2_in        => id_ex_rs2,
      rs_val_in     => id_ex_rs_val,
      rd_val_in     => id_ex_rd_val,
      rd_in         => id_ex_rd,
      imm_ext_in    => id_ex_imm_ext,
      addr_target_in => id_ex_addr_target,
      reg_write_in  => id_ex_reg_write,
      mem_read_in   => id_ex_mem_read,
      mem_write_in  => id_ex_mem_write,
      mem_to_reg_in => id_ex_mem_to_reg,
      rd_src_in     => id_ex_rd_src,
      alu_op_in     => id_ex_alu_op,
      branch_in     => id_ex_branch,
      jump_in       => id_ex_jump,
      halt_in       => id_ex_halt,
      forward_a     => forward_a,
      forward_b     => forward_b,
      ex_mem_alu    => ex_mem_alu_result,
      mem_wb_data   => mem_wb_wdata,
      alu_result    => ex_alu_result,
      rs_val_out    => ex_rs_val,
      rs_out        => ex_rs,
      rs2_val_out   => ex_rs2_val,
      rs2_out       => ex_rs2,
      rd_val_out    => ex_rd_val,
      rd_out        => ex_rd,
      branch_taken  => ex_branch_taken,
      branch_target => ex_branch_target,
      reg_write_out => ex_reg_write,
      mem_read_out  => ex_mem_read,
      mem_write_out => ex_mem_write,
      mem_to_reg_out => ex_mem_to_reg,
      rd_src_out    => ex_rd_src,
      alu_op_out    => ex_alu_op,
      branch_out    => ex_branch,
      jump_out      => ex_jump,
      forward_rs    => ex_forward_rs,
      forward_rd    => ex_forward_rd,
      halt_out      => ex_halt
    );

  u_mem : mem_stage
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      alu_result_in    => ex_mem_alu_result,
      rd_val_in        => ex_mem_rd_val,
      rd_in            => ex_mem_rd,
      branch_taken_in  => ex_mem_branch_taken,
      branch_target_in => ex_mem_branch_target,
      reg_write_in     => ex_mem_reg_write,
      mem_read_in      => ex_mem_mem_read,
      mem_write_in     => ex_mem_mem_write,
      mem_to_reg_in    => ex_mem_mem_to_reg,
      rd_src_in        => ex_mem_rd_src,
      alu_op_in        => ex_mem_alu_op,
      branch_in        => ex_mem_branch,
      jump_in          => ex_mem_jump,
      halt_in          => ex_mem_halt,
      mem_rdata        => mem_rdata,
      mem_addr         => mem_addr,
      mem_wdata        => mem_wdata,
      mem_read_en      => mem_read_en,
      mem_write_en     => mem_write_en,
      mem_data_out     => mem_data,
      alu_result_out   => mem_alu_result,
      rd_out           => mem_rd,
      branch_taken_out => open,
      branch_target_out => open,
      reg_write_out    => mem_reg_write,
      mem_read_out     => open,
      mem_write_out    => open,
      mem_to_reg_out   => mem_mem_to_reg,
      rd_src_out       => open,
      alu_op_out       => open,
      branch_out       => open,
      jump_out         => open,
      halt_out         => open
    );

  u_wb : wb_stage
    generic map (DATA_WIDTH => DATA_WIDTH)
    port map (
      mem_data_in   => mem_wb_mem_data,
      alu_result_in => mem_wb_alu_result,
      rd_in         => mem_wb_rd,
      reg_write_in  => mem_wb_reg_write,
      mem_to_reg_in => mem_wb_mem_to_reg,
      wb_addr       => wb_addr,
      wb_data       => wb_data,
      wb_en         => wb_en
    );

  mem_wb_wdata <= mem_wb_mem_data when mem_wb_mem_to_reg = '1' else mem_wb_alu_result;

  u_forward : forward_unit
    port map (
      id_ex_rs  => id_ex_rs,
      id_ex_rs2 => id_ex_rs2,
      ex_mem_rd => ex_mem_rd,
      ex_mem_we => ex_mem_reg_write,
      ex_mem_mr => ex_mem_mem_read,
      mem_wb_rd => mem_wb_rd,
      mem_wb_we => mem_wb_reg_write,
      forward_a => forward_a,
      forward_b => forward_b
    );

  u_hazard : hazard_unit
    generic map (ADDR_WIDTH => ADDR_WIDTH)
    port map (
      bne_taken      => ex_branch_taken,
      id_ex_mem_read => id_ex_mem_read,
      id_ex_rd       => id_ex_rd,
      id_ex_valid    => id_ex_valid,
      if_id_rs1      => id_rs,
      if_id_rs2      => id_rs2,
      load_use_stall => load_use_stall,
      pc_src         => hz_pc_src,
      pc_en          => hz_pc_en,
      ifid_en        => hz_ifid_en,
      ifid_src       => hz_ifid_src,
      control_src    => hz_control_src
    );

  u_irq : interrupt_controller
    generic map (ADDR_WIDTH => ADDR_WIDTH)
    port map (
      clk         => clk,
      rst         => rst,
      irq_timer   => irq_timer,
      epc_out     => epc_reg,
      status_ie   => status_ie,
      cause_out   => open,
      epc_write   => epc_write,
      epc_wdata   => epc_wdata,
      ie_set      => ie_set,
      ie_clear    => ie_clear,
      cause_write => cause_write,
      cause_wdata => cause_wdata,
      irq_ack     => irq_ack,
      irq_pending => irq_pending
    );

  wb_commit <= mem_wb_valid when cache_stall = '0' else '0';
  iret_commit <= mem_wb_valid and mem_wb_sys_iret and (not cache_stall);
  irq_take <= irq_pending and status_ie and wb_commit and (not cache_stall) and (not mem_wb_sys_iret);
  flush_all <= irq_take or iret_commit;

  pc_redirect <= epc_reg when iret_commit = '1' else ISR_ADDR;
  pc_src <= "11" when flush_all = '1' else
            "10" when id_ex_jump = '1' else hz_pc_src;

  pc_en <= '0' when cache_stall = '1' or load_use_stall = '1' else
           '1' when flush_all = '1' else hz_pc_en;

  ifid_src <= '1' when hz_ifid_src = '1' or id_ex_jump = '1' or flush_all = '1' else '0';
  control_src <= '0' when hz_control_src = '0' or flush_all = '1' else '1';
  branch_target <= ex_branch_target;
  jump_target <= id_ex_addr_target;
  -- HALT 在 ID 时提前停 PC；进入 EX 后锁存 halt_latched。
  -- irq_take 清除锁存，ISR 内 PC 可顺序取指（0x0100→0x0101 IRET）；
  -- iret_commit 恢复锁存，回到 EPC 后再次冻结 PC。
  halt_reg : process (clk, rst)
  begin
    if rst = '0' then
      halt_latched <= '0';
    elsif rising_edge(clk) then
      if irq_take = '1' then
        halt_latched <= '0';
      elsif iret_commit = '1' then
        halt_latched <= '1';
      elsif cache_stall = '0' and id_ex_halt = '1' and id_ex_valid = '1' then
        halt_latched <= '1';
      end if;
    end if;
  end process halt_reg;

  cpu_halt <= halt_latched or id_halt or id_ex_halt;

  epc_write   <= '1' when irq_take = '1' else '0';
  epc_wdata   <= if_pc;
  ie_set      <= '1' when iret_commit = '1' or (mem_wb_valid = '1' and mem_wb_sys_ei = '1' and cache_stall = '0') else '0';
  ie_clear    <= '1' when irq_take = '1' or (mem_wb_valid = '1' and mem_wb_sys_di = '1' and cache_stall = '0') else '0';
  cause_write <= '1' when irq_take = '1' else '0';
  cause_wdata <= CAUSE_TIMER;
  irq_ack     <= irq_take;
  debug_epc         <= epc_reg;
  debug_irq_pending <= irq_pending;
  debug_status_ie   <= status_ie;

  -- IF/ID 指令 MUX（Ifid_src=1 时选 0，冲刷误取指）
  if_id_instr_in <= (others => '0') when ifid_src = '1' else if_instruction;

  debug_pc    <= if_id_pc;
  debug_instr <= if_id_instr;

  -- IF/ID
  if_id_reg : process (clk, rst)
  begin
    if rst = '0' then
      if_id_pc    <= (others => '0');
      if_id_instr <= (others => '0');
    elsif rising_edge(clk) then
      if hz_ifid_en = '1' and cache_stall = '0' and load_use_stall = '0' then
        if_id_pc    <= if_pc;
        if_id_instr <= if_id_instr_in;
      end if;
    end if;
  end process if_id_reg;

  -- ID/EX
  id_ex_reg : process (clk, rst)
  begin
    if rst = '0' then
      id_ex_pc         <= (others => '0');
      id_ex_rs         <= (others => '0');
      id_ex_rs2        <= (others => '0');
      id_ex_rd         <= (others => '0');
      id_ex_rs_val     <= (others => '0');
      id_ex_rd_val     <= (others => '0');
      id_ex_imm_ext    <= (others => '0');
      id_ex_addr_target <= (others => '0');
      id_ex_instr      <= (others => '0');
      id_ex_reg_write  <= '0';
      id_ex_mem_read   <= '0';
      id_ex_mem_write  <= '0';
      id_ex_mem_to_reg <= '0';
      id_ex_rd_src     <= '0';
      id_ex_alu_op     <= (others => '0');
      id_ex_branch     <= '0';
      id_ex_jump       <= '0';
      id_ex_halt       <= '0';
      id_ex_sys_ei     <= '0';
      id_ex_sys_di     <= '0';
      id_ex_sys_iret   <= '0';
      id_ex_valid      <= '0';
    elsif rising_edge(clk) then
      if cache_stall = '0' then
        if control_src = '0' then
          id_ex_reg_write  <= '0';
          id_ex_mem_read   <= '0';
          id_ex_mem_write  <= '0';
          id_ex_mem_to_reg <= '0';
          id_ex_rd_src     <= '0';
          id_ex_alu_op     <= (others => '0');
          id_ex_branch     <= '0';
          id_ex_jump       <= '0';
          id_ex_halt       <= '0';
          id_ex_sys_ei     <= '0';
          id_ex_sys_di     <= '0';
          id_ex_sys_iret   <= '0';
          id_ex_valid      <= '0';
        else
          id_ex_pc         <= std_logic_vector(resize(unsigned(if_id_pc), ADDR_WIDTH));
          id_ex_rs         <= id_rs;
          id_ex_rs2        <= id_rs2;
          id_ex_rd         <= id_rd;
          id_ex_rs_val     <= id_rs_val;
          id_ex_rd_val     <= id_rd_val;
          id_ex_imm_ext    <= id_imm_ext;
          id_ex_addr_target <= id_addr_target;
          id_ex_instr      <= if_id_instr;
          id_ex_reg_write  <= id_reg_write;
          id_ex_mem_read   <= id_mem_read;
          id_ex_mem_write  <= id_mem_write;
          id_ex_mem_to_reg <= id_mem_to_reg;
          id_ex_rd_src     <= id_rd_src;
          id_ex_alu_op     <= id_alu_op;
          id_ex_branch     <= id_branch;
          id_ex_jump       <= id_jump;
          id_ex_halt       <= id_halt;
          id_ex_sys_ei     <= id_sys_ei;
          id_ex_sys_di     <= id_sys_di;
          id_ex_sys_iret   <= id_sys_iret;
          id_ex_valid      <= '1';
        end if;
      end if;
    end if;
  end process id_ex_reg;

  -- EX/MEM
  ex_mem_reg : process (clk, rst)
  begin
    if rst = '0' then
      ex_mem_alu_result    <= (others => '0');
      ex_mem_rd_val        <= (others => '0');
      ex_mem_rd            <= (others => '0');
      ex_mem_branch_taken  <= '0';
      ex_mem_branch_target <= (others => '0');
      ex_mem_reg_write     <= '0';
      ex_mem_mem_read      <= '0';
      ex_mem_mem_write     <= '0';
      ex_mem_mem_to_reg    <= '0';
      ex_mem_rd_src        <= '0';
      ex_mem_alu_op        <= (others => '0');
      ex_mem_branch        <= '0';
      ex_mem_jump          <= '0';
      ex_mem_halt          <= '0';
      ex_mem_sys_ei        <= '0';
      ex_mem_sys_di        <= '0';
      ex_mem_sys_iret      <= '0';
      ex_mem_valid         <= '0';
    elsif rising_edge(clk) then
      if cache_stall = '0' then
        if flush_all = '1' then
          ex_mem_reg_write  <= '0';
          ex_mem_mem_read   <= '0';
          ex_mem_mem_write  <= '0';
          ex_mem_mem_to_reg <= '0';
          ex_mem_branch     <= '0';
          ex_mem_jump       <= '0';
          ex_mem_halt       <= '0';
          ex_mem_sys_ei     <= '0';
          ex_mem_sys_di     <= '0';
          ex_mem_sys_iret   <= '0';
          ex_mem_valid      <= '0';
        else
          ex_mem_alu_result    <= ex_alu_result;
          ex_mem_rd_val        <= ex_rd_val;
          ex_mem_rd            <= ex_rd;
          ex_mem_branch_taken  <= ex_branch_taken;
          ex_mem_branch_target <= ex_branch_target;
          ex_mem_reg_write     <= ex_reg_write;
          ex_mem_mem_read      <= ex_mem_read;
          ex_mem_mem_write     <= ex_mem_write;
          ex_mem_mem_to_reg    <= ex_mem_to_reg;
          ex_mem_rd_src        <= ex_rd_src;
          ex_mem_alu_op        <= ex_alu_op;
          ex_mem_branch        <= ex_branch;
          ex_mem_jump          <= ex_jump;
          ex_mem_halt          <= ex_halt;
          ex_mem_sys_ei        <= id_ex_sys_ei;
          ex_mem_sys_di        <= id_ex_sys_di;
          ex_mem_sys_iret      <= id_ex_sys_iret;
          ex_mem_valid         <= id_ex_valid;
        end if;
      end if;
    end if;
  end process ex_mem_reg;

  -- MEM/WB
  mem_wb_reg : process (clk, rst)
  begin
    if rst = '0' then
      mem_wb_mem_data   <= (others => '0');
      mem_wb_alu_result <= (others => '0');
      mem_wb_rd         <= (others => '0');
      mem_wb_reg_write  <= '0';
      mem_wb_mem_to_reg <= '0';
      mem_wb_sys_ei     <= '0';
      mem_wb_sys_di     <= '0';
      mem_wb_sys_iret   <= '0';
      mem_wb_valid      <= '0';
    elsif rising_edge(clk) then
      if cache_stall = '0' then
        if flush_all = '1' then
          mem_wb_reg_write  <= '0';
          mem_wb_mem_to_reg <= '0';
          mem_wb_sys_ei     <= '0';
          mem_wb_sys_di     <= '0';
          mem_wb_sys_iret   <= '0';
          mem_wb_valid      <= '0';
        else
          mem_wb_mem_data   <= mem_data;
          mem_wb_alu_result <= mem_alu_result;
          mem_wb_rd         <= mem_rd;
          mem_wb_reg_write  <= mem_reg_write;
          mem_wb_mem_to_reg <= mem_mem_to_reg;
          mem_wb_sys_ei     <= ex_mem_sys_ei;
          mem_wb_sys_di     <= ex_mem_sys_di;
          mem_wb_sys_iret   <= ex_mem_sys_iret;
          mem_wb_valid      <= ex_mem_valid;
        end if;
      end if;
    end if;
  end process mem_wb_reg;

end architecture rtl;
