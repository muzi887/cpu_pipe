# Forward（转发）是什么？

**Forward（转发）**，也叫 **旁路（Bypass）** 或 **定向技术**，是流水线里解决 **数据相关** 的一种硬件手段：

> **不等到 WB 写回寄存器，就把上一条指令的结果，直接从 EX/MEM 或 MEM/WB 送到当前 EX 阶段 ALU 的输入。**

---

## 1. 要解决什么问题？

流水线里多条指令**同时**在执行：

```asm
ADD  x3, x1, x2    ; ① 算 x3
ADDI2 x2, x3, 0    ; ② 马上要用 x3
```

时间关系：

```text
周期:     3      4      5      6
① ADD:   EX    MEM    WB
② ADDI2:       EX    MEM    WB
                      ↑
                 这里就要用 x3
```

② 在 **EX** 就要 x3 时，① 的 x3 可能还在 **EX/MEM** 或 **MEM/WB**，**还没写进 Registers**。

若只从寄存器堆读 → 读到的是 **旧 x3** → 算错。

---

## 2. Forward 怎么做？

加 **Forward MUX**，给 ALU 选数据来源：

```text
Forward = 00  →  用 ID/EX 读出的 RS/RD（正常）
Forward = 01  →  用 EX/MEM.alu_result（上一条在 MEM）
Forward = 10  →  用 MEM/WB.write_data（上一条在 WB）
```

示意：

```text
① 的 alu_result ──转发──> ② 的 ALU 输入
         ↑
    绕过 Registers，直接送过去
```

这就是 **Forward**：结果从产生处 **向前送** 到需要的地方。

---

## 3. 为什么叫 Forward？

数据在流水线里是 **从左往右** 流动的（IF → ID → EX → MEM → WB）。

正常写回是：EX → MEM → WB → **Registers** → 下一条 ID 再读。

Forward 是 **从右边（后面阶段）绕回到左边 EX**，把结果 **提前** 送给 ALU，所以叫 **向前转发 / 定向**。

---

## 4. 和你图里的对应关系

| 你图里的东西 | 作用 |
|--------------|------|
| **MUXA / MUXB** | Forward MUX，给 ALU 的 A、B 选数据来源 |
| **ForwardA / ForwardB** | 控制信号，选 00/01/10 |
| **EX/MEM.alu_result** | 转发源 1 |
| **MEM/WB.write_data** | 转发源 2 |
| **forwarding_unit** | 检测相关，产生 ForwardA/B |

---

## 5. 什么时候需要 Forward？

**需要：** 后一条在 EX 要用前一条的结果，且前一条还没 WB。

```text
ADD  x3, x1, x2
ADDI2 x2, x3, 0   ← 需要 Forward（x3 从 EX/MEM 转发）
```

**不需要：** 中间隔得够远，WB 已完成，直接从 Registers 读即可。

```text
ADDI x1, 1
... 几条别的指令 ...
ADD  x3, x1, x2   ← 读 x1 时 x1 早已写回，Forward=00
```

---

## 6. Forward 解决不了什么？

**Load-use 必须 Stall：**

```asm
LD   x3, 0(x4)
ADD  x5, x3, x1   ; x3 要到 MEM 末才有，EX 太早
```

Load 的数据 **MEM 阶段末** 才从内存出来，EX 阶段转发不了 → 必须 **stall 1 拍**。

---

## 7. 三种处理方式对比

| 方式 | 做法 | 代价 |
|------|------|------|
| **Forward** | 旁路送 ALU 结果 | 0 周期 |
| **寄存器先写后读** | 同周期 WB 写、ID 读 | 0 周期（仅同拍情况） |
| **Stall** | 停顿等待 | 1+ 周期 |

Forward 是流水线 CPU 里 **最常用、零代价** 的数据相关处理方式。

---

## 8. 一句话

**Forward = 把上一条指令在 EX/MEM 或 MEM/WB 里的结果，直接送给当前 EX 的 ALU，不用等写回寄存器。** 你图里的 MUXA/MUXB + 从 EX/MEM、MEM/WB 绕回来的线，就是在画 Forward。