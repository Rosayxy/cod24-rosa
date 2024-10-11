module sram_controller #(
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

    // sram interface
    output reg [SRAM_ADDR_WIDTH-1:0] sram_addr,
    inout wire [SRAM_DATA_WIDTH-1:0] sram_data,
    output reg sram_ce_n,
    output reg sram_oe_n,
    output reg sram_we_n,
    output reg [SRAM_BYTES-1:0] sram_be_n,

    // output debug info for baseram
    output reg [19:0] sram_addr_dbg,
    output reg [31:0] sram_data_dbg,
    output reg [3:0] sram_be_n_dbg,
    output reg wb_ack_o_dbg,
    output reg [31:0] wb_dat_o_dbg,
    output reg [2:0] state_dbg
);

    typedef enum logic [2:0] {
      STATE_IDLE,   // 0
      STATE_READ,   // 1
      STATE_READ_2, // 2
      STATE_WRITE,  // 3
      STATE_WRITE_2, // 4
      STATE_WRITE_3, // 5
      STATE_DONE     // 6
    } state_t;

    // reg ram_ce_n_reg;
    // reg ram_oe_n_reg;
    // reg ram_we_n_reg;

    // // initial begin
    // //   ram_ce_n_reg = 1'b1;
    // //   ram_oe_n_reg = 1'b1;
    // //   ram_we_n_reg = 1'b1;
    // // end

    // assign sram_ce_n = ram_ce_n_reg;
    // assign sram_oe_n = ram_oe_n_reg;
    // assign sram_we_n = ram_we_n_reg;

    // step1 实现三态门的 wrapper 
    wire [SRAM_DATA_WIDTH-1:0] sram_data_i_comb; // ram 的输出 todo 到了对应阶段用他给 wb_dat_o 赋值
    reg [SRAM_DATA_WIDTH-1:0] sram_data_o_comb; // 给 ram 的输入 todo 到了对应阶段去赋值 wb_data_i
    reg sram_data_t_comb; // 是否是高阻态 1 代表高阻态 进入读状态

    assign sram_data = sram_data_t_comb ? 32'bz : sram_data_o_comb;
    assign sram_data_i_comb = sram_data;

    // always_comb begin
    //     sram_data_t_comb = 1'b0;
    //     sram_data_t_comb_debug = 1'b0;
    //     // 看 wishbone 的读写信号 WE_I
    //     if (wb_we_i) begin
    //       sram_data_t_comb = 1'b0;
    //       sram_data_t_comb_debug = 1'b0;
    //     end
    //     else begin
    //       sram_data_t_comb= 1'b1;
    //       sram_data_t_comb_debug = 1'b1;
    //     end
    // end

    // step2 把那个状态转换塞到时序逻辑里面去，和其他信号一块赋值吧
  state_t state;
  always_ff @ (posedge clk_i or posedge rst_i) begin
      if (rst_i) begin
          state <= STATE_IDLE;
          sram_ce_n <= 1'b1;
          sram_oe_n <= 1'b1;
          sram_be_n <= 1'b1;
          sram_we_n <= 1'b1;
          wb_ack_o <= 1'b0;
          wb_dat_o <= 0;
          sram_addr <= 0;

        state_dbg <= 0;
        wb_ack_o_dbg <= 0;
        sram_addr_dbg <= 0;
        wb_dat_o_dbg <= 0;
        sram_be_n_dbg <= 1;
      end else begin
          case (state)
              STATE_IDLE: begin
                  if (wb_stb_i && wb_cyc_i) begin
                      if (wb_we_i) begin
                          sram_addr <= wb_adr_i/4;
                          sram_data_o_comb <= wb_dat_i;
                          sram_oe_n <= 1'b1;
                          sram_ce_n <= 1'b0;
                          sram_we_n <= 1'b1;
                          sram_be_n <= ~wb_sel_i;
                          state <= STATE_WRITE;
                          sram_data_t_comb <= 0;
                          wb_ack_o <= 1'b0;

                      end else begin
                          // 赋值
                          sram_addr <= wb_adr_i/4;
                          sram_oe_n <= 0;
                          sram_ce_n <= 0;
                          sram_we_n <= 1'b1; // **改了这里 不确定和文档上是否一致 update: 看文档 得是1！**
                          sram_be_n <= ~wb_sel_i; // **在实验5的时候改了这里和上面**
                          state <= STATE_READ;
                          sram_data_t_comb <= 1;
                          wb_ack_o <= 0;

                            sram_addr_dbg <= wb_adr_i/4;
                            state_dbg <= 1;
                            sram_be_n_dbg <= ~wb_sel_i;
                            wb_ack_o_dbg <= 0;
                      end
                  end
              end

              STATE_READ: begin
                // other signals: wait for the effective address
                  state <= STATE_READ_2;
                  state_dbg <= 2;
              end

              STATE_READ_2: begin
                  // 赋值 data 是用三态门的
                  wb_dat_o <= sram_data_i_comb;
                  wb_ack_o <= 1;
                  sram_ce_n <= 1;
                  sram_oe_n <= 1;
                  state <= STATE_DONE;

                    wb_dat_o_dbg <= sram_data_i_comb;
                    wb_ack_o_dbg <= 1;
                    state_dbg <= 6;
              end

              STATE_WRITE: begin
                  sram_we_n <= 0;
                  state <= STATE_WRITE_2;
                  
              end

              STATE_WRITE_2: begin
                  sram_we_n <= 1;
                  state <= STATE_WRITE_3;

              end

              STATE_WRITE_3: begin
                  wb_ack_o <= 1;
                  sram_ce_n <= 1;
                  state <= STATE_DONE;

              end

              STATE_DONE: begin
                  state <= STATE_IDLE;
                  wb_ack_o <= 0;

                    state_dbg <= 0;
                    wb_ack_o_dbg <= 0;
              end

          endcase
      end
  end

endmodule