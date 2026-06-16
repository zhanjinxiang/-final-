// ============================================================
//  ctrl.v  —  流水线 RISC-V CPU 控制器（Final 扩展版）
//  作者：占锦翔
//  说明：在 CODExp demo 基础上扩展，支持所有 Final 要求指令：
//        beq, bne, blt, bge, bltu, bgeu
//        slt, sltu, andi, ori, xori
//        srli, srai, slli
//        slti, sltiu
//        jal, jalr
//  注意：NPCOp 使用 5 位（[4:1] 操作类型 + [0] 条件），
//        jalr 需要 EX 阶段拿到 rs1 后才能计算目标地址，
//        控制冒险由 PLCPU 的冲刷逻辑处理。
// ============================================================
`include "ctrl_encode_def.v"

module ctrl(
    input  [6:0] Op,
    input  [6:0] Funct7,
    input  [2:0] Funct3,
    input        Zero,        // 来自 EX 阶段 ALU（由 PLCPU 通过 EX_NPCOp[0]&Zero 逻辑使用）

    output reg       RegWrite,
    output reg       MemWrite,
    output reg       MemRead,
    output reg [5:0] EXTOp,
    output reg [4:0] ALUOp,
    output reg [4:0] NPCOp,   // [4:1]=操作类型, [0]=是否为条件跳转（需与Zero配合）
    output reg       ALUSrc,
    output reg [1:0] WDSel
);

    always @(*) begin
        // 默认 NOP
        RegWrite = 1'b0;
        MemWrite = 1'b0;
        MemRead  = 1'b0;
        EXTOp    = 6'b0;
        ALUOp    = `ALUOp_nop;
        NPCOp    = 5'b00000;   // 低位[0]=0表示非分支，高位[4:1]=0表示PC+4
        ALUSrc   = 1'b0;
        WDSel    = `WDSel_FromALU;

        case (Op)
        //----------------------------------------------------
        // LUI: U-type
        //----------------------------------------------------
        7'b0110111: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_UTYPE;
            ALUOp    = `ALUOp_lui;
        end

        //----------------------------------------------------
        // R-type: 0110011
        //----------------------------------------------------
        7'b0110011: begin
            RegWrite = 1'b1;
            case ({Funct7, Funct3})
                {7'b0000000, 3'b000}: ALUOp = `ALUOp_add;
                {7'b0100000, 3'b000}: ALUOp = `ALUOp_sub;
                {7'b0000000, 3'b010}: ALUOp = `ALUOp_slt;
                {7'b0000000, 3'b011}: ALUOp = `ALUOp_sltu;
                {7'b0000000, 3'b100}: ALUOp = `ALUOp_xor;
                {7'b0000000, 3'b110}: ALUOp = `ALUOp_or;
                {7'b0000000, 3'b111}: ALUOp = `ALUOp_and;
                {7'b0000000, 3'b001}: ALUOp = `ALUOp_sll;
                {7'b0000000, 3'b101}: ALUOp = `ALUOp_srl;
                {7'b0100000, 3'b101}: ALUOp = `ALUOp_sra;
                default: begin
                    RegWrite = 1'b0;
                    ALUOp    = `ALUOp_nop;
                end
            endcase
        end

        //----------------------------------------------------
        // I-type arithmetic: 0010011
        //----------------------------------------------------
        7'b0010011: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_ITYPE;
            case (Funct3)
                3'b000: ALUOp = `ALUOp_add;   // addi
                3'b010: ALUOp = `ALUOp_slt;   // slti
                3'b011: ALUOp = `ALUOp_sltu;  // sltiu
                3'b100: ALUOp = `ALUOp_xor;   // xori
                3'b110: ALUOp = `ALUOp_or;    // ori
                3'b111: ALUOp = `ALUOp_and;   // andi
                3'b001: ALUOp = (Funct7 == 7'b0000000) ? `ALUOp_sll : `ALUOp_nop; // slli
                3'b101: ALUOp = (Funct7 == 7'b0100000) ? `ALUOp_sra : `ALUOp_srl; // srai/srli
                default: begin
                    RegWrite = 1'b0;
                    ALUOp    = `ALUOp_nop;
                end
            endcase
        end

        //----------------------------------------------------
        // I-type load: 0000011
        //----------------------------------------------------
        7'b0000011: begin
            RegWrite = 1'b1;
            MemRead  = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_ITYPE;
            ALUOp    = `ALUOp_add;
            WDSel    = `WDSel_FromMEM;
        end

        //----------------------------------------------------
        // S-type: 0100011
        //----------------------------------------------------
        7'b0100011: begin
            MemWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_STYPE;
            ALUOp    = `ALUOp_add;
        end

        //----------------------------------------------------
        // B-type: 1100011
        // NPCOp[4:1] 编码分支类型，[0] 固定为1表示"有条件"
        // EX 阶段：EX_NPCOp = {NPCOp[4:1], NPCOp[0] & Zero}
        //----------------------------------------------------
        7'b1100011: begin
            EXTOp = `EXT_CTRL_BTYPE;
            case (Funct3)
                3'b000: begin // beq: sub, Zero=(C==0)
                    ALUOp = `ALUOp_sub;
                    NPCOp = {4'b0000, 1'b1}; // [0]=1 表示条件跳转，结合 Zero
                end
                3'b001: begin // bne
                    ALUOp = `ALUOp_bne;
                    NPCOp = {4'b0001, 1'b1};
                end
                3'b100: begin // blt
                    ALUOp = `ALUOp_blt;
                    NPCOp = {4'b0010, 1'b1};
                end
                3'b101: begin // bge
                    ALUOp = `ALUOp_bge;
                    NPCOp = {4'b0011, 1'b1};
                end
                3'b110: begin // bltu
                    ALUOp = `ALUOp_bltu;
                    NPCOp = {4'b0100, 1'b1};
                end
                3'b111: begin // bgeu
                    ALUOp = `ALUOp_bgeu;
                    NPCOp = {4'b0101, 1'b1};
                end
                default: begin
                    ALUOp = `ALUOp_nop;
                    NPCOp = 5'b00000;
                end
            endcase
        end

        //----------------------------------------------------
        // JAL: 1101111
        //----------------------------------------------------
        7'b1101111: begin
            RegWrite = 1'b1;
            EXTOp    = `EXT_CTRL_JTYPE;
            NPCOp    = {4'b1000, 1'b1}; // 无条件跳转，高位编码 JAL
            WDSel    = `WDSel_FromPC;
        end

        //----------------------------------------------------
        // JALR: 1100111
        // 需要 EX 阶段拿到 rs1 才能计算目标，控制冒险在 PLCPU 处理
        //----------------------------------------------------
        7'b1100111: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_ITYPE;
            ALUOp    = `ALUOp_add;
            NPCOp    = {4'b1001, 1'b1}; // 无条件跳转，高位编码 JALR
            WDSel    = `WDSel_FromPC;
        end

        default: begin
            RegWrite = 1'b0;
            MemWrite = 1'b0;
        end
        endcase
    end
endmodule
