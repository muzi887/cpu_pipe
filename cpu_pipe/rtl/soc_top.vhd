-- soc_top.vhd

-- SoC 顶层：CPU + i_cache + d_cache + 共享 main_memory

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



    debug_pc    : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

    debug_instr : out std_logic_vector(DATA_WIDTH - 1 downto 0)

  );

end entity soc_top;



architecture rtl of soc_top is

  component cpu_top is

    generic (

      ADDR_WIDTH : integer := 16;

      DATA_WIDTH : integer := 16

    );

    port (

      clk          : in  std_logic;

      rst          : in  std_logic;

      instr_addr   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

      instr_data   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

      mem_addr     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

      mem_wdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0);

      mem_rdata    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

      mem_read_en  : out std_logic;

      mem_write_en : out std_logic;

      cache_stall  : in  std_logic;

      debug_pc     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);

      debug_instr  : out std_logic_vector(DATA_WIDTH - 1 downto 0)

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

      mem_grant    : in  std_logic

    );

  end component;



  component main_memory is

    generic (

      ADDR_WIDTH : integer := 16;

      DATA_WIDTH : integer := 16

    );

    port (

      clk       : in  std_logic;

      addr      : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);

      wdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);

      write_en  : in  std_logic;

      read_en   : in  std_logic;

      rdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0)

    );

  end component;



  component cache_control is

    port (

      i_miss    : in  std_logic;

      cpu_ready : in  std_logic;

      stall     : out std_logic

    );

  end component;



  signal instr_addr : std_logic_vector(ADDR_WIDTH - 1 downto 0);

  signal instr_data : std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal mem_addr   : std_logic_vector(ADDR_WIDTH - 1 downto 0);

  signal mem_wdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal mem_rdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal mem_read_en  : std_logic;

  signal mem_write_en : std_logic;



  signal i_miss       : std_logic;

  signal d_miss       : std_logic;

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

  u_cpu : cpu_top

    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)

    port map (

      clk          => clk,

      rst          => rst,

      instr_addr   => instr_addr,

      instr_data   => instr_data,

      mem_addr     => mem_addr,

      mem_wdata    => mem_wdata,

      mem_rdata    => mem_rdata,

      mem_read_en  => mem_read_en,

      mem_write_en => mem_write_en,

      cache_stall  => cache_stall,

      debug_pc     => debug_pc,

      debug_instr  => debug_instr

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

      addr         => mem_addr,

      wdata        => mem_wdata,

      write_en     => mem_write_en,

      read_en      => mem_read_en,

      rdata        => mem_rdata,

      d_miss       => d_miss,

      cpu_ready    => cpu_ready,

      mem_req      => d_mem_req,

      mem_addr     => d_mem_addr,

      mem_wdata    => d_mem_wdata,

      mem_read_en  => d_mem_read_en,

      mem_write_en => d_mem_write_en,

      mem_rdata    => mm_rdata,

      mem_grant    => d_mem_grant

    );



  -- 总线授权：仅对方在读主存时暂停本侧 refill
  i_mem_grant <= '0' when d_mem_read_en = '1' else '1';
  d_mem_grant <= '0' when i_mem_read_en = '1' else '1';

  -- 主存仲裁：I-Cache 读优先；D-Cache 写可在 I-Cache 不读时进行
  mm_addr     <= i_mem_addr     when i_mem_read_en = '1' else d_mem_addr;
  mm_wdata    <= d_mem_wdata;
  mm_read_en  <= i_mem_read_en  when i_mem_read_en = '1' else d_mem_read_en;
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

