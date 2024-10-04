`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/10/04 15:28:40
// Design Name: 
// Module Name: cpu
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


module cpu #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,

    // TODO: 添加需要的控制信号，例如按键开关? 还要把 leds 信号接出去
    input wire push_btn,
    input wire reset_btn,
    input wire [31:0] dip_sw,     // 32 位拨码开关，拨到“ON”时为 1
    output reg [15:0] leds,       // 16 位 LED，输出时 1 点亮 按照之前 tester 的模式点亮
    // wishbone master
    output reg wb_cyc_o,
    output reg wb_stb_o,
    input wire wb_ack_i,
    output reg [ADDR_WIDTH-1:0] wb_adr_o,
    output reg [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output reg [DATA_WIDTH/8-1:0] wb_sel_o,
    output reg wb_we_o,

    // connect with alu
    output reg [15:0] alu_a,
    output reg [15:0] alu_b,
    output reg [3:0] alu_op,
    input wire [15:0] alu_y,

    // connect with register file
    output reg [4:0] raddr_a,
    output reg [4:0] raddr_b,
    output reg [4:0] waddr,
    output reg [15:0] wdata,
    output reg we,
    input wire [15:0] rdata_a,
    input wire [15:0] rdata_b

);

  typedef enum logic [4:0] {  
    STATE_IF,   // 0
    STATE_ID,   // 1
    STATE_EXE_ARITH, // 2
    STATE_WB_ARITH,  // 3
    STATE_EXE_BEQ, // 4
    STATE_EXE_LD,
    STATE_READ_LD,
    STATE_EXE_ST, // store
    STATE_WRITE_ST // store
  } state_t;

  typedef enum logic [2:0]{
    STATE_ASSIGN,
    STATE_WAIT,
    STATE_DONE
  } regfile_state_t;
  typedef enum logic [3:0]{
    LUI,
    BEQ,
    LB,
    SB,
    SW,
    ADDI,
    ANDI,
    ADD,
    UNK  // unknown
  }instr_type;

reg [31:0] pc_reg;
reg [31:0] pc_now_reg;
reg [31:0] instr_reg;
state_t state;
regfile_state_t regfile_state;
  instr_type ty;
  logic [12:0] imm; // 12 or 13 bits
  logic [31:0] lui_imm;
  logic [4:0] rd, rs1, rs2;
  logic [15:0] rs1_val, rs2_val, rd_val;
  logic exe_arith_done; // 标志是赋值的状态还是从 alu 取数的状态
  
  always_comb begin
    case(instr_reg[6:0])
      7'b0110111:begin
         ty = LUI;
          lui_imm = instr_reg[31:12]<<12;
          rd= instr_reg[11:7];
      end
      7'b1100011:begin
         ty = BEQ;
         imm= {instr_reg[31],instr_reg[7],instr_reg[30:25],instr_reg[11:8],1'b0};
          rs1 = instr_reg[19:15];
          rs2 = instr_reg[24:20];
      end
      7'b0000011:begin
         ty = LB;
         imm=instr_reg[31:20];
          rs1 = instr_reg[19:15];
          rd = instr_reg[11:7];
      end
      7'b0100011:begin
         if (instr_reg[14:12] == 3'b010) ty = SW;
         else ty = SB;
         imm ={instr_reg[7:11],instr_reg[31:25]};
          rs1 = instr_reg[19:15];
          rs2 = instr_reg[24:20];
      end
      7'b0010011:begin
        if (instr_reg[14:12] == 3'b000) ty = ADDI;
        else ty = ANDI;
        rs1= instr_reg[19:15];
        imm = instr_reg[31:20];
      end
      7'b0110011:begin
         ty = ADD;
          rs1 = instr_reg[19:15];
          rs2 = instr_reg[24:20];
          rd = instr_reg[11:7];
      end
      default: ty = UNK;
    endcase
  end

always_ff @ (posedge clk or posedge rst) begin
    if (rst) begin
        pc_reg <= 32'h8000_1000;
        pc_now_reg <= 32'h8000_1000;
        instr_reg <= 32'h00000000;

        leds <= 16'h0000;
        wb_cyc_o <= 1'b0;
        wb_stb_o <= 1'b0;
        wb_adr_o <= 32'h00000000;
        wb_dat_o <= 32'h00000000;
        wb_sel_o <= 4'h0;
        wb_we_o <= 1'b0;

        alu_a <= 16'h0000;
        alu_b <= 16'h0000;
        alu_op <= 4'h0;

        raddr_a <= 5'h0;
        raddr_b <= 5'h0;
        waddr <= 5'h0;
        wdata <= 16'h0000;
        we <= 1'b0;
        state <= STATE_IF;
        ty <= UNK;
        imm <= 13'h0000;
        lui_imm <= 32'h0000_0000;
        rd <= 5'h0;
        rs1 <= 5'h0;
        rs2 <= 5'h0;
        rs1_val <= 16'h0000;
        rs2_val <= 16'h0000;
        rd_val <= 16'h0000;
        regfile_state <= STATE_ASSIGN;
        exe_arith_done <= 1'b0;
    end
    else begin
        case(state)
            STATE_IF: begin
                pc_now_reg <= pc_reg;
                wb_adr_o = pc_reg;
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o = 1'b0;
                wb_sel_o = 4'b1111;
                if (wb_ack_i) begin
                    instr_reg <= wb_dat_i;
                    state <= STATE_ID;
                    pc_reg <= pc_reg + 32'h00000004;
                end
            end
            STATE_ID: begin
               // 在这个周期的开始，ty imm 这些都已经被赋值了 所以只需要把 rs1, rs2 给寄存器堆读出数据就好了
               if (regfile_state == STATE_ASSIGN) begin
                   raddr_a <= rs1;
                   raddr_b <= rs2;
                   regfile_state <= STATE_WAIT;
               end
               else if (regfile_state == STATE_WAIT) begin
                   regfile_state <= STATE_DONE;
               end
               else if (regfile_state == STATE_DONE) begin
                    rs1_val <= rdata_a;
                    rs2_val <= rdata_b;
                    regfile_state <= STATE_ASSIGN;
                    if(ty==LUI||ty==ADDI||ty==ANDI||ty==ADD) begin
                        state <= STATE_EXE_ARITH;
                    end
                    else if(ty==BEQ) begin
                        state <= STATE_EXE_BEQ;
                    end
                    else if(ty==LB) begin
                        state <= STATE_EXE_LD;
                    end
                    else if(ty==SB||ty==SW) begin
                        state <= STATE_EXE_ST;
                    end
                    else begin
                        state <= STATE_IF;
                    end
               end
            end
            STATE_EXE_ARITH: begin
                // 传信号给 alu 等待 alu 返回 这里应该也需要等待一个周期
                if (!exe_arith_done) begin
                  if(ty==ADD) begin
                    alu_a <= rs1_val;
                    alu_b <= rs2_val;
                    alu_op <= 4'b0001;
                  end
                  else if (ty==ADDI) begin
                    alu_a <= rs1_val;
                    alu_b <= imm;
                    alu_op <= 4'b0001;
                  end
                  else if (ty==ANDI) begin
                    alu_a <= rs1_val;
                    alu_b <= imm;
                    alu_op <= 4'b0011;
                  end
                  else if (ty==LUI) begin
                    alu_a <= lui_imm;
                    alu_b <= 16'h000c;
                    alu_op <= 4'b0111;
                  end
                  exe_arith_done <= 1'b1;
                end
                else begin
                  exe_arith_done <= 1'b0;
                  state <= STATE_WB_ARITH;
                  rd_val <= alu_y;
                end
            end
            STATE_WB_ARITH: begin
                // 写回寄存器
                waddr <= rd;
                wdata <= rd_val;
                we <= 1'b1;
                state <= STATE_IF;
            end
            STATE_EXE_BEQ: begin
              if(rs1_val==rs2_val) begin
                // imm 可能需要符号扩展，因为 lui_imm 没人用 就用它了
                if (imm[12]) begin
                  lui_imm = {19{imm[12]}}+imm;
                end
                else begin
                  lui_imm = imm;
                end
                pc_reg <= pc_now_reg + lui_imm;
                state <= STATE_IF;
              end
            end
            STATE_EXE_LD: begin
              // 算出 load 的偏移 此外该步也要处理非对齐

            end
        endcase
    end
end    
endmodule
