-- soc_top.vhd
-- SoC 顶层：CPU + I/D Cache + MMIO（Timer/UART/GPIO）+ 共享 main_memory
library ieee;
use ieee.std_logic_1164.all;

entity soc_top is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

    debug_pc          : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    debug_instr       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_epc         : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    debug_irq_pending : out std_logic;
    debug_status_ie   : out std_logic;
    debug_uart_data   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    debug_led         : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity soc_top;

architecture rtl of soc_top is
  component cpu_top is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk               : in  std_logic;
      rst               : in  std_logic;
      instr_addr        : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      instr_data        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_addr          : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      mem_wdata         : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_rdata         : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_read_en       : out std_logic;
      mem_write_en      : out std_logic;
      cache_stall       : in  std_logic;
      irq_timer         : in  std_logic;
      debug_pc          : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      debug_instr       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      debug_epc         : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      debug_irq_pending : out std_logic;
      debug_status_ie   : out std_logic
    );
  end component;

  component i_cache is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      addr        : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      data        : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      i_miss      : out std_logic;
      mem_req     : out std_logic;
      mem_addr    : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      mem_read_en : out std_logic;
      mem_rdata   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_grant   : in  std_logic
    );
  end component;

  component d_cache is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk          : in  std_logic;
      rst          : in  std_logic;
      addr         : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      wdata        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      write_en     : in  std_logic;
      read_en      : in  std_logic;
      rdata        : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      d_miss       : out std_logic;
      cpu_ready    : out std_logic;
      mem_req      : out std_logic;
      mem_addr     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      mem_wdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_read_en  : out std_logic;
      mem_write_en : out std_logic;
      mem_rdata    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      mem_grant    : in  std_logic;
      hit_count    : out std_logic_vector(15 downto 0);
      miss_count   : out std_logic_vector(15 downto 0);
      hit_rate     : out std_logic_vector(7 downto 0)
    );
  end component;

  component main_memory is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      clk      : in  std_logic;
      addr     : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      wdata    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      write_en : in  std_logic;
      read_en  : in  std_logic;
      rdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

  component cache_control is
    port (
      i_miss    : in  std_logic;
      cpu_ready : in  std_logic;
      stall     : out std_logic
    );
  end component;

  component timer is
    generic (
      DATA_WIDTH     : integer := 16;
      DEFAULT_PERIOD : integer := 80
    );
    port (
      clk       : in  std_logic;
      rst       : in  std_logic;
      addr      : in  std_logic_vector(15 downto 0);
      wdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      write_en  : in  std_logic;
      read_en   : in  std_logic;
      rdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      sel       : in  std_logic;
      irq_timer : out std_logic
    );
  end component;

  component uart_mmio is
    generic (DATA_WIDTH : integer := 16);
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      addr     : in  std_logic_vector(15 downto 0);
      wdata    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      write_en : in  std_logic;
      read_en  : in  std_logic;
      rdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      sel      : in  std_logic;
      uart_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

  component gpio_mmio is
    generic (DATA_WIDTH : integer := 16);
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      addr     : in  std_logic_vector(15 downto 0);
      wdata    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      write_en : in  std_logic;
      read_en  : in  std_logic;
      rdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      sel      : in  std_logic;
      led_out  : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

  signal instr_addr : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal instr_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_addr   : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal mem_wdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_rdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_read_en  : std_logic;
  signal mem_write_en : std_logic;

  signal is_mmio      : std_logic;
  signal mmio_addr    : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal mmio_wdata   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mmio_rdata   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mmio_read_en : std_logic;
  signal mmio_write_en : std_logic;

  signal dc_addr      : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal dc_wdata     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal dc_rdata     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal dc_read_en   : std_logic;
  signal dc_write_en  : std_logic;

  signal timer_rdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal uart_rdata   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal gpio_rdata   : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal timer_sel    : std_logic;
  signal uart_sel     : std_logic;
  signal gpio_sel     : std_logic;
  signal irq_timer    : std_logic;

  signal i_miss       : std_logic;
  signal cpu_ready    : std_logic;
  signal cache_stall  : std_logic;

  signal i_mem_req     : std_logic;
  signal i_mem_addr    : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal i_mem_read_en : std_logic;
  signal d_mem_req      : std_logic;
  signal d_mem_addr     : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal d_mem_wdata    : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal d_mem_read_en  : std_logic;
  signal d_mem_write_en : std_logic;

  signal mm_addr      : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal mm_wdata     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mm_rdata     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mm_read_en   : std_logic;
  signal mm_write_en  : std_logic;
  signal i_mem_grant  : std_logic;
  signal d_mem_grant  : std_logic;

begin
  is_mmio <= '1' when mem_addr(15 downto 8) = x"FF" else '0';

  dc_addr      <= mem_addr;
  dc_wdata     <= mem_wdata;
  dc_read_en   <= mem_read_en when is_mmio = '0' else '0';
  dc_write_en  <= mem_write_en when is_mmio = '0' else '0';
  mem_rdata    <= mmio_rdata when is_mmio = '1' else dc_rdata;

  mmio_addr     <= mem_addr;
  mmio_wdata    <= mem_wdata;
  mmio_read_en  <= mem_read_en when is_mmio = '1' else '0';
  mmio_write_en <= mem_write_en when is_mmio = '1' else '0';

  timer_sel <= '1' when is_mmio = '1' and
                         (mmio_addr = x"FF20" or mmio_addr = x"FF24") else '0';
  uart_sel  <= '1' when is_mmio = '1' and
                         (mmio_addr = x"FF00" or mmio_addr = x"FF04") else '0';
  gpio_sel  <= '1' when is_mmio = '1' and mmio_addr = x"FF10" else '0';

  mmio_rdata <= timer_rdata when timer_sel = '1' else
                uart_rdata  when uart_sel = '1'  else
                gpio_rdata  when gpio_sel = '1'  else
                (others => '0');

  u_cpu : cpu_top
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      clk               => clk,
      rst               => rst,
      instr_addr        => instr_addr,
      instr_data        => instr_data,
      mem_addr          => mem_addr,
      mem_wdata         => mem_wdata,
      mem_rdata         => mem_rdata,
      mem_read_en       => mem_read_en,
      mem_write_en      => mem_write_en,
      cache_stall       => cache_stall,
      irq_timer         => irq_timer,
      debug_pc          => debug_pc,
      debug_instr       => debug_instr,
      debug_epc         => debug_epc,
      debug_irq_pending => debug_irq_pending,
      debug_status_ie   => debug_status_ie
    );

  u_icache : i_cache
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      clk         => clk,
      rst         => rst,
      addr        => instr_addr,
      data        => instr_data,
      i_miss      => i_miss,
      mem_req     => i_mem_req,
      mem_addr    => i_mem_addr,
      mem_read_en => i_mem_read_en,
      mem_rdata   => mm_rdata,
      mem_grant   => i_mem_grant
    );

  u_dcache : d_cache
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      clk          => clk,
      rst          => rst,
      addr         => dc_addr,
      wdata        => dc_wdata,
      write_en     => dc_write_en,
      read_en      => dc_read_en,
      rdata        => dc_rdata,
      d_miss       => open,
      cpu_ready    => cpu_ready,
      mem_req      => d_mem_req,
      mem_addr     => d_mem_addr,
      mem_wdata    => d_mem_wdata,
      mem_read_en  => d_mem_read_en,
      mem_write_en => d_mem_write_en,
      mem_rdata    => mm_rdata,
      mem_grant    => d_mem_grant,
      hit_count    => open,
      miss_count   => open,
      hit_rate     => open
    );

  u_timer : timer
    generic map (DATA_WIDTH => DATA_WIDTH, DEFAULT_PERIOD => 80)
    port map (
      clk       => clk,
      rst       => rst,
      addr      => mmio_addr,
      wdata     => mmio_wdata,
      write_en  => mmio_write_en,
      read_en   => mmio_read_en,
      rdata     => timer_rdata,
      sel       => timer_sel,
      irq_timer => irq_timer
    );

  u_uart : uart_mmio
    generic map (DATA_WIDTH => DATA_WIDTH)
    port map (
      clk       => clk,
      rst       => rst,
      addr      => mmio_addr,
      wdata     => mmio_wdata,
      write_en  => mmio_write_en,
      read_en   => mmio_read_en,
      rdata     => uart_rdata,
      sel       => uart_sel,
      uart_data => debug_uart_data
    );

  u_gpio : gpio_mmio
    generic map (DATA_WIDTH => DATA_WIDTH)
    port map (
      clk      => clk,
      rst      => rst,
      addr     => mmio_addr,
      wdata    => mmio_wdata,
      write_en => mmio_write_en,
      read_en  => mmio_read_en,
      rdata    => gpio_rdata,
      sel      => gpio_sel,
      led_out  => debug_led
    );

  i_mem_grant <= '0' when d_mem_read_en = '1' else '1';
  d_mem_grant <= '0' when i_mem_read_en = '1' else '1';

  mm_addr     <= i_mem_addr when i_mem_read_en = '1' else d_mem_addr;
  mm_wdata    <= d_mem_wdata;
  mm_read_en  <= i_mem_read_en when i_mem_read_en = '1' else d_mem_read_en;
  mm_write_en <= d_mem_write_en when d_mem_write_en = '1' and i_mem_read_en = '0' else '0';

  u_main_memory : main_memory
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      clk      => clk,
      addr     => mm_addr,
      wdata    => mm_wdata,
      write_en => mm_write_en,
      read_en  => mm_read_en,
      rdata    => mm_rdata
    );

  u_cache_control : cache_control
    port map (
      i_miss    => i_miss,
      cpu_ready => cpu_ready,
      stall     => cache_stall
    );

end architecture rtl;
