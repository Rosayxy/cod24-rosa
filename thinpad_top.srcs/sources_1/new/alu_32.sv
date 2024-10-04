`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/10/04 21:10:35
// Design Name: 
// Module Name: alu_32
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


module alu_32(
   // input wire clk,
   // input wire reset, // 这个好像不是时序逻辑？ 所以不需要时钟信号？
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] op,
    output reg [31:0] y
    );
    // TODO write logic
    always_comb begin
        case(op)
            4'b0001: y = a + b;
            4'b0010: y = a - b;
            4'b0011: y = a & b;
            4'b0100: y = a | b;
            4'b0101: y = a ^ b;
            4'b0110: y = ~a;
            4'b0111: y = a << b;
            4'b1000: y = a >> b;
            4'b1001: y = a >>> b;
            4'b1010: y = a << b | a >> (32 - b);
            default: y = 31'b0;
        endcase
    end
endmodule
