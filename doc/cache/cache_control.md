## 4. Cache_control：与 CALL 如何配合

### 4.1 结构

```text
i_cache(PC) ──miss──┐
                     ├──> Cache_control ──stall──> Hazard detect
d_cache(MEM 地址) ──miss──┘
```

- **I-Cache miss**：IF 取指未完成，CALL 的目标指令也取不出 → 必须停流水。
- **D-Cache miss**：MEM 级卡住；若 stall 只冻 IF/ID，CALL 在 ID 的判定可能已完成，但 **不应在 miss 期间乱改 PC/栈**。

### 4.2 stall 时 Hazard 覆盖 CALL（优先级最高）

与互锁 / load-use 表一致（`doc/6/跳转指令导致的流水线暂停.md`、`doc/4/HarzardDetect2.md`）：

| 场景 | Pc_src | Pc_en | Ifid_src | Ifid_en | Control_src |
|------|--------|-------|----------|---------|---------------|
| **CALL** | 10 | 1 | 1 | 1 | 1 |
| **Cache stall** | * | **0** | * | **0** | **0** |
| **load-use** | * | 0 | * | 0 | 0 |

**Cache_control 实现要点：**

```text
stall <= i_miss or d_miss;   -- 或再与 cpu_ready='0' 组合

Hazard 组合逻辑（优先级从高到低）:
  if stall = '1' then
      Pc_en <= '0'; Ifid_en <= '0'; Control_src <= '0';
      -- Pc_src / Ifid_src 无关，因 PC、IF/ID 不更新
  elsif is_call = '1' then
      Pc_src <= "10"; Pc_en <= '1';
      Ifid_src <= '1'; Ifid_en <= '1'; Control_src <= '1';
      -- 且 stack.push_en = '1'（与 CALL 同拍）
  elsif ... -- load-use, J, BNE, 默认
```

与初期报告 **miss 冻结整条流水** 一致：

```text
if (MemRead or MemWrite) and cpu_ready = '0':
    PCWrite      = 0
    IF_ID_Write  = 0
    ID_EX_Write  = 0
    EX_MEM_Write = 0
    MEM_WB_Write = 0
```

图上若只画了 `Pc_en/Ifid_en` 到 Hazard，**建议 stall 时各级流水线寄存器写使能一并拉低**，避免 CALL 在 miss 拍误 push 或误改 PC。

### 4.3 CALL 遇到 I-Cache miss 的时序

```text
T:   ID 译码出 CALL，但 IF 侧 i_cache 仍 miss
     → Cache_control.stall=1 → 暂不执行 CALL 的 Pc_src=10 / push
T+k: i_cache ready，stall=0
     → 下一拍 Hazard 发 CALL 表 → PC←目标，push 返回地址，冲 IF/ID
```

这样 **返回地址与跳转目标在取指就绪后同一拍提交**，语义正确。

---
