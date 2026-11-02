if {![file exists work]} {vlib work}
vlog -sv "PE_Block(2).sv" "Systolic_Array(2).sv" "tiling(4).sv" top.v tb_top.sv
vsim -c work.tb_top -do "run -all; quit -f"
