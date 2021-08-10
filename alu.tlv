\m4_TLV_version 1d: tl-x.org
\SV 
   m4_define(['m4_debug'], 0)
   
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   m4_ifelse_block(m4_debug, 1, ['
   // Makerchip interfaces with this module, coded in SV.
   m4_makerchip_module
      // Instantiate a 1st CLaaS kernel with random inputs.
       logic [M4_WORD_RANGE] reg_value1; 
       logic [M4_WORD_RANGE] reg_value2;
       logic [M4_PC_RANGE]raw_i_imm;
       logic raw_funct7_5;
       logic valid_exe;
       logic [M4_WORD_RANGE] addi_rslt;
       logic [M4_WORD_RANGE] add_rslt;
       logic [M4_WORD_RANGE] sub_rslt;                           
      alu kernel (
            .*,  // clk, reset, and signals above
            .addi_rslt(),
            .add_rslt(),
            .sub_rslt()
            );
      assign passed = cyc_cnt > 40;
   endmodule
'])
         
    module alu (
       input clk,
       input reset,
       input [M4_WORD_RANGE] reg_value1, 
       input [M4_WORD_RANGE] reg_value2,
       input [M4_PC_RANGE]raw_i_imm,
       input raw_funct7_5, 
       input valid_exe, 
       output reg [M4_WORD_RANGE] addi_rslt,
       output reg [M4_WORD_RANGE] add_rslt,
       output reg [M4_WORD_RANGE] sub_rslt
       ); 

\TLV
   $reset = *reset;
   $reg_value1 = *reg_value1; 
   $reg_value2 = *reg_value2; 
   $raw_i_imm = *raw_i_imm; 
   $raw_funct7_5 = *raw_funct7_5;
   $valid_exe = *valid_exe; 

   //?$valid_exe
   $addi_rslt[M4_WORD_RANGE]  = $reg_value1 + $raw_i_imm;  // TODO: This has its own adder; could share w/ add/sub.
   $add_sub_rslt[M4_WORD_RANGE] = ($raw_funct7_5 == 1) ?  $reg_value1 - $reg_value2 : $reg_value1 + $reg_value2;
   $add_rslt[M4_WORD_RANGE]   = $add_sub_rslt;
   $sub_rslt[M4_WORD_RANGE]   = $add_sub_rslt;

   *addi_rslt = $addi_rslt;
   *add_rslt = $add_rslt;
   *sub_rslt = $sub_rslt;
\SV
   endmodule
