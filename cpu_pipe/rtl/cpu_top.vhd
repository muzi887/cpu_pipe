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

    -- 调试观测
    debug_pc   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    debug_instr : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity cpu_top;

architecture rtl of cpu_top is
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
      halt        : out std_logic
    );
  end component;

  component ex_stage is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      pc_in         : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
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

  -- EX 级输出
  signal ex_alu_result   : std_logic_vector(DATA_WIDTH - 1 downto 0);
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
  signal branch_flush  : std_logic;
  signal forward_a     : std_logic_vector(1 downto 0);
  signal forward_b     : std_logic_vector(1 downto 0);
  signal mem_wb_wdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);

  function forward_sel (
    id_ex_rs    : std_logic_vector(3 downto 0);
    ex_mem_rd   : std_logic_vector(3 downto 0);
    ex_mem_we   : std_logic;
    ex_mem_mr   : std_logic;
    mem_wb_rd   : std_logic_vector(3 downto 0);
    mem_wb_we   : std_logic
  ) return std_logic_vector is
  begin
    if ex_mem_we = '1' and ex_mem_mr = '0' and ex_mem_rd /= "0000" and ex_mem_rd = id_ex_rs then
      return "01";
    elsif mem_wb_we = '1' and mem_wb_rd /= "0000" and mem_wb_rd = id_ex_rs then
      return "10";
    else
      return "00";
    end if;
  end function forward_sel;

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
      halt        => id_halt
    );

  u_ex : ex_stage
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      pc_in         => id_ex_pc,
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
      forward_rs    => open,
      forward_rd    => open,
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

  forward_a <= forward_sel(
    id_ex_rs, ex_mem_rd, ex_mem_reg_write, ex_mem_mem_read,
    mem_wb_rd, mem_wb_reg_write
  );
  forward_b <= forward_sel(
    id_ex_rs2, ex_mem_rd, ex_mem_reg_write, ex_mem_mem_read,
    mem_wb_rd, mem_wb_reg_write
  );

  branch_flush <= ex_branch_taken or id_ex_jump;

  pc_src <= "10" when id_ex_jump = '1' else
            "01" when ex_branch_taken = '1' else
            "00";
  pc_en <= '1';
  branch_target <= ex_branch_target;
  jump_target <= id_ex_addr_target;
  cpu_halt <= '1' when if_id_instr(15 downto 12) = "1111" else '0';

  debug_pc    <= if_pc;
  debug_instr <= if_id_instr;

  -- IF/ID
  if_id_reg : process (clk, rst)
  begin
    if rst = '0' then
      if_id_pc    <= (others => '0');
      if_id_instr <= (others => '0');
    elsif rising_edge(clk) then
      if branch_flush = '1' then
        if_id_pc    <= (others => '0');
        if_id_instr <= (others => '0');
      else
        if_id_pc    <= if_pc;
        if_id_instr <= if_instruction;
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
    elsif rising_edge(clk) then
      if branch_flush = '1' then
        id_ex_reg_write  <= '0';
        id_ex_mem_read   <= '0';
        id_ex_mem_write  <= '0';
        id_ex_mem_to_reg <= '0';
        id_ex_rd_src     <= '0';
        id_ex_alu_op     <= (others => '0');
        id_ex_branch     <= '0';
        id_ex_jump       <= '0';
        id_ex_halt       <= '0';
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
    elsif rising_edge(clk) then
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
    elsif rising_edge(clk) then
      mem_wb_mem_data   <= mem_data;
      mem_wb_alu_result <= mem_alu_result;
      mem_wb_rd         <= mem_rd;
      mem_wb_reg_write  <= mem_reg_write;
      mem_wb_mem_to_reg <= mem_mem_to_reg;
    end if;
  end process mem_wb_reg;

end architecture rtl;
