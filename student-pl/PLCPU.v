// ============================================================
//  PLCPU.v  —  五级流水线 RISC-V CPU 顶层（Final 扩展版）
//  作者：占锦翔
//
//  ╔══════════════════════════════════════════════════════════╗
//  ║  整体架构：经典五级流水线                                  ║
//  ║  IF → ID → EX → MEM → WB                                ║
//  ║                                                          ║
//  ║  IF  ：取指，PC 送给指令存储器，读出 inst_in               ║
//  ║  ID  ：译码，读寄存器堆、生成立即数、产生控制信号           ║
//  ║  EX  ：ALU 运算、分支判断、JAL/JALR 目标地址计算           ║
//  ║  MEM ：访问数据存储器（lw/sw）                             ║
//  ║  WB  ：写回寄存器堆（ALU结果 / 内存数据 / PC+4）           ║
//  ║                                                          ║
//  ║  流水线寄存器（四组）：                                    ║
//  ║  IF/ID   — 保存 PC + instr                               ║
//  ║  ID/EX   — 保存译码结果、寄存器值、立即数、控制信号        ║
//  ║  EX/MEM  — 保存 ALU 结果、写内存数据、MEM/WB 控制信号     ║
//  ║  MEM/WB  — 保存内存读出数据、ALU 结果、写回控制信号        ║
//  ╚══════════════════════════════════════════════════════════╝
//
//  核心设计要点：
//  1. 数据前推（forwarding）：解决 ALU-ALU 数据相关
//     - MEM→EX 前推：上一条指令结果在 MEM 阶段，直接旁路到 ALU
//     - WB→EX  前推：上上条指令结果在 WB 阶段，也能旁路到 ALU
//     例：add x1, x2, x3
//          sub x4, x1, x5   ← sub 在 EX 需要 x1，但 add 还没写回 RF
//          → 从 MEM 或 WB 阶段直接把结果送到 ALU 输入端
//
//  2. Load-Use 阻塞（stall）：解决 load 后立即使用
//     lw 的数据要到 MEM 阶段访问存储器后才拿到，下一条指令的 EX 阶段来不及
//     例：lw  x1, 0(x2)
//          add x3, x1, x4   ← add 在 EX 需要 x1，但 lw 数据还没读到
//     → 暂停 PC 和 IF/ID 一个周期，清空 ID/EX 插入气泡（bubble）
//     → rd == x0 时不阻塞，因为 x0 恒为 0 没有真实相关
//
//  3. 控制冒险冲刷（flush）：分支/跳转在 EX 阶段才确定
//     分支在 EX 阶段判断是否跳转，此时 IF/ID 中已取入顺序地址的指令
//     例：beq x1, x2, label
//          addi x3, x3, 1    ← 跳转发生时这条已经在 ID 了，必须冲刷
//     → branch_taken 时清空 IF/ID，并向 ID/EX 插入气泡
//     → JAL/JALR 是无条件跳转（不依赖 Zero 标志），始终冲刷
//
//  4. JAL 和 JALR 的区别：
//     JAL  ：目标 = PC + imm，PC 相对跳转（常用于函数调用）
//     JALR ：目标 = rs1 + imm 且最低位清 0，寄存器间接跳转（常用于返回）
//     → JALR 的 rs1 可能来自上一条 ALU 指令，目标地址必须用前推后的 alu_in1
//
//  5. WB 写回数据来源（WDSel 选择）：
//     FromALU：R/I/U 型等算术结果
//     FromMEM：lw 从内存读回的数据
//     FromPC ：JAL/JALR 的返回地址（PC+4 存到 rd）
//
//  扩展内容（相对于 CODExp demo）：
//  1. ctrl.v 支持所有 Final 指令（详见 ctrl.v 注释）
//  2. alu.v 支持 slt/sltu/xori/ori/andi/srli/srai/slli 等
//  3. 数据前推（MEM→EX 和 WB→EX 两级 forwarding）
//  4. Load-Use 阻塞（load 后紧跟使用，插入一个气泡）
//  5. 控制冒险冲刷（B-type/jal/jalr 跳转时冲刷 IF+ID 寄存器）
//  6. JALR 支持：EX 阶段用 rs1+imm 计算目标并冲刷
//
//  流水线寄存器宽度说明：
//    IF/ID  : [31:0]PC + [31:0]instr = 64 位
//    ID/EX  : 200 位（详见 assign 段）
//    EX/MEM : 146 位
//    MEM/WB : 136 位
// ============================================================
`include "ctrl_encode_def.v"

module PLCPU(
    input         clk,
    input         reset,
    input  [31:0] inst_in,   // 来自指令存储器（IF 阶段）
    input  [31:0] Data_in,   // 来自数据存储器（MEM 阶段）
    output [31:0] PC_out,    // 当前 PC（指令存储器地址）
    output [31:0] Addr_out,  // 数据存储器地址（MEM_aluout）
    output [31:0] Data_out,  // 写入数据存储器的数据
    output        mem_w,     // 数据存储器写使能
    output        mem_r      // 数据存储器读使能
);

// ═════════════════════════════════════════════════════════════
//  阶段一：ID（Instruction Decode）— 指令译码
//
//  功能：
//  1. 从 IF/ID 寄存器取出指令，拆分 opcode / funct3 / funct7 / rs1 / rs2 / rd
//  2. 分解五种立即数格式（I/S/B/U/J）送给 EXT 做符号扩展
//  3. 读寄存器堆得到 RD1、RD2
//  4. 控制单元 ctrl 根据 opcode 产生 ALUOp、NPCOp、RegWrite 等控制信号
// ═════════════════════════════════════════════════════════════
    wire [31:0] instr;       // 从 IF/ID 寄存器取出的指令
    wire [6:0]  Op     = instr[6:0];
    wire [6:0]  Funct7 = instr[31:25];
    wire [2:0]  Funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [4:0]  rd     = instr[11:7];

    // --- 立即数分解（5 种格式，由 EXT 模块完成符号扩展）---
    // I-type : inst[31:20] → 12 位有符号立即数
    // S-type : inst[31:25] + inst[11:7] → store 偏移
    // B-type : inst[31]+inst[7]+inst[30:25]+inst[11:8] → 分支偏移（bit0 恒为 0）
    // U-type : inst[31:12] → 20 位高立即数（lui/auipc）
    // J-type : inst[31]+inst[19:12]+inst[20]+inst[30:21] → 跳转偏移（bit0 恒为 0）
    wire [11:0] iimm = instr[31:20];
    wire [11:0] simm = {instr[31:25], instr[11:7]};
    wire [11:0] bimm = {instr[31], instr[7], instr[30:25], instr[11:8]};
    wire [19:0] uimm = instr[31:12];
    wire [19:0] jimm = {instr[31], instr[19:12], instr[20], instr[30:21]};

    wire [31:0] immout;      // EXT 模块输出的 32 位符号扩展立即数
    wire [31:0] RD1, RD2;   // 寄存器堆读出的两个操作数
    wire        Zero;        // ALU 条件标志（C==0 时为 1，用于 beq）

    // ID 阶段控制信号（由 ctrl 模块产生，下一周期才被 EX 使用）
    wire        RegWrite, ID_MemWrite, ID_MemRead;
    wire [5:0]  EXTOp;
    wire [4:0]  ALUOp, NPCOp;
    wire        ALUSrc;
    wire [1:0]  WDSel;

    // WB 阶段写回信号（反馈到 ID 阶段用于 forwarding 判断）
    wire [4:0]  WB_rd;
    wire [31:0] WB_aluout, WB_MemData;
    wire        WB_RegWrite;
    wire [1:0]  WB_WDSel;
    wire [31:0] WB_pc;
    reg  [31:0] WD;         // 最终写回寄存器堆的数据

// ═════════════════════════════════════════════════════════════
//  阶段二：EX（Execute）— 执行 / 地址计算
//
//  功能：
//  1. ALU 运算（算术/逻辑/比较/移位）
//  2. 分支条件判断（Zero 与 NPCOp[0] 做 AND）
//  3. JAL/JALR 目标地址计算
//  4. 数据前推（forwarding）MUX 在这里实现
// ═════════════════════════════════════════════════════════════
    wire [4:0]  EX_rd, EX_rs1, EX_rs2;
    wire [31:0] EX_immout, EX_RD1, EX_RD2;
    wire        EX_RegWrite, EX_MemWrite, EX_MemRead;
    wire [4:0]  EX_ALUOp;
    wire [4:0]  EX_NPCOp_raw;  // ID/EX 传入的原始 NPCOp（未经 Zero 修正）
    wire        EX_ALUSrc;
    wire [1:0]  EX_WDSel;
    wire [31:0] EX_pc;
    wire [2:0]  EX_DMType;

    // ═══ NPCOp 编码说明 ═══
    // EX_NPCOp 格式：[4:1] 操作类型编码，[0] 与 Zero AND 后的实际跳转标志
    //
    // [4:1] 编码（B-type 分支，依赖 Zero）：
    //   0000x = beq  （Zero=1 时跳转 → EX_NPCOp[0] = 1 & Zero）
    //   0001x = bne  （Zero=0 时跳转 → EX_NPCOp[0] = 1 & ~Zero）
    //   0010x = blt  （符号小于   → EX_NPCOp[0] = 1 & C[31]）
    //   0011x = bge  （符号大于等于 → EX_NPCOp[0] = 1 & ~C[31]）
    //   0100x = bltu （无符号小于 → EX_NPCOp[0] = 1 & ~Cout）
    //   0101x = bgeu （无符号大于等于 → EX_NPCOp[0] = 1 & Cout）
    //
    // [4:1] 编码（无条件跳转，不依赖 Zero）：
    //   1000x = JAL  （无条件，目标 = PC + imm）
    //   1001x = JALR （无条件，目标 = rs1 + imm，最低位清零）
    //
    // 关键：JAL/JALR 不依赖 Zero！ctrl 在发出 JAL/JALR 时 ALUOp 默认 nop，
    // 导致 Zero 可能为 1（取决于 ALU 默认行为），所以用 is_unconditional 强制 [0]=1
    wire is_unconditional = (EX_NPCOp_raw[4:1] == 4'b1000) || (EX_NPCOp_raw[4:1] == 4'b1001);
    wire [4:0] EX_NPCOp;
    assign EX_NPCOp = {EX_NPCOp_raw[4:1],
                       is_unconditional ? 1'b1 : (EX_NPCOp_raw[0] & Zero)};

// ═════════════════════════════════════════════════════════════
//  阶段三：MEM（Memory Access）— 存储器访问
//
//  功能：
//  lw：用 ALU 计算出的地址读 Data_in
//  sw：用 ALU 计算出的地址写 Data_out（RD2 值）
// ═════════════════════════════════════════════════════════════
    wire [4:0]  MEM_rd, MEM_rs2;
    wire [31:0] MEM_RD2, MEM_aluout;
    wire        MEM_RegWrite, MEM_MemWrite, MEM_MemRead;
    wire [1:0]  MEM_WDSel;
    wire [2:0]  MEM_DMType;
    wire [31:0] MEM_pc;

    assign mem_w    = MEM_MemWrite;
    assign mem_r    = MEM_MemRead;
    assign Addr_out = MEM_aluout;

// ═════════════════════════════════════════════════════════════
//  数据前推（Forwarding）— 解决 ALU-ALU 数据相关
//
//  问题场景：
//    add x1, x2, x3    // x1 在 EX 阶段末尾产生，下一周期才写回 RF
//    sub x4, x1, x5    // sub 在 EX 阶段需要 x1，但 RF 里还是旧值
//
//  解决方案：检测 EX 阶段的 rs1/rs2 是否等于 MEM 或 WB 阶段的 rd，
//           如果匹配则直接旁路（bypass）数据，不等 RF 写回。
//
//  前推优先级：
//    MEM→EX（fwd=01）优先于 WB→EX（fwd=10）
//    因为 MEM 阶段的数据更新（离 EX 更近），如果两者都匹配应该用 MEM 的
//
//  关键：rs1/rs2 == 0 时不前推，因为 x0 硬件连线恒为 0
// ═════════════════════════════════════════════════════════════
    wire [31:0] aluout;
    reg  [31:0] alu_in1, alu_in2, memdata_wr;

    // --- 前推数据来源 ---
    // WB 阶段写回数据（根据 WDSel 选择 ALU 结果 / 内存数据 / PC+4）
    wire [31:0] WB_wd = (WB_WDSel == `WDSel_FromALU) ? WB_aluout :
                        (WB_WDSel == `WDSel_FromMEM)  ? WB_MemData :
                                                         WB_pc + 4;
    // MEM 阶段 ALU 结果（用于 MEM→EX 前推）
    // lw 的 MEM_aluout 是地址不是数据，但此处仅用于 forwarding 到 EX 的运算
    wire [31:0] MEM_wd = MEM_aluout;

    // --- 前推控制信号 ---
    // fwd_a: 控制 alu_in1 的来源（ALU 操作数 A）
    // fwd_b: 控制 alu_in2 的来源（ALU 操作数 B，非立即数时）
    // 编码：00=无前推（用 EX_RD1/RD2），01=MEM→EX，10=WB→EX
    wire [1:0] fwd_a, fwd_b;
    assign fwd_a = (EX_rs1 != 0 && MEM_RegWrite && MEM_rd == EX_rs1) ? 2'b01 :
                   (EX_rs1 != 0 && WB_RegWrite  && WB_rd  == EX_rs1) ? 2'b10 : 2'b00;
    assign fwd_b = (EX_rs2 != 0 && MEM_RegWrite && MEM_rd == EX_rs2) ? 2'b01 :
                   (EX_rs2 != 0 && WB_RegWrite  && WB_rd  == EX_rs2) ? 2'b10 : 2'b00;

    // --- 前推 MUX：alu_in1 ---
    always @(*) begin
        case (fwd_a)
            2'b01:   alu_in1 = MEM_aluout; // MEM→EX 前推
            2'b10:   alu_in1 = WB_wd;      // WB→EX 前推
            default: alu_in1 = EX_RD1;     // 无相关，直接用 ID/EX 寄存器值
        endcase
    end

    // --- 前推 MUX：alu_in2 ---
    always @(*) begin
        case (fwd_b)
            2'b01:   alu_in2 = MEM_aluout; // MEM→EX 前推
            2'b10:   alu_in2 = WB_wd;      // WB→EX 前推
            default: alu_in2 = EX_RD2;     // 无相关，直接用 ID/EX 寄存器值
        endcase
    end

    // 存储器写数据：默认用 MEM 阶段的 RD2（来自 EX/MEM 寄存器）
    always @(*) begin
        memdata_wr = MEM_RD2;
    end

    assign Data_out = memdata_wr;

    // ALU 输入：A = 前推后的操作数1，B = 立即数或前推后的操作数2
    wire [31:0] A = alu_in1;
    wire [31:0] B = EX_ALUSrc ? EX_immout : alu_in2;

// ═════════════════════════════════════════════════════════════
//  Load-Use 冒险（Stall）— 只有这里 forwarding 解决不了
//
//  为什么 forwarding 解决不了 load-use？
//    ALU 指令的结果在 EX 阶段末尾就确定了，可以前推；
//    但 load 指令的数据要等到 MEM 阶段访问存储器后才拿到，
//    而下一条指令的 EX 阶段与当前 load 的 MEM 阶段同时进行，
//    数据来不及送到 ALU 输入端。
//
//  例：
//    lw  x1, 0(x2)     // MEM 阶段才拿到 Data_in
//    add x3, x1, x4    // EX 阶段同时发生，需要 x1 但数据还没到
//
//  处理：暂停 PC 和 IF/ID 一个周期，清空 ID/EX 插入 bubble
//  效果：add 指令在 ID 阶段多停一拍，等 lw 的 MEM 完成后再进 EX
//
//  为什么排除 x0？
//    x0 硬件连线恒为 0，不存在真实数据依赖
//    例：lw x0, 0(x1); add x2, x0, x3 → x0 永远为 0，无需 stall
// ═════════════════════════════════════════════════════════════
    wire load_use_hazard = EX_MemRead &&
                           (EX_rd != 5'b0) &&
                           ((EX_rd == rs1) || (EX_rd == rs2));

    wire stall = load_use_hazard;  // 暂停 PC 和 IF/ID
    wire flush_ex = stall;         // 同时清空 ID/EX（插入 bubble）

// ═════════════════════════════════════════════════════════════
//  控制冒险（Flush）— 分支/跳转时冲刷错误路径指令
//
//  为什么需要冲刷？
//    分支/跳转在 EX 阶段才确定要不要跳，此时 IF 和 ID 阶段
//    已经按顺序地址取了下两条指令。如果最终决定跳转，
//    这两条顺序地址上的指令就是错误的，必须清掉。
//
//  冲刷策略：
//    flush_if_id = branch_taken：清空 IF/ID 寄存器（全 0 = nop）
//    ID/EX 的输入被 gated（flush_if_id 时送入全 0）：确保错误指令不进 EX
//
//  时机说明：
//    当前周期 EX 阶段判断跳转 → 同一周期：
//    - IF/ID 被 flush（里面是错误路径的第二条指令）
//    - ID/EX 的输入被 gated（里面是错误路径的第一条指令，但用 flush 后的
//      IF/ID 输出产生，所以也是全 0）
//    - 下一周期：跳转目标地址的指令进入 IF，nop 进入 ID
// ═════════════════════════════════════════════════════════════
    wire branch_taken = EX_NPCOp[0];
    wire flush_if_id  = branch_taken;  // 跳转时冲刷 IF/ID 两个流水寄存器

// ═════════════════════════════════════════════════════════════
//  NPC 计算 — 下一 PC 的三种来源
//
//  PC+4         ：不跳转，顺序执行
//  branch_target：B-type 分支或 JAL（PC + 符号扩展立即数）
//  jalr_target  ：JALR（rs1 + 符号扩展立即数，最低位清零）
//
//  JAL vs JALR 区别：
//  JAL  目标 = 当前 PC + imm（PC 相对跳转，范围 ±1MB）
//        适用场景：函数调用（call）、远跳转
//  JALR 目标 = rs1 + imm 且最低位清零（寄存器间接跳转）
//        适用场景：函数返回（ret = jalr x0, ra, 0）、函数指针调用
//        最低位清零原因：RISC-V 指令必须 2 字节对齐
//
//  ⚠ JALR 的 rs1 可能被上一条指令修改，必须用前推后的 alu_in1
//    例：addi x1, x0, 100; jalr x0, x1, 0
//        若用 EX_RD1 读到的还是 0（addi 还没写回 RF），会跳错！
// ═════════════════════════════════════════════════════════════
    wire [31:0] NPC;
    wire is_jalr = (EX_NPCOp_raw[4:1] == 4'b1001);
    wire is_jal  = (EX_NPCOp_raw[4:1] == 4'b1000);
    wire is_branch = !is_jalr && !is_jal && EX_NPCOp_raw[0];

    // B-type 分支 & JAL 目标地址：PC + 立即数
    wire [31:0] branch_target = EX_pc + EX_immout;

    // JALR 目标地址：前推后的 rs1 + 立即数，最低位清零（对齐要求）
    wire [31:0] jalr_target   = (alu_in1 + EX_immout) & 32'hFFFF_FFFE;

    // 优先级：JALR > B-type/JAL > PC+4
    assign NPC = (branch_taken && is_jalr)  ? jalr_target   :
                 (branch_taken)              ? branch_target :
                                              PC_out + 4;

// ═════════════════════════════════════════════════════════════
//  子模块例化
// ═════════════════════════════════════════════════════════════

    // PC 寄存器
    // 下降沿更新，与 demo 时钟方案一致
    // stall 时 PC 保持不变（load-use 暂停）
    PC U_PC(
        .clk(~clk), .rst(reset),
        .NPC(NPC), .PC(PC_out),
        .stall(stall)
    );

    // 控制单元（ID 阶段）
    // 根据 opcode/funct3/funct7 产生各阶段控制信号
    ctrl U_ctrl(
        .Op(Op), .Funct7(Funct7), .Funct3(Funct3), .Zero(Zero),
        .RegWrite(RegWrite), .MemWrite(ID_MemWrite), .MemRead(ID_MemRead),
        .EXTOp(EXTOp), .ALUOp(ALUOp), .NPCOp(NPCOp),
        .ALUSrc(ALUSrc), .WDSel(WDSel)
    );

    // 立即数扩展（ID 阶段）
    EXT U_EXT(
        .iimm(iimm), .simm(simm), .bimm(bimm), .uimm(uimm), .jimm(jimm),
        .EXTOp(EXTOp), .immout(immout)
    );

    // 寄存器堆
    // WB 阶段写（A3=WB_rd, WD=前推/ALU/内存/PC+4）
    // ID 阶段读（A1=rs1, A2=rs2 → RD1, RD2）
    RF U_RF(
        .clk(clk), .rst(reset),
        .RFWr(WB_RegWrite),
        .A1(rs1), .A2(rs2), .A3(WB_rd),
        .WD(WD),
        .RD1(RD1), .RD2(RD2)
    );

    // ALU（EX 阶段）
    // A = 前推后的 alu_in1，B = 立即数或前推后的 alu_in2
    alu U_alu(
        .A(A), .B(B), .ALUOp(EX_ALUOp), .C(aluout), .Zero(Zero)
    );

    // ═══ WB 写回数据多路选择 ═══
    // ALU 指令（add/sub/and/or/sll 等）→ 写回 ALU 结果
    // load 指令（lw）                 → 写回内存读出的数据
    // JAL/JALR                       → 写回 PC+4（作为返回地址存到 rd）
    always @(*) begin
        case (WB_WDSel)
            `WDSel_FromALU: WD = WB_aluout;
            `WDSel_FromMEM: WD = WB_MemData;
            `WDSel_FromPC:  WD = WB_pc + 4;  // jal/jalr 返回地址
            default:        WD = WB_aluout;
        endcase
    end

// ═════════════════════════════════════════════════════════════
//  流水线寄存器（四组）
//
//  所有寄存器在 ~clk（下降沿）更新，与 demo 保持一致
//  rst（同步复位）= 1 时清零，flush 信号也通过 rst 端口实现冲刷
//  stall = 1 时寄存器保持当前值不更新
// ═════════════════════════════════════════════════════════════

    //──────────────────────────────────────────
    // IF/ID 寄存器（64 位）
    // [31:0]  = PC_out    — 当前指令的 PC
    // [63:32] = inst_in   — 从指令存储器读出的 32 位指令
    //
    // flush_if_id = 1 → 寄存器清零 = 插入 nop
    // stall = 1 → 保持不动（load-use 时 PC 也不变，重新取同一条指令）
    //──────────────────────────────────────────
    wire [63:0] IF_ID_in, IF_ID_out;
    assign IF_ID_in[31:0]  = PC_out;
    assign IF_ID_in[63:32] = inst_in;
    assign instr            = IF_ID_out[63:32];

    pl_reg #(.WIDTH(64)) IF_ID (
        .clk(~clk), .rst(reset | flush_if_id),
        .stall(stall),
        .in(IF_ID_in), .out(IF_ID_out)
    );

    //──────────────────────────────────────────
    // ID/EX 寄存器（200 位）
    //
    // 位分布：
    // [31:0]   = PC         — 当前指令 PC
    // [36:32]  = rd         — 目标寄存器号
    // [41:37]  = rs1        — 源寄存器1
    // [46:42]  = rs2        — 源寄存器2
    // [78:47]  = immout     — 符号扩展后的立即数
    // [110:79] = RD1        — 寄存器 rs1 的值
    // [142:111]= RD2        — 寄存器 rs2 的值
    // [143]    = RegWrite   — WB 写使能
    // [144]    = MemWrite   — MEM 写使能
    // [149:145]= ALUOp      — ALU 操作码（5 位）
    // [154:150]= NPCOp      — NPC 操作码（5 位，含条件位）
    // [155]    = ALUSrc     — ALU B 源选择（1=立即数）
    // [158:156]= DMType     — 数据存储器访问类型（保留）
    // [160:159]= WDSel      — 写回数据选择
    // [161]    = MemRead    — MEM 读使能
    // [199:162]= reserved   — 保留
    //
    // 冲刷逻辑：当 flush_if_id=1（跳转发生）时，
    //   所有进入 ID/EX 的信号都被 gated 为 0，
    //   相当于往 EX 阶段插入一个全 0 的 bubble（nop）
    //──────────────────────────────────────────
    wire [31:0] id_pc   = flush_if_id ? 32'b0 : IF_ID_out[31:0];
    wire [4:0]  id_rd   = flush_if_id ? 5'b0  : rd;
    wire [4:0]  id_rs1  = flush_if_id ? 5'b0  : rs1;
    wire [4:0]  id_rs2  = flush_if_id ? 5'b0  : rs2;
    wire [31:0] id_imm  = flush_if_id ? 32'b0 : immout;
    wire [31:0] id_rd1  = flush_if_id ? 32'b0 : RD1;
    wire [31:0] id_rd2  = flush_if_id ? 32'b0 : RD2;
    wire        id_rw   = flush_if_id ? 1'b0  : RegWrite;
    wire        id_mw   = flush_if_id ? 1'b0  : ID_MemWrite;
    wire [4:0]  id_aluo = flush_if_id ? 5'b0  : ALUOp;
    wire [4:0]  id_npco = flush_if_id ? 5'b0  : NPCOp;
    wire        id_as   = flush_if_id ? 1'b0  : ALUSrc;
    wire [1:0]  id_wds  = flush_if_id ? 2'b0  : WDSel;
    wire        id_mr   = flush_if_id ? 1'b0  : ID_MemRead;

    wire [199:0] ID_EX_in, ID_EX_out;
    assign ID_EX_in[31:0]    = id_pc;
    assign ID_EX_in[36:32]   = id_rd;
    assign ID_EX_in[41:37]   = id_rs1;
    assign ID_EX_in[46:42]   = id_rs2;
    assign ID_EX_in[78:47]   = id_imm;
    assign ID_EX_in[110:79]  = id_rd1;
    assign ID_EX_in[142:111] = id_rd2;
    assign ID_EX_in[143]     = id_rw;
    assign ID_EX_in[144]     = id_mw;
    assign ID_EX_in[149:145] = id_aluo;
    assign ID_EX_in[154:150] = id_npco;
    assign ID_EX_in[155]     = id_as;
    assign ID_EX_in[158:156] = 3'b000;
    assign ID_EX_in[160:159] = id_wds;
    assign ID_EX_in[161]     = id_mr;
    assign ID_EX_in[199:162] = 38'b0;

    // ID/EX 输出 → EX 阶段信号
    assign EX_rd           = ID_EX_out[36:32];
    assign EX_rs1          = ID_EX_out[41:37];
    assign EX_rs2          = ID_EX_out[46:42];
    assign EX_immout        = ID_EX_out[78:47];
    assign EX_RD1           = ID_EX_out[110:79];
    assign EX_RD2           = ID_EX_out[142:111];
    assign EX_RegWrite       = ID_EX_out[143];
    assign EX_MemWrite       = ID_EX_out[144];
    assign EX_ALUOp          = ID_EX_out[149:145];
    assign EX_NPCOp_raw      = ID_EX_out[154:150];
    assign EX_ALUSrc         = ID_EX_out[155];
    assign EX_DMType         = ID_EX_out[158:156];
    assign EX_WDSel          = ID_EX_out[160:159];
    assign EX_MemRead        = ID_EX_out[161];
    assign EX_pc             = ID_EX_out[31:0];

    // flush_ex = stall（load-use 时）→ ID/EX 清零插入 bubble
    pl_reg #(.WIDTH(200)) ID_EX (
        .clk(~clk), .rst(reset | flush_ex),
        .stall(1'b0),
        .in(ID_EX_in), .out(ID_EX_out)
    );

    //──────────────────────────────────────────
    // EX/MEM 寄存器（146 位）
    //
    // 位分布：
    // [31:0]   = PC         — 指令 PC
    // [36:32]  = rd         — 目标寄存器
    // [68:37]  = alu_in2    — 前推后的操作数2（用于 sw 写内存）
    // [100:69] = aluout     — ALU 计算结果（地址或数据）
    // [101]    = RegWrite   — WB 写使能
    // [102]    = MemWrite   — 存储器写使能
    // [105:103]= DMType     — 数据存储器访问类型
    // [107:106]= WDSel      — 写回选择
    // [112:108]= rs2        — 源寄存器2（调试用）
    // [113]    = MemRead    — 存储器读使能
    // [145:114]= reserved   — 保留
    //──────────────────────────────────────────
    wire [145:0] EX_MEM_in, EX_MEM_out;
    assign EX_MEM_in[31:0]   = EX_pc;
    assign EX_MEM_in[36:32]  = EX_rd;
    assign EX_MEM_in[68:37]  = alu_in2;    // 前推后的值（sw 写内存用）
    assign EX_MEM_in[100:69] = aluout;
    assign EX_MEM_in[101]    = EX_RegWrite;
    assign EX_MEM_in[102]    = EX_MemWrite;
    assign EX_MEM_in[105:103]= EX_DMType;
    assign EX_MEM_in[107:106]= EX_WDSel;
    assign EX_MEM_in[112:108]= EX_rs2;
    assign EX_MEM_in[113]    = EX_MemRead;
    assign EX_MEM_in[145:114]= 32'b0;

    // EX/MEM 输出 → MEM 阶段信号
    assign MEM_rd       = EX_MEM_out[36:32];
    assign MEM_RD2      = EX_MEM_out[68:37];
    assign MEM_aluout   = EX_MEM_out[100:69];
    assign MEM_RegWrite  = EX_MEM_out[101];
    assign MEM_MemWrite  = EX_MEM_out[102];
    assign MEM_DMType    = EX_MEM_out[105:103];
    assign MEM_WDSel    = EX_MEM_out[107:106];
    assign MEM_rs2       = EX_MEM_out[112:108];
    assign MEM_MemRead   = EX_MEM_out[113];
    assign MEM_pc        = EX_MEM_out[31:0];

    pl_reg #(.WIDTH(146)) EX_MEM (
        .clk(~clk), .rst(reset),
        .stall(1'b0),
        .in(EX_MEM_in), .out(EX_MEM_out)
    );

    //──────────────────────────────────────────
    // MEM/WB 寄存器（136 位）
    //
    // 位分布：
    // [31:0]   = PC         — 指令 PC（用于 JAL/JALR 返回地址 = PC+4）
    // [36:32]  = rd         — 写回目标寄存器
    // [68:37]  = aluout     — ALU 结果（FromALU 时写回）
    // [100:69] = Data_in    — 内存读出数据（FromMEM 时写回）
    // [101]    = RegWrite   — 寄存器写使能
    // [103:102]= WDSel      — 写回数据来源选择
    // [135:104]= reserved   — 保留
    //──────────────────────────────────────────
    wire [135:0] MEM_WB_in, MEM_WB_out;
    assign MEM_WB_in[31:0]   = MEM_pc;
    assign MEM_WB_in[36:32]  = MEM_rd;
    assign MEM_WB_in[68:37]  = MEM_aluout;
    assign MEM_WB_in[100:69] = Data_in;
    assign MEM_WB_in[101]    = MEM_RegWrite;
    assign MEM_WB_in[103:102]= MEM_WDSel;
    assign MEM_WB_in[135:104]= 32'b0;

    // MEM/WB 输出 → WB 阶段信号
    assign WB_pc        = MEM_WB_out[31:0];
    assign WB_rd        = MEM_WB_out[36:32];
    assign WB_aluout    = MEM_WB_out[68:37];
    assign WB_MemData   = MEM_WB_out[100:69];
    assign WB_RegWrite   = MEM_WB_out[101];
    assign WB_WDSel     = MEM_WB_out[103:102];

    pl_reg #(.WIDTH(136)) MEM_WB (
        .clk(~clk), .rst(reset),
        .stall(1'b0),
        .in(MEM_WB_in), .out(MEM_WB_out)
    );

endmodule

// ═════════════════════════════════════════════════════════════
//  PC 寄存器 — 支持 stall 的程序计数器
//
//  stall = 1 时 PC 保持不变（load-use 暂停）
//  rst  = 1 时 PC 清零（复位到 0x00000000）
//  上升沿触发（~clk 为下降沿的 pl_reg 传入，此处 posedge 即实际的 negedge）
// ═════════════════════════════════════════════════════════════
module PC(
    input         clk,
    input         rst,
    input         stall,
    input  [31:0] NPC,
    output reg [31:0] PC
);
    always @(posedge clk or posedge rst) begin
        if (rst)        PC <= 32'b0;
        else if (!stall) PC <= NPC;
    end
endmodule

// ═════════════════════════════════════════════════════════════
//  通用流水线寄存器 — pl_reg
//
//  参数：
//    WIDTH — 寄存器位宽（IF/ID=64, ID/EX=200, EX/MEM=146, MEM/WB=136）
//
//  控制信号：
//    rst=1   → 同步清零（插入 bubble / 冲刷）
//    stall=1 → 保持当前值不更新（load-use 暂停）
//    stall 优先级低于 rst：rst 时无论如何都清零
//
//  时钟：~clk（下降沿），与 demo 保持一致的双沿时钟方案
// ═════════════════════════════════════════════════════════════
module pl_reg #(parameter WIDTH = 32)(
    input              clk,
    input              rst,    // 同步复位（冲刷时置1）
    input              stall,  // 阻塞时保持不变
    input  [WIDTH-1:0] in,
    output reg [WIDTH-1:0] out
);
    always @(posedge clk) begin
        if (rst)        out <= {WIDTH{1'b0}};
        else if (!stall) out <= in;
    end
endmodule
