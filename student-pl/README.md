# Lab 6：单周期 CPU 学号排序模拟参考实现

## 目标

本实验给出一个可以在 `iverilog` 中运行的单周期 CPU 参考实现，用来执行 CODExp 提供的学号排序程序。

学生需要参考这个模拟环境，理解排序程序依赖的指令实现方式，再把相同思路迁移到 Nexys4 DDR FPGA 开发板上的单周期和流水线处理器工程中。

## 已完成内容

`source-sc` 目录中包含：

- 单周期 CPU Verilog 源码。
- 学号排序机器码：`rv32_sid_sort_sim.dat`。
- 学号排序汇编：`rv32_sid_sort_sim.asm`。
- 自动检查排序结果的 testbench：`sccomp_tb.v`。
- Windows 启动脚本：`build.bat`。
- Linux/macOS 启动方式：`Makefile`。

当前程序内置的学号 BCD 值是：

```text
0x54873530
```

排序完成后，testbench 期望数据内存中出现：

```text
mem[0x180] = 0x54873530
mem[0x184] = 0x03345578
```

其中 `0x03345578` 是把 8 个十进制数字从小到大排序后的 BCD 结果。

## 本实验涉及的关键指令

排序程序主要依赖以下指令：

- 算术/逻辑：`add`、`addi`、`and`、`andi`、`or`、`ori`、`xori`
- 比较：`slt`
- 移位：`sll`、`slli`、`srl`
- 访存：`lw`、`sw`
- 分支/跳转：`beq`、`bne`、`jal`、`jalr`
- 高位立即数：`lui`

这些指令已经在 `source-sc` 的控制器、ALU、立即数扩展和 NPC 逻辑中实现。

## Windows 运行方法

进入目录：

```powershell
cd lab-6\source-sc
```

运行：

```powershell
.\build.bat
```

成功时应该看到：

```text
[RESULT] original_sid=54873530
[RESULT] sorted_sid=03345578
[PASS] lab-6 sid sorting simulation passed.
```

如果只想编译：

```powershell
.\build.bat build
```

如果想清理生成文件：

```powershell
.\build.bat clean
```

## Linux/macOS 运行方法

```bash
cd lab-6/source-sc
make run
```

清理：

```bash
make clean
```

## 如何替换为自己的学号

打开：

```text
source-sc/rv32_sid_sort_sim.asm
```

找到程序开头构造学号的部分：

```asm
addi    x2, x0, 0x54
slli    x2, x2, 8
addi    x2, x2, 0x87
slli    x2, x2, 16
addi    x3, x0, 0x35
slli    x3, x3, 8
addi    x3, x3, 0x30
add     x2, x2, x3
```

这段代码把 8 位学号数字拼成一个 32 位 BCD 数。例如 `54873530` 被编码成 `0x54873530`。

如果要换成自己的学号，需要：

1. 修改汇编中的立即数。
2. 重新汇编生成 `.dat` 机器码。
3. 修改 `sccomp_tb.v` 中对 `mem[0x180]` 和 `mem[0x184]` 的期望值。

可使用Rars.jar导出 `.dat` 文件完成实验流程。

## 上板实现建议

模拟环境跑通后，上板时建议按这个顺序迁移：

1. 先确认 FPGA 工程中指令存储器能读取排序程序。
2. 再确认数据存储器能写入 `0x180` 和 `0x184` 对应地址。
3. 用 LED 或数码管显示 `mem[0x184]` 的排序结果。
4. 单周期 CPU 先跑通，再迁移到流水线 CPU。
5. 流水线 CPU 要额外处理数据冒险、控制冒险和跳转冲刷。

## 验收建议

报告中建议包含：

1. `.\build.bat` 或 `make run` 通过截图。
2. `original_sid=54873530` 和 `sorted_sid=03345578` 输出截图。
3. 说明排序程序使用了哪些新增指令。
4. 说明 `jalr` 返回 `swap` 子过程的原理。
5. 如果完成上板，提供开发板显示排序结果的照片。
