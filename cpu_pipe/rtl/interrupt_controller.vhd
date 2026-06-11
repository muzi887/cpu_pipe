-- interrupt_controller.vhd
-- CSR：EPC / STATUS.IE / CAUSE；汇总 Timer 中断请求
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interrupt_controller is
  generic (
    ADDR_WIDTH : integer := 16
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

    -- 中断源
    irq_timer : in std_logic;

    -- CPU 读 CSR
    epc_out   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    status_ie : out std_logic;
    cause_out : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

    -- CPU 写 CSR / 响应
    epc_write   : in  std_logic;
    epc_wdata   : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    ie_set      : in  std_logic;
    ie_clear    : in  std_logic;
    cause_write : in  std_logic;
    cause_wdata : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    irq_ack     : in  std_logic;

    irq_pending : out std_logic
  );
end entity interrupt_controller;

architecture rtl of interrupt_controller is
  signal epc_reg    : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal status_reg : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal cause_reg  : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal pending    : std_logic;
begin
  epc_out   <= epc_reg;
  status_ie <= status_reg(0);
  cause_out <= cause_reg;
  irq_pending <= pending;

  csr_proc : process (clk, rst)
  begin
    if rst = '0' then
      epc_reg    <= (others => '0');
      status_reg <= (others => '0');
      cause_reg  <= (others => '0');
      pending    <= '0';
    elsif rising_edge(clk) then
      if irq_timer = '1' then
        pending <= '1';
      end if;

      if irq_ack = '1' then
        pending <= '0';
      end if;

      if epc_write = '1' then
        epc_reg <= epc_wdata;
      end if;

      if cause_write = '1' then
        cause_reg <= cause_wdata;
      end if;

      if ie_set = '1' then
        status_reg(0) <= '1';
      elsif ie_clear = '1' then
        status_reg(0) <= '0';
      end if;
    end if;
  end process csr_proc;
end architecture rtl;
