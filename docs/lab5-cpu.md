# lab5-cpu

## 控制信号设计
我们需要实现以下指令：lui,beq,lb,sb,sw,addi,add,andi
其中 beq 指令比较特殊，belike beq rs1,rs2,imm: if rs1 == rs2 then pc <- pc + imm
### 状态机
- STATE_IF: 在 sram 中按照 pc 读取 32 位数 对 alu 发出 pc <- pc + 4 的请求（先得存了当前的 pc）（不是啊 这步在本地直接算不就得了吗） 得到回应之后去更新 pc 更新状态，我们接收的是 sram 发过来的 ack 收到之后，把指令存到本地 然后进入 STATE_ID 状态   
- STATE_ID: 首先我们还得实现一个对含有立即数指令的 imm_get 从指令中把立即数拖出来
  - 我们把指令的 rs1 rs2 给寄存器堆读出数据 然后让 imm_get 把立即数拖出来
  - 嗯 文档里面是用 addi 指令举例的，但是我们这一步可以得到是 I 指令还是 R 类型的指令
#### arith instr (lui 也算吧)

- STATE_EXE
  - 把结果给 alu 等待 alu 返回
- STATE_WB
  - 把结果写回寄存器堆

#### beq instr

- STATE_EXE: 分类讨论 rs1 和 rs2 是否相等，如果不相等，则进行以下操作,**其中 imm 需要做符号扩展**
  
  - pc <= pc_now_reg + imm

#### load instr
- 如 `lb t1, 5(t0)`
- STATE_EXE: 计算 base_reg + offset
- STATE_READ: 设置 addr 从 sram 里面读出数据
- STATE_WB: 写入寄存器堆

#### store instr
- 如 `sb a0, 0(t0)`
- STATE_EXE: 计算 base_reg+offset；拿到数之后进行相应的右移
- STATE_WRITE: 写入 sram
- **注意非对其访问里面讲的要点**
## soc
直接用那个 lab4 的 soc 就行

## 二进制程序装载
是不是 sim 的时候把 BASE_RAM_INIT_FILE 换成我们编译出的文件就行了 111是的   

## 框架
首先我们看一下需要接上哪些部分：首先再像之前几个 lab 一样单独抽象一个模块出来吧，然后我们需要接上的是 alu，寄存器堆，sram，pc，还有一个 imm_get 模块，这个模块用来从指令中拖出立即数    
可以对照一下 lab5，lab5_master 就是 cpu 的一部分，已经有和 sram 和串口读写的能力了，在这个基础上，我们需要这些附加的功能：
- 第一步是拖出指令，这一步我们可以实现了
- 然后从指令中提取类型，立即数，rs1,rs2，rd 这些 应该都可以就地完成
- 把 rs1 对应编号的寄存器的值拖出来 需要接那个 regfile 模块
- 计算数：需要用那个 alu 模块
- 省流就是 还是在 lab5_master 的基础上做（魔改），然后把 alu regfile 的接口加上应该就问题不大了，此外，因为不明原因，regfile 可能不能在一个周期内返回(但是 alu 是可以的)     