library verilog;
use verilog.vl_types.all;
entity cpu_fibo is
    port(
        debug_LoadPC    : out    vl_logic;
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        debug_PSW_Z_flag_out: out    vl_logic;
        data_from_ram   : out    vl_logic_vector(15 downto 0);
        debug_AC_reg    : out    vl_logic_vector(15 downto 0);
        debug_AX_reg    : out    vl_logic_vector(15 downto 0);
        debug_Bus_Sel   : out    vl_logic_vector(2 downto 0);
        debug_BX_reg    : out    vl_logic_vector(15 downto 0);
        debug_CX_reg    : out    vl_logic_vector(15 downto 0);
        debug_internal_bus: out    vl_logic_vector(15 downto 0);
        debug_IR_reg    : out    vl_logic_vector(15 downto 0);
        debug_MAR_reg   : out    vl_logic_vector(15 downto 0);
        debug_MDR_reg   : out    vl_logic_vector(15 downto 0);
        debug_MDR_Sel   : out    vl_logic_vector(1 downto 0);
        debug_PC_next   : out    vl_logic_vector(15 downto 0);
        debug_PC_reg    : out    vl_logic_vector(15 downto 0);
        debug_PC_Sel    : out    vl_logic_vector(1 downto 0);
        IR_opCode_out   : out    vl_logic_vector(3 downto 0);
        microCommands   : out    vl_logic_vector(31 downto 0);
        nextAddress     : out    vl_logic_vector(4 downto 0)
    );
end cpu_fibo;
