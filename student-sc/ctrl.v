// ============================================================
//  ctrl.v  —  单周期 RISC-V CPU 控制器（Final 扩展版）
//  作者：占锦翔
//  说明：在 lab-6 基础上已完整支持以下扩展指令：
//        R-type: add, sub, slt, sltu, xor, or, and, sll, srl, sra
//        I-arith: addi, slti, sltiu, xori, ori, andi, slli, srli, srai
//        I-load : lw
//        S-type : sw
//        B-type : beq, bne, blt, bge, bltu, bgeu
//        J-type : jal, jalr
//        U-type : lui
// ============================================================
`include "ctrl_encode_def.v"

module ctrl(
    input  [6:0] Op,
    input  [6:0] Funct7,
    input  [2:0] Funct3,
    input        Zero,       // ALU 条件标志（由 alu.v 根据 ALUOp 语义定义）

    output reg       RegWrite,
    output reg       MemWrite,
    output reg [5:0] EXTOp,
    output reg [4:0] ALUOp,
    output reg [2:0] NPCOp,
    output reg       ALUSrc,
    output reg [1:0] WDSel
);

    always @(*) begin
        // 默认值：NOP 行为
        RegWrite = 1'b0;
        MemWrite = 1'b0;
        EXTOp    = 6'b0;
        ALUOp    = `ALUOp_nop;
        NPCOp    = `NPC_PLUS4;
        ALUSrc   = 1'b0;
        WDSel    = `WDSel_FromALU;

        case (Op)
        //----------------------------------------------------
        // LUI: U-type，rd = imm << 12
        //----------------------------------------------------
        7'b0110111: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_UTYPE;
            ALUOp    = `ALUOp_lui;
        end

        //----------------------------------------------------
        // R-type: 0110011
        // add, sub, slt, sltu, xor, or, and, sll, srl, sra
        //----------------------------------------------------
        7'b0110011: begin
            RegWrite = 1'b1;
            case ({Funct7, Funct3})
                {7'b0000000, 3'b000}: ALUOp = `ALUOp_add;   // add
                {7'b0100000, 3'b000}: ALUOp = `ALUOp_sub;   // sub
                {7'b0000000, 3'b010}: ALUOp = `ALUOp_slt;   // slt
                {7'b0000000, 3'b011}: ALUOp = `ALUOp_sltu;  // sltu
                {7'b0000000, 3'b100}: ALUOp = `ALUOp_xor;   // xor
                {7'b0000000, 3'b110}: ALUOp = `ALUOp_or;    // or
                {7'b0000000, 3'b111}: ALUOp = `ALUOp_and;   // and
                {7'b0000000, 3'b001}: ALUOp = `ALUOp_sll;   // sll
                {7'b0000000, 3'b101}: ALUOp = `ALUOp_srl;   // srl
                {7'b0100000, 3'b101}: ALUOp = `ALUOp_sra;   // sra
                default: begin
                    RegWrite = 1'b0;
                    ALUOp    = `ALUOp_nop;
                end
            endcase
        end

        //----------------------------------------------------
        // I-type arithmetic: 0010011
        // addi, slti, sltiu, xori, ori, andi, slli, srli, srai
        //----------------------------------------------------
        7'b0010011: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_ITYPE;
            case (Funct3)
                3'b000: ALUOp = `ALUOp_add;   // addi
                3'b010: ALUOp = `ALUOp_slt;   // slti  (有符号)
                3'b011: ALUOp = `ALUOp_sltu;  // sltiu (无符号，立即数符号扩展后无符号比较)
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
        // I-type load: 0000011  lw
        //----------------------------------------------------
        7'b0000011: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_ITYPE;
            ALUOp    = `ALUOp_add;
            WDSel    = `WDSel_FromMEM;
        end

        //----------------------------------------------------
        // S-type: 0100011  sw
        //----------------------------------------------------
        7'b0100011: begin
            MemWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_STYPE;
            ALUOp    = `ALUOp_add;
        end

        //----------------------------------------------------
        // B-type: 1100011  beq, bne, blt, bge, bltu, bgeu
        // Zero 信号由 alu.v 统一定义为"条件成立=1"
        //----------------------------------------------------
        7'b1100011: begin
            EXTOp = `EXT_CTRL_BTYPE;
            case (Funct3)
                3'b000: begin // beq:  条件 A==B，ALU 做 sub，Zero=(C==0)
                    ALUOp = `ALUOp_sub;
                    NPCOp = Zero ? `NPC_BRANCH : `NPC_PLUS4;
                end
                3'b001: begin // bne:  条件 A!=B
                    ALUOp = `ALUOp_bne;
                    NPCOp = Zero ? `NPC_BRANCH : `NPC_PLUS4;
                end
                3'b100: begin // blt:  有符号 A<B
                    ALUOp = `ALUOp_blt;
                    NPCOp = Zero ? `NPC_BRANCH : `NPC_PLUS4;
                end
                3'b101: begin // bge:  有符号 A>=B
                    ALUOp = `ALUOp_bge;
                    NPCOp = Zero ? `NPC_BRANCH : `NPC_PLUS4;
                end
                3'b110: begin // bltu: 无符号 A<B
                    ALUOp = `ALUOp_bltu;
                    NPCOp = Zero ? `NPC_BRANCH : `NPC_PLUS4;
                end
                3'b111: begin // bgeu: 无符号 A>=B
                    ALUOp = `ALUOp_bgeu;
                    NPCOp = Zero ? `NPC_BRANCH : `NPC_PLUS4;
                end
                default: begin
                    ALUOp = `ALUOp_nop;
                    NPCOp = `NPC_PLUS4;
                end
            endcase
        end

        //----------------------------------------------------
        // J-type: 1101111  jal
        // rd = PC+4, PC = PC + imm
        //----------------------------------------------------
        7'b1101111: begin
            RegWrite = 1'b1;
            EXTOp    = `EXT_CTRL_JTYPE;
            NPCOp    = `NPC_JUMP;
            WDSel    = `WDSel_FromPC;
        end

        //----------------------------------------------------
        // I-type jump: 1100111  jalr
        // rd = PC+4, PC = (rs1 + imm) & ~1
        //----------------------------------------------------
        7'b1100111: begin
            RegWrite = 1'b1;
            ALUSrc   = 1'b1;
            EXTOp    = `EXT_CTRL_ITYPE;
            ALUOp    = `ALUOp_add;
            NPCOp    = `NPC_JALR;
            WDSel    = `WDSel_FromPC;
        end

        default: begin
            RegWrite = 1'b0;
            MemWrite = 1'b0;
        end
        endcase
    end
endmodule
