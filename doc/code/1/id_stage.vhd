-- id_stage.vhd: ID 译码阶段：字段拆分、立即数扩展、控制信号产生、寄存器读地址
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity id_stage is
  generic(
    ADDR_WIDTH: integer := 16;
    DATA_WIDTH: integer := 16
  );
  port(
    clk             : in  std_logic;
    rst             : in  std_logic;

    instruction_in : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    pc_in          : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
    
    -- register file write interface from WB stage
    wr_en          : in std_logic;
    wr_addr        : in std_logic_vector(3 downto 0); -- 寄存器地址宽度为 3 位（8 个寄存器）
    wr_data        : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    
    -- register file debug / external observation
    rs_addr        : out std_logic_vector(3 downto 0);
    rd_addr        : out std_logic_vector(3 downto 0);
    rs             : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd             : out std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- to ID/EX pipeline register
    pc_out         : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    rs_out         : out std_logic_vector(3 downto 0);
    rd_out         : out std_logic_vector(3 downto 0);
    rs_val         : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_val         : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    imm_ext        : out std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- control signals (ID 产生，向后级流水传递)
    reg_write      : out std_logic;
    mem_read       : out std_logic;
    mem_write      : out std_logic;
    mem_to_reg     : out std_logic;
    alu_src        : out std_logic;
    alu_op         : out std_logic_vector(2 downto 0);
    branch         : out std_logic;
    jump           : out std_logic;
    halt           : out std_logic
  );
end entity id_stage;

architecture rtl of id_stage is
  type reg_array_t is array (0 to 15) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  
  signal opcode    : std_logic_vector(3 downto 0);
  signal rs_field  : std_logic_vector(3 downto 0);
  signal rd_field  : std_logic_vector(3 downto 0);
  signal imm6      : std_logic_vector(5 downto 0);
  signal funct3    : std_logic_vector(2 downto 0);
  
  signal regs      : reg_array_t;
  signal rs_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rd_data   : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  opcode <= instruction_in(15 downto 12);

  -- 编码：
  -- R 型: | opcode(4) | rs1(3) | rs2(3) | rd(3) | funct(3) |
  -- I 型: | opcode(4) | rs1(3) | rd(3)  | imm(6)          |
  -- S/B型:| opcode(4) | rs1(3) | rs2(3) | offset(6)       |
  -- Registers 使用 4 位地址，这里把 3 位寄存器号高位补 0。
  rs_field <= '0' & instruction(11 downto 9);
  rd_field <= '0' & instruction(8 downto 6) when opcode = "0000" or opcode = "0010" else
              '0' & instruction(5 downto 3);
  imm6     <= instruction(5 downto 0);
  funct3    <= instruction(2 downto 0);

  reg_file_write: process(clk, rst)
  begin
    if rst = '0' then 
      regs <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if wr_en = '1' and wr_addr /= "0000" then
        regs(to_integer(unsigned(wr_addr))) <= wr_data;
      end if;
    end if;
  end process reg_file_write;

  -- x0 寄存器始终为 0；读端口为组合读，方便 ID 阶段同拍取得 RS/RD。
  rs_data <= (others => '0') when rs_field = "0000" else regs(to_integer(unsigned(rs_field)));
  rd_data <= (others => '0') when rd_field = "0000" else regs(to_integer(unsigned(rd_field)));

  pc_out <= pc_in;
  rs_out <= rs_field;
  rd_out <= rd_field;
  rs_val <= rs_data;
  rd_val <= rd_data;  

  rs_addr <= rs_field;
  rd_addr <= rd_field;
  rs <= rs_data;
  rd <= rd_data;

  imm_ext <= std_logic_vector(resize(signed(imm6), DATA_WIDTH));
  
  control_decode : process (opcode, funct3)
  begin
    reg_write  <= '0';
    mem_read   <= '0';
    mem_write  <= '0';
    mem_to_reg <= '0';
    alu_src    <= '0';
    alu_op     <= "000";
    branch     <= '0';
    jump       <= '0';
    halt       <= '0';

    case opcode is
      when "0000" => -- ADDI
        reg_write <= '1';
        alu_src   <= '1';
        alu_op    <= "000";

      when "0001" => -- ADD / SUB
        reg_write <= '1';
        alu_src   <= '0';
        alu_op    <= funct3;

      when "0010" => -- LD
        reg_write  <= '1';
        mem_read   <= '1';
        mem_to_reg <= '1';
        alu_src    <= '1';
        alu_op     <= "000";

      when "0011" => -- ST
        mem_write <= '1';
        alu_src   <= '1';
        alu_op    <= "000";

      when "0100" => -- BNE
        branch  <= '1';
        alu_src <= '0';

      when "0101" => -- J
        jump <= '1';

      when "1111" => -- HALT
        halt <= '1';

      when others =>
        null;
    end case;
  end process control_decode;
end architecture rtl;
