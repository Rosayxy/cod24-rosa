`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/10/07 22:42:14
// Design Name: 
// Module Name: trigger
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


module trigger(
    input wire push,
    input wire clk,
    output reg out
    );

    reg prev;
    always_ff @(posedge clk) begin
        if(push && !prev) begin
            out <= 1;
        end
        else begin
            out <= 0;
        end
        prev <= push;
    end
endmodule
