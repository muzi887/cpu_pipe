## 六、用斐波那契例子走一遍

```asm
ADD  x3, x1, x2      ; ① 上一条
ADDI2 x2, x3, 0      ; ② 当前在 EX，要用 x3
```

② 在 EX 时，① 在 **EX/MEM**：

```text
ID/EX.RS = x3 的编号（ADDI2 里 rs=x3）
EX/MEM.RD = x3
EX/MEM.REGWrite = 1

→ EX/MEM.RD = ID/EX.RS 成立
→ forward_rs = 01
→ ALU 下端用 EX/MEM.alu_result（新的 x3），不用寄存器堆里旧的 x3
```

若 ① 已在 **MEM/WB**、② 才进 EX：

```text
MEM/WB.RD = x3,  ID/EX.RS = x3
→ forward_rs = 10
→ 用 MEM/WB.write_data
```

---

## 七、整条五级数据通路

### 1. IF 取指

```text
PC → i_cache → Inst → IF/ID
PC+1 → IF/ID
```

### 2. ID 译码

```text
Ins[15:8] → Control
Ins[3:0]  → RS_addr → Registers → RS
Ins[7:4]  → RD_addr → Registers → RD
Ins[3:0]  → 扩展 → imm

锁入 ID/EX：
  RS_data, RD_data, RS_addr, RD_addr, imm, rd, 控制信号
```

### 3. EX 执行（核心）

```text
Rs_src：RS 或 imm
Forward_rs MUX → ALU(B)
Forward_rd MUX → ALU(A)
ALU → result → EX/MEM

Forward 块比较地址 → forward_rs, forward_rd
```

### 4. MEM 访存

```text
EX/MEM.alu_result → d_mem 地址
EX/MEM.RS 或 write_data → d_mem 写数据（ST 用）
d_mem 读出 → MEM/WB.mem_data
```

### 5. WB 写回

```text
memtoreg MUX：alu_result 或 mem_data → write_data
MEM/WB.rd → Wr_addr
REGWrite → Reg_w
write_data → Registers
```

### 6. 反馈线（Forward 用）

```text
EX/MEM.alu_result ──绕回──> Forward MUX 上输入
MEM/WB.write_data ──绕回──> Forward MUX 下输入
MEM/WB ──> Registers.writedata（正常写回）
```

---

## 八、一张表总结 Forward

| forward 值 | 含义 | MUX 选哪路 | 数据来源 |
|------------|------|------------|----------|
| **00** | 不转发 | 中间 | ID/EX 正常读（或 Rs_src） |
| **01** | 第一类 | 上面 | **EX/MEM.alu_result** |
| **10** | 第二类 | 下面 | **MEM/WB.write_data** |

| 检测 | forward_rs=01 | forward_rd=01 | forward_rs=10 | forward_rd=10 |
|------|---------------|---------------|---------------|---------------|
| 条件 | EX/MEM 写且 RD=ID/EX.RS | EX/MEM 写且 RD=ID/EX.RD | MEM/WB 写且 RD=ID/EX.RS | MEM/WB 写且 RD=ID/EX.RD |

---

## 九、和参考图对照检查清单

| 参考图元素 | 是否正确理解 |
|------------|--------------|
| Forward_rd MUX → ALU 上 | ✅ |
| Rs_src → Forward_rs → ALU 下 | ✅ |
| EX/MEM 反馈到 MUX **上** | ✅ = forward 01 |
| WB/MEM/WB 反馈到 MUX **下** | ✅ = forward 10 |
| Forward 块接 RS/RD **地址** + REGWrite | ✅ |
| Forward 输出 forward_rs / forward_rd | ✅ |

---

## 十、一句话串起来

```text
ID/EX 带着 RS、RD 寄存器编号和数据进入 EX；
Forward 比较「当前要的 RS/RD」和「前面指令写的 RD」：
  对上了且 EX/MEM 更近 → forward=01，从 EX/MEM 取结果；
  对上了且只在 MEM/WB → forward=10，从 MEM/WB 取结果；
  没对上 → forward=00，正常用 ID/EX 读出的值。
```