\m4_TLV_version 1d -p verilog --bestsv --noline: tl-x.org
\SV
   /*
   Copyright 2021 Redwood EDA
   
   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
   
   The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
   
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
   */
m4+definitions(['
   m4_def(ISA, RISCV)
   m4_def(EXT_E, 0)
   m4_def(EXT_M, 0)
   m4_def(EXT_F, 0)
   m4_def(EXT_B, 0)
   m4_def(NUM_CORES, 1)
   m4_def(NUM_VCS, 2)
   m4_def(NUM_PRIOS, 2)
   m4_def(MAX_PACKET_SIZE, 8)
   m4_def(soft_reset, 1'b0)
   m4_def(cpu_blocked, 1'b0)
   m4_def(BRANCH_PRED, two_bit)
   m4_def(EXTRA_REPLAY_BUBBLE, 0)
   m4_def(EXTRA_PRED_TAKEN_BUBBLE, 0)
   m4_def(EXTRA_JUMP_BUBBLE, 0)
   m4_def(EXTRA_BRANCH_BUBBLE, 0)
   m4_def(EXTRA_INDIRECT_JUMP_BUBBLE, 0)
   m4_def(EXTRA_NON_PIPELINED_BUBBLE, 1)
   m4_def(EXTRA_TRAP_BUBBLE, 1)
   m4_def(NEXT_PC_STAGE, 0)
   m4_def(FETCH_STAGE, 0)
   m4_def(DECODE_STAGE, 1)
   m4_def(BRANCH_PRED_STAGE, 1)
   m4_def(REG_RD_STAGE, 1)
   m4_def(EXECUTE_STAGE, 2)
   m4_def(RESULT_STAGE, 2)
   m4_def(REG_WR_STAGE, 4)
   m4_def(MEM_WR_STAGE, 4)
   m4_def(LD_RETURN_ALIGN, 5)
'])

\SV
   m4_include_lib(['https://raw.githubusercontent.com/mayank-kabra2001/WARPV-TSMC/main/warpv.tlv'])

\SV
   // Include WARP-V.
   m4_ifelse_block(M4_MAKERCHIP, 1, [''], ['
   module cpu(input clk, input reset, output reg led);
   '])
      

                         
\TLV
   // Generated logic
   // Instantiate the _gen macro for the right ISA. (This approach is required for an m4-defined name.)
   m4_define(['m4_gen'], M4_isa['_gen'])
   m4+m4_gen()
   // Instruction memory and fetch of $raw.
   //m4+M4_IMEM_MACRO_NAME(M4_PROG_NAME)
   
   // /=========\
   // | instructions|
   // \=========/
   
   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               $addr_instr_sram[11:0] = $Pc[m4_eval(M4_PC_MIN + m4_width(11-1) - 1) : M4_PC_MIN] ;
               $raw[M4_INSTR_RANGE] = >>2$dout_instr;
               
   // /=========\
   // | The CPU |
   // \=========/
   
   |fetch
      /instr
         
         
         // Provide a longer reset to cover the pipeline depth.
         @m4_stage_eval(@M4_NEXT_PC_STAGE<<1)
            *led = 1; 
            $clk = *clk; 
            $soft_reset = (m4_soft_reset) || *reset;
            $Cnt[7:0] <= $soft_reset   ? 8'b0 :       // reset
                         $Cnt == 8'hFF ? 8'hFF :      // max out to avoid wrapping
                                         $Cnt + 8'b1; // increment
            $reset = $soft_reset || $Cnt < m4_eval(M4_LD_RETURN_ALIGN + M4_MAX_REDIRECT_BUBBLES + 3);
         @M4_FETCH_STAGE
            $fetch = ! $reset && ! $NoFetch;
            // (M4_IMEM_MACRO_NAME instantiation produces ?$fetch$raw.)
         @M4_NEXT_PC_STAGE
            
            // ========
            // Overview
            // ========
            
            // Terminology:
            //
            // Instruction: An instruction, as viewed by the CPU pipeline (i.e. ld and returning_ld are separate instructions,
            //              and the returning_ld and the instruction it clobbers are one in the same).
            // ISA Instruction: An instruction, as defined by the ISA.
            // Good-Path (vs. Bad-Path): On the proper flow of execution of the program, excluding aborted instructions.
            // Path (of an instruction): The sequence of instructions that led to a particular instruction.
            // Current Path: The sequence of instructions fetched by next-PC logic that are not known to be bad-path.
            // Redirect: Adjust the PC from the predicted next-PC.
            // Redirect Shadow: Between the instruction causing the redirect and the redirect target instruction.
            // Bubbles: The cycles in the redirect shadow.
            // Commit: Results are made visible to subsequent instructions.
            // Abort: Do not commit. All aborts are also redirects and put the instruction on bad path. Non-aborting
            //        redirects do not mark the triggering instruction as bad-path. Aborts mask future redirects on the
            //        aborted instruction.
            // Retire: Commit results of an ISA instruction.
            
            // Control flow:
            //
            // Redirects include (earliest to latest):
            //   o Returning load: (aborting) A returning load clobbers an instruction and takes its slot, resulting in a
            //                     one-cycle redirect to repeat the clobbered instruction.
            //   o Predict-taken branch: A predicted-taken branch must determine the target before it can redirect the PC.
            //                           (This might be followed up by a mispredition.)
            //   o Replay: (aborting) Replay the same instruction (because a source register is pending (awaiting a long-latency/2nd issuing instruction))
            //   o Jump: A jump instruction.
            //   o Mispredicted branch: A branch condition was mispredicted.
            //   o Aborting traps: (aborting) illegal instructions, others?
            //   o Non-aborting traps: misaligned PC target
            
            // ==============
            // Redirect Logic
            // ==============
                            
            // PC logic will redirect the PC for conditions on current-path instructions. PC logic keeps track of which
            // instructions are on the current path with a $GoodPathMask. $GoodPathMask[n] of an instruction indicates
            // whether the instruction n instructions prior to this instruction is on its path.
            //
            //                 $GoodPathMask for Redir'edX => {o,X,o,y,y,y,o,o} == {1,1,1,1,0,0,1,1}
            // Waterfall View: |
            //                 V
            // 0)       oooooooo                  Good-path
            // 1) InstX  ooooooXo  (Non-aborting) Good-path
            // 2)         ooooooxx
            // 3) InstY    ooYyyxxx  (Aborting)
            // 4) InstZ     ooyyxZxx
            // 5) Redir'edY  oyyxxxxx
            // 6) TargetY     ooxxxxxx
            // 7) Redir'edX    oxxxxxxx
            // 8) TargetX       oooooooo          Good-path
            // 9) Not redir'edZ  oooooooo         Good-path
            //
            // Above depicts a waterfall diagram where three triggering redirection conditions X, Y, and Z are detected on three different
            // instructions. A trigger in the 1st depicted stage, M4_NEXT_PC_STAGE, results in a zero-bubble redirect so it would be
            // a condition that is factored directly into the next-PC logic of the triggering instruction, and it would have
            // no impact on the $GoodPathMask.
            //
            // Waveform View:
            //
            //   Inst 0123456789
            //        ---------- /
            // GPM[7]        ooxxxxxxoo
            // GPM[6]       oXxxxxxxoo
            // GPM[5]      oooxZxxxoo
            // GPM[4]     oooyxxxxoo
            // GPM[3]    oooyyxxxoo
            // GPM[2]   oooYyyxxoo
            // GPM[1]  oooooyoxoo
            // GPM[0] oooooooooo
            //          /
            //         Triggers for InstY
            //
            // In the waveform view, the mask shifts up each cycle, as instructions age, and trigger conditions mask instructions
            // in the shadow, down to the redirect target (GPM[0]).
            //
            // Terminology:
            //   Triggering instruction: The instruction on which the condition is detected.
            //   Redirected instruction: The instruction whose next PC is redirected.
            //   Redirection target instruction: The first new-path instruction resulting from the redirection.
            //
            // Above, Y redirects first, though it is for a later instruction than X. The redirections for X and Y are taken
            // because their instructions are on the path of the redirected instructions. Z is not on the path of its
            // potentially-redirected instruction, so no redirection happens.
            //
            // For simultaneous conditions on different instructions, the PC must redirect to the earlier instruction's
            // redirect target, so later-stage redirects take priority in the PC-mux.
            //
            // Aborting redirects result in the aborting instruction being marked as bad-path. Aborted instructions will
            // not commit. Subsequent redirect conditions on aborting instructions are ignored. (For conditions within the
            // same stage, this is accomplished by the PC-mux prioritization.)
            
            
            // Macros are defined elsewhere based on the ordered set of conditions that generate code here.
            
            // Redirect Shadow
            // A mask of stages ahead of this one (older) in which instructions are on the path of this instruction.
            // Index 1 is ahead by 1, etc.
            // In the example above, $GoodPathMask for Redir'edX == {0,0,0,0,1,1,0,0}
            //     (Looking up in the waterfall diagram from its first "o", in reverse order {o,X,o,o,y,y,o,o}.)
            // The LSB is fetch-valid. It only exists for m4_prev_instr_valid_through macro.
            $next_good_path_mask[M4_MAX_REDIRECT_BUBBLES+1:0] =
               // Shift up and mask w/ redirect conditions.
               {$GoodPathMask[M4_MAX_REDIRECT_BUBBLES:0]
                // & terms for each condition (order doesn't matter since masks are the same within a cycle)
                m4_redirect_squash_terms,
                1'b1}; // Shift in 1'b1 (fetch-valid).
            
            $GoodPathMask[M4_MAX_REDIRECT_BUBBLES+1:0] <=
               <<1$reset ? m4_eval(M4_MAX_REDIRECT_BUBBLES + 2)'b0 :  // All bad-path (through self) on reset (next mask based on next reset).
               $next_good_path_mask;
            
            m4_ifelse_block(M4_FORMAL, ['1'], ['
            // Formal verfication must consider trapping instructions. For this, we need to maintain $RvfiGoodPathMask, which is similar to
            // $GoodPathMask, except that it does not mask out aborted instructions.
            $next_rvfi_good_path_mask[M4_MAX_REDIRECT_BUBBLES+1:0] =
               {$RvfiGoodPathMask[M4_MAX_REDIRECT_BUBBLES:0]
                m4_redirect_shadow_terms,
                1'b1};
            $RvfiGoodPathMask[M4_MAX_REDIRECT_BUBBLES+1:0] <=
               <<1$reset ? m4_eval(M4_MAX_REDIRECT_BUBBLES + 2)'b0 :
               $next_rvfi_good_path_mask;
            '])
            
            
            // A returning load clobbers the instruction.
            // (Could do this with lower latency. Right now it goes through memory pipeline $ANY, and
            //  it is non-speculative. Both could easily be fixed.)
            $second_issue_ld = /top|mem/data>>M4_LD_RETURN_ALIGN$valid_ld && 1'b['']M4_INJECT_RETURNING_LD;
            $second_issue = $second_issue_ld m4_ifelse(M4_EXT_M, 1, ['|| $second_issue_div_mul']) m4_ifelse(M4_EXT_F, 1, ['|| $fpu_second_issue_div_sqrt']) m4_ifelse(M4_EXT_B, 1, ['|| $second_issue_clmul_crc']);
            // Recirculate returning load or the div_mul_result from /orig_inst scope
            
            ?$second_issue_ld
               // This scope holds the original load for a returning load.
               /orig_load_inst
                  $ANY = /top|mem/data>>M4_LD_RETURN_ALIGN$ANY;
                  /src[2:1]
                     $ANY = /top|mem/data/src>>M4_LD_RETURN_ALIGN$ANY;
            ?$second_issue
               /orig_inst
                  // pull values from /orig_load_inst or /hold_inst depending on which second issue
                  $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst$ANY : m4_ifelse(M4_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_F, 1, ['|fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst$ANY;
                  /src[2:1]
                     $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst/src$ANY : m4_ifelse(M4_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst/src>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_F, 1, ['|fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst/src>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst/src>>M4_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst/src$ANY;
            
            // Next PC
            $pc_inc[M4_PC_RANGE] = $Pc + M4_PC_CNT'b1;
            // Current parsing does not allow concatenated state on left-hand-side, so, first, a non-state expression.
            {$next_pc[M4_PC_RANGE], $next_no_fetch} =
               $reset ? {M4_PC_CNT'b0, 1'b0} :
               // ? : terms for each condition (order does matter)
               m4_redirect_pc_terms
                          ({$pc_inc, 1'b0});
            // Then as state.
            $Pc[M4_PC_RANGE] <= $next_pc;
            $NoFetch <= $next_no_fetch;
            
         @M4_DECODE_STAGE
            
            // ======
            // DECODE
            // ======
            
            // Decode of the fetched instruction
            $valid_decode = $fetch;  // Always decode if we fetch.
            $valid_decode_branch = $valid_decode && $branch;
            // A load that will return later.
            //$split_ld = $spec_ld && 1'b['']M4_INJECT_RETURNING_LD;
            // Instantiate the program. (This approach is required for an m4-defined name.)
            m4_define(['m4_decode_macro_name'], M4_isa['_decode'])
            m4+m4_decode_macro_name()
         // Instantiate the program. (This approach is required for an m4-defined name.)
         m4_define(['m4_branch_pred_macro_name'], ['branch_pred_']M4_BRANCH_PRED)
         m4+m4_branch_pred_macro_name()
         
         @M4_REG_RD_STAGE
            // Pending value to write to dest reg. Loads (not replaced by returning ld) write pending.
            $reg_wr_pending = $ld && ! $second_issue && 1'b['']M4_INJECT_RETURNING_LD;
            `BOGUS_USE($reg_wr_pending)  // Not used if no bypass and no pending.
            
            // ======
            // Reg Rd
            // ======
            
            // INPUT SIGNALS TO REGISTER FILE - READ//
            $is_reg1_rd = /src[1]$is_reg;
            $is_reg2_rd = /src[2]$is_reg;  
            $reg_rs1_rd[4:0] = /src[1]$reg;
            $reg_rs2_rd[4:0] = /src[2]$reg;  
            $valid_decode_rd = /instr$valid_decode;
            $valid_dest_reg_valid_rd[2:0] = {/instr>>3$valid_dest_reg_valid, /instr>>2$valid_dest_reg_valid, /instr>>1$valid_dest_reg_valid}; 
            $goodPathMask_rd[2:0] = {/instr$GoodPathMask[3], /instr$GoodPathMask[2], /instr$GoodPathMask[1]};
            $second_issue_rd[2:0] = {/instr>>3$second_issue, /instr>>2$second_issue, /instr>>1$second_issue}; 
            $dest_reg_rd[2:0] = {/instr>>3$dest_reg, /instr>>2$dest_reg, /instr>>1$dest_reg};
            $rslt_rd[2:0] = {/instr>>3$rslt, /instr>>2$rslt, /instr>>1$rslt};
            $reg_wr_pending_rd[2:0] = {/instr>>3$reg_wr_pending, /instr>>2$reg_wr_pending, /instr>>1$reg_wr_pending}; 
            $dest_reg_valid_rd = $dest_reg_valid;
            $dest_reg_now_rd = $dest_reg; 
            
            // OUTPUT SIGNALS TO REGISTER FILE - READ// 
            /src[2:1]
               $reg_value[M4_WORD_RANGE] = (#src == 1) ? |fetch/instr$out_reg_value1_rd : |fetch/instr$out_reg_value2_rd ; 
               $pending = (#src == 1) ? |fetch/instr$out_pending1_rd : |fetch/instr$out_pending2_rd; 
               `BOGUS_USE($pending)
               $dummy = 0; 
               `BOGUS_USE($dummy)
            
            $dest_pending = $out_dest_pending_rd; 
            `BOGUS_USE($dest_pending)
            $replay_int = $replay_int_rd; 
                        
            // Obtain source register values and pending bit for source registers. Bypass up to 3
            // stages.
            // It is not necessary to bypass pending, as we could delay the replay, but we implement
            // bypass for performance.
            // Pending has an additional read for the dest register as we need to replay for write-after-write
            // hazard as well as write-after-read. To replay for dest write with the same timing, we must also
            // bypass the dest reg's pending bit.
            
            /////////////////////////////////////////////////////////////////////////
            // NOW READING FROM THE REGISTER FILE INSIDE A MODULE IN INCLUDE FILE //
            ////////////////////////////////////////////////////////////////////////
            
            
            m4_ifelse_block(M4_EXT_F, 1, ['
            //
            // ======
            // Reg Rd for Floating Point Unit
            // ======
            // 
            /M4_FPU_REGS_HIER
            /fpu_src[3:1]
               $is_reg_condition = $is_reg && /instr$valid_decode;  // Note: $is_reg can be set for RISC-V sr0.
               ?$is_reg_condition
                  {$reg_value[M4_WORD_RANGE], $pending} =
                     m4_ifelse(M4_ISA, ['RISCV'], ['// Note: f0 is not hardwired to ground as x0 does'])
                     // Bypass stages. Both register and pending are bypassed.
                     // Bypassed registers must be from instructions that are good-path as of this instruction or are 2nd issuing.
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(/instr>>1$valid_dest_fpu_reg_valid && (/instr$GoodPathMask[1] || /instr>>1$second_issue) && (/instr>>1$dest_fpu_reg == $reg)) ? {/instr>>1$rslt, /instr>>1$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(/instr>>2$valid_dest_fpu_reg_valid && (/instr$GoodPathMask[2] || /instr>>2$second_issue) && (/instr>>2$dest_fpu_reg == $reg)) ? {/instr>>2$rslt, /instr>>2$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(/instr>>3$valid_dest_fpu_reg_valid && (/instr$GoodPathMask[3] || /instr>>3$second_issue) && (/instr>>3$dest_fpu_reg == $reg)) ? {/instr>>3$rslt, /instr>>3$reg_wr_pending} :'])
                     {/instr/fpu_regs[$reg]>>M4_REG_BYPASS_STAGES$value, m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['/instr/fpu_regs[$reg]>>M4_REG_BYPASS_STAGES$pending'])};
               // Replay if FPU source register is pending.
               $replay_fpu = $is_reg_condition && $pending;
               
            // Also replay for pending dest reg to keep writes in order. Bypass dest reg pending to support this.
            $is_dest_fpu_condition = $dest_fpu_reg_valid && /instr$valid_decode;
            ?$is_dest_fpu_condition
               $dest_fpu_pending =
                  m4_ifelse(M4_ISA, ['RISCV'], ['// Note: f0 is not hardwired to ground as x0 does'])
                  // Bypass stages. Both register and pending are bypassed.
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(>>1$valid_dest_fpu_reg_valid && ($GoodPathMask[1] || /instr>>1$second_issue) && (>>1$dest_fpu_reg == $dest_fpu_reg)) ? >>1$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(>>2$valid_dest_fpu_reg_valid && ($GoodPathMask[2] || /instr>>2$second_issue) && (>>2$dest_fpu_reg == $dest_fpu_reg)) ? >>2$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(>>3$valid_dest_fpu_reg_valid && ($GoodPathMask[3] || /instr>>3$second_issue) && (>>3$dest_fpu_reg == $dest_fpu_reg)) ? >>3$reg_wr_pending :'])
                  m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['/fpu_regs[$dest_fpu_reg]>>M4_REG_BYPASS_STAGES$pending']);
            // Combine replay conditions for pending source or dest registers.
            $replay_fpu = | /fpu_src[*]$replay_fpu || ($is_dest_fpu_condition && $dest_fpu_pending);
            '])
            $replay = $replay_int m4_ifelse(M4_EXT_F, 1, ['|| $replay_fpu']);
         
         // =======
         // Execute
         // =======
         
         // Instantiate the program. (This approach is required for an m4-defined name.)
         m4_define(['m4_exe_macro_name'], M4_isa['_exe'])
         m4+m4_exe_macro_name(@M4_EXECUTE_STAGE, @M4_RESULT_STAGE)
         
         @M4_EXECUTE_STAGE
            ?$valid_exe
               // INPUT SIGNALS TO ALU - ADDER//
               $reg_value1_alu[M4_WORD_RANGE] = /src[1]$reg_value; 
               $reg_value2_alu[M4_WORD_RANGE] = /src[2]$reg_value; 
               $raw_i_imm_alu[M4_WORD_RANGE] = $raw_i_imm; 
               $raw_funct7_5_alu = $raw_funct7[5];
               $valid_exe_alu = $valid_exe; 
               
               // OUTPUT SIGNALS TO ALU - ADDER//
               $addi_rslt[31:0] = $addi_rslt_out; 
               $add_rslt[31:0] = $add_rslt_out; 
               $sub_rslt[31:0] = $sub_rslt_out; 
            
            
         @M4_BRANCH_PRED_STAGE
            m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['$pred_taken_branch = $pred_taken && $branch;'])
         @M4_EXECUTE_STAGE
            
            // =======
            // Control
            // =======
            
            // A version of PC we can pull through $ANYs.
            $pc[M4_PC_RANGE] = $Pc[M4_PC_RANGE];
            `BOGUS_USE($pc)
            
            
            // Execute stage redirect conditions.
            $non_pipelined = $div_mul m4_ifelse(M4_EXT_F, 1, ['|| $fpu_div_sqrt_type_instr']) m4_ifelse(M4_EXT_B, 1, ['|| $clmul_crc_type_instr']);
            $replay_trap = m4_cpu_blocked;
            $aborting_trap = $replay_trap || ($valid_decode && $illegal) || $aborting_isa_trap;
            $non_aborting_trap = $non_aborting_isa_trap;
            $mispred_branch = $branch && ! ($conditional_branch && ($taken == $pred_taken));
            ?$valid_decode_branch
               $branch_redir_pc[M4_PC_RANGE] =
                  // If fallthrough predictor, branch mispred always redirects taken, otherwise PC+1 for not-taken.
                  m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['(! $taken) ? $Pc + M4_PC_CNT'b1 :'])
                  $branch_target;
                  
            $trap_target[M4_PC_RANGE] = $replay_trap ? $Pc : {M4_PC_CNT{1'b1}};  // TODO: What should this be? Using ones to terminate test for now.
            
            // Determine whether the instruction should commit it's result.
            //
            // Abort: Instruction triggers a condition causing a no-commit.
            // Commit: Ultimate decision to commit results of this instruction, considering aborts and
            //         prior-instruction redirects (good-path)
            //
            // Treatment of loads:
            //    Loads will commit. They write a garbage value and "pending" to the register file.
            //    Returning loads clobber an instruction. This instruction is $abort'ed (as is the
            //    returning load, since they are one in the same). Returning load must explicitly
            //    write results.
            //
            
            $abort = m4_abort_terms;  // Note that register bypass logic requires that abort conditions also redirect.
            // $commit = m4_prev_instr_valid_through(M4_MAX_REDIRECT_BUBBLES + 1), where +1 accounts for this
            // instruction's redirects. However, to meet timing, we consider this instruction separately, so,
            // commit if valid as of the latest redirect from prior instructions and not abort of this instruction.
            m4_ifelse_block(M4_RETIMING_EXPERIMENT_ALWAYS_COMMIT, ['M4_RETIMING_EXPERIMENT_ALWAYS_COMMIT'], ['
            // Normal case:
            $good_path = m4_prev_instr_valid_through(M4_MAX_REDIRECT_BUBBLES);
            $commit = $good_path && ! $abort;
            '], ['
            // For the retiming experiments, $commit is determined too late, and it is inconvenient to make the $GoodPathMask
            // logic retimable. Let's drive it to 1'b1 for now, and give synthesis the benefit of the doubt.
            $commit = 1'b1 && ! $abort;
            '])
            
            // Conditions that commit results.
            $valid_dest_reg_valid = ($dest_reg_valid && $commit) || ($second_issue m4_ifelse_block(M4_EXT_F, 1, ['&&  (! >>M4_LD_RETURN_ALIGN$is_flw_instr) && (! $fpu_second_issue_div_sqrt)']) );
            
            m4_ifelse_block(M4_EXT_F, 1, ['
            $valid_dest_fpu_reg_valid = ($dest_fpu_reg_valid && $commit) || ($fpu_second_issue_div_sqrt || ($second_issue && >>M4_LD_RETURN_ALIGN$is_flw_instr));
            '])
            $valid_ld = $ld && $commit;
            $valid_st = $st && $commit;
            
   |fetch
      /instr
         @M4_REG_WR_STAGE
            // =========
            // Reg Write
            // =========
            
            // INPUT SIGNALS TO REGISTER FILE - WRITE//
            $valid_dest_reg_valid_wr = $valid_dest_reg_valid;
            $dest_reg_wr[4:0] = $dest_reg;
            $rslt_wr[M4_WORD_RANGE] = $rslt;
            $reg_wr_pending_wr = $reg_wr_pending;             
            
            /////////////////////////////////////////////////////////////////////////
            // NOW WRITING IN THE REGISTER FILE INSIDE A MODULE IN INCLUDE FILE //
            ////////////////////////////////////////////////////////////////////////
            
            
            m4_ifelse_block(M4_EXT_F, 1, ['
            // Reg Write (Floating Point Register)
            // TODO. Seperate the $rslt comit to both "int" and "fpu" regs.
            $fpu_reg_write = $reset ? 1'b0 : $valid_dest_fpu_reg_valid;
            \SV_plus
               always @ (posedge clk) begin
                  if ($fpu_reg_write)
                     /fpu_regs[$dest_fpu_reg]<<0$$^value[M4_WORD_RANGE] <= $rslt;
               end
            m4_ifelse_block(M4_PENDING_ENABLED, 1, ['
            // Write $pending along with $value, but coded differently because it must be reset.
            /fpu_regs[*]
               <<1$pending = ! /instr$reset && (((#fpu_regs == /instr$dest_fpu_reg) && /instr$valid_dest_fpu_reg_valid) ? /instr$reg_wr_pending : $pending);
              '])
            '])
            
         @M4_REG_WR_STAGE
            `BOGUS_USE(/orig_inst/src[2]$dummy) // To pull $dummy through $ANY expressions, avoiding empty expressions.
         
         // ====
         // Load
         // ====
         
         @M4_MEM_WR_STAGE
            ?$spec_ld
               $addr_data_load_sram[11:0] = $addr[M4_DATA_MEM_WORDS_INDEX_MAX + M4_SUB_WORD_BITS : M4_SUB_WORD_BITS]; 
               $ld_value[(M4_WORD_HIGH / M4_ADDRS_PER_WORD) - 1 : 0] = $dout_data;           
         // =====
         // Store
         // =====
      /byte_en[3:0]
         @M4_MEM_WR_STAGE
            $write_enable_byte = (|fetch/instr$valid_st && |fetch/instr$st_mask[#byte_en]) ? 1 : 0;
            
      /instr
         @M4_MEM_WR_STAGE
            $web = {|fetch/byte_en[3]$write_enable_byte,|fetch/byte_en[2]$write_enable_byte,|fetch/byte_en[1]$write_enable_byte,|fetch/byte_en[0]$write_enable_byte};
            $check_en_valid = ($web == 0) ? 0 : 1 ; 
            ?$check_en_valid
               $addr_data_store_sram[11:0] = $addr[M4_DATA_MEM_WORDS_INDEX_MAX + M4_SUB_WORD_BITS : M4_SUB_WORD_BITS]; 
               $din_data[M4_WORD_RANGE] = $st_value;
            $addr_data_sram[11:0] = ($spec_ld == 1) ? $addr_data_load_sram : ($check_en_valid == 1) ? $addr_data_store_sram : 0; 
            `BOGUS_USE($ld_value)
            `BOGUS_USE($valid_ld)
   |mem
      /data
         @m4_eval(m4_strip_prefix(['@M4_MEM_WR_STAGE']) - 0)
            $ANY = /top|fetch/instr>>0$ANY;
            /src[2:1]
               $ANY = /top|fetch/instr/src>>0$ANY;
               
            
   |fetch 
      /instr 
         @M4_REG_RD_STAGE
            \SV_plus
               register_file reg_file(
                          .clk($clk), 
                          .reset($reset),
                          .is_reg_rs1($is_reg1_rd),
                          .is_reg_rs2($is_reg2_rd), 
                          .valid_decode($valid_decode_rd), 
                          .dest_reg_valid($dest_reg_valid_rd), 
                          .reg_rs1($reg_rs1_rd),
                          .reg_rs2($reg_rs2_rd),
                          .valid_dest_reg_valid_rd($valid_dest_reg_valid_rd),
                          .goodPathMask($goodPathMask_rd),
                          .second_issue($second_issue_rd), 
                          .dest_reg($dest_reg_rd),
                          .dest_reg_now($dest_reg_now_rd), 
                          .rslt($rslt_rd),
                          .reg_wr_pending($reg_wr_pending_rd),
                          .replay_int($$replay_int_rd),
                          .out_pending1($$out_pending1_rd),
                          .out_pending2($$out_pending2_rd),
                          .reg_value1($$out_reg_value1_rd[31:0]),
                          .reg_value2($$out_reg_value2_rd[31:0]), 
                          .dest_pending($$out_dest_pending_rd),
                          .valid_dest_reg_valid_wr(>>m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE)$valid_dest_reg_valid_wr),
                          .dest_reg_wr(>>m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE)$dest_reg_wr),
                          .rslt_wr(>>m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE)$rslt_wr),
                          .reg_wr_pending_wr(>>m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE)$reg_wr_pending_wr)); 
                          
         @M4_EXECUTE_STAGE
            \SV_plus
               alu adder(
                         .clk($clk),
                         .reset($reset),
                         .reg_value1($reg_value1_alu), 
                         .reg_value2($reg_value2_alu),
                         .raw_i_imm($raw_i_imm_alu),
                         .raw_funct7_5($raw_funct7_5_alu), 
                         .valid_exe($valid_exe_alu), 
                         .addi_rslt($$addi_rslt_out[31:0]),
                         .add_rslt($$add_rslt_out[31:0]),
                         .sub_rslt($$sub_rslt_out[31:0]));
                         
         @M4_FETCH_STAGE
            \SV_plus
               sram #(
                        .NB_COL(4),                           // Specify number of columns (number of bytes)
                        .COL_WIDTH(8),                        // Specify column width (byte width, typically 8 or 9)
                        .RAM_DEPTH(2048),                     // Specify RAM depth (number of entries)
                        .RAM_PERFORMANCE("LOW_LATENCY"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
                        .INIT_FILE("home/atom/Warp-V/program.coe")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
                      )memory(
                       .addra($addr_instr_sram),   // Port A address bus, width determined from RAM_DEPTH
                       .addrb(>>m4_eval(M4_MEM_WR_STAGE - M4_FETCH_STAGE)$addr_data_sram),   // Port B address bus, width determined from RAM_DEPTH
                       .dina(0),   // Port A RAM input data
                       .dinb(>>m4_eval(M4_MEM_WR_STAGE - M4_FETCH_STAGE)$din_data),   // Port B RAM input data
                       .clka($clk),                            // Clock
                       .wea(0),                // Port A write enable
                       .web(>>m4_eval(M4_MEM_WR_STAGE - M4_FETCH_STAGE)$web),                // Port B write enable
                       .ena(1),                            // Port A RAM Enable, for additional power savings, disable port when not in use
                       .enb(1),                             // Port B RAM Enable, for additional power savings, disable port when not in use
                       .rsta($reset),                            // Port A output reset (does not affect memory contents)
                       .rstb($reset),                            // Port B output reset (does not affect memory contents)
                       .regcea(0),                          // Port A output register enable
                       .regceb(0),                          // Port B output register enable
                       .douta($$dout_instr[31:0]), // Port A RAM output data
                       .doutb(>>m4_eval(M4_MEM_WR_STAGE - M4_FETCH_STAGE)$$dout_data[31:0])  // Port B RAM output data
                     );
         
   
\SV
   endmodule

