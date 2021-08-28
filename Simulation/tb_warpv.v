`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/16/2021 10:39:29 PM
// Design Name: 
// Module Name: tb_warpv
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_warpv();
    reg clock ;
    reg rst ;
    wire led ;
    cpu warpv(.clk(clock), .reset(rst) ,.led(led));
    
    initial 
    begin 
    	$dumpfile ("./../Simulation/out.vcd"); 
	$dumpvars(0, tb_warpv);
        rst = 1;
        clock = 0;
        #200 rst = 0 ; 
        
    end 
   
    // generate clock
    always #(5) clock = ~clock;

    initial begin 
    
        #20000 $finish;  // 18 ms (one frame is 16.7 ms)]
        
    end


endmodule
