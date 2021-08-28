\m4_TLV_version 1d -p verilog --bestsv --noline: tl-x.org

\SV
   m4_include_lib(['https://raw.githubusercontent.com/mayank-kabra2001/WARPV-TSMC/main/warpv.tlv'])
     

\SV
   module register_file(
        input clk, 
        input reset,
        input is_reg_rs1,
        input is_reg_rs2, 
        input valid_decode, 
        input dest_reg_valid, 
        input [4:0] reg_rs1,
        input [4:0] reg_rs2,
        input [2:0] valid_dest_reg_valid_rd,
        input [2:0] goodPathMask,
        input [2:0] second_issue, 
        input [2:0] dest_reg,
        input dest_reg_now, 
        input [2:0] rslt,
        input [2:0] reg_wr_pending,
        output reg replay_int,
        output reg out_pending1,
        output reg out_pending2,
        output reg [M4_WORD_RANGE] reg_value1,
        output reg [M4_WORD_RANGE] reg_value2, 
        output reg dest_pending,
        input valid_dest_reg_valid_wr,
        input [4:0] dest_reg_wr,
        input [M4_WORD_RANGE] rslt_wr,
        input reg_wr_pending_wr
   );

\TLV
   m4+register_file() 

\SV
   endmodule

