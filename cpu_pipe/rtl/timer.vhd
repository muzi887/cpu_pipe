-- timer.vhd
-- MMIO Timer：0xFF20 CTRL（本课设：bit0=EN，bit1=重载）；溢出产生 irq_timer
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer is
  generic (
    DATA_WIDTH : integer := 16;
    DEFAULT_PERIOD : integer := 80
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

    addr      : in  std_logic_vector(15 downto 0);
    wdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    write_en  : in  std_logic;
    read_en   : in  std_logic;
    rdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    sel       : in  std_logic;

    irq_timer : out std_logic
  );
end entity timer;

architecture rtl of timer is
  constant ADDR_CTRL   : std_logic_vector(15 downto 0) := x"FF20";
  constant ADDR_PERIOD : std_logic_vector(15 downto 0) := x"FF24";

  signal ctrl_en    : std_logic := '0';
  signal period_reg : unsigned(15 downto 0) := to_unsigned(DEFAULT_PERIOD, 16);
  signal counter    : unsigned(15 downto 0) := (others => '0');
  signal irq_pulse  : std_logic := '0';
begin
  irq_timer <= irq_pulse;

  mmio_proc : process (clk, rst)
  begin
    if rst = '0' then
      ctrl_en    <= '1';
      period_reg <= to_unsigned(DEFAULT_PERIOD, 16);
      counter    <= to_unsigned(DEFAULT_PERIOD, 16);
      irq_pulse  <= '0';
    elsif rising_edge(clk) then
      irq_pulse <= '0';

      if sel = '1' and write_en = '1' then
        if addr = ADDR_CTRL then
          ctrl_en <= wdata(0);
          if wdata(1) = '1' then
            irq_pulse <= '0';
            counter   <= period_reg;
          end if;
        elsif addr = ADDR_PERIOD then
          period_reg <= unsigned(wdata);
          counter    <= unsigned(wdata);
        end if;
      end if;

      if ctrl_en = '1' then
        if counter = 0 then
          irq_pulse <= '1';
          counter   <= period_reg;
        else
          counter <= counter - 1;
        end if;
      end if;
    end if;
  end process mmio_proc;

  rdata <= (0 => ctrl_en, others => '0')
           when sel = '1' and read_en = '1' and addr = ADDR_CTRL else
           std_logic_vector(period_reg)
           when sel = '1' and read_en = '1' and addr = ADDR_PERIOD else
           (others => '0');
end architecture rtl;
