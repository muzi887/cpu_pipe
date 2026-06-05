onerror {quit -f}
vlib work
vlog -work work cpu_fibo.vo
vlog -work work cpu_fibo.vt
vsim -novopt -c -t 1ps -L cycloneii_ver -L altera_ver -L altera_mf_ver -L 220model_ver -L sgate work.cpu_fibo_vlg_vec_tst
vcd file -direction cpu_fibo.msim.vcd
vcd add -internal cpu_fibo_vlg_vec_tst/*
vcd add -internal cpu_fibo_vlg_vec_tst/i1/*
add wave /*
run -all
