建议把 **ModelSim 工程目录** 放在：

```text
d:\code2\hardware\Structure\final\cpu_pipe\sim
```

也就是和 `rtl/`、`tb/`、`prj/` 平级，不要放在 `rtl` 里，也不要直接放在 `prj` 根目录。

## 推荐目录结构

```text
cpu_pipe/
├── rtl/                 # 设计源码（不动）
├── tb/                  # testbench
├── prj/                 # Quartus 工程
└── sim/                 # ModelSim 工程放这里（新建）
    ├── work/            # 编译库（自动生成）
    ├── run.do           # 一键仿真脚本（可选）
    ├── transcript       # 仿真日志（自动生成）
    └── vsim.wlf         # 波形文件（自动生成）
```

这样分工最清楚：

| 目录 | 用途 |
|------|------|
| `rtl/` | 只放 VHDL 设计 |
| `tb/` | 只放 testbench |
| `prj/` | Quartus 综合/下载 |
| `sim/` | ModelSim 工程、work 库、波形 |

## 在 ModelSim 里怎么建

1. **File → New → Project**
2. **Project Location** 选：`d:\code2\hardware\Structure\final\cpu_pipe\sim`
3. **Project Name** 可填：`cpu_pipe_sim`
4. 添加文件时，从上级目录引用源码，不要复制一份：
   - `..\rtl\if_stage.vhd`
   - `..\rtl\id_stage.vhd`
   - `..\rtl\ex_stage.vhd`
   - `..\rtl\mem_stage.vhd`
   - `..\rtl\wb_stage.vhd`
   - `..\rtl\cpu_top.vhd`
   - `..\rtl\instr_memory.vhd`
   - `..\rtl\data_memory.vhd`
   - `..\rtl\soc_top.vhd`
   - `..\tb\tb_soc_top.vhd`
5. 顶层仿真实体选：**`tb_soc_top`**

## 为什么不建议放别的地方

- **不要放 `rtl/`**：会把 `work/`、波形等仿真垃圾混进源码目录。
- **不要放 `prj/` 根目录**：会和 Quartus 的 `db/`、`output_files/` 搅在一起。
- **`prj/simulation/modelsim/`** 也可以，但那是 Quartus 联动仿真时常用的位置；你现在想单独用 ModelSim，用 `cpu_pipe/sim/` 更简单。

## 和旧项目 `cpu_fibo` 的对应关系

你之前的 `cpu_fibo` 是：

```text
cpu_fibo/prj/simulation/modelsim/
```

那是 Quartus 自动生成的仿真目录。现在 `cpu_pipe` 独立仿真，用 `cpu_pipe/sim/` 更直观，效果和 `cpu_fibo` 里单独跑 ModelSim 是一样的。

如果你要，我可以下一步直接帮你在 `cpu_pipe/sim/` 里写一个 `run.do`，在 ModelSim 里执行 `do run.do` 就能编译并仿真。