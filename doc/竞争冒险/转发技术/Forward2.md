
![[attachments/Pasted image 20260602171017.png]]

**Forward 块**：

1. **判断**要不要转发（比较寄存器编号）
2. **输出** `forward_rs`、`forward_rd`，**控制**两个 MUX 选哪一路

---

## EX 阶段

```text
ID/EX
  │
  ├─ RS ──> Rs_src MUX ──┐
  │         (选 RS/imm)   │
  └─ RD ──────────────────┼──> Forward_rd MUX ──> ALU 上端(A)
                          │
                          └──> Forward_rs MUX ──> ALU 下端(B)

EX/MEM 的 alu_result ──> 两个 Forward MUX 的【上输入】  (forward=01)
MEM/WB 的 write_data ──> 两个 Forward MUX 的【下输入】  (forward=10)
ID/EX 正常数据     ──> 两个 Forward MUX 的【中输入】  (forward=00)
```

**Rs_src 在 Forward_rs 前面**：先决定用 RS 还是 imm，再决定要不要用转发值覆盖。


```text
Rs_src = 0  →  选 ID/EX.RS
Rs_src = 1  →  选 imm（立即数）
```

---

## Forward 块

### 输入（只用于**比较**，不是 ALU 数据）

```text
来自 ID/EX：
  ID/EX.RS   ← 当前指令要用的源寄存器编号（Ins[3:0] 锁存）
  ID/EX.RD   ← 当前指令要用的另一寄存器编号（Ins[7:4] 锁存）

来自 EX/MEM：
  EX/MEM.RD       ← 上一条指令要写哪个寄存器
  EX/MEM.REGWrite ← 上一条要不要写寄存器

来自 MEM/WB：
  MEM/WB.RD       ← 再前一条要写哪个寄存器
  MEM/WB.REGWrite ← 再前一条要不要写寄存器
```

### 输出（控制信号）

```text
forward_rs  →  Forward_rs MUX 的选择端
forward_rd  →  Forward_rd MUX 的选择端
```

**数据**不经过 Forward 块：  
`EX/MEM.alu_result`、`MEM/WB.write_data` 是**直接连到 MUX 上/下输入**的；Forward 块只发“选谁”的命令。

---

```
				┌─── 控制（2 bit）─── forward_rs ──> MUX 选择端
				│
Forward 块 <── 地址比较 ── ID/EX.RS_addr
		<── EX/MEM.RD, REGWrite
		<── MEM/WB.RD, REGWrite
				┌─── 数据（16 bit）─── EX/MEM.alu_result ──> MUX 上输入
				│
				├─── RS_data ──────────────────────────> MUX 中输入
				│
				└─── MEM/WB.write_data ────────────────> MUX 下输入
						│
						v
						ALU（运算用的仍是 16 位操作数）
```

- 控制：forward_rs → 「选上/中/下哪一路」
- 数据：选出来的 16 位数 → 进 ALU

### Forward 比较寄存器编号

当前指令在 EX，需要：

ID/EX.RS_addr = 1
ID/EX.RD_addr = 2

上一条在 EX/MEM，要写：

EX/MEM.RD = 3
EX/MEM.REGWrite = 1

比较：

EX/MEM.RD(3) == ID/EX.RS_addr(1) ? 否
EX/MEM.RD(3) == ID/EX.RD_addr(2) ? 否

→ 没有相关 → forward_rs = 00, forward_rd = 00

→ MUX 选中间：正常用 RS_data=5, RD_data=8

---

### 第一类：forward = 01（从 EX/MEM 转发）

**条件 1：**

```text
IF (EX/MEM.REGWrite = 1  AND  EX/MEM.RD = ID/EX.RS)
   forward_rs = 01
```

**含义：**

- 上一条（在 EX/MEM）要写寄存器 `EX/MEM.RD`
- 当前这条在 EX 需要的 **RS 编号** 正好是这个寄存器
- → ALU **下端**不用 ID/EX 里的旧 RS，改用 **EX/MEM.alu_result**

**条件 2：**

```text
IF (EX/MEM.REGWrite = 1  AND  EX/MEM.RD = ID/EX.RD)
   forward_rd = 01
```

**含义：**

- 当前 EX 需要的 **RD 编号** 等于上一条的目标寄存器
- → ALU **上端**改用 **EX/MEM.alu_result**

**转发来源：** MUX 的 **上输入** = `EX/MEM.alu_result`

> 文字里写「转发 EX/MEM.RD」容易误解：  
> **RD 是地址（编号），转发的是 EX/MEM 里的运算结果 alu_result。**

---

### 第二类：forward = 10（从 MEM/WB 转发）

**条件 1：**

```text
IF (MEM/WB.REGWrite = 1  AND  MEM/WB.RD = ID/EX.RS)
   forward_rs = 10
```

**条件 2：**

```text
IF (MEM/WB.REGWrite = 1  AND  MEM/WB.RD = ID/EX.RD)
   forward_rd = 10
```

（你原文第二条误写成 `EX/MEM.REGWrite`，应为 **`MEM/WB.REGWrite`**。）

**含义：** 上一条结果已到 WB，但还没写进 Registers（或同拍来不及），从 **MEM/WB.write_data** 转发。

**转发来源：** MUX 的 **下输入** = `MEM/WB.write_data`

---

### 优先级（两类同时成立时）

```text
第一类 (01) 优先于 第二类 (10)
```

因为 **EX/MEM 更近、数据更新**。  
若 `EX/MEM.RD = ID/EX.RS` 且 `MEM/WB.RD = ID/EX.RS` 同时成立 → 选 **01**，用 EX/MEM 的结果。

---



