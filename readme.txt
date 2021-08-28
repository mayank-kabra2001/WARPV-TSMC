This Project supports warp-V to be converted into netlist using Open source Yosys tool. 

Clone the repository to your local system. 

1. Convert TLV to RTL - 
On terminal write = ./TLV_to_RTL.sh

2. To simulate the Warp-V code by iverilog and generate .vcd file 
On terminal write = cd RTL 
              then = ./../script_simulation.sh 

3. TO synthesize to get a netlist using YOSYS. 
On terminal write = cd RTL 
              then = yosys 
              then = tcl ./../script_synthesis.tcl
