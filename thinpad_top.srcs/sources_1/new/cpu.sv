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

    input wire push_btn,
    input wire reset_btn,
    input wire [31:0] dip_sw,     // 32 位拨码开关，拨到“ON”时为 1
    output reg [15:0] leds,       // 16 位 LED，输出时 1 点亮 按照之前 tester 的模式点亮
    // wishbone master 分隔开两段吧

    // connect with icache
    output reg wbic_cyc_o,
    output reg wbic_stb_o,
    input wire wbic_ack_i,
    output reg [ADDR_WIDTH-1:0] wbic_adr_o,
    output reg [DATA_WIDTH-1:0] wbic_dat_o,
    input wire [DATA_WIDTH-1:0] wbic_dat_i,
    output reg [DATA_WIDTH/8-1:0] wbic_sel_o,
    output reg wbic_we_o,

    // connect with (to be) dcache
    output reg wbdc_cyc_o,
    output reg wbdc_stb_o,
    input wire wbdc_ack_i,
    output reg [ADDR_WIDTH-1:0] wbdc_adr_o,
    output reg [DATA_WIDTH-1:0] wbdc_dat_o,
    input wire [DATA_WIDTH-1:0] wbdc_dat_i,
    output reg [DATA_WIDTH/8-1:0] wbdc_sel_o,
    output reg wbdc_we_o,

    // connect with alu
    output reg [31:0] alu_a,
    output reg [31:0] alu_b,
    output reg [3:0] alu_op,
    input wire [31:0] alu_y,

    // connect with register file
    output reg [4:0] raddr_a,
    output reg [4:0] raddr_b,
    output reg [4:0] waddr,
    output reg [31:0] wdata,
    output reg we,
    input wire [31:0] rdata_a,
    input wire [31:0] rdata_b,

    output reg [4:0] state_dbg,
    output wire wbic_cyc_o_dbg,
    output wire [ADDR_WIDTH-1:0] wbic_adr_o_dbg
);

  typedef enum logic [4:0] {  
    STATE_IF,   // 0
    STATE_ID,   // 1
    STATE_EXE_ARITH, // 2
    STATE_WB_ARITH,  // 3
    STATE_EXE_BEQ, // 4
    STATE_EXE_LD,  // 5
    STATE_READ_LD,  // 6
    STATE_REG_LD,   // load 的值写回 regfile 7
    STATE_EXE_ST, // store 8
    STATE_WRITE_ST // store 9
  } state_t;

  typedef enum logic [2:0]{
    STATE_ASSIGN,
    STATE_WAIT,
    STATE_DONE
  } regfile_state_t;

  typedef enum logic [3:0]{
    LUI,       // 0
    BEQ,       // 1
    LB,        // 2
    SB,       // 3
    SW,       // 4
    ADDI,     // 5
    ANDI,     // 6
    ADD,       // 7
    UNK  // unknown 8
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
  logic [31:0] rs1_val, rs2_val, rd_val;
  logic exe_arith_done; // 标志是赋值的状态还是从 alu 取数的状态
  logic [4:0] shift_val; // 因为非对齐访问，取值回来之后需要右移的位数
  logic [11:0] sram_addr_tmp; // 临时算出的 sram_addr
  logic exe_beq_done; // beq 的执行状态
  logic exe_mem_done; // load/store 的执行状态
  logic [1:0] reg_write_state; // 写回寄存器的状态
  logic is_split;     // 非对齐访问，store 分两次写入

  always_comb begin
    case (sram_addr_tmp%4)
      2'b00: shift_val = 5'd0;
      2'b01: shift_val = 5'd8;
      2'b10: shift_val = 5'd16;
      2'b11: shift_val = 5'd24;
    endcase
  end

  // TODO debug info
  assign wbic_cyc_o_dbg = wbic_cyc_o;
  assign wbic_adr_o_dbg = pc_reg;
  // // 计算sel_o todo 思考特殊情况：非对齐访问中 store 分两次写入
  // // TODO 把这一段移到时序逻辑里面！！
  // always_comb begin
  //   if (ty == LB||ty==SB) begin
  //     case(sram_addr_tmp%4)
  //     2'b00: wb_sel_o = 4'b0001;
  //     2'b01: wb_sel_o = 4'b0010;
  //     2'b10: wb_sel_o = 4'b0100;
  //     2'b11: wb_sel_o = 4'b1000;
  //     endcase
  //   end
  //   else begin
  //     case(sram_addr_tmp%4)
  //     2'b00: wb_sel_o = 4'b0011;
  //     2'b01: wb_sel_o = 4'b0110;
  //     2'b10: wb_sel_o = 4'b1100;
  //     2'b11: begin
  //       wb_sel_o = 4'b1000;
  //       is_split = 1'b1;
  //     end
  //     endcase
  //   end
  // end

  always_comb begin
    case(instr_reg[6:0])
      7'b0110111:begin
         ty = LUI;
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
         if (instr_reg[14:12] == 3'b010) begin
           ty = SW;
         end
         else begin
          ty = SB;
          end

         imm ={instr_reg[31:25],instr_reg[11:7]};
          rs1 = instr_reg[19:15];
          rs2 = instr_reg[24:20];
      end
      7'b0010011:begin
        if (instr_reg[14:12] == 3'b000) begin
         ty = ADDI;
        end
        else begin
          ty = ANDI;
        end
        rs1= instr_reg[19:15];
        imm = instr_reg[31:20];
        rd= instr_reg[11:7];

      end
      7'b0110011:begin
         ty = ADD;
          rs1 = instr_reg[19:15];
          rs2 = instr_reg[24:20];
          rd = instr_reg[11:7];
      end
      default: begin
        ty = UNK;

      end
    endcase
  end

always_ff @ (posedge clk or posedge rst) begin
    if (rst) begin
        pc_reg <= 32'h8000_0000;
        pc_now_reg <= 32'h8000_0000;
        instr_reg <= 32'h00000000;

        leds <= 16'h0000;

        wbic_cyc_o <= 1'b0;
        wbic_stb_o <= 1'b0;
        wbic_adr_o <= 32'h0000_0000;
        wbic_dat_o <= 32'h0000_0000;
        wbic_sel_o <= 4'h0;
        wbic_we_o <= 1'b0;
        
        wbdc_cyc_o <= 1'b0;
        wbdc_stb_o <= 1'b0;
        wbdc_adr_o <= 32'h0000_0000;
        wbdc_dat_o <= 32'h0000_0000;
        wbdc_sel_o <= 4'h0;
        wbdc_we_o <= 1'b0;

        alu_a <= 32'h0000;
        alu_b <= 32'h0000;
        alu_op <= 4'h0;

        raddr_a <= 5'h0;
        raddr_b <= 5'h0;
        waddr <= 5'h0;
        wdata <= 32'h0000;
        we <= 1'b0;
        state <= STATE_IF;
        lui_imm <= 32'h0000_0000;

        rs1_val <= 32'h0000;
        rs2_val <= 32'h0000;
        rd_val <= 32'h0000;
        regfile_state <= STATE_ASSIGN;
        exe_arith_done <= 1'b0;
        sram_addr_tmp <= 12'h0000;
        exe_beq_done <= 1'b0;
        exe_mem_done <= 1'b0;
        reg_write_state <= 2'h0;
        is_split <= 1'b0;

        state_dbg <= 5'h0;
    end
    else begin
        case(state)
            STATE_IF: begin
                pc_now_reg <= pc_reg;
                wbic_adr_o <= pc_reg;
                wbic_cyc_o <= 1'b1;
                wbic_stb_o <= 1'b1;
                wbic_we_o <= 1'b0;
                wbic_sel_o <= 4'b1111;

                if (wbic_ack_i) begin
                    instr_reg <= wbic_dat_i;
                    state <= STATE_ID;
                    pc_reg <= pc_reg + 32'h00000004;
                    wbic_cyc_o <= 1'b0;
                    wbic_stb_o <= 1'b0;

                    state_dbg <= 1;
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
                        state_dbg <= 2;
                    end
                    else if(ty==BEQ) begin
                        state <= STATE_EXE_BEQ;
                        state_dbg <= 4;
                    end
                    else if(ty==LB) begin
                        state <= STATE_EXE_LD;
                        state_dbg <= 5;
                    end
                    else if(ty==SB||ty==SW) begin
                        state <= STATE_EXE_ST;
                        state_dbg <= 8;
                    end 
                    else begin
                        state <= STATE_IF;
                        state_dbg <= 0;
                    end
                    if (ty == LUI) begin
                      lui_imm <= {instr_reg[31:12], 12'h000};
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
                    alu_b <= 16'h0000;
                    alu_op <= 4'b0001; // lui_imm 是平移后的结果
                  end
                  exe_arith_done <= 1'b1;
                end
                else begin
                  exe_arith_done <= 1'b0;
                  state <= STATE_WB_ARITH;
                  rd_val <= alu_y;

                  state_dbg <= 3;
                end
            end
            STATE_WB_ARITH: begin
                // 写回寄存器 设定成多周期
                if (reg_write_state==0) begin
                waddr <= rd;
                wdata <= rd_val;
                we <= 1'b1;
                reg_write_state <= 1;
                end
                else if (reg_write_state==1) begin
                  reg_write_state <= 2;
                end
                if (reg_write_state==2) begin
                  we <= 1'b0;
                  reg_write_state <= 0;
                  state <= STATE_IF;
                  state_dbg <= 0;
                end
            end
            STATE_EXE_BEQ: begin
              if(rs1_val==rs2_val) begin
                // imm 可能需要符号扩展，因为 lui_imm 没人用 就用它了
                if(!exe_beq_done) begin
                lui_imm <= $signed(imm);
                exe_beq_done <= 1'b1;
                end
                else begin
                  exe_beq_done <= 1'b0;
                  // 这个需要等一个周期
                  pc_reg <= pc_now_reg + lui_imm;
                  state <= STATE_IF;
                  state_dbg <= 0;
                end
              end
              else begin
                state <= STATE_IF;
                state_dbg <= 0;
              end
            end
            STATE_EXE_LD: begin
              // 算 base_reg + offset 算 sel_o 考虑到非对齐访问，最后到某个阶段要右移
              // 符号扩展
              if (!exe_mem_done) begin
              lui_imm <= $signed(imm);
              exe_mem_done <= 1'b1;
              end
              else begin
                exe_mem_done <= 1'b0;
                sram_addr_tmp <= rs1_val + lui_imm;
                state <= STATE_READ_LD;
                state_dbg <= 6;
              end
            end
            STATE_READ_LD: begin
              wbdc_adr_o <= $signed(imm)+rs1_val;
              wbdc_cyc_o <= 1'b1;
              wbdc_stb_o <= 1'b1;
              wbdc_we_o <= 1'b0;

              // wb_sel_o 已经在上面赋值了 但是因为过不了编译 所以移到这里了
              case(sram_addr_tmp%4)
                2'b00: wbdc_sel_o = 4'b0001;
                2'b01: wbdc_sel_o = 4'b0010;
                2'b10: wbdc_sel_o = 4'b0100;
                2'b11: wbdc_sel_o = 4'b1000;
              endcase

              if (wbdc_ack_i) begin
                case (wbdc_adr_o%4)
                  2'b00: begin
                    rd_val <= wbdc_dat_i[7:0];
                  end
                  2'b01: begin
                    rd_val <= wbdc_dat_i[15:8];
                  end
                  2'b10: begin
                    rd_val <= wbdc_dat_i[23:16];
                  end
                  2'b11: begin
                    rd_val <= wbdc_dat_i[31:24];
                  end
                endcase

                wbdc_cyc_o <= 1'b0;
                wbdc_stb_o <= 1'b0;
                state <= STATE_REG_LD;
                state_dbg <= 7;
              end
            end

            STATE_REG_LD: begin
              if (reg_write_state==0) begin
                waddr <= rd;
                wdata <= rd_val;
                we <= 1'b1;
                reg_write_state <= 1;
              end
              else if (reg_write_state==1) begin
                reg_write_state <= 2;
              end
              else begin
                we <= 1'b0;
                reg_write_state <= 0;
                state <= STATE_IF;
                state_dbg <= 0;
              end
            end
            STATE_EXE_ST: begin
              // store 的执行阶段
              if (!exe_mem_done) begin
              lui_imm <= $signed(imm);
              exe_mem_done <= 1'b1;
              end
              else begin
                exe_mem_done <= 1'b0;
                sram_addr_tmp <= rs1_val + lui_imm;
                state <= STATE_WRITE_ST;
                if ((rs1_val + lui_imm)%4 ==3) begin
                  is_split <= 1;
                end

                state_dbg <= 9;
              end
            end
            STATE_WRITE_ST: begin  // 应该到这里 is_split 已经被正常赋值了 非对齐访问是正常的么
              if (!is_split) begin
                wbdc_adr_o <= rs1_val + $signed(imm);
                wbdc_dat_o <= rs2_val;  // TODO 考虑要不要左移
                wbdc_cyc_o <= 1'b1;
                wbdc_stb_o <= 1'b1;
                wbdc_we_o <= 1'b1;
                if (ty == SB) begin
                  case(sram_addr_tmp%4)
                    2'b00: wbdc_sel_o = 4'b0001;
                    2'b01: wbdc_sel_o = 4'b0010;
                    2'b10: wbdc_sel_o = 4'b0100;
                    2'b11: wbdc_sel_o = 4'b1000;
                    endcase
                end
                else begin
                  case(sram_addr_tmp%4)
                    2'b00: wbdc_sel_o = 4'b0011;
                    2'b01: wbdc_sel_o = 4'b0110;
                    2'b10: wbdc_sel_o = 4'b1100;
                    2'b11: wbdc_sel_o = 4'b0001;
                  endcase
                end
                if (wbdc_ack_i) begin
                  wbdc_cyc_o <= 1'b0;
                  wbdc_stb_o <= 1'b0;
                  state <= STATE_IF;
                  state_dbg <= 0;
                end
              end
              else begin  // 这个分状态写吧
                wbdc_adr_o <= sram_addr_tmp;
                wbdc_dat_o <= rs2_val[7:0];
                wbdc_cyc_o <= 1'b1;
                wbdc_stb_o <= 1'b1;
                wbdc_we_o <= 1'b1;
                wbdc_sel_o <= 4'b1000;
                if (wbdc_ack_i) begin
                  sram_addr_tmp <= sram_addr_tmp + 4;   // 这个确定是 + 1 莫 **改了这里**
                  // 这一步的 write2ram 是把 rs2_val 换成 rs2_val 的次低8位然后写进去 但是因为之前 always_comb 的原因 使能是 b0011 
                  // 如果之后有问题的话 把 always_comb 的分支换成 write_word/write_byte 试试
                  is_split <= 0;
                  rs2_val <= rs2_val[15:8];
                  wbdc_cyc_o <= 1'b0;
                  wbdc_stb_o <= 1'b0;
                end
              end
            end
        endcase
    end
end    
endmodule
