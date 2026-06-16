// ============================================================
//  SCCPU.v  —  单周期 RISC-V CPU 顶层（Final 扩展版）
//  作者：占锦翔
//  说明：整合 ctrl / alu / NPC / EXT / RF / PC 各子模块
// ============================================================
`include "ctrl_encode_def.v"

module SCCPU(
    input         clk,
    input         reset,
    input  [31:0] inst_in,     // 来自指令存储器
    input  [31:0] Data_in,     // 来自数据存储器

    output        mem_w,       // 数据存储器写使能
    output [31:0] PC_out,      // 当前 PC（指令存储器地址）
    output [31:0] Addr_out,    // ALU 结果（数据存储器地址）
    output [31:0] Data_out,    // 写入数据存储器的数据

    input  [4:0]  reg_sel,     // 调试用寄存器选择
    output [31:0] reg_data     // 调试用寄存器输出
);

    // ---- 控制信号 ----
    wire        RegWrite;
    wire [5:0]  EXTOp;
    wire [4:0]  ALUOp;
    wire [2:0]  NPCOp;
    wire [1:0]  WDSel;
    wire        ALUSrc;
    wire        Zero;

    // ---- 数据通路信号 ----
    wire [31:0] NPC;
    wire [4:0]  rs1, rs2, rd;
    wire [6:0]  Op, Funct7;
    wire [2:0]  Funct3;
    wire [31:0] immout;
    wire [31:0] RD1, RD2;
    wire [31:0] B;
    wire [31:0] aluout;
    reg  [31:0] WD;

    // ---- 立即数分解 ----
    wire [11:0] iimm, simm, bimm;
    wire [19:0] uimm, jimm;

    assign iimm = inst_in[31:20];
    assign simm = {inst_in[31:25], inst_in[11:7]};
    assign bimm = {inst_in[31], inst_in[7], inst_in[30:25], inst_in[11:8]};
    assign uimm = inst_in[31:12];
    assign jimm = {inst_in[31], inst_in[19:12], inst_in[20], inst_in[30:21]};

    // ---- 指令字段 ----
    assign Op     = inst_in[6:0];
    assign Funct7 = inst_in[31:25];
    assign Funct3 = inst_in[14:12];
    assign rs1    = inst_in[19:15];
    assign rs2    = inst_in[24:20];
    assign rd     = inst_in[11:7];

    // ---- ALU B 源选择 ----
    assign B        = ALUSrc ? immout : RD2;
    assign Addr_out = aluout;
    assign Data_out = RD2;

    // ---- 子模块例化 ----
    ctrl U_ctrl(
        .Op(Op), .Funct7(Funct7), .Funct3(Funct3), .Zero(Zero),
        .RegWrite(RegWrite), .MemWrite(mem_w),
        .EXTOp(EXTOp), .ALUOp(ALUOp), .NPCOp(NPCOp),
        .ALUSrc(ALUSrc), .WDSel(WDSel)
    );

    PC U_PC(
        .clk(clk), .rst(reset), .NPC(NPC), .PC(PC_out)
    );

    NPC U_NPC(
        .PC(PC_out), .NPCOp(NPCOp), .IMM(immout), .RS1(RD1), .NPC(NPC)
    );

    EXT U_EXT(
        .iimm(iimm), .simm(simm), .bimm(bimm), .uimm(uimm), .jimm(jimm),
        .EXTOp(EXTOp), .immout(immout)
    );

    RF U_RF(
        .clk(clk), .rst(reset),
        .RFWr(RegWrite),
        .A1(rs1), .A2(rs2), .A3(rd),
        .WD(WD),
        .RD1(RD1), .RD2(RD2),
        .reg_sel(reg_sel), .reg_data(reg_data)
    );

    alu U_alu(
        .A(RD1), .B(B), .ALUOp(ALUOp), .C(aluout), .Zero(Zero)
    );

    // ---- 写回数据选择 ----
    always @(*) begin
        case (WDSel)
            `WDSel_FromALU: WD = aluout;
            `WDSel_FromMEM: WD = Data_in;
            `WDSel_FromPC:  WD = PC_out + 4;  // jal/jalr：返回地址 = 当前 PC + 4
            default:        WD = aluout;
        endcase
    end

endmodule
