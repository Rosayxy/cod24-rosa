# lab4-内存串口
## UART protocol
用两条信号线实现全双工，分别由 A->B 由 B->A 传输数据        
- rx/rxd：receive，接收
- tx/txd：transmit，发送

- 按照字节传输数据 传输一个字节，最简单的方法就是用 8 个时间间隔，每个时间间隔传一个 bit
- 不传输数据的时候一直输出 1，传输字节前输出一个时间间隔的 0，然后是字节的 8 个位，最后输出一个时间间隔的 1

## MMIO
把 IO 操作映射到内存地址上，和之前轩哥说的和 IoT 设备交流是同样的原理    
只要约定好，哪个地址代表什么意思，我们就可以用一个 Wishbone 总线接口解决所有的内存和外设控制器的访问问题。    
伪装出来的串口读写： 
- 发送：**发送方** 写入地址 0x10000000 就是向串口发送一个字节的数据，写入/读取其他地址则无效，读取 0x10000001：不为零，表示现在串口控制器可以发送数据    
- 接收：如果需要读取串口寄存器当前接受到的字节，则应该读取 0x10000003，读取 0x10000002：不为零，表示现在串口控制器已经接受到了数据，CPU 可以读取

## Master
### 地址空间判断
wb_mux。它的功能就是判断地址属于哪个外设，然后进行“连接”，至于具体的收发过程也由那个 uart_controller 模块实现了
### 状态机
```
IDLE->ACTION
 ^      |
 |      v
 ---- DONE
```

> 在 IDLE 状态下，如果想要发送一次请求，就把请求的地址等信息保存在寄存器中，并设置 STB_O=1, CYC_O=1，转移到 ACTION 状态
> 在 ACTION 状态下，等待 ACK_I=1；如果发现 ACK_I=1，把返回的数据 DAT_I 记录下来，转移到 DONE 状态
> 在 DONE 状态下，根据自己的需求，对返回的结果做一些处理，然后转移到 IDLE 状态 (TODO 思考做啥处理)

### 数据流
```sv
    output reg wb_cyc_o,
    output reg wb_stb_o,
    input wire wb_ack_i,
    output reg [ADDR_WIDTH-1:0] wb_adr_o,
    output reg [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output reg [DATA_WIDTH/8-1:0] wb_sel_o,
    output reg wb_we_o,
```
之前的一个 master 是 lab4 目录下的 sram_tester，感觉控制信号可以大参考  
作为 master 我们主要还是输出对应的信号，然后等待 slave 的回应，协议部分看 lab3 文档，对于 sram 的读写参考 lab3 代码，感觉还是比较直白的，对于串口的读写 我们需要先加一步：   
- 读取 0x10000001：不为零，表示现在我们可以发送数据
- 读取 0x10000002：不为零，表示现在我们已经接受到了数据，可以传给上层模块
- 但是还是有一个问题，我们是从哪里得到写使能，数据和地址呢，看实验内容，分为以下步骤：
  - 人会把拨码开关设为起始地址 Addr，也是 Wishbone 总线的地址，所以我们从复位中恢复的时候，把拨码开关指示的地址记录下来，记作 addr，保证 addr 对齐到四字节的边界
  - 读串口：从串口读取数据，循环读取串口控制器的状态寄存器（地址是 0x1000_0005），如果状态显示可以读取新的数据就进行读取串口控制器的数据寄存器（地址是 0x1000_0000）   
    - 读串口部分实现
    - IDLE: 设置 addr_o 为 0x1000_0005，sel_o 为 b0010
    - READ_WAIT_ACTION: 如果收到 ack_i dat_i 为串口状态，检测我能不能发出去 转 RWC，否则停留在本状态  
    - RWC: 如果上一步可以发出去 那么这一步发 addr_o 0x1000_0000 sel_o 为 b0001 转到 READ_DATA_ACTION; 否则设置 addr_o 为 0x1000_0005，sel_o 为 b0010 转到READ_WAIT_ACTION
    - READ_DATA_ACTION: 如果收到 ack_i dat_i 为串口状态 则保存这个值 进入 READ_ACTION_DONE 状态 否则停留在本状态
    - READ_ACTION_DONE: 进入 WRITE_RAM_IDLE 状态
  - 写内存：
    - WRITE_RAM_IDLE: 设置 CYC_O SEL_O STB_O ADR_O WE_O 进入 WRITE_RAM 状态
    - WRITE_RAM: 等待 ACK 有 ACK 之后拉低 STB_O CYC_O 进入 WRITE_RAM_DONE 状态
    - WRITE_RAM_DONE: 地址+1 进入 WRITE_DATA_IDLE 状态
  
  - 写串口
    - 写入内容：从串口读取的数据 流程和读串口类似

### 第二部分：比较十个数和读出来的数
这一部分基本模仿那个 sram_tester 就行
首先当 cnt==9 时 转到 cmp_read 状态
cmp_read: 
cmp_read: 设置 addr cyc stb cel we 进入 read_action 或者 done 状态（读够10个数的时候）
cmp_read_action: 接收到 ack 之后比较 进 error 或者 read 状态

### 非对齐访问
唉 看文档吧 不难 不用考虑非串口的非对齐访问     