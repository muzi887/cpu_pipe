-- main_memory
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity main_memory is
	generic(
		ADDR_WIDTH:integer:=16; 				-- 16位地址 -> 2^16 = 65536 个存储位置
		DATA_WIDTH:integer:=16; 				-- 16位数据 (存放指令和数据)
		MICROINSTRUCT_WIDTH:integer:=32 -- 32位微指令
	);
	port(
			clk				 : in 	std_logic;
			addr		   : in  	std_logic_vector(ADDR_WIDTH - 1 downto 0);   -- 地址输入：from MAR
			data_in    : in  	std_logic_vector(DATA_WIDTH - 1 downto 0);   -- 要写入的数据：from MDR	
    	write_en   : in  	std_logic;      --写使能端, '1' 表示在下一个时钟沿写入
			data_out 	 : out 	std_logic_vector(DATA_WIDTH - 1 downto 0)   -- 读出的数据：to MDR	
		);
end entity main_memory;

architecture behav_main_memory of main_memory is
	
	-- 1. 定义RAM的存储阵列类型	
	-- 深度由地址宽度决定
	constant RAM_DEPTH: integer:=2**ADDR_WIDTH; -- ** 是指数运算符（幂运算）
  type ram_array_t is array(0 to RAM_DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

	-- 2. 声明存储阵列 (内存本身)
	-- 声明一个 signal 并使用 ' := ' 语法来赋初始值
	signal memory_array: ram_array_t:=(
		0  => "0000" & x"00B", -- 0: LOAD BX, #11 (立即数11)
		1  => "0001" & x"005", -- 1: LOAD CX, #5 (n-2),计算斐波那契数列第七项 
		2  => "0010000000000000", -- 2: LOOP: MOVE AC,[BX]
		3  => "0100000000000000", -- 3: INC BX
		4  => "0101000000000000", -- 4: MOVE AX, BX
		5  => "0110000000000000", -- 5: ADD AC,[BX]
		6  => "0011000000000000", -- 6: INC AX
		7  => "0111000000000000", -- 7: STORE AC, [AX]
		8  => "1000000000000000", -- 8: DEC CX
		9  => "1001" & x"002", 		-- 9: JNZ LOOP (跳转到地址 2)
		10 => "1010" & x"00A", 		-- 10：HLT(JMP 10, 死循环)
		11 => x"0001", -- 12: f1 = 1 
		12 => x"0001", -- 13: f2 = 1
		-- 13: f3 将被程序写入这里
		-- 14: f4 将被程序写入这里
		-- ...

		-- 将所有其他未定义的内存地址初始化为 0
		others => (others => '0')
	);

	-- 内部信号，用于地址转换
	signal addr_int: integer range 0 to RAM_DEPTH - 1;

begin

	-- 把 std_logic_vector 类型的地址转换为整数，以便数组索引
	addr_int <= to_integer(unsigned(addr));

	-- 3.同步读写逻辑，所有的内存操作都在时钟上升沿发生
	read_write_process: process(clk)
	begin
		if rising_edge(clk) then
		
			-- 写入逻辑（优先级更高）
			-- 如果写使能为高，就把 data_in 的数据写入 addr 指定的位置。
			if write_en = '1' then
				memory_array(addr_int) <= data_in;
			end if;

			-- 读取逻辑
			-- 无论是否写入，data_out都会在时钟沿更新（输出addr_int地址对应的内容）
			data_out <= memory_array(addr_int) ; 	-- 避免内存读写冲突

		end if;
	end process read_write_process;

end architecture behav_main_memory;