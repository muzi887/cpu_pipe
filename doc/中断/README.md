# 中断模块 RTL 索引

> 详细说明见 [Timer精确中断实现.md](./Timer精确中断实现.md)（**设计与 RTL 逐段对照**）

| 文档 | 内容 |
|------|------|
| [中断相关名词解释.md](./中断相关名词解释.md) | 名词解释（CSR、MMIO、wdata、x6、ctrl_en、irq_timer 等） |
| [Timer精确中断实现.md](./Timer精确中断实现.md) | 数据通路、CSR/SYS、irq_take 逻辑、flush、MMIO、仿真波形 |
| [ISR-IRET与I-Cache时序.md](./ISR-IRET与I-Cache时序.md) | **仿真时序表** + **§3 RTL 因果**（985–995 过渡、两段 refill） |

| RTL 文件 | 说明 |
|----------|------|
| `cpu_pipe/rtl/interrupt_controller.vhd` | EPC / STATUS / CAUSE / irq_pending |
| `cpu_pipe/rtl/timer.vhd` | MMIO Timer，产生 irq_timer |
| `cpu_pipe/rtl/uart_mmio.vhd` | UART 0xFF00 |
| `cpu_pipe/rtl/gpio_mmio.vhd` | GPIO 0xFF10 |
| `cpu_pipe/rtl/cpu_top.vhd` | irq_take、SYS 提交、流水线 flush |
| `cpu_pipe/rtl/id_stage.vhd` | SYS 指令译码 |
| `cpu_pipe/rtl/if_stage.vhd` | pc_src=11 重定向 |
| `cpu_pipe/rtl/soc_top.vhd` | MMIO 旁路 + 外设互联 |
