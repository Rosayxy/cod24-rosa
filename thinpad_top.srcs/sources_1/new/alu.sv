`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/09/15 17:36:52
// Design Name: 
// Module Name: alu
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


module alu(
   // input wire clk,
   // input wire reset, // 这个好像不是时序逻辑？ 所以不需要时钟信号？
    input wire [15:0] a,
    input wire [15:0] b,
    input wire [3:0] op,
    output reg [15:0] y
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
            4'b0111: y = a << (b&4'b1111);
            4'b1000: y = a >> (b&4'b1111);
            4'b1001: y = $signed(a) >>> (b&4'b1111); // 算术右移
            4'b1010: y = a << (b&4'b1111) | a >> (16 - (b&4'b1111)); // todo 实现的有问题
            default: y = 16'b0;
        endcase
    end
endmodule
