\m4_TLV_version 1d -p verilog --bestsv --noline: tl-x.org
\SV
   m4_include_lib(['https://raw.githubusercontent.com/mayank-kabra2001/WARPV-TSMC/main/warpv.tlv'])
   m4_define(['m4_debug'],0)
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
      logic is_reg_rs1 = ^ RW_rand_vect[15:8];
      logic is_reg_rs2 = ^ RW_rand_vect[23:16];
      logic valid_decode = ^ RW_rand_vect[31:24]; 
      logic dest_reg_valid = ^ RW_rand_vect[39:32];
      logic [4:0] reg_rs1 = RW_rand_vect[44:40];
      logic [4:0] reg_rs2 = RW_rand_vect[49:45];
      logic [2:0] valid_dest_reg_valid_rd = RW_rand_vect[52:50];
      logic [2:0] goodPathMask = RW_rand_vect[55:53];
      logic [2:0] second_issue = RW_rand_vect[58:56];
      logic [2:0] dest_reg = RW_rand_vect[61:59];
      logic dest_reg_now = ^ RW_rand_vect[69:62];
      logic [2:0] rslt = RW_rand_vect[72:70];
      logic [2:0] reg_wr_pending = RW_rand_vect[75:73];
      logic [M4_WORD_RANGE] data_value = RW_rand_vect[76 +: M4_WORD_MAX];
      logic src_pending = ^ RW_rand_vect[107:100];
      logic valid_dest_reg_valid_wr = ^ RW_rand_vect[115:108];
      logic [4:0] dest_reg_wr = RW_rand_vect[120:116];
      logic [M4_WORD_RANGE] rslt_wr = RW_rand_vect[121 +: M4_WORD_MAX];
      logic pending_wr = ^ RW_rand_vect[157:150];
      logic dest_inp_pending = ^ RW_rand_vect[165:158];

      register_file kernel (
            .*,  // clk, reset, and signals above
            .replay_int(),
            .out_pending1(),
            .out_pending2(),
            .reg_value1(),
            .reg_value2(),
            .dest_pending(),
            .pending()
         );
      assign passed = cyc_cnt > 40;
   endmodule
'])
                   
                   
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
        input [M4_WORD_RANGE] data_value, 
        input src_pending, 
        output reg replay_int,
        output reg out_pending1,
        output reg out_pending2,
        output reg [M4_WORD_RANGE] reg_value1,
        output reg [M4_WORD_RANGE] reg_value2, 
        output reg dest_pending,
        input valid_dest_reg_valid_wr,
        input [4:0] dest_reg_wr,
        input [M4_WORD_RANGE] rslt_wr,
        input pending_wr,
        input dest_inp_pending,
        output reg pending
   ); 
       
\TLV
   |reg
      @0
         // READ SIGNALS //
         $reset = *reset;
         $is_reg_rs1 = *is_reg_rs1;
         $is_reg_rs2 = *is_reg_rs2;
         $reg_rs1 = *reg_rs1;
         $reg_rs2 = *reg_rs2;
         $valid_decode = *valid_decode;
         $dest_reg_valid = *dest_reg_valid; 
         $valid_dest_reg_valid_rd[2:0] = *valid_dest_reg_valid_rd;
         $goodPathMask[2:0] = *goodPathMask;
         $second_issue[2:0] = *second_issue; 
         $dest_reg[2:0] = *dest_reg;
         $dest_reg_now = *dest_reg_now; 
         $rslt[2:0] = *rslt; 
         $reg_wr_pending[2:0] = *reg_wr_pending; 
         $data_value = *data_value ; 
         $src_pending = *src_pending ; 
         $dest_inp_pending = *dest_inp_pending ; 
         // WRITE SIGNALS //
      @1
         
         $valid_dest_reg_valid_wr = *valid_dest_reg_valid_wr;
         $dest_reg_wr[4:0] = *dest_reg_wr;
         $rslt_wr[M4_WORD_RANGE] = *rslt_wr;
         $pending_wr = *pending_wr;
         
      @0 
         /M4_REGS_HIER
         /src[2:1]
            $is_reg = (#src == 1) ? |reg$is_reg_rs1 : |reg$is_reg_rs2;
            $reg[4:0] = (#src == 1) ? |reg$reg_rs1 : |reg$reg_rs2;
            
            $is_reg_condition = $is_reg && |reg$valid_decode;  // Note: $is_reg can be set for RISC-V sr0.
            ?$is_reg_condition
               {$reg_value[M4_WORD_RANGE], $pending} =
                  m4_ifelse(M4_ISA, ['RISCV'], ['($reg == M4_REGS_INDEX_CNT'b0) ? {M4_WORD_CNT'b0, 1'b0} : ']) // Read r0 as 0 (not pending).
                  // Bypass stages. Both register and pending are bypassed.
                  // Bypassed registers must be from instructions that are good-path as of this instruction or are 2nd issuing.
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(|reg$valid_dest_reg_valid_rd[0] && (|reg$goodPathMask[0] || |reg$second_issue[0]) && (|reg$dest_reg[0] == $reg)) ? {|reg$rslt[0], |reg$reg_wr_pending[0]} :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(|reg$valid_dest_reg_valid_rd[1] && (|reg$goodPathMask[1] || |reg$second_issue[1]) && (|reg$dest_reg[1] == $reg)) ? {|reg$rslt[1], |reg$reg_wr_pending[1]} :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(|reg$valid_dest_reg_valid_rd[2] && (|reg$goodPathMask[2] || |reg$second_issue[2]) && (|reg$dest_reg[2] == $reg)) ? {|reg$rslt[2], |reg$reg_wr_pending[2]} :'])
                  {|reg$data_value, m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['|reg$src_pending'])};
            // Replay if this source register is pending.
            $replay = $is_reg_condition && $pending;
            $dummy = 1'b0; 
            `BOGUS_USE($dummy)// Dummy signal to pull through $ANY expressions when not building verification harness (since SandPiper currently complains about empty $ANY).
      
         // Also replay for pending dest reg to keep writes in order. Bypass dest reg pending to support this.
         $is_dest_condition = |reg$dest_reg_valid && |reg$valid_decode;  // Note, $dest_reg_valid is 0 for RISC-V sr0.
         ?$is_dest_condition
            $dest_pending =
               m4_ifelse(M4_ISA, ['RISCV'], ['(|reg$dest_reg_now == M4_REGS_INDEX_CNT'b0) ? 1'b0 :  // Read r0 as 0 (not pending). Not actually necessary, but it cuts off read of non-existent rs0, which might be an issue for formal verif tools.'])
               // Bypass stages. Both register and pending are bypassed.
               m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(|reg$valid_dest_reg_valid_rd[0] && (|reg$goodPathMask[0] || |reg$second_issue[0]) && (|reg$dest_reg[0] == |reg$dest_reg_now)) ? |reg$reg_wr_pending[0] :'])
               m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(|reg$valid_dest_reg_valid_rd[1] && (|reg$goodPathMask[1] || |reg$second_issue[1]) && (|reg$dest_reg[1] == |reg$dest_reg_now)) ? |reg$reg_wr_pending[1] :'])
               m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(|reg$valid_dest_reg_valid_rd[2] && (|reg$goodPathMask[2] || |reg$second_issue[2]) && (|reg$dest_reg[2] == |reg$dest_reg_now)) ? |reg$reg_wr_pending[2] :'])
               m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['|reg$dest_inp_pending']);
         // Combine replay conditions for pending source or dest registers.
         $replay_int = | /src[*]$replay || ($is_dest_condition && $dest_pending);
         
         \SV_plus
            always @(posedge clk) begin
               *replay_int = |reg$replay_int;
               *dest_pending = |reg$dest_pending;
               *reg_value1 = |reg/src[1]$reg_value[M4_WORD_RANGE];
               *reg_value2 = |reg/src[2]$reg_value[M4_WORD_RANGE];
               *out_pending1 = |reg/src[1]$pending;
               *out_pending2 = |reg/src[2]$pending;
            end
         
      @5
         $reg_write = |reg$reset ? 1'b0 : |reg$valid_dest_reg_valid_wr;
         \SV_plus
            always @ (posedge clk) begin
               if ($reg_write)
                  |reg/regs[|reg$dest_reg_wr]<<0$$^value[M4_WORD_RANGE] <= |reg$rslt_wr;
            end
         m4_ifelse_block(M4_PENDING_ENABLED, 1, ['
         // Write $pending along with $value, but coded differently because it must be reset.
         /regs[*]
            <<1$pending = ! |reg$reset && (((#regs == |reg$dest_reg_wr) && |reg$valid_dest_reg_valid_wr) ? |reg$reg_wr_pending : |reg$pending_wr);
            `BOGUS_USE($value)
         '])
         
         \SV_plus 
            always @(posedge clk) begin 
               *pending = |reg/regs[|reg$dest_reg_wr]<<1$pending; 
            end
         
   
\SV
   endmodule
