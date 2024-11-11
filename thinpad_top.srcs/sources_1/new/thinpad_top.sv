`default_nettype none

module thinpad_top (
    input wire clk_50M,     // 50MHz 时钟输入
    input wire clk_11M0592, // 11.0592MHz 时钟输入（备用，可不用）

    input wire push_btn,  // BTN5 按钮开关，带消抖电路，按下时为 1
    input wire reset_btn, // BTN6 复位按钮，带消抖电路，按下时为 1

    input  wire [ 3:0] touch_btn,  // BTN1~BTN4，按钮开关，按下时为 1
    input  wire [31:0] dip_sw,     // 32 位拨码开关，拨到“ON”时为 1
    output wire [15:0] leds,       // 16 位 LED，输出时 1 点亮
    output wire [ 7:0] dpy0,       // 数码管低位信号，包括小数点，输出 1 点亮
    output wire [ 7:0] dpy1,       // 数码管高位信号，包括小数点，输出 1 点亮

    // CPLD 串口控制器信号
    output wire uart_rdn,        // 读串口信号，低有效
    output wire uart_wrn,        // 写串口信号，低有效
    input  wire uart_dataready,  // 串口数据准备好
    input  wire uart_tbre,       // 发送数据标志
    input  wire uart_tsre,       // 数据发送完毕标志

    // BaseRAM 信号
    inout wire [31:0] base_ram_data,  // BaseRAM 数据，低 8 位与 CPLD 串口控制器共享
    output wire [19:0] base_ram_addr,  // BaseRAM 地址
    output wire [3:0] base_ram_be_n,  // BaseRAM 字节使能，低有效。如果不使用字节使能，请保持为 0
    output wire base_ram_ce_n,  // BaseRAM 片选，低有效
    output wire base_ram_oe_n,  // BaseRAM 读使能，低有效
    output wire base_ram_we_n,  // BaseRAM 写使能，低有效

    // ExtRAM 信号
    inout wire [31:0] ext_ram_data,  // ExtRAM 数据
    output wire [19:0] ext_ram_addr,  // ExtRAM 地址
    output wire [3:0] ext_ram_be_n,  // ExtRAM 字节使能，低有效。如果不使用字节使能，请保持为 0
    output wire ext_ram_ce_n,  // ExtRAM 片选，低有效
    output wire ext_ram_oe_n,  // ExtRAM 读使能，低有效
    output wire ext_ram_we_n,  // ExtRAM 写使能，低有效

    // 直连串口信号
    output wire txd,  // 直连串口发送端
    input  wire rxd,  // 直连串口接收端

    // Flash 存储器信号，参考 JS28F640 芯片手册
    output wire [22:0] flash_a,  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
    inout wire [15:0] flash_d,  // Flash 数据
    output wire flash_rp_n,  // Flash 复位信号，低有效
    output wire flash_vpen,  // Flash 写保护信号，低电平时不能擦除、烧写
    output wire flash_ce_n,  // Flash 片选信号，低有效
    output wire flash_oe_n,  // Flash 读使能信号，低有效
    output wire flash_we_n,  // Flash 写使能信号，低有效
    output wire flash_byte_n, // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1

    // USB 控制器信号，参考 SL811 芯片手册
    output wire sl811_a0,
    // inout  wire [7:0] sl811_d,     // USB 数据线与网络控制器的 dm9k_sd[7:0] 共享
    output wire sl811_wr_n,
    output wire sl811_rd_n,
    output wire sl811_cs_n,
    output wire sl811_rst_n,
    output wire sl811_dack_n,
    input  wire sl811_intrq,
    input  wire sl811_drq_n,

    // 网络控制器信号，参考 DM9000A 芯片手册
    output wire dm9k_cmd,
    inout wire [15:0] dm9k_sd,
    output wire dm9k_iow_n,
    output wire dm9k_ior_n,
    output wire dm9k_cs_n,
    output wire dm9k_pwrst_n,
    input wire dm9k_int,

    // 图像输出信号
    output wire [2:0] video_red,    // 红色像素，3 位
    output wire [2:0] video_green,  // 绿色像素，3 位
    output wire [1:0] video_blue,   // 蓝色像素，2 位
    output wire       video_hsync,  // 行同步（水平同步）信号
    output wire       video_vsync,  // 场同步（垂直同步）信号
    output wire       video_clk,    // 像素时钟输出
    output wire       video_de,      // 行数据有效信号，用于区分消隐区

    output reg [3:0] dcache_state_dbg,
    output wire d_wbs_cyc_o_dbg,
    output wire [31:0] d_wbs_adr_o_dbg,
    output wire [31:0] d_wbs_dat_o_dbg,
    output wire d_wbs_ack_i_dbg,
    output wire [31:0] d_wbs_dat_i_dbg,
    output wire [31:0] d_wb_dat_o_dbg,
    output wire d_wb_ack_o_dbg,
    output wire [31:0] d_wb_dat_i_dbg,
    output wire [31:0] d_wb_adr_i_dbg,

    output reg [4:0] cpu_state_dbg,
    output wire wbic_cyc_o_dbg,
    output wire [31:0] wbic_adr_o_dbg
);

  /* =========== Demo code begin =========== */

  // PLL 分频示例
  logic locked, clk_10M, clk_20M;
  pll_example clock_gen (
      // Clock in ports
      .clk_in1(clk_50M),  // 外部时钟输入
      // Clock out ports
      .clk_out1(clk_10M),  // 时钟输出 1，频率在 IP 配置界面中设置
      .clk_out2(clk_20M),  // 时钟输出 2，频率在 IP 配置界面中设置
      // Status and control signals
      .reset(reset_btn),  // PLL 复位输入
      .locked(locked)  // PLL 锁定指示输出，"1"表示时钟稳定，
                       // 后级电路复位信号应当由它生成（见下）
  );

  logic reset_of_clk10M;
  // 异步复位，同步释放，将 locked 信号转为后级电路的复位 reset_of_clk10M
  always_ff @(posedge clk_10M or negedge locked) begin
    if (~locked) reset_of_clk10M <= 1'b1;
    else reset_of_clk10M <= 1'b0;
  end


// start of code
  logic sys_clk;
  logic sys_rst;

  assign sys_clk = clk_10M;
  assign sys_rst = reset_of_clk10M;

  // 本实验不使用 CPLD 串口，禁用防止总线冲突
  assign uart_rdn = 1'b1;
  assign uart_wrn = 1'b1;

  // cpu => Wishbone MUX (Slave)
  logic        wbm_cyc_o;
  logic        wbm_stb_o;
  logic        wbm_ack_i;
  logic [31:0] wbm_adr_o;
  logic [31:0] wbm_dat_o;
  logic [31:0] wbm_dat_i;
  logic [ 3:0] wbm_sel_o;
  logic        wbm_we_o;

    // 第二组
    logic wbmd_cyc_o;
    logic wbmd_stb_o;
    logic wbmd_ack_i;
    logic [31:0] wbmd_adr_o;
    logic [31:0] wbmd_dat_o;
    logic [31:0] wbmd_dat_i;
    logic [ 3:0] wbmd_sel_o;
    logic wbmd_we_o;

    logic wbdc_cyc_o;
    logic wbdc_stb_o;
    logic wbdc_ack_i;
    logic [31:0] wbdc_adr_o;
    logic [31:0] wbdc_dat_o;
    logic [31:0] wbdc_dat_i;
    logic [ 3:0] wbdc_sel_o;
    logic wbdc_we_o;

  wire [4:0] raddr_a;
  wire [4:0] raddr_b;
  wire [4:0] waddr;
  wire [31:0] wdata;
  wire [4:0] we;
  wire [31:0] rdata_a;
  wire [31:0] rdata_b;

  wire [31:0] alu_a;
  wire [31:0] alu_b;
  wire [3:0] alu_op;
  reg [31:0] alu_res;

  // icache 输出信号
  logic icache_cyc_o;
    logic icache_stb_o;
    logic icache_ack_i;
    logic [31:0] icache_adr_o;
    logic [31:0] icache_dat_o;
    logic [31:0] icache_dat_i;
    logic [3:0] icache_sel_o;
    logic icache_we_o;

  // for arbiter output
  logic arbiter_cyc_o;
    logic arbiter_stb_o;
    logic arbiter_ack_i;
    logic [31:0] arbiter_adr_o;
    logic [31:0] arbiter_dat_o;
    logic [31:0] arbiter_dat_i;
    logic [3:0] arbiter_sel_o;
    logic arbiter_we_o;

    // for validate
    reg invalidate;
    reg [31:0] invalidate_addr;

  cpu #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) my_cpu (
      .clk(sys_clk),
      .rst(sys_rst),

      // TODO: 添加需要的控制信号，例如按键开关？
      .push_btn(push_btn),
      .reset_btn(reset_btn),
      .dip_sw(dip_sw),
      .leds(leds),
      // wishbone master
      .wbic_cyc_o(wbm_cyc_o),
      .wbic_stb_o(wbm_stb_o),
      .wbic_ack_i(wbm_ack_i),
      .wbic_adr_o(wbm_adr_o),
      .wbic_dat_o(wbm_dat_o),
      .wbic_dat_i(wbm_dat_i),
      .wbic_sel_o(wbm_sel_o),
      .wbic_we_o (wbm_we_o),

      .wbdc_cyc_o(wbdc_cyc_o),
      .wbdc_stb_o(wbdc_stb_o),
      .wbdc_ack_i(wbdc_ack_i),
      .wbdc_adr_o(wbdc_adr_o),
      .wbdc_dat_o(wbdc_dat_o),
      .wbdc_dat_i(wbdc_dat_i),
      .wbdc_sel_o(wbdc_sel_o),
      .wbdc_we_o (wbdc_we_o),

      .alu_a(alu_a),
      .alu_b(alu_b),
      .alu_op(alu_op),
      .alu_y(alu_res),

      .raddr_a(raddr_a),
      .raddr_b(raddr_b),
      .waddr(waddr),
      .wdata(wdata),
      .we(we),
      .rdata_a(rdata_a),
      .rdata_b(rdata_b),

      .state_dbg(cpu_state_dbg),
      .wbic_cyc_o_dbg(wbic_cyc_o_dbg),
      .wbic_adr_o_dbg(wbic_adr_o_dbg)
  );
   /* =========== CONNECT WITH REGFILE =========== */

    register_file_32 regfile (
        .clk(sys_clk),
        .reset(sys_rst),

        .raddr_a(raddr_a),
        .raddr_b(raddr_b),
        .waddr(waddr),
        .wdata(wdata),
        .we(we),
        .rdata_a(rdata_a),
        .rdata_b(rdata_b)
    );
  /* =========== CONNECT WITH REGFILE END =========== */

  /* =========== CONNECT WITH ALU =========== */

  alu_32 alu (
      .a(alu_a),
      .b(alu_b),
      .op(alu_op),
      .y(alu_res)
  );
  /* =========== CONNECT WITH ALU END =========== */

    /* =========== CONNECT WITH ICACHE =========== */
    icache #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .SRAM_ADDR_WIDTH(20),
        .SRAM_DATA_WIDTH(32)
    ) icache (
        .clk_i(sys_clk),
        .rst_i(sys_rst),

        .wb_cyc_i(wbm_cyc_o),
        .wb_stb_i(wbm_stb_o),
        .wb_ack_o(wbm_ack_i),
        .wb_adr_i(wbm_adr_o),
        .wb_dat_i(wbm_dat_o),
        .wb_dat_o(wbm_dat_i),
        .wb_sel_i(wbm_sel_o),
        .wb_we_i (wbm_we_o),

        .wbs_cyc_o(icache_cyc_o),
        .wbs_stb_o(icache_stb_o),
        .wbs_ack_i(icache_ack_i),
        .wbs_adr_o(icache_adr_o),
        .wbs_dat_o(icache_dat_o),
        .wbs_dat_i(icache_dat_i),
        .wbs_sel_o(icache_sel_o),
        .wbs_we_o (icache_we_o),

        .invalidate_i(invalidate),
        .invalidate_addr_i(invalidate_addr)

    );
    /* =========== CONNECT WITH ICACHE END =========== */
    
    /* =========== CONNECT WITH DCACHE =========== */
    dcache #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(32),
      .SRAM_ADDR_WIDTH(20),
      .SRAM_DATA_WIDTH(32)
    ) dcache (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      .wb_cyc_i(wbdc_cyc_o),
      .wb_stb_i(wbdc_stb_o),
      .wb_ack_o(wbdc_ack_i),
      .wb_adr_i(wbdc_adr_o),
      .wb_dat_i(wbdc_dat_o),
      .wb_dat_o(wbdc_dat_i),
      .wb_sel_i(wbdc_sel_o),
      .wb_we_i (wbdc_we_o),

      .invalidate_o(invalidate),
      .invalidate_addr_o(invalidate_addr),

      .wbs_cyc_o(wbmd_cyc_o),
      .wbs_stb_o(wbmd_stb_o),
      .wbs_ack_i(wbmd_ack_i),
      .wbs_adr_o(wbmd_adr_o),
      .wbs_dat_o(wbmd_dat_o),
      .wbs_dat_i(wbmd_dat_i),
      .wbs_sel_o(wbmd_sel_o),
      .wbs_we_o (wbmd_we_o),

      // debug info
      .state_dbg(dcache_state_dbg),
      .wbs_cyc_o_dbg(d_wbs_cyc_o_dbg),
      .wbs_adr_o_dbg(d_wbs_adr_o_dbg),
      .wbs_dat_o_dbg(d_wbs_dat_o_dbg),
      .wbs_ack_i_dbg(d_wbs_ack_i_dbg),
      .wbs_dat_i_dbg(d_wbs_dat_i_dbg),
      .wb_dat_o_dbg(d_wb_dat_o_dbg),
      .wb_ack_o_dbg(d_wb_ack_o_dbg),
      .wb_dat_i_dbg(d_wb_dat_i_dbg),
      .wb_adr_i_dbg(d_wb_adr_i_dbg)
    );
    /* =========== CONNECT WITH DCACHE END =========== */
    
    // connect with arbiter, putting the datacache output first
    wb_arbiter_2 #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .SELECT_WIDTH(4)
    ) arbiter (
        .clk(sys_clk),
        .rst(sys_rst),

        .wbm0_cyc_i(wbmd_cyc_o),
        .wbm0_stb_i(wbmd_stb_o),
        .wbm0_ack_o(wbmd_ack_i),
        .wbm0_adr_i(wbmd_adr_o),
        .wbm0_dat_i(wbmd_dat_o),
        .wbm0_dat_o(wbmd_dat_i),
        .wbm0_sel_i(wbmd_sel_o),
        .wbm0_we_i (wbmd_we_o),

        .wbm1_cyc_i(icache_cyc_o),
        .wbm1_stb_i(icache_stb_o),
        .wbm1_ack_o(icache_ack_i),
        .wbm1_adr_i(icache_adr_o),
        .wbm1_dat_i(icache_dat_o),
        .wbm1_dat_o(icache_dat_i),
        .wbm1_sel_i(icache_sel_o),
        .wbm1_we_i (icache_we_o),

        // output 
        .wbs_adr_o(arbiter_adr_o),
        .wbs_dat_o(arbiter_dat_o),
        .wbs_dat_i(arbiter_dat_i),
        .wbs_we_o(arbiter_we_o),
        .wbs_sel_o(arbiter_sel_o),
        .wbs_stb_o(arbiter_stb_o),
        .wbs_cyc_o(arbiter_cyc_o),
        .wbs_ack_i(arbiter_ack_i)
    );

  /* =========== Final MUX begin =========== */
  // Wishbone MUX (Masters) => bus slaves
  logic wbs0_cyc_o;
  logic wbs0_stb_o;
  logic wbs0_ack_i;
  logic [31:0] wbs0_adr_o;
  logic [31:0] wbs0_dat_o;
  logic [31:0] wbs0_dat_i;
  logic [3:0] wbs0_sel_o;
  logic wbs0_we_o;

  logic wbs1_cyc_o;
  logic wbs1_stb_o;
  logic wbs1_ack_i;
  logic [31:0] wbs1_adr_o;
  logic [31:0] wbs1_dat_o;
  logic [31:0] wbs1_dat_i;
  logic [3:0] wbs1_sel_o;
  logic wbs1_we_o;

  logic wbs2_cyc_o;
  logic wbs2_stb_o;
  logic wbs2_ack_i;
  logic [31:0] wbs2_adr_o;
  logic [31:0] wbs2_dat_o;
  logic [31:0] wbs2_dat_i;
  logic [3:0] wbs2_sel_o;
  logic wbs2_we_o;

  wb_mux_3 wb_mux (
      .clk(sys_clk),
      .rst(sys_rst),

      // Master interface (to Lab5 master) connect through arbiter
      .wbm_adr_i(arbiter_adr_o),
      .wbm_dat_i(arbiter_dat_o),
      .wbm_dat_o(arbiter_dat_i),
      .wbm_we_i (arbiter_we_o),
      .wbm_sel_i(arbiter_sel_o),
      .wbm_stb_i(arbiter_stb_o),
      .wbm_ack_o(arbiter_ack_i),
      .wbm_err_o(),
      .wbm_rty_o(),
      .wbm_cyc_i(arbiter_cyc_o),

      // Slave interface 0 (to BaseRAM controller)
      // Address range: 0x8000_0000 ~ 0x803F_FFFF
      .wbs0_addr    (32'h8000_0000),
      .wbs0_addr_msk(32'hFFC0_0000),

      .wbs0_adr_o(wbs0_adr_o),
      .wbs0_dat_i(wbs0_dat_i),
      .wbs0_dat_o(wbs0_dat_o),
      .wbs0_we_o (wbs0_we_o),
      .wbs0_sel_o(wbs0_sel_o),
      .wbs0_stb_o(wbs0_stb_o),
      .wbs0_ack_i(wbs0_ack_i),
      .wbs0_err_i('0),
      .wbs0_rty_i('0),
      .wbs0_cyc_o(wbs0_cyc_o),

      // Slave interface 1 (to ExtRAM controller)
      // Address range: 0x8040_0000 ~ 0x807F_FFFF
      .wbs1_addr    (32'h8040_0000),
      .wbs1_addr_msk(32'hFFC0_0000),

      .wbs1_adr_o(wbs1_adr_o),
      .wbs1_dat_i(wbs1_dat_i),
      .wbs1_dat_o(wbs1_dat_o),
      .wbs1_we_o (wbs1_we_o),
      .wbs1_sel_o(wbs1_sel_o),
      .wbs1_stb_o(wbs1_stb_o),
      .wbs1_ack_i(wbs1_ack_i),
      .wbs1_err_i('0),
      .wbs1_rty_i('0),
      .wbs1_cyc_o(wbs1_cyc_o),

      // Slave interface 2 (to UART controller)
      // Address range: 0x1000_0000 ~ 0x1000_FFFF
      .wbs2_addr    (32'h1000_0000),
      .wbs2_addr_msk(32'hFFFF_0000),

      .wbs2_adr_o(wbs2_adr_o),
      .wbs2_dat_i(wbs2_dat_i),
      .wbs2_dat_o(wbs2_dat_o),
      .wbs2_we_o (wbs2_we_o),
      .wbs2_sel_o(wbs2_sel_o),
      .wbs2_stb_o(wbs2_stb_o),
      .wbs2_ack_i(wbs2_ack_i),
      .wbs2_err_i('0),
      .wbs2_rty_i('0),
      .wbs2_cyc_o(wbs2_cyc_o)
  );

  /* =========== Final MUX end =========== */

  /* =========== Final Slaves begin =========== */
  sram_controller #(
      .SRAM_ADDR_WIDTH(20),
      .SRAM_DATA_WIDTH(32)
  ) sram_controller_base (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs0_cyc_o),
      .wb_stb_i(wbs0_stb_o),
      .wb_ack_o(wbs0_ack_i),
      .wb_adr_i(wbs0_adr_o),
      .wb_dat_i(wbs0_dat_o),
      .wb_dat_o(wbs0_dat_i),
      .wb_sel_i(wbs0_sel_o),
      .wb_we_i (wbs0_we_o),

      // To SRAM chip
      .sram_addr(base_ram_addr),
      .sram_data(base_ram_data),
      .sram_ce_n(base_ram_ce_n),
      .sram_oe_n(base_ram_oe_n),
      .sram_we_n(base_ram_we_n),
      .sram_be_n(base_ram_be_n)
  );

  sram_controller #(
      .SRAM_ADDR_WIDTH(20),
      .SRAM_DATA_WIDTH(32)
  ) sram_controller_ext (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs1_cyc_o),
      .wb_stb_i(wbs1_stb_o),
      .wb_ack_o(wbs1_ack_i),
      .wb_adr_i(wbs1_adr_o),
      .wb_dat_i(wbs1_dat_o),
      .wb_dat_o(wbs1_dat_i),
      .wb_sel_i(wbs1_sel_o),
      .wb_we_i (wbs1_we_o),

      // To SRAM chip
      .sram_addr(ext_ram_addr),
      .sram_data(ext_ram_data),
      .sram_ce_n(ext_ram_ce_n),
      .sram_oe_n(ext_ram_oe_n),
      .sram_we_n(ext_ram_we_n),
      .sram_be_n(ext_ram_be_n)
  );

  // 串口控制器模块
  // NOTE: 如果修改系统时钟频率，也需要修改此处的时钟频率参数
  uart_controller #(
      .CLK_FREQ(10_000_000),
      .BAUD    (115200)
  ) uart_controller (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      .wb_cyc_i(wbs2_cyc_o),
      .wb_stb_i(wbs2_stb_o),
      .wb_ack_o(wbs2_ack_i),
      .wb_adr_i(wbs2_adr_o),
      .wb_dat_i(wbs2_dat_o),
      .wb_dat_o(wbs2_dat_i),
      .wb_sel_i(wbs2_sel_o),
      .wb_we_i (wbs2_we_o),

      // to UART pins
      .uart_txd_o(txd),
      .uart_rxd_i(rxd)
  );

endmodule
