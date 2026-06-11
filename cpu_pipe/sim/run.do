transcript on

# Usage in ModelSim Transcript:
#   cd D:/code2/hardware/Structure/final/cpu_pipe/sim
#   do run.do
#
# Do NOT use: run run.do

# Always resolve paths relative to this script.
set script_dir [file dirname [file normalize [info script]]]
cd $script_dir
echo "Working directory: [pwd]"

if {[file exists work]} {
  vdel -lib work -all
}

vlib work
vmap work work

set rtl_files {
  ../rtl/if_stage.vhd
  ../rtl/id_stage.vhd
  ../rtl/ex_stage.vhd
  ../rtl/mem_stage.vhd
  ../rtl/wb_stage.vhd
  ../rtl/hazard_unit.vhd
  ../rtl/forward_unit.vhd
  ../rtl/interrupt_controller.vhd
  ../rtl/cpu_top.vhd
  ../rtl/timer.vhd
  ../rtl/uart_mmio.vhd
  ../rtl/gpio_mmio.vhd
  ../rtl/main_memory.vhd
  ../rtl/i_cache.vhd
  ../rtl/d_cache.vhd
  ../rtl/cache_control.vhd
  ../rtl/soc_top.vhd
  ../tb/tb_soc_top.vhd
}

foreach src $rtl_files {
  if {![file exists $src]} {
    echo "ERROR: source file not found: $src"
    return -code error
  }

  echo "Compiling $src"
  if {[catch {vcom -work work -2002 -explicit -stats=none $src} err]} {
    echo "ERROR: compile failed for $src"
    echo $err
    return -code error
  }
}

echo "Starting simulation: work.tb_soc_top"
if {[catch {vsim -voptargs=+acc work.tb_soc_top} err]} {
  echo "ERROR: vsim failed to load work.tb_soc_top"
  echo $err
  return -code error
}

radix hexadecimal

add wave -divider "TB"
add wave sim:/tb_soc_top/clk
add wave sim:/tb_soc_top/rst
add wave sim:/tb_soc_top/debug_pc
add wave sim:/tb_soc_top/debug_instr

add wave sim:/tb_soc_top/debug_epc
add wave sim:/tb_soc_top/debug_irq_pending
add wave sim:/tb_soc_top/debug_status_ie

add wave -divider "IRQ"
add wave sim:/tb_soc_top/u_dut/u_timer/irq_timer
add wave sim:/tb_soc_top/u_dut/u_cpu/flush_all
add wave sim:/tb_soc_top/u_dut/u_cpu/irq_take
add wave sim:/tb_soc_top/u_dut/u_cpu/iret_commit

add wave -divider "EX"
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_alu_result
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_rs
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_rs_val
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_rs2
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_rs2_val
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_rd
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_rd_val
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_reg_write
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_mem_read
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_mem_write
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_branch_taken
add wave sim:/tb_soc_top/u_dut/u_cpu/ex_branch_target

add wave -divider "D-Cache Stats"
add wave sim:/tb_soc_top/u_dut/u_dcache/hit_count
add wave sim:/tb_soc_top/u_dut/u_dcache/miss_count
add wave sim:/tb_soc_top/u_dut/u_dcache/hit_rate

add wave -divider "SOC"
add wave -r sim:/tb_soc_top/u_dut/*

echo "Running 8000 ns..."
run 8000 ns
echo "Simulation finished."
