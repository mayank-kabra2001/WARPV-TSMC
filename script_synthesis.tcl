yosys read_verilog cpu.v adder.v register_file.v includes/proj_default/clk_gate.v blockram.v
yosys hierarchy -check -top cpu
yosys proc
yosys opt
yosys fsm
yosys opt
yosys memory
yosys opt
yosys techmap
yosys opt
yosys dfflibmap -liberty ./../XARlogic_223_svt_mac.yosys.trimmed.lib
yosys abc -liberty ./../XARlogic_223_svt_mac.yosys.trimmed.lib
yosys clean
yosys write_verilog output/synth.v


