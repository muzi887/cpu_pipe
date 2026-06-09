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
  ../rtl/cpu_top.vhd
  ../rtl/instr_memory.vhd
  ../rtl/data_memory.vhd
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

add wave -divider "SOC"
add wave -r sim:/tb_soc_top/u_dut/*

echo "Running 4000 ns..."
run 4000 ns
echo "Simulation finished."
