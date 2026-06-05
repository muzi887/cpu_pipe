
|来源|典型信号|什么时候为 1|
|---|---|---|
|i_cache（取指）|`i_miss`|PC 指向的指令不在 I-Cache 里，要去主存读|
|d_cache（访存）|`d_miss`|MEM 阶段访问的地址不在 D-Cache 里，要 refill|

可以记：miss = “没命中，还得等存储器”。
miss 时：Cache 自己（或 cache_control 状态机）去访问 memory；同时 cache_control 发 stall 给 Hazard。
`cache_control` 连 memory 是为了 miss 时发起 refill / 写回主存

> [!Summary]
> 两条数据链（IF→i_cache、MEM→d_cache）+ 一条控制链（miss→cache_control→stall）+ 一条存储链（两 Cache 背后各连/共连 main_memory）

---

## 1. `i_cache`（IF 段）——管**取指**

| 项目 | 说明 |
|------|------|
| **位置** | IF 段，PC 送地址进去 |
| **存什么** | **只存指令**（程序代码） |
| **谁用** | 只有取指：PC → `i_cache` → `Inst` → IF/ID |
| **作用** | 多数时候 **1 拍** 从 Cache 读出指令，比直接访问慢速主存快 |
| **输出** | `Inst`（指令字）、`i_miss`（本拍要的字不在 Cache 里） |

可以记：**i_cache = 指令的“快取窗口”**，加快 **IF 取指**。

图上 IF 里还有 **ADD 算 NPC**（PC+2 等），和 `i_cache` 分工不同：一个算地址，一个按地址取指令。

---

## 2. `d_cache`（MEM 段）——管**访存数据**

| 项目 | 说明 |
|------|------|
| **位置** | MEM 段，地址来自 EX 的 ALU 结果 |
| **存什么** | **只存数据**（Load/Store 访问的内存数据） |
| **谁用** | `LD` / `ST` 等：EX 算地址 → MEM 用 `d_cache` 读/写 |
| **作用** | Load 命中时快速读出；Store 常配合写直达（写 Cache + 写主存） |
| **输出** | 读出的 `data`、`d_miss`（数据不在 Cache 里） |

可以记：**d_cache = 数据的“快取窗口”**，加快 **MEM 的 Load/Store**。

WB 段前面的 MUX 在 **ALU 结果** 和 **从 d_cache 读出的 data** 之间选，那是 Load 写回寄存器用的，和 `i_cache` 无关。

---

## 3. 一张表对比

| | **i_cache** | **d_cache** |
|--|-------------|-------------|
| 阶段 | IF | MEM |
| 内容 | 指令 | 数据 |
| 地址从哪来 | PC | ALU 结果（有效地址） |
| 典型指令 | 所有指令的取指 | LD、ST |
| miss 信号 | `i_miss` | `d_miss` |
| 影响 | 取指停（stall） | 访存停（stall） |

**为什么要分开？**  
取指和访存地址不同、访问规律不同（哈佛结构思想）；斐波那契里循环取指、反复读写在不同地址，分开 Cache 更贴近真实 CPU，也避免 IF 和 MEM 抢同一块存储器。

---

## 4. Memory（主存）存 **完整程序 + 全部数据**；miss 时由控制器从主存 **fill（填充）** 到 Cache

 **`i_miss` / `d_miss` → `Cache_control` → `stall`** 的含义就是：

1. 本拍 Cache **给不出** 指令或数据  
2. `Cache_control` 拉高 **stall**，流水线先停  
3. 背后 **主存** 把整块/整行读进 Cache  
4. 准备好后再取消 stall，继续执行  

---

## 6. 一句话总结

| 问题 | 答案 |
|------|------|
| **i_cache 功能？** | IF 段按 PC **快取指令**；miss 则等主存填指令 Cache |
| **d_cache 功能？** | MEM 段按地址 **快取/写数据**；miss 则等主存填数据 Cache |
| **还要 Memory 吗？** | **要**；主存是“全集”，Cache 是“热点副本”，miss 必须回主存 |

