-- i_cache.vhd
-- 直接映射 I-Cache：miss 时从 main_memory refill 整行（4 word）
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i_cache is
  generic (
    ADDR_WIDTH : integer := 16;
    DATA_WIDTH : integer := 16;
    NUM_LINES  : integer := 16;
    LINE_WORDS : integer := 4
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    addr  : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    data  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    i_miss : out std_logic;

    mem_req     : out std_logic;
    mem_addr    : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    mem_read_en : out std_logic;
    mem_rdata   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    mem_grant   : in  std_logic
  );
end entity i_cache;

architecture rtl of i_cache is
  constant INDEX_BITS  : integer := 4;
  constant OFFSET_BITS : integer := 2;
  constant TAG_WIDTH    : integer := ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

  type line_t is array (0 to LINE_WORDS - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  type cache_t is array (0 to NUM_LINES - 1) of line_t;
  type tag_array_t is array (0 to NUM_LINES - 1) of std_logic_vector(TAG_WIDTH - 1 downto 0);

  type state_t is (S_IDLE, S_REFILL);

  signal cache_lines : cache_t := (others => (others => (others => '0')));
  signal valid_bits  : std_logic_vector(0 to NUM_LINES - 1) := (others => '0');
  signal tag_bits    : tag_array_t;

  signal state        : state_t := S_IDLE;
  signal refill_index : unsigned(INDEX_BITS - 1 downto 0);
  signal refill_tag   : std_logic_vector(TAG_WIDTH - 1 downto 0);
  signal refill_line  : unsigned(INDEX_BITS - 1 downto 0);
  signal refill_cnt   : unsigned(1 downto 0);

  signal req_index  : unsigned(INDEX_BITS - 1 downto 0);
  signal req_offset : unsigned(OFFSET_BITS - 1 downto 0);
  signal req_tag    : std_logic_vector(TAG_WIDTH - 1 downto 0);
  signal hit        : std_logic;
  signal refill_base : std_logic_vector(ADDR_WIDTH - 1 downto 0);
begin
  req_index  <= unsigned(addr(INDEX_BITS + OFFSET_BITS - 1 downto OFFSET_BITS));
  req_offset <= unsigned(addr(OFFSET_BITS - 1 downto 0));
  req_tag    <= addr(ADDR_WIDTH - 1 downto INDEX_BITS + OFFSET_BITS);

  hit <= '1' when valid_bits(to_integer(req_index)) = '1' and
                  tag_bits(to_integer(req_index)) = req_tag else
         '0';

  refill_base <= refill_tag &
                 std_logic_vector(refill_line) &
                 (OFFSET_BITS - 1 downto 0 => '0');

  data <= cache_lines(to_integer(req_index))(to_integer(req_offset))
          when state = S_IDLE and hit = '1' else
          (others => '0');

  i_miss <= '1' when state = S_REFILL or (state = S_IDLE and hit = '0') else '0';

  mem_req     <= '1' when state = S_REFILL else '0';
  mem_read_en <= '1' when state = S_REFILL and mem_grant = '1' else '0';
  mem_addr    <= std_logic_vector(unsigned(refill_base) + resize(refill_cnt, ADDR_WIDTH))
                 when state = S_REFILL else
                 (others => '0');

  ctrl_proc : process (clk, rst)
    variable idx : integer;
  begin
    if rst = '0' then
      state        <= S_IDLE;
      refill_cnt   <= (others => '0');
      valid_bits   <= (others => '0');
      cache_lines  <= (others => (others => (others => '0')));
    elsif rising_edge(clk) then
      case state is
        when S_IDLE =>
          if hit = '0' then
            refill_line  <= req_index;
            refill_tag   <= req_tag;
            refill_index <= req_index;
            refill_cnt   <= (others => '0');
            state        <= S_REFILL;
          end if;

        when S_REFILL =>
          if mem_grant = '1' then
            idx := to_integer(refill_index);
            cache_lines(idx)(to_integer(refill_cnt)) <= mem_rdata;

            if refill_cnt = to_unsigned(LINE_WORDS - 1, refill_cnt'length) then
              valid_bits(idx) <= '1';
              tag_bits(idx)   <= refill_tag;
              state           <= S_IDLE;
              refill_cnt      <= (others => '0');
            else
              refill_cnt <= refill_cnt + 1;
            end if;
          end if;
      end case;
    end if;
  end process ctrl_proc;

end architecture rtl;
