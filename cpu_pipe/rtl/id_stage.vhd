-- id_stage.vhd
-- ID 译码阶段：字段拆分、寄存器堆读写、立即数扩展、控制信号产生
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity id_stage is
  generic (
    DATA_WIDTH : integer := 16
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;

    instruction : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    pc_in       : in  std_logic_vector(15 downto 0);

    -- register file write interface from WB stage
    wr_en       : in  std_logic;
    wr_addr     : in  std_logic_vector(3 downto 0);
    wr_data     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- register file debug / external observation
    rs_addr     : out std_logic_vector(3 downto 0);
    rd_addr     : out std_logic_vector(3 downto 0);
    rs          : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd          : out std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- to ID/EX pipeline register
    pc_out      : out std_logic_vector(15 downto 0);
    rs_out      : out std_logic_vector(3 downto 0);
    rs2_out     : out std_logic_vector(3 downto 0);
    rd_out      : out std_logic_vector(3 downto 0);
    rs_val      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_val      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    imm_ext     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    addr_target : out std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- control signals (ID 产生，向后级流水传递)
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
end entity id_stage;

architecture rtl of id_stage is
  type reg_array_t is array (0 to 15) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal opcode    : std_logic_vector(3 downto 0);
  signal rs_field  : std_logic_vector(3 downto 0);
  signal rs2_field : std_logic_vector(3 downto 0);
  signal rd_field  : std_logic_vector(3 downto 0);
  signal imm6      : std_logic_vector(5 downto 0);
  signal funct3    : std_logic_vector(2 downto 0);
  signal regs      : reg_array_t;
  signal rs_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rs2_data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rd_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal op2_data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal imm_ext_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal jump_target_data : std_logic_vector(DATA_WIDTH - 1 downto 0);

  -- 写优先读：WB 同拍写、ID 同拍读同一寄存器时，读口直接返回 wb_data，
  -- 保证锁入 ID/EX 的操作数为最新值；与 EX 阶段转发互补（转发管流水寄存器里的生产者）。
  function reg_read_write_first (
    addr      : std_logic_vector(3 downto 0);
    wr_en_i   : std_logic;
    wr_addr_i : std_logic_vector(3 downto 0);
    wr_data_i : std_logic_vector(DATA_WIDTH - 1 downto 0);
    regs_i    : reg_array_t
  ) return std_logic_vector is
    variable zero_v : std_logic_vector(wr_data_i'length - 1 downto 0);
  begin
    if addr = "0000" then
      zero_v := (others => '0');
      return zero_v;
    elsif wr_en_i = '1' and wr_addr_i /= "0000" and wr_addr_i = addr then
      return wr_data_i;
    else
      return regs_i(to_integer(unsigned(addr)));
    end if;
  end function reg_read_write_first;
begin
  opcode    <= instruction(15 downto 12);

  -- 编码：
  -- R 型: | opcode(4) | rs1(3) | rs2(3) | rd(3) | funct(3) | 0001
  -- I 型: | opcode(4) | rs1(3) | rd(3)  | imm(6)          | 0000, 0010, 1110
  -- S/B型:| opcode(4) | rs1(3) | rs2(3) | offset(6)       | 0011, 0100
  -- J 型: | opcode(4) | target(12)                      | 0101
  -- Registers 使用 4 位地址，这里把 3 位寄存器号高位补 0。
  rs_field  <= '0' & instruction(11 downto 9)
               when opcode = "0000" or opcode = "0001" or opcode = "0010" or
                    opcode = "0011" or opcode = "0100" or opcode = "1110" else
               (others => '0');
  rs2_field <= '0' & instruction(8 downto 6)
               when opcode = "0001" or opcode = "0011" or opcode = "0100" else
               (others => '0');
  rd_field  <= '0' & instruction(8 downto 6)
               when opcode = "0000" or opcode = "0010" else
               '0' & instruction(5 downto 3)
               when opcode = "0001" else
               (others => '0');
  imm6     <= instruction(5 downto 0);
  funct3    <= instruction(2 downto 0);

  reg_file_write : process (clk, rst)
  begin
    if rst = '0' then
      regs <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if wr_en = '1' and wr_addr /= "0000" then
        regs(to_integer(unsigned(wr_addr))) <= wr_data;
      end if;
    end if;
  end process reg_file_write;

  -- x0 恒为 0；组合读 + 写优先，支持 WB 与 ID 同拍访问同一寄存器。
  rs_data  <= reg_read_write_first(rs_field, wr_en, wr_addr, wr_data, regs);
  rs2_data <= reg_read_write_first(rs2_field, wr_en, wr_addr, wr_data, regs);
  rd_data  <= reg_read_write_first(rd_field, wr_en, wr_addr, wr_data, regs);

  op2_data <= rs2_data when opcode = "0001" or opcode = "0011" or opcode = "0100" else
              rd_data;

  pc_out  <= pc_in;
  rs_out  <= rs_field;
  rs2_out <= rs2_field;
  rd_out  <= rd_field;
  rs_val  <= rs_data;
  rd_val  <= op2_data;

  rs_addr <= rs_field;
  rd_addr <= rs2_field when opcode = "0001" or opcode = "0011" or opcode = "0100" else rd_field;
  rs      <= rs_data;
  rd      <= op2_data;

  imm_ext_data <= std_logic_vector(resize(signed(imm6), DATA_WIDTH));
  jump_target_data <= std_logic_vector(resize(unsigned(instruction(11 downto 0)), DATA_WIDTH));

  imm_ext <= imm_ext_data;

  -- ID 阶段专用地址 ALU：提前计算 J/BNE 的目标地址。
  addr_target <= jump_target_data
                 when opcode = "0101" else
                 std_logic_vector(resize(signed(pc_in), DATA_WIDTH) + signed(imm_ext_data))
                 when opcode = "0100" else
                 (others => '0');

  control_decode : process (opcode, funct3)
  begin
    reg_write  <= '0';
    mem_read   <= '0';
    mem_write  <= '0';
    mem_to_reg <= '0';
    rd_src     <= '0';
    alu_op     <= "000";
    branch     <= '0';
    jump       <= '0';
    halt       <= '0';
    sys_ei     <= '0';
    sys_di     <= '0';
    sys_iret   <= '0';

    case opcode is
      when "0000" => -- ADDI
        reg_write <= '1';
        rd_src    <= '1';
        alu_op    <= "000";

      when "0001" => -- ADD / SUB
        reg_write <= '1';
        rd_src    <= '0';
        alu_op    <= funct3;

      when "0010" => -- LD
        reg_write  <= '1';
        mem_read   <= '1';
        mem_to_reg <= '1';
        rd_src     <= '1';
        alu_op     <= "000";

      when "0011" => -- ST
        mem_write <= '1';
        rd_src    <= '1';
        alu_op    <= "000";

      when "0100" => -- BNE
        branch  <= '1';
        rd_src  <= '0';

      when "0101" => -- J
        jump <= '1';

      when "1110" => -- SYS: EI / DI / IRET
        case funct3 is
          when "000" => sys_ei   <= '1';
          when "001" => sys_di   <= '1';
          when "010" => sys_iret <= '1';
          when others => null;
        end case;

      when "1111" => -- HALT
        halt <= '1';

      when others =>
        null;
    end case;
  end process control_decode;
end architecture rtl;
