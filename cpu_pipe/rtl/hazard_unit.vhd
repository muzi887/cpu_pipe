-- hazard_unit.vhd
-- 冒险处理单元（当前仅实现 BNE 分支 flush）
--
-- BNE 在 EX 阶段判定 branch_taken；成立时冲刷误取指：
--   Pc_src       = 01  → PC ← branch_target
--   Ifid_src     = 1   → MUX 选 0（IF/ID 指令 ← NOP）
--   Control_src  = 0   → MUX 选 bubble（ID/EX 控制 ← 全 0）
--   Pc_en        = 1
--   Ifid_en      = 1
library ieee;
use ieee.std_logic_1164.all;

entity hazard_unit is
  generic (
    ADDR_WIDTH : integer := 16
  );
  port (
    -- EX 级 BNE 判定：branch_taken = Branch AND (rs1 ≠ rs2)
    bne_taken : in std_logic;

    -- Hazard 输出
    pc_src      : out std_logic_vector(1 downto 0);  -- 00: PC+1, 01: branch_target
    pc_en       : out std_logic;                      -- 1: 允许更新 PC
    ifid_en     : out std_logic;                      -- 1: 允许更新 IF/ID
    ifid_src    : out std_logic;                      -- 0: Inst, 1: 0（NOP）
    control_src : out std_logic                       -- 0: bubble, 1: ID 正常控制
  );
end entity hazard_unit;

architecture rtl of hazard_unit is
begin
  -- 默认（BNE 不成立 / 无 BNE）
  pc_src      <= "01" when bne_taken = '1' else "00";
  pc_en       <= '1';
  ifid_en     <= '1';
  ifid_src    <= bne_taken;
  control_src <= '0' when bne_taken = '1' else '1';
end architecture rtl;
