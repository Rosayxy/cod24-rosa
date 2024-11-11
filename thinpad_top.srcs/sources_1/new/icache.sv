`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/10/29 18:17:56
// Design Name: 
// Module Name: icache
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


module icache #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,

    parameter SRAM_ADDR_WIDTH = 20,
    parameter SRAM_DATA_WIDTH = 32,

    localparam SRAM_BYTES = SRAM_DATA_WIDTH / 8, // 4
    localparam SRAM_BYTE_WIDTH = $clog2(SRAM_BYTES) // 2
) (
    // clk and reset
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
    
    // 处理写指令的情况 直接把对应的行的 valid 位清零
    input reg invalidate_i,
    input reg [ADDR_WIDTH-1:0] invalidate_addr_i,

    // sram_controller interface
    output reg wbs_cyc_o,
    output reg wbs_stb_o,
    input wire wbs_ack_i,
    output reg [ADDR_WIDTH-1:0] wbs_adr_o,
    output reg [DATA_WIDTH-1:0] wbs_dat_o,
    input wire [DATA_WIDTH-1:0] wbs_dat_i,
    output reg [DATA_WIDTH/8-1:0] wbs_sel_o,
    output reg wbs_we_o,

    // dbg output
    output reg [150:0] entry_dbg,
    output wire [3:0] index_dbg,
    output wire [18:0] tag_dbg,
    output wire [1:0] offset_dbg,
    output reg [3:0] state_dbg,
    output wire [127:0] block_dbg,
    output wire [DATA_WIDTH-1:0] wbs_dat_i_dbg,
    output wire [31:0] wb_dat_o_dbg,
    output wire wb_cyc_i_dbg,
    output wire wb_stb_i_dbg,
    output wire wb_ack_o_dbg
);

// cache layout: 四路组相联，总大小 4kB 块 16 字节 共 64 行 0x7f404030 (64*16*4)
// 每行结构：有效位 1 位，地址32位，tag 22 位 地址 belike tag [31:10] index [9:4] offset [3:0] 而我们一个块的结构是 valid + tag[149:128] + data[127:0]
// 重要：往 cache 里面塞块的地址一定是 16 字节的倍数，此外，因为只是 icache 所以 narrow_down 了一些情况
// TODO think about fence.i implementation

reg [150:0] cache [63:0][3:0]; // 64 行 4 路
reg [127:0] block;
reg [21:0] tag;
reg valid;
reg [3:0] index;
reg [1:0] way;
reg [3:0] i;
reg [1:0] offset;
reg[DATA_WIDTH/8-1:0] tmp_sel;
reg [3:0] free_way[63:0];
reg [3:0] tmp_way;
// states
typedef enum logic [3:0] {
    STATE_HIT,   // 0
    STATE_READ_0,   // 1
    STATE_READ_1,   // 2
    STATE_READ_2, // 3
    STATE_READ_3  // 4
} state_t;

state_t state;

always_comb begin
    index = wb_adr_i[9:4];
    tag = wb_adr_i[31:10];
    offset = wb_adr_i[3:2]; // 这个改了
end

assign index_dbg = index;
assign tag_dbg = tag;
assign offset_dbg = offset;
assign block_dbg = block;
assign wbs_dat_i_dbg = wbs_dat_i;
assign wb_dat_o_dbg = wb_dat_o;
assign wb_cyc_i_dbg = wb_cyc_i;
assign wb_stb_i_dbg = wb_stb_i;
assign wb_ack_o_dbg = wb_ack_o;

// TODO 目前存在问题是 wb_cyc_i wb_stb_i 信号不对 需要把 cpu 状态接出来
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
        i<=0;
        way<=0;
        tmp_sel<=0;

        for(int i=0;i<64;i=i+1) begin
            free_way[i]<=0;
        end

        entry_dbg <= 0;
        state_dbg <= 0;
    end else begin
        // start invalidate
        if(invalidate_i) begin
            // try match
            if (cache[invalidate_addr_i[9:4]][0][149:128] == invalidate_addr_i[31:10] && cache[invalidate_addr_i[9:4]][0][150:150] == 1) begin
                cache[invalidate_addr_i[9:4]][0][150:150] <= 0;
            end
            else if (cache[invalidate_addr_i[9:4]][1][149:128] == invalidate_addr_i[31:10] && cache[invalidate_addr_i[9:4]][1][150:150] == 1) begin
                cache[invalidate_addr_i[9:4]][1][150:150] <= 0;
            end
            else if (cache[invalidate_addr_i[9:4]][2][149:128] == invalidate_addr_i[31:10] && cache[invalidate_addr_i[9:4]][2][150:150] == 1) begin
                cache[invalidate_addr_i[9:4]][2][150:150] <= 0;
            end
            else if (cache[invalidate_addr_i[9:4]][3][149:128] == invalidate_addr_i[31:10] && cache[invalidate_addr_i[9:4]][3][150:150] == 1) begin
                cache[invalidate_addr_i[9:4]][3][150:150] <= 0;
            end
        end
        case (state)
            STATE_HIT: begin
                // 判断是 hit 还是 miss
                // 对于当前 index 行的四路，判断 is_valid 的路有无 tag 相同的
            if(wb_cyc_i && wb_stb_i) begin // todo check for invalidate
                if(!(invalidate_i&&(wb_adr_i[31:4]==invalidate_addr_i[31:4]))) begin
                for(i=0;i<4;i=i+1) begin
                    if(cache[index][i][150:150] == 1 && cache[index][i][149:128] == tag) begin
                        // hit
                        state <= STATE_HIT;
                        // 返回
                        wb_ack_o <= 1'b1;
                        case (offset)
                            2'b00: wb_dat_o <= cache[index][i][31:0];
                            2'b01: wb_dat_o <= cache[index][i][63:32];
                            2'b10: wb_dat_o <= cache[index][i][95:64];
                            2'b11: wb_dat_o <= cache[index][i][127:96];
                        endcase
                        break;
                    end
                end
                if (!(cache[index][0][150:150]==1 && cache[index][0][149:128] == tag)&&!(cache[index][1][150:150]==1 && cache[index][1][149:128] == tag)&&!(cache[index][2][150:150]==1 && cache[index][2][149:128] == tag)&&!(cache[index][3][150:150]==1 && cache[index][3][149:128] == tag)) begin
                    state <= STATE_READ_0;
                    wb_ack_o <= 1'b0;
                    // 升信号
                    wbs_cyc_o <= 1'b1;
                    wbs_stb_o <= 1'b1;
                    // 赋成 wb_adr_i 向下16对齐
                    wbs_adr_o <= {wb_adr_i[ADDR_WIDTH-1:4],4'b0000};
                    wbs_sel_o <= 4'b1111;
                    wbs_we_o <= 1'b0;

                    state_dbg <= 1;
                end
                end else begin
                    // 求取的地址和 invalidate 的地址相同 没事已经有 arbiter 了而且 dcache 优先级高 直接发就好
                    state <= STATE_READ_0;
                    wb_ack_o <= 1'b0;
                    // 升信号
                    wbs_cyc_o <= 1'b1;
                    wbs_stb_o <= 1'b1;
                    wbs_adr_o <= {wb_adr_i[ADDR_WIDTH-1:4],4'b0000};
                    wbs_sel_o <= 4'b1111;
                    wbs_we_o <= 1'b0;

                    state_dbg <=1;
                end
            end else begin
                wb_ack_o <= 1'b0;
            end
            end
        STATE_READ_0: begin
            if(wbs_ack_i) begin
                block <= wbs_dat_i;
                state <= STATE_READ_1;
                // 不拉低信号，直接继续输出
                wbs_cyc_o <= 1'b1;
                wbs_stb_o <= 1'b1;
                wbs_adr_o <= {wb_adr_i[ADDR_WIDTH-1:4],4'b0100};
                wbs_sel_o <= 4'b1111;
                wbs_we_o <= 1'b0;

                state_dbg <= 2;
            end
        end
        STATE_READ_1: begin
            if(wbs_ack_i) begin
                block <= {wbs_dat_i,block[31:0]};
                state <= STATE_READ_2;
                // 不拉低信号，直接继续输出
                wbs_cyc_o <= 1'b1;
                wbs_stb_o <= 1'b1;
                wbs_adr_o <= {wb_adr_i[ADDR_WIDTH-1:4],4'b1000};
                wbs_sel_o <= 4'b1111;
                wbs_we_o <= 1'b0;

                state_dbg <= 3;
            end
        end
        STATE_READ_2:begin
            if (wbs_ack_i) begin
                block <= {wbs_dat_i,block[63:0]};
                state <= STATE_READ_3;
                // 不拉低信号，直接继续输出
                wbs_cyc_o <= 1'b1;
                wbs_stb_o <= 1'b1;
                wbs_adr_o <= {wb_adr_i[ADDR_WIDTH-1:4],4'b1100};
                wbs_sel_o <= 4'b1111;
                wbs_we_o <= 1'b0;

                state_dbg <= 4;
            end
        end
        STATE_READ_3:begin
            if(wbs_ack_i) begin
                // 拉低信号
                wbs_cyc_o <= 1'b0;
                wbs_stb_o <= 1'b0;
                // 将 block 存入 cache
                cache[index][free_way[index]] <= {1'b1,tag,wbs_dat_i,block[95:0]};
                entry_dbg <= {1'b1,tag,wb_dat_o,block[95:0]};
                free_way[index] <= (free_way[index] + 1)%4;
                state <= STATE_HIT;
                // 返回
                wb_ack_o <= 1'b1;
                case (offset)
                    2'b00: wb_dat_o <= block[31:0];
                    2'b01: wb_dat_o <= block[63:32];
                    2'b10: wb_dat_o <= block[95:64];
                    2'b11: wb_dat_o <= wbs_dat_i;
                endcase

                state_dbg <= 0;
            end
        end
        endcase
    end
end
endmodule
