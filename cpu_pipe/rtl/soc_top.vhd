-- soc_top.vhd
-- 最小 SoC 顶层：CPU + 指令/数据存储器
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
      debug_pc     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
      debug_instr  : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

  component instr_memory is
    generic (
      ADDR_WIDTH : integer := 16;
      DATA_WIDTH : integer := 16
    );
    port (
      addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

  component data_memory is
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

  signal instr_addr : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal instr_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_addr   : std_logic_vector(ADDR_WIDTH - 1 downto 0);
  signal mem_wdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_rdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem_read_en  : std_logic;
  signal mem_write_en : std_logic;

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
      debug_pc     => debug_pc,
      debug_instr  => debug_instr
    );

  u_imem : instr_memory
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      addr => instr_addr,
      data => instr_data
    );

  u_dmem : data_memory
    generic map (ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      clk      => clk,
      addr     => mem_addr,
      wdata    => mem_wdata,
      write_en => mem_write_en,
      read_en  => mem_read_en,
      rdata    => mem_rdata
    );

end architecture rtl;
