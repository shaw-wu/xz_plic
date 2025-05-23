# PLIC手册  
> 本设计移植[RoaLogic](https://github.com/RoaLogic/plic)的设计，将system verilog语法换成verilog语法，并重构了寄存器文件。  
> [PLIC设计规范](https://github.com/riscv/riscv-plic-spec/blob/master/riscv-plic.adoc)


## PLIC设计规范  

PLIC(Platform-Level Interrupt Controller)是RISC-V官方规范的中断控制器设计，负责协调中断源与多个Hart上下文(即中断目标)。PLIC接受来自外部中断的中断请求，经PLIC核心送至Hart上下文。上下文可以包括多个核心的多个线程的多个特权模式（M-Mode/S-Mode），例如三个拥有M、S特权模式的四线程核心就需要3x2x4个中断上下文。  
```bash
    +----------+        +----------+       +-----------+
    |          |        |          |       |           |
    |   hart   | <----- |   plic   | <---- | interrupt | 
    |          |        |          |       |           |
    +----------+        +----------+       +-----------+
         ^                    ^                  ^
         |                    |                  |
         v                    V                  V
    +--------------------------------------------------+
    |                    Internection                  |
    +--------------------------------------------------+
```

PLIC在RISC-V系统的位置如上所示，外部中断请求经由PLIC送给核心处理。除此之外，中断请求还可以通过系统总线(Internection)送给PLIC处理，。

### PLIC工作流程
![图](./PLICInterruptFlow.jpg)

如图，PLIC流程涉及五个部分。
- 中断源(Interrupt Source)发起中断请求
    外设产生中断请求，通常是一个电平或边沿信号，或者MSI消息(来自Internection)，中断网关(GateWay)负责将中断请求转换成相应的格式，然后送入PLIC核心。
<br>
- PLIC核心设置中断挂起标志(IP)
    中断网关将该中断源的挂起位(IP)在PLIC核心中置1,表示该中断源有未处理的中断请求(Interrupt Request)。
<br>
- PLIC核心处理
    PLIC通过中断使能寄存器(IE)、中断优先级寄存器(priority)和阈值寄存器(Threshold)决定将中断请求送到哪个中断目标，将中断号写入对应中断目标的Claim寄存器，称为中断通知
<br>
- 核心处理中断
    核心通过查询Claim寄存器，响应中断源的中断请求，执行完中断后向Complete寄存器写入中断号以报告中断执行完毕。
<br>
- 下一次中断请求
    在核心返回正确的Complete信号之前，中断网关不会将该中断源的中断请求放行。至于在此期间再次生成的中断请求能否被暂存，并在中断目标Complete之后将其送至PLIC核心处理，取决于[具体实施方式](#中断触发)。

### PLIC寄存器

```
base + 0x000000: Reserved (interrupt source 0 does not exist)
base + 0x000004: Interrupt source 1 priority
base + 0x000008: Interrupt source 2 priority
...
base + 0x000FFC: Interrupt source 1023 priority
base + 0x001000: Interrupt Pending bit 0-31
base + 0x00107C: Interrupt Pending bit 992-1023
...
base + 0x002000: Enable bits for sources 0-31 on context 0
base + 0x002004: Enable bits for sources 32-63 on context 0
...
base + 0x00207C: Enable bits for sources 992-1023 on context 0
base + 0x002080: Enable bits for sources 0-31 on context 1
base + 0x002084: Enable bits for sources 32-63 on context 1
...
base + 0x0020FC: Enable bits for sources 992-1023 on context 1
base + 0x002100: Enable bits for sources 0-31 on context 2
base + 0x002104: Enable bits for sources 32-63 on context 2
...
base + 0x00217C: Enable bits for sources 992-1023 on context 2
...
base + 0x1F1F80: Enable bits for sources 0-31 on context 15871
base + 0x1F1F84: Enable bits for sources 32-63 on context 15871
base + 0x1F1FFC: Enable bits for sources 992-1023 on context 15871
...
base + 0x1FFFFC: Reserved
base + 0x200000: Priority threshold for context 0
base + 0x200004: Claim/complete for context 0
base + 0x200008: Reserved
...
base + 0x200FFC: Reserved
base + 0x201000: Priority threshold for context 1
base + 0x201004: Claim/complete for context 1
...
base + 0x3FFF000: Priority threshold for context 15871
base + 0x3FFF004: Claim/complete for context 15871
base + 0x3FFF008: Reserved
...
base + 0x3FFFFFC: Reserved
```

PLIC寄存器采用DMA的地址映射方式，核心可以直接对PLIC地址进行访问。最多支持1023个中断源，0号中断源保留用以表示没有中断请求；最多支持15872个中断目标。

现在依次介绍PLIC寄存器：

#### 配置寄存器
1. 优先级寄存器(Priority)
针对中断源设置，数值越大优先级越高，0表示永不中断。
<br>
2. 中断使能寄存器(Interrupt Enable, IE)
该寄存器堆映射到核心的xie寄存器(meie/seie)。中断源和中断目标一一对应，例如2个中断源3个中断目标就有2x3个有效的中断使能位。
<br>
3. 优先级阈值(Priority Threshold)
针对中断目标设置，只有优先级严格大于这个阈值的中断源才能被广播到对应的Claim位等待处理。

#### 行为寄存器

4. 中断待处理寄存器(Interrupt Pending, IP)
用与指示中断源的中断请求状态。中断网关放行中断请求后送给PLIC核心，由PLIC核心对相应ip位置位，PLIC核心通过读ip位就可以知道哪个中断源需要被处理；中断目标执行完中断服务、向PLIC写入有效Complete信号后，恢复相应的ip位。
<br>
5. 中断声明寄存器(Claim)
一个中断目标对应一个Claim寄存器，PLIC核心对ip中的待处理中断进行判断，[若认为中断源能够被中断目标响应](#优先级)，就会将Claim设置成对应的中断号。
<br>
6. 中断完成寄存器(Complete)
和Claim共用一个地址，中断目标完成中断程序后会对Complete寄存器写入执行的中断号，只有当中断号与Claim寄存器的中断号相同时才是一个有效的中断完成标识。有效的中断完成标识可以告知网关中断完成，可以对接下来的中断请求放行。
<br>

### PLIC机制说明

#### 广播

PLIC只负责将中断请求广播到Hart上下文，不负责对中断请求的仲裁和调度，同一个中断由哪一个中断目标Claim到,取决于Hart上下文的响应速度或者由软件调度。简单来说就是 **谁最快Claim到就由谁处理。** 如果要实现中断抢占(高权限打断低权限)或者中断嵌套，需要由核心或者软件处理。

#### 特权级委托

PLIC默认将中断源送到M-Mode的Hart上下文，只有核心将低权限的特权级(比如S-Mode)委托给PLIC，低权限特权级才会接收到中断请求。[具体方式是调整Hart上下文的中断阈值(Threshould)](#配置寄存器)。

#### 中断触发

PLIC的中断请求可以配置为电平触发和边沿触发两种模式。一般的实施方式为，电平或者边沿的中断请求送到PLIC处理，在该请求被处理完成之前，PLIC会屏蔽所有该中断源的中断请求。若PLIC实现了中断计数器，中断源送来的中断请求会通过中断网关的计数器记录下来，在中断执行完毕、核心写入有效Complete信息后，能够将记录的中断请求继续送给PLIC核心处理。`需要注意，该机制只有边沿触发模式才能启用，电平触发时依然无法记录正在执行的中断源的中断请求。`

#### 优先级

PLIC核心判断能不能把某个中断源送到某个中断目标，具体条件为：
- 中断源的优先级严格大于优先级阈值
- ip位中没有更高优先级的中断pending
- 中断源在中断目标的中断使能为1

**多个中断源优先级一样时，中断号小的先被送给中断目标。**

## 硬件设计