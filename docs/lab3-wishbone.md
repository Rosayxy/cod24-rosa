# lab3-wishbone sram controller design
## 实现内容
需要实现 SRAM controller, 即是文档中 slave 侧的五周期写五周期读状态机    
## 接口分析
文档中写了以下接口
```text
CLK_I: 时钟输入，即自研总线中的 clock_i
STB_I：高表示 master 要发送请求，即自研总线中的 valid_o
ACK_O：高表示 slave 完成请求，即自研总线中的 ready_i
ADR_I：master 想要读写的地址，即自研总线中的 addr_o
WE_I：master 想要读还是写，即自研总线中的 we_o
DAT_I：master 想要写入的数据，即自研总线中的 data_o
SEL_I：master 读写的字节使能，即自研总线中的 be_o
DAT_O：master 从 slave 读取的数据，即自研总线中的 data_i
CYC_I：总线的使能信号，无对应的自研总线信号
```

在代码中，有以下段落
```verilog
module sram_controller #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,

    parameter SRAM_ADDR_WIDTH = 20,
    parameter SRAM_DATA_WIDTH = 32,

    localparam SRAM_BYTES = SRAM_DATA_WIDTH / 8,
    localparam SRAM_BYTE_WIDTH = $clog2(SRAM_BYTES)
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
    output reg [SRAM_BYTES-1:0] sram_be_n
);

  // TODO: 实现 SRAM 控制器

endmodule

```

首先这个 module 语法是 belike `module sram_controller #(parameter ...) (input/output/inout wire ...);`   
注释中标注 `wishbone slave interface` 的段落和文档中接口一一对应，类似于控制信号        
下面的 sram interface belike     

```verilog
    output reg [SRAM_ADDR_WIDTH-1:0] sram_addr, // 地址
    inout wire [SRAM_DATA_WIDTH-1:0] sram_data, // 拿到 ram 传来的数据
    output reg sram_ce_n, // 片选
    output reg sram_oe_n, // 读使能
    output reg sram_we_n, // 写使能
    output reg [SRAM_BYTES-1:0] sram_be_n // 字节使能
```
这个不用管 sram 具体实现 看 thinpad_top.srcs/sim_1/new/sram_model.v   

## 时序
下面把文档中的要点按自己的理解复述一遍     
### sram 读写时序
- 每次读取都需要等待一个周期，读的时候保持地址和 flags 不变  
- addr 和 ce_n 同步（read 和 write 都是这样子）：需要读数据的时候 同步 设置 addr 和 ce_n，读完之后，同步把 addr 和 ce_n 搞回去
- 写入需要 3 个周期，flag 保持不变 除了 we_n 为 1，0，1
### 状态转移
不难 按照数电实验的写就行
```
IDLE -> READ 
 ^      |
 |      v
DONE <- READ2

IDLE -> WRITE 
 ^      |
 |      |
DONE    |
 ^      |
 |      v
WRITE3 <- WRITE2

```
### 五周期读
注意我们进行赋值，对应的点位会变化，但是在下一个上边沿才会引起对面的相应变化 ~ 以及我们都是在 slave 侧，只需要关注**什么时候可以接收到 master/sram 的有效信号**qaq   

**问题 我们 state 转化是用 always_comb 赋值的，所以在逻辑中 对于状态应该就是 比如在这个周期有 state->IDLE 就是用 state==DONE/INITIAL_IDLE 来判断吗 感觉是这样的**   
和杰哥的对话，**区分协议和实现qaq**，像是在波形图中的state,“设置”和“输出”信号值应该都是针对两者的通信，而和实现的时序不是直接相关
1. IDLE(initial)/DONE: 人如其名 master 在这个时钟上边沿后赋值成准备读入的 CYC_I=1, STB_I=1, WE_I=0 ADR_I SEL_I WE_I，作为 slave 的一方，我们这个周期不需要做啥，只用 state->IDLE 就行   
2. IDLE: 这个周期，我们接收到了 master 传入的有效的 CYC_I 等量，对于 sram 输出一侧，赋值 addr := ADR_I/4 , oe_n=0, ce_n=0, we_n=1 be_n=0，state->READ     
3. READ: 这个周期的开始的上边沿，sram 接收到了一个有效的地址和使能，于是它会赋值一个有效的 data。但是我们无法在时钟上边沿时读到他所以要等一个周期，这个周期我们只需要 state->READ2 就行
4. READ2: 我们把 sram 传来的 data 赋值到 DAT_O 赋值 ACK_O=1，对 sram 输出 ce_n=1, oe_n=1 STATE->DONE

### 五周期写
1. state->IDLE: master 设置 CYC_I=1, STB_I=1, WE_I=0 我们啥都不干 (DONE state)
2. state->WRITE: 输出 addr, data, oe_n=1, ce_n=0, we_n=1 be_n=0b0000  (IDLE state)
3. state->WRITE2: 输出 we_n=0 （WRITE state）
4. state->WRITE3: 输出 we_n=1 (WRITE2 state)
5. state->DONE: 输出 ce_n=1, ACK_O=1 (WRITE3 state)

然后对于那个状态机实现技巧，咱们的思路更接近给出的第一个方法 就按杰哥写的实现就行    

## 三态门
给 sram_data 套个壳 感觉图中的 sram_data_i_comb 和 sram_data_o_comb 分别是 wb_data_o wb_data_i 的套壳，assign 是组合逻辑 所以咱不用管那个落后一个周期的事情吧        
       

```verilog
module sram_controller (
    inout [31:0] sram_data
);

   wire [SRAM_DATA_WIDTH-1:0] sram_data_i_comb; // ram 的输出 到了对应阶段用他给 wb_dat_o 赋值
    reg [SRAM_DATA_WIDTH-1:0] sram_data_o_comb; // 给 ram 的输入 到了对应阶段去被 wb_data_i 赋值
    reg sram_data_t_comb; // 是否是高阻态 1 代表高阻态 进入读状态

    assign sram_data = sram_data_t_comb ? 32'bz : sram_data_o_comb;
    assign sram_data_i_comb = sram_data;

        // 根据外面的 读写使能设置 sram_data_t_comb 即可
    end
endmodule
```
在 state_read 中可以 `wb_dat_o <= sram_data_i_comb;` idle 时可以 `sram_data_o_comb <= wb_dat_i;`

p(t)<->P(jw) = (2pi/T)sigma(-inf, inf) delta(w-2pi*n/T)    
p(t) = 1/T sigma(-inf, inf) P(jw) e^(jwnT) dw    
