// ============================================================
//  NPC.v  —  单周期 RISC-V CPU 下一条 PC 计算模块（Final 版）
//  作者：占锦翔
//  说明：支持 PC+4、B-type 分支、JAL 跳转、JALR 跳转
// ============================================================
`include "ctrl_encode_def.v"

module NPC(
    input  [31:0] PC,       // 当前 PC
    input  [2:0]  NPCOp,    // 控制信号
    input  [31:0] IMM,      // 符号扩展后的立即数
    input  [31:0] RS1,      // jalr 所用的 rs1 寄存器值
    output reg [31:0] NPC   // 下一条 PC
);

    wire [31:0] PCPLUS4;
    assign PCPLUS4 = PC + 4;

    always @(*) begin
        case (NPCOp)
            `NPC_PLUS4:  NPC = PCPLUS4;                         // 顺序执行
            `NPC_BRANCH: NPC = PC + IMM;                        // B-type 分支目标
            `NPC_JUMP:   NPC = PC + IMM;                        // JAL 跳转目标
            `NPC_JALR:   NPC = (RS1 + IMM) & 32'hFFFF_FFFE;    // JALR：最低位清零
            default:     NPC = PCPLUS4;
        endcase
    end

endmodule
