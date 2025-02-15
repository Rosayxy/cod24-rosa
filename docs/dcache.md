# dcache
和 icache 较大的区别是要读写，然后要检测地址范围是否可以塞到 dcache 里面    

dcache 的读状态机在检测后和 icache 一样，但是写有区别   

dcache 的写状态机 belike: (我们采用写回写分配，fetch-on-miss 的策略) （不然可能满分不了）  

先检测地址范围是否可以塞到 cache 里面，如果不行，就发 wishbone 请求 否则如下   
```
- va[0x00000000, 0x002FFFFF] = pa[0x80100000, 0x803FFFFF] DAGUX-RV 用户态代码
- va[0x7FC10000, 0x7FFFFFFF] = pa[0x80400000, 0x807EFFFF] DAGU-WRV 用户态数据
- va[0x80000000, 0x80000FFF] = pa[0x80000000, 0x80000FFF] DAGUX-RV 用于返回内核态
- va[0x80001000, 0x80001FFF] = pa[0x80001000, 0x80001FFF] DAGUX-RV 用于运行 UTEST 程序（CRYPTONIGHT 除外）
- va[0x80100000, 0x80100FFF] = pa[0x80100000, 0x80100FFF] DAGUX-RV 方便测试
```
- 如果监控程序修改的是代码部分的内容（例如装载器装入代码），则修改完成之后监控程序需要调用 FENCE.I 指令，使得修改部分的内容可以被 IF master（即指令取指阶段的总线 master）所获知，我们需要将 cache 中 dirty 的部分写到 SRAM 当中，并且把 icache 清空 所以我们只需要 implement FENCE.I 指令即可
- 如果监控程序修改了页表，则修改完成之后需要调用 SFENCE.VMA 指令，使得修改部分的内容可以及时被程序所使用（这个可能需要和写页表的友友确定一下接口）
- FENCE.I 的一种实现是在写回数据缓存 dcache 的所有 dirty 项之后清空代码缓存 icache，并且从内存中获取更新之后的代码，因此在此之前要保证内存中的数据是最新的。所以 FENCE.I （假设在 exe 段开始操作）需要把当前 IF ID 段的指令 flush 掉 然后插入气泡到清空 icache 之后才可以继续执行 (在监控程序中 只有导入用户态程序的地方有用 icache)   
- SFENCE.VMA implementation 我们先把 dirty 的写入 sram 然后清空 dcache 再清空 icache 和 tlb 就可以了（需要插入气泡到清空 tlb 之后才可以执行 所以也要输出一个 stall 信号）（**问题：需要把当前 IF ID 段的指令 flush 掉么**）
- 由于我们采用 fetch on miss 所以数据结构上只需要在 icache 的基础上每个块增加一个 is_dirty 位即可    
- 写的话 分类讨论 hit miss
- hit 就直接赋值 cache 标记 is_dirty 然后单周期返回 否则 miss 的话就发 wishbone 请求 把其他四个块拉过来之后写数据 存 cache 并且标记 is_dirty
- 然后把 fence.i 和 sfence.vma 的实现写一下就好了   