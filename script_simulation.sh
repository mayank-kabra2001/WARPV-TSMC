iverilog cpu.v adder.v register_file.v blockram.v ./includes/proj_default/clk_gate.v ./../Simulation/tb_warpv.v 
vvp a.out
gtkwave ./../Simulation/out.vcd