module lab5_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk_i,
    input wire rst_i,

    // TODO: 添加需要的控制信号，例如按键开关? 还要把 leds 信号接出去
    input wire push_btn,
    input wire reset_btn,
    input wire [31:0] dip_sw,     // 32 位拨码开关，拨到“ON”时为 1
    output wire [15:0] leds,       // 16 位 LED，输出时 1 点亮 按照之前 tester 的模式点亮
    // wishbone master
    output reg wb_cyc_o,
    output reg wb_stb_o,
    input wire wb_ack_i,
    output reg [ADDR_WIDTH-1:0] wb_adr_o,
    output reg [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output reg [DATA_WIDTH/8-1:0] wb_sel_o,
    output reg wb_we_o

);

  // TODO: 实现实验 5 的内存+串口 Master
  // 状态转移，因为比较复杂，所以单独放到一个 always_comb 里面

  typedef enum logic [4:0] {
    ST_IDLE,                  // 0

    ST_READ_WAIT_ACTION,     // 1
    ST_RWC,                  // 2

    ST_READ_DATA_ACTION,    // 3
    ST_READ_ACTION_DONE,    // 4

    ST_WRITE_RAM_IDLE,      // 5
    ST_WRITE_RAM,           // 6
    ST_WRITE_RAM_DONE,     // 7

    ST_WRITE_DATA_IDLE,    // 8
    ST_WRITE_WAIT_ACTION,  // 9
    ST_WWC,                // 10
    ST_WRITE_DATA_ACTION,  // 11
    ST_WRITE_ACTION_DONE,  // 12

    ST_CMP_IDLE,           // 13
    ST_CMP_READ,          // 14
    ST_CMP_READ_ACTION,    // 15
    ST_DONE,               // 16
    ST_ERROR              // 17
  } state_t;

  state_t state, state_n;
  reg [ADDR_WIDTH-1:0] addr;
  reg [3:0] cnt;
  reg [DATA_WIDTH-1:0] is_send;
  reg [DATA_WIDTH-1:0] target_data;
  reg [3:0] cnt2;
  

  // 把实验结果接出去
  logic test_done, test_error;
  assign leds[0] = test_done;
  assign leds[1] = test_error;
  assign leds[15:2] = '0;
// 把 10 个数存下来
  reg [31:0] data[0:9];
  always_comb begin
    state_n = state;

    case (state)
      ST_IDLE: begin
        if (push_btn) begin
            state_n = ST_READ_WAIT_ACTION;
        end
        else if (cnt>0 && cnt<10)begin
            state_n = ST_READ_WAIT_ACTION;
        end
        else begin
          state_n = ST_CMP_IDLE;
        end
      end
      ST_READ_WAIT_ACTION: begin
        if (wb_ack_i) begin
          state_n = ST_RWC;
        end
      end
      ST_RWC: begin
        if (is_send&32'h100) begin // 非对齐的写法 留出低八位 
          state_n = ST_READ_DATA_ACTION;
        end
        else begin
          state_n = ST_READ_WAIT_ACTION;
        end
      end
      ST_READ_DATA_ACTION: begin
        if (wb_ack_i) begin
          state_n = ST_READ_ACTION_DONE;
        end
      end
      ST_READ_ACTION_DONE: begin
        if (wb_dat_i) begin
          state_n = ST_WRITE_RAM_IDLE;
        end
      end
      ST_WRITE_RAM_IDLE: begin
        state_n = ST_WRITE_RAM;
      end
      ST_WRITE_RAM: begin
        if (wb_ack_i) begin
          state_n = ST_WRITE_RAM_DONE;
        end
      end
      ST_WRITE_RAM_DONE: begin
          state_n = ST_WRITE_DATA_IDLE;
      end
      ST_WRITE_DATA_IDLE: begin
        state_n = ST_WRITE_WAIT_ACTION;
      end
      ST_WRITE_WAIT_ACTION: begin
        if (wb_ack_i) begin
          state_n = ST_WWC;
        end
      end
      ST_WWC: begin
        if (is_send&32'h2000) begin
          state_n = ST_WRITE_DATA_ACTION;
        end
        else begin
          state_n = ST_WRITE_WAIT_ACTION;
        end
      end
      ST_WRITE_DATA_ACTION: begin
        if (wb_ack_i) begin
          state_n = ST_WRITE_ACTION_DONE;
        end
      end
      ST_WRITE_ACTION_DONE: begin
          state_n = ST_IDLE;
          cnt = cnt + 1;
      end
      ST_CMP_IDLE: begin
        state_n=ST_CMP_READ;
      end
      ST_CMP_READ: begin
        if (cnt2<10) begin
          state_n=ST_CMP_READ_ACTION;
        end
        else begin
          state_n=ST_DONE;
        end
      end
      ST_CMP_READ_ACTION: begin
        if (wb_ack_i) begin
          if (data[cnt2]!=wb_dat_i) begin
            state_n=ST_ERROR;
          end
          else begin
          state_n=ST_CMP_READ;
          cnt2=cnt2+1;
          addr<=addr+4;
          end
        end
      end
      ST_ERROR: begin
        state_n = ST_ERROR;
      end
      ST_DONE: begin
        state_n = ST_DONE;
      end
      default: begin
        state_n = ST_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state <= ST_IDLE;
    end else begin
      state <= state_n;
    end
  end
  // 主要逻辑
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      // 所有信号全清零
      wb_cyc_o <= 0;
      wb_stb_o <= 0;
      wb_adr_o <= 0;
      wb_dat_o <= 0;
      wb_sel_o <= 0;
      wb_we_o <= 0;
      is_send <= 0;
      test_done <= 0;
      test_error <= 0;
      cnt <= 0;
      addr <= 32'h00000000;
      target_data <= 32'h00000000;
      cnt2<=0;

    end else begin
      case (state)
      ST_IDLE: begin
        // 判断是否是可以发送的条件
        if (push_btn||(cnt>0 && cnt<10)) begin
          wb_cyc_o <= 1;
          wb_stb_o <= 1;
          wb_adr_o <= 32'h10000005;
          wb_sel_o <= 4'b0010;
          wb_we_o <= 0;

        end
        if (push_btn) begin
          addr <= dip_sw;
        end
      end

      ST_READ_WAIT_ACTION: begin
        if (wb_ack_i) begin
          // 拉低 wb_cyc_o wb_stb_o
          wb_cyc_o <= 0;
          wb_stb_o <= 0;
          is_send <= wb_dat_i;

        end
        else begin
          is_send <= 0;
        end
      end

      ST_RWC: begin
        if (is_send&32'h100) begin
          wb_cyc_o <= 1;
          wb_stb_o <= 1;
          wb_adr_o <= 32'h10000000;
          wb_sel_o <= 4'b0001;
          wb_we_o <= 0;
        end
        else begin
          wb_cyc_o <= 1;
          wb_stb_o <= 1;
          wb_adr_o <= 32'h10000005;
          wb_sel_o <= 4'b0010;
          wb_we_o <= 0;

        end
      end

      ST_READ_DATA_ACTION: begin
        // do nothing
        if (wb_ack_i) begin
          // 拉低 wb_cyc_o wb_stb_o
          wb_cyc_o <= 0;
          wb_stb_o <= 0;
          target_data <= wb_dat_i;
          data[cnt] <= wb_dat_i;
        end
      end

      ST_READ_ACTION_DONE: begin
        // do nothing
      end

      ST_WRITE_RAM_IDLE: begin
        wb_cyc_o <= 1;
        wb_stb_o <= 1;
        wb_adr_o <= addr;
        wb_sel_o <= 4'b0001;
        wb_we_o <= 1;
        wb_dat_o <= target_data;

      end

      ST_WRITE_RAM: begin
        if (wb_ack_i) begin
          wb_cyc_o <= 0;
          wb_stb_o <= 0;

        end
      end

      ST_WRITE_RAM_DONE: begin
        addr <= addr + 4;
      end

      // 是要读取 0x10000005 的数据
      ST_WRITE_DATA_IDLE: begin
        wb_cyc_o <= 1;
        wb_stb_o <= 1;
        wb_adr_o <= 32'h10000005;
        wb_sel_o <= 4'b0010;
        wb_we_o <= 0;

      end

      ST_WRITE_WAIT_ACTION: begin
        if (wb_ack_i) begin
          wb_cyc_o <= 0;
          wb_stb_o <= 0;
          is_send <= wb_dat_i;

        end
        else begin
          is_send <= 0;
        end
      end

      ST_WWC: begin
        if (is_send&32'h2000) begin
          wb_cyc_o <= 1;
          wb_stb_o <= 1;
          wb_adr_o <= 32'h10000000;
          wb_sel_o <= 4'b0001;
          wb_we_o <= 1;
          wb_dat_o <= target_data;

        end
        else begin
          wb_cyc_o <= 1;
          wb_stb_o <= 1;
          wb_adr_o <= 32'h10000005;
          wb_sel_o <= 4'b0010;
          wb_we_o <= 0;
        end
      end

      ST_WRITE_DATA_ACTION: begin
        if (wb_ack_i) begin
          wb_cyc_o <= 0;
          wb_stb_o <= 0;
        end
      end

      ST_WRITE_ACTION_DONE: begin
        // do nothing
      end
      ST_CMP_IDLE: begin
        cnt2=0;
        addr<=addr-40;
      end
      ST_CMP_READ: begin
        wb_cyc_o <= 1;
        wb_stb_o <= 1;
        wb_adr_o <= addr;
        wb_sel_o <= 4'b0001;
        wb_we_o <= 0;

      end
      ST_CMP_READ_ACTION: begin
        // do nothing
        if (wb_ack_i) begin
          wb_cyc_o <= 0;
          wb_stb_o <= 0;
        end
      end
      ST_DONE: begin
        test_done <= 1;
      end
      ST_ERROR: begin
        test_error <= 1;
      end
      endcase
    end
  end
endmodule


