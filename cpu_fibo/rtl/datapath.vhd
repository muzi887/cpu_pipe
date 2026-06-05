-- datapath.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity datapath is
  generic(
    ADDR_WIDTH:integer:=16;         -- 地址宽度
    DATA_WIDTH:integer:=16; 				-- 16位数据 (存放指令和数据)
		MICROINSTRUCT_WIDTH:integer:=32 -- 32位微指令
  );
  port(
    clk: in std_logic;
    rst: in std_logic;

    -- micro-instruction 
    microCommands:  in std_logic_vector(MICROINSTRUCT_WIDTH - 1 downto 0);
    -- main memory interface
    data_from_ram:  in std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- debug signals
    debug_LoadPC      : out std_logic;
    debug_PC_reg      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_AX_reg      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_BX_reg      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_CX_reg      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_Bus_Sel     : out std_logic_vector(2 downto 0);
    debug_internal_bus: out std_logic_vector(DATA_WIDTH - 1 downto 0);

    -- states back to microController 
    IR_opCode_out     : out std_logic_vector(3 downto 0); -- 10 instructions
    PSW_Z_flag_out    : out std_logic;
    -- memory signals
    address_to_ram    : out std_logic_vector(ADDR_WIDTH - 1 downto 0); -- debug_MAR_reg
    data_to_ram       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    ram_write_en      : out std_logic;
    debug_PC_next     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_PC_Sel      : out std_logic_vector(1 downto 0);    
    debug_AC_reg      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_MDR_Sel     : out std_logic_vector(1 downto 0);    
    debug_IR_reg      : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity datapath;

architecture behav_datapath of datapath is
  -- 1. alias 映射:定义微指令信号别名
  alias LoadPC      : std_logic is microCommands(31);
  alias LoadMAR     : std_logic is microCommands(30);
  alias LoadMDR     : std_logic is microCommands(29);
  alias LoadIR      : std_logic is microCommands(28);
  alias LoadAC      : std_logic is microCommands(27);
  alias LoadPSW     : std_logic is microCommands(26);
  alias LoadAX      : std_logic is microCommands(25);
  alias LoadBX      : std_logic is microCommands(24);
  alias LoadCX      : std_logic is microCommands(23);
  alias IncAX       : std_logic is microCommands(22);
  alias IncBX       : std_logic is microCommands(21);
  alias DecCX       : std_logic is microCommands(20);
  alias MemW        : std_logic is microCommands(19);
  
  alias Bus_Sel     : std_logic_vector(2 downto 0) is microCommands(18 downto 16);
  alias PC_Sel      : std_logic_vector(1 downto 0) is microCommands(15 downto 14);
  alias MDR_Sel     : std_logic_vector(1 downto 0) is microCommands(13 downto 12);
  alias AC_Sel      : std_logic_vector(1 downto 0) is microCommands(11 downto 10);
  alias ALU_op      : std_logic_vector(2 downto 0) is microCommands(9 downto 7);
  alias SHIFT       : std_logic_vector(1 downto 0) is microCommands(6 downto 5);
  alias NextAddress : std_logic_vector(4 downto 0) is microCommands(4 downto 0);

  -- 2.声明所有寄存器
  signal PC_reg,PC_next     : unsigned(ADDR_WIDTH - 1 downto 0);
  signal PC_incremented     : unsigned(ADDR_WIDTH - 1 downto 0); 
  signal MAR_reg            : unsigned(ADDR_WIDTH - 1 downto 0);
  signal MDR_reg, MDR_next  : unsigned(DATA_WIDTH - 1 downto 0);
  signal IR_reg             : unsigned(DATA_WIDTH - 1 downto 0); 
  signal AC_reg, AC_next    : unsigned(DATA_WIDTH - 1 downto 0);
  signal PSW_Z_flag         : std_logic;
  signal AX_reg             : unsigned(DATA_WIDTH - 1 downto 0); 
  signal BX_reg             : unsigned(DATA_WIDTH - 1 downto 0);
  signal CX_reg             : unsigned(DATA_WIDTH - 1 downto 0);
  signal CX_Z_flag          : std_logic;

  -- 3.声明ALU和总线信号
  signal ALU_A              : unsigned(DATA_WIDTH - 1 downto 0);
  signal ALU_B              : unsigned(DATA_WIDTH - 1 downto 0);
  signal ALU_out            : unsigned(DATA_WIDTH - 1 downto 0);
  signal internal_bus       : unsigned(DATA_WIDTH - 1 downto 0); 
  signal IR_Operand_Ext     : unsigned(DATA_WIDTH - 1 downto 0); -- 立即数（12位）零扩展到 16 位

begin

  -- 提取 IR_reg(11 downto 0) (12位操作数/立即数) 并零扩展到 16 位
  -- resize 函数可以自动进行零扩展，从 12 位扩展到 16 位 (DATA_WIDTH)
  IR_Operand_Ext <= resize(IR_reg(11 downto 0),DATA_WIDTH);

  -- 3.总线驱动/仲裁逻辑（内部总线MUX）
  with Bus_Sel select
    internal_bus <= PC_reg    when "000",
                    MDR_reg   when "001",
                    IR_reg    when "010",
                    AC_reg    when "011",
                    AX_reg    when "100",
                    BX_reg    when "101",
                    CX_reg    when "110",
                    IR_Operand_Ext when "111",
                    (others => '0') when others;

  -- 4.寄存器时序逻辑
  Reg_Process: process(clk,rst)
  begin
    if rst = '0' then 
      PC_reg  <= (others => '0');
      MAR_reg <= (others => '0');
      MDR_reg <= (others => '0');
      IR_reg <=  (others => '0');
      AC_reg <=  (others => '0');
      AX_reg <=  (others => '0');
      BX_reg <=  (others => '0');
      CX_reg <=  (others => '0');
    elsif rising_edge(clk) then
      if LoadPC   = '1'   then PC_reg <= PC_next; end if;
      if LoadMAR  = '1'   then MAR_reg <= internal_bus; end if;
      if LoadMDR  = '1'   then MDR_reg <= MDR_next; end if;
      if LoadIR   = '1'   then IR_reg <= internal_bus; end if; -- from RAM
      if LoadAC   = '1'   then AC_reg <= AC_next; end if;
      if LoadPSW  = '1'   then PSW_Z_flag <= CX_Z_flag; end if;
      if LoadAX   = '1'   then 
        AX_reg <= internal_bus; 
      elsif IncAX = '1'   then
        AX_reg <= AX_reg + 1;
      end if;
      if LoadBX   = '1'   then 
        BX_reg <= internal_bus; 
      elsif IncBX = '1'   then
        BX_reg <= BX_reg + 1; 
      end if;
      if LoadCX   = '1'   then 
        CX_reg <= internal_bus; 
      elsif DecCX = '1'   then
        CX_reg <= CX_reg - 1; 
      end if;
    end if;
  end process Reg_Process; 
  CX_Z_flag <= '1' when CX_reg = 0 else '0';

  -- 5.组合逻辑

  -- PC_Sel: 根据PC_Sel选择PC_next
  -- PC_incremented <= PC_reg + 1; 
  with PC_Sel select
  PC_next <= internal_bus             when "01",
             PC_reg + 1               when "10", --  PC + 1 
             PC_reg                   when "00", -- default:stay  
             PC_reg                   when others; 

  -- MDR_Sel 的逻辑 
  with MDR_Sel select
    MDR_next <= internal_bus when "01",      -- 从总线加载 
                unsigned(data_from_ram) when "10",      -- 从 RAM 加载 (f3,f4,...)
                (others => '0')       when others;

  -- AC_Sel: 根据AC_Sel选择AC_next
  with AC_Sel select
  AC_next <= internal_bus when "01",      -- 从总线加载 
             ALU_out                when "10",      -- 从 ALU 加载 
             (others => '0')        when others;

 
  -- ALU 组合逻辑（支持 ADD, SUB, AND，可扩展）
  ALU_A <= AC_reg;
  ALU_B <= internal_bus;
  ALU_Logic: process(ALU_A, ALU_B, ALU_op)
  begin
    case ALU_op is
      when "000" => -- ADD
        ALU_out <= ALU_A + ALU_B;
      when "001" => -- SUB
        ALU_out <= ALU_A - ALU_B;
      when "010" => -- AND
        ALU_out <= ALU_A AND ALU_B;
      when others =>
        ALU_out <= (others => '0');
    end case;
  end process ALU_Logic;
            
  -- 6.连接输出
  -- 将内部信号连接到实体端口
  address_to_ram <= std_logic_vector(MAR_reg); -- debug_MAR_reg
  data_to_ram    <= std_logic_vector(MDR_reg); -- debug_MDR_reg
  ram_write_en   <= MemW;

  -- 把状态反馈给控制器 microController
  IR_opCode_out  <= std_logic_vector(IR_reg(15 downto 12));
  PSW_Z_flag_out <= PSW_Z_flag; 

  -- debug signals
  debug_MDR_Sel       <= MDR_Sel;
  debug_LoadPC        <= std_logic(LoadPC);
  debug_PC_reg        <= std_logic_vector(PC_reg);
  debug_AX_reg        <= std_logic_vector(AX_reg);
  debug_BX_reg        <= std_logic_vector(BX_reg);
  debug_CX_reg        <= std_logic_vector(CX_reg);
  debug_Bus_Sel       <= std_logic_vector(Bus_Sel);
  debug_internal_bus  <= std_logic_vector(internal_bus);
  debug_PC_next       <= std_logic_vector(PC_next);
  debug_PC_Sel        <= std_logic_vector(PC_Sel);
  debug_AC_reg        <= std_logic_vector(AC_reg);
  debug_IR_reg        <= std_logic_vector(IR_reg);

end architecture behav_datapath;