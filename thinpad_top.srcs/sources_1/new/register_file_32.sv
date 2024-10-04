`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/10/04 21:11:28
// Design Name: 
// Module Name: register_file_32
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


module register_file_32(
    input wire [4:0] raddr_a,
    input wire [4:0] raddr_b,
    input wire [4:0] waddr,
    input wire [31:0] wdata,
    input wire we,
    input wire clk,
    input wire reset,
    output reg [31:0] rdata_a,
    output reg [31:0] rdata_b
    );
    // 内部变量： 所有 riscv 寄存器
    reg [31:0] regs[0:31];

    // TODO write logic
    always_ff @(posedge clk or posedge reset) begin
        if(reset) begin
            rdata_a <= 32'b0;
            rdata_b <= 32'b0;
            for(int i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
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
