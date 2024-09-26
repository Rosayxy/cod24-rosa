`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/09/15 17:58:47
// Design Name: 
// Module Name: register_file
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


module register_file(
    input wire [4:0] raddr_a,
    input wire [4:0] raddr_b,
    input wire [4:0] waddr,
    input wire [15:0] wdata,
    input wire we,
    input wire clk,
    input wire reset,
    output reg [15:0] rdata_a,
    output reg [15:0] rdata_b
    );
    // 内部变量： 所有 riscv 寄存器
    reg [15:0] regs[0:31];

    // TODO write logic
    always_ff @(posedge clk or posedge reset) begin
        if(reset) begin
            rdata_a <= 16'b0;
            rdata_b <= 16'b0;
            for(int i = 0; i < 32; i = i + 1) begin
                regs[i] <= 16'b0;
            end

        end
        else begin
            if(we) begin
                if(waddr > 0 && waddr <= 31) begin
                    regs[waddr] <= wdata;
                end
            end
            // read
            if(raddr_a >= 0 && raddr_a <= 31) begin
                rdata_a <= regs[raddr_a];
            end
            if(raddr_b >= 0 && raddr_b <= 31) begin
                rdata_b <= regs[raddr_b];
            end
        end
    end
endmodule
