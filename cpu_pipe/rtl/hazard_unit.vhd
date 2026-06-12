-- hazard_unit.vhd
-- 冒险处理单元：BNE 分支 flush + load-use stall
--
-- load-use：ID/EX 为 LD 且 IF/ID 下一条紧接使用 rd 时
--   Pc_en=0, Ifid_en=0（冻结 PC/IF/ID），Control_src=0（ID/EX 插 bubble）
--   与 BNE flush 不同：load-use 不清 IF/ID（Ifid_src 保持 0）
--
-- BNE：EX 判定 branch_taken 成立时
--   Pc_src=01, Ifid_src=1（IF/ID←NOP）, Control_src=0（ID/EX←bubble）
library ieee;
use ieee.std_logic_1164.all;

entity hazard_unit is
  generic (
    ADDR_WIDTH : integer := 16
  );
  port (
    -- EX 级 BNE 判定
    bne_taken : in std_logic;

    -- load-use 检测：LD 在 EX（ID/EX.MemRead=1），IF/ID 指令使用其 rd
    id_ex_mem_read : in  std_logic;
    id_ex_rd       : in  std_logic_vector(3 downto 0);
    id_ex_valid    : in  std_logic;
    if_id_rs1      : in  std_logic_vector(3 downto 0);
    if_id_rs2      : in  std_logic_vector(3 downto 0);

    -- Hazard 输出
    load_use_stall : out std_logic;
    pc_src         : out std_logic_vector(1 downto 0);
    pc_en          : out std_logic;
    ifid_en        : out std_logic;
    ifid_src       : out std_logic;
    control_src    : out std_logic
  );
end entity hazard_unit;

architecture rtl of hazard_unit is
  signal load_use : std_logic;
begin
  load_use <= '1' when id_ex_mem_read = '1' and id_ex_valid = '1' and
                      id_ex_rd /= "0000" and
                      (id_ex_rd = if_id_rs1 or id_ex_rd = if_id_rs2) else
              '0';

  load_use_stall <= load_use;

  pc_src      <= "01" when bne_taken = '1' and load_use = '0' else "00";
  pc_en       <= '0' when load_use = '1' else '1';
  ifid_en     <= '0' when load_use = '1' else '1';
  ifid_src    <= bne_taken when load_use = '0' else '0';
  control_src <= '0' when load_use = '1' or bne_taken = '1' else '1';
end architecture rtl;
