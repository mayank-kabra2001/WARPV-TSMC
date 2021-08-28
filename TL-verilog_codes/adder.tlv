\m4_TLV_version 1d -p verilog --bestsv --noline: tl-x.org
\SV
   m4_include_lib(['https://raw.githubusercontent.com/mayank-kabra2001/WARPV-TSMC/main/warpv.tlv'])
     
\SV
   module alu(
       input clk,
       input reset,
       input [M4_WORD_RANGE] reg_value1, 
       input [M4_WORD_RANGE] reg_value2,
       input [M4_PC_RANGE]raw_i_imm,
       input raw_funct7_5, 
       input valid_exe, 
       output reg [M4_WORD_RANGE] addi_rslt,
       output reg [M4_WORD_RANGE] add_rslt,
       output reg [M4_WORD_RANGE] sub_rslt);
      
\TLV
   m4+adder() 

\SV
   endmodule

