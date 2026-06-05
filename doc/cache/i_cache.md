# `i_cache` 是什么

在你这张图里，**`i_cache` 是 Instruction Cache（指令 Cache，常简称 I-Cache）**，属于 **IF（取指）阶段** 的核心部件。

## 在数据通路中的位置


## 它和主存（RAM）的区别

| 项目 | `i_cache`（I-Cache） | 主存 `main_memory` |
|------|----------------------|---------------------|
| 存什么 | **只存指令** | 指令 + 数据 |
| 谁访问 | **IF 阶段**，用 PC 寻址 | **MEM 阶段**，用 ALU 算出的地址 |
| 速度 | 通常 1 拍命中 | 较慢 |
| 典型接口 | `Addr` → `Inst` | `Addr` ↔ `Data`，带 `MemR/MemW` |

五级流水中：
- **IF** 用 **I-Cache / 指令存储器** 取指  
- **MEM** 用 **D-Cache / 数据存储器** 做 Load/Store  

所以图里的 `i_cache` 只管 **“取指令”**，不管 Load/Store 的数据访问。

## 和你课设的关系

根据你的初期报告，当前设计是：

- **D-Cache**：要实现（数据 Cache）  
- **I-Cache**：**第一版不实现**，IF 仍可直接连 `main_memory` 单周期取指  

因此：

- 教学/通用五级流水图里常画 **`i_cache`**，表示完整 CPU 结构  
- 你若暂未做 I-Cache，可把 `i_cache` **替换成 `instr_mem` 或直接连 `main_memory`**，功能仍是：PC 给地址 → 读出 Inst → 进 IF/ID  

## 一句话

**`i_cache` = 指令 Cache，IF 阶段按 PC 取指令的部件；输出 `Inst` 给 IF/ID。** 有 Cache 时加速取指；没实现时，用主存或独立指令存储器代替即可。