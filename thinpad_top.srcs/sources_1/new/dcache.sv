`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/11/04 20:49:59
// Design Name: 
// Module Name: dcache
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


module dcache #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,

    parameter SRAM_ADDR_WIDTH = 20,
    parameter SRAM_DATA_WIDTH = 32,

    localparam SRAM_BYTES = SRAM_DATA_WIDTH / 8, // 4
    localparam SRAM_BYTE_WIDTH = $clog2(SRAM_BYTES) // 2
)(
    input wire clk_i,
    input wire rst_i,

    // wishbone slave interface
    input wire wb_cyc_i,
    input wire wb_stb_i,
    output reg wb_ack_o,
    input wire [ADDR_WIDTH-1:0] wb_adr_i,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output reg [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH/8-1:0] wb_sel_i,
    input wire wb_we_i,

    // sram_controller interface
    output reg wbs_cyc_o,
    output reg wbs_stb_o,
    input wire wbs_ack_i,
    output reg [ADDR_WIDTH-1:0] wbs_adr_o,
    output reg [DATA_WIDTH-1:0] wbs_dat_o,
    input wire [DATA_WIDTH-1:0] wbs_dat_i,
    output reg [DATA_WIDTH/8-1:0] wbs_sel_o,
    output reg wbs_we_o,

    // to icache 所有的 invalidate_o 都在 WAIT_ACK 之前给 在 WAIT_ACK 的时候拉下来
    output reg invalidate_o,
    output reg [ADDR_WIDTH-1:0] invalidate_addr_o,   // 这俩信号只用给一个周期就行

    // todo 把信号接出来试试
    output reg [3:0] state_dbg,
    output wire  wbs_cyc_o_dbg,
    output wire [31:0] wbs_adr_o_dbg,
    output wire [31:0] wbs_dat_o_dbg,
    output wire wbs_ack_i_dbg,
    output wire [31:0] wbs_dat_i_dbg,
    output wire [31:0] wb_dat_o_dbg,
    output wire wb_ack_o_dbg,
    output wire [31:0] wb_dat_i_dbg,
    output wire [31:0] wb_adr_i_dbg
);
// cache layout: 四路组相联，总大小 4kB 块 16 字节 共 64 行 (64*16*4)
// 每行结构：有效位 1 位，地址32位，tag 22 位 地址 belike tag [31:10] index [9:4] offset [3:0] 而我们一个块的结构是 valid + tag[149:128] + data[127:0]
// 重要：往 cache 里面塞块的地址一定是 16 字节的倍数，之前 icache 的设计 narrow down 了非对齐访问的一些情况，我们这里需要考虑的情况更多
// TODO 输出信号看看 dcache 是不是正常的 好像现在 read 有问题 判断 hit miss 的时候
reg [150:0] cache [63:0][3:0];
reg [127:0] block;
reg [21:0] tag;
reg valid;
reg [3:0] index;
reg [1:0] way;
reg [3:0] i;
reg [1:0] offset;
reg [1:0] offset_least;
reg[DATA_WIDTH/8-1:0] tmp_sel;
reg [3:0] free_way[63:0];
reg [3:0] tmp_way;
reg [31:0] mask;


typedef enum logic [4:0] {
    STATE_HIT,   // 0
    STATE_READ_0,   // 1
    STATE_READ_1,   // 2
    STATE_READ_2, // 3
    STATE_READ_3,  // 4
    STATE_WAIT_ACK, // 5
    STATE_THROUGH_READ // 6
} state_t;

state_t state;

always_comb begin
    index = wb_adr_i[9:4];
    tag = wb_adr_i[31:10];
    offset = wb_adr_i[3:2];
    offset_least = wb_adr_i[1:0];
    // generate mask according to sel
    mask = 32'h0;
    for (int i = 0; i < 4; i = i + 1) begin
        mask[i*8 +: 8] = wb_sel_i[i] ? 8'hff : 8'h00;
    end
end

assign wbs_cyc_o_dbg = wbs_cyc_o;
assign wbs_adr_o_dbg = wbs_adr_o;
assign wbs_dat_o_dbg = wbs_dat_o;
assign wbs_ack_i_dbg = wbs_ack_i;
assign wb_dat_o_dbg = wb_dat_o;
assign wb_ack_o_dbg = wb_ack_o;
assign wbs_dat_i_dbg = wbs_dat_i;
assign wb_dat_i_dbg = wb_dat_i;
assign wb_adr_i_dbg = wb_adr_i;

always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
        state <= STATE_HIT;
        wb_ack_o <= 1'b0;
        wb_dat_o <= 0;
        wbs_cyc_o <= 1'b0;
        wbs_stb_o <= 1'b0;
        wbs_adr_o <= 0;
        wbs_dat_o <= 0;
        wbs_sel_o <= 0;
        wbs_we_o <= 0;

        for (int i = 0; i < 64; i = i + 1) begin
            for (int j = 0; j < 4; j = j + 1) begin
                cache[i][j] <= 0;
            end
        end
        for(int i = 0; i < 64; i = i + 1) begin
            free_way[i] <= 0;
        end
        i<=0;
        way<=0;
        tmp_sel<=0;
        invalidate_o<=0;
        invalidate_addr_o<=0;

        state_dbg <= 0;
    end else begin
        case (state)
            STATE_HIT: begin
                if (wb_cyc_i && wb_stb_i) begin
                    if(wb_adr_i > 32'h8000_0000 && wb_adr_i<32'h80800000) begin
                        if(!wb_we_i) begin
                            for (int j = 0; j < 4; j = j + 1) begin
                                if (cache[index][j][150:150] == 1 && cache[index][j][149:128] == tag) begin
                                    state <= STATE_HIT;
                                    wb_ack_o <= 1'b1;
                                    wb_dat_o <= cache[index][j][offset*32+:32] & mask;
                                    break;
                                end
                            end

                            if(!(cache[index][0][150:150]==1 && cache[index][0][149:128] == tag)&&!(cache[index][1][150:150]==1 && cache[index][1][149:128] == tag)&&!(cache[index][2][150:150]==1 && cache[index][2][149:128] == tag)&&!(cache[index][3][150:150]==1 && cache[index][3][149:128] == tag)) begin
                                state <= STATE_READ_0;
                                wbs_cyc_o <= 1'b1;
                                wbs_stb_o <= 1'b1;
                                // round down to 16 bytes
                                wbs_adr_o <= {wb_adr_i[31:4], 4'h0};
                                wbs_sel_o <= 4'b1111;
                                wbs_we_o <= 1'b0;
                                wb_ack_o <= 1'b0;
                                state_dbg <= 1;
                            end
                        end else begin
                            // start matching
                            for (int j = 0; j < 4; j = j + 1) begin
                                if (cache[index][j][150:150] == 1 && cache[index][j][149:128] == tag) begin
                                    state <= STATE_WAIT_ACK;
                                    cache[index][j][offset*32 +: 32] <= (wb_dat_i & mask) | (cache[index][j][offset*32 +: 32] & ~mask);
                                    // send wishbone request
                                    wbs_cyc_o <= 1'b1;
                                    wbs_stb_o <= 1'b1;
                                    wbs_adr_o <= wb_adr_i;
                                    wbs_dat_o <= wb_dat_i;
                                    wbs_sel_o <= wb_sel_i;
                                    wbs_we_o <= 1'b1;

                                    // invalidate for icache
                                    invalidate_o <= 1'b1;
                                    invalidate_addr_o <= wb_adr_i;

                                    state_dbg <= 5;
                                    break;
                                end
                            end
                            if (!(cache[index][0][150:150]==1 && cache[index][0][149:128] == tag)&&!(cache[index][1][150:150]==1 && cache[index][1][149:128] == tag)&&!(cache[index][2][150:150]==1 && cache[index][2][149:128] == tag)&&!(cache[index][3][150:150]==1 && cache[index][3][149:128] == tag)) begin
                                state <= STATE_WAIT_ACK;
                                wbs_cyc_o <= 1'b1;
                                wbs_stb_o <= 1'b1;
                                wbs_adr_o <= wb_adr_i;
                                wbs_dat_o <= wb_dat_i;
                                wbs_sel_o <= wb_sel_i;
                                wbs_we_o <= 1'b1;
                                invalidate_o <= 1'b1;
                                invalidate_addr_o <= wb_adr_i;

                                state_dbg <= 5;
                            end
                        end
                    end else begin
                        // 直接转发请求
                        wbs_cyc_o <= 1'b1;
                        wbs_stb_o <= 1'b1;
                        wbs_adr_o <= wb_adr_i;
                        wbs_dat_o <= wb_dat_i;
                        wbs_sel_o <= wb_sel_i;
                        wbs_we_o <= wb_we_i;
                        // state
                        if (!wb_we_i) begin
                            state <= STATE_THROUGH_READ;

                            state_dbg <= 6;
                        end else begin
                            state <= STATE_WAIT_ACK;
                            invalidate_o <= 1'b1;
                            invalidate_addr_o <= wb_adr_i;

                            state_dbg <= 5;
                        end
                    end
                end
                else begin
                    wb_ack_o <= 1'b0;
                end
            end
            STATE_READ_0: begin
                if (wbs_ack_i) begin
                    block <= wbs_dat_i;
                    state <= STATE_READ_1;
                    wbs_cyc_o <= 1'b1;
                    wbs_stb_o <= 1'b1;
                    wbs_adr_o <= wb_adr_i + 4;
                    wbs_sel_o <= 4'b1111;
                    wbs_we_o <= 1'b0;

                    state_dbg <= 2;
                end
            end
            STATE_READ_1: begin
                if(wbs_ack_i) begin
                    block <= {wbs_dat_i,block[31:0]};
                    state <= STATE_READ_2;
                    wbs_cyc_o <= 1'b1;
                    wbs_stb_o <= 1'b1;
                    wbs_adr_o <= wb_adr_i + 8;
                    wbs_sel_o <= 4'b1111;
                    wbs_we_o <= 1'b0;

                    state_dbg <= 3;
                end
            end
            STATE_READ_2: begin
                if(wbs_ack_i) begin
                    block <= {wbs_dat_i,block[63:0]};
                    state <= STATE_READ_3;
                    wbs_cyc_o <= 1'b1;
                    wbs_stb_o <= 1'b1;
                    wbs_adr_o <= wb_adr_i + 12;
                    wbs_sel_o <= 4'b1111;
                    wbs_we_o <= 1'b0;

                    state_dbg <= 4;
                end
            end
            STATE_READ_3: begin
                if(wbs_ack_i) begin
                    wbs_cyc_o <= 1'b0;
                    wbs_stb_o <= 1'b0;
                    block <= {wbs_dat_i,block[95:0]};
                    cache[index][free_way[index]] <= {1'b1,tag,wb_dat_o,block[95:0]};
                    free_way[index] <= (free_way[index] + 1)%4;
                    state <= STATE_HIT;
                    wb_ack_o <= 1'b1;
                    wb_dat_o <= block[offset*32+:32]&mask;

                    state_dbg <= 0;
                end
            end
            STATE_WAIT_ACK: begin
                invalidate_o <= 0;
                invalidate_addr_o <= 0;

                if (wbs_ack_i) begin
                    wb_ack_o <= 1'b1;
                    wbs_cyc_o <= 1'b0;
                    wbs_stb_o <= 1'b0;
                    state <= STATE_HIT;

                    state_dbg <= 0;
                end
            end
            STATE_THROUGH_READ: begin
                if (wbs_ack_i) begin
                    wb_ack_o <= 1'b1;
                    wb_dat_o <= wbs_dat_i;
                    wbs_cyc_o <= 1'b0;
                    wbs_stb_o <= 1'b0;
                    state <= STATE_HIT;

                    state_dbg <= 0;
                end
            end
        endcase
    end
end

endmodule
