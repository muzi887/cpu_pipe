library verilog;
use verilog.vl_types.all;
entity cpu_fibo_vlg_check_tst is
    port(
        data_from_ram   : in     vl_logic_vector(15 downto 0);
        debug_AC_reg    : in     vl_logic_vector(15 downto 0);
        debug_AX_reg    : in     vl_logic_vector(15 downto 0);
        debug_Bus_Sel   : in     vl_logic_vector(2 downto 0);
        debug_BX_reg    : in     vl_logic_vector(15 downto 0);
        debug_CX_reg    : in     vl_logic_vector(15 downto 0);
        debug_internal_bus: in     vl_logic_vector(15 downto 0);
        debug_IR_reg    : in     vl_logic_vector(15 downto 0);
        debug_LoadPC    : in     vl_logic;
        debug_MAR_reg   : in     vl_logic_vector(15 downto 0);
        debug_MDR_reg   : in     vl_logic_vector(15 downto 0);
        debug_MDR_Sel   : in     vl_logic_vector(1 downto 0);
        debug_PC_next   : in     vl_logic_vector(15 downto 0);
        debug_PC_reg    : in     vl_logic_vector(15 downto 0);
        debug_PC_Sel    : in     vl_logic_vector(1 downto 0);
        debug_PSW_Z_flag_out: in     vl_logic;
        IR_opCode_out   : in     vl_logic_vector(3 downto 0);
        microCommands   : in     vl_logic_vector(31 downto 0);
        nextAddress     : in     vl_logic_vector(4 downto 0);
        sampler_rx      : in     vl_logic
    );
end cpu_fibo_vlg_check_tst;
