// ============================================================
//  alu.v  —  单周期 RISC-V CPU 算术逻辑单元（Final 扩展版）
//  作者：占锦翔
//  说明：Zero 信号统一语义为"条件成立=1"：
//        · B-type 比较类指令（bne/blt/bge/bltu/bgeu）：C!=0 即条件成立
//        · beq/其他：C==0 即条件成立（保持原始 sub 结果语义）
// ============================================================
`include "ctrl_encode_def.v"

module alu(
    input  signed [31:0] A,
    input  signed [31:0] B,
    input         [4:0]  ALUOp,
    output signed [31:0] C,
    output               Zero   // 条件标志：条件成立时为 1
);

    reg [31:0] C;

    always @(*) begin
        case (ALUOp)
            `ALUOp_lui:  C = B;                                          // lui: 直通立即数
            `ALUOp_add:  C = A + B;                                      // add/addi/lw/sw/jalr 地址计算
            `ALUOp_sub:  C = A - B;                                      // sub/beq 差值
            `ALUOp_bne:  C = (A != B)  ? 32'd1 : 32'd0;                 // bne  条件
            `ALUOp_blt:  C = ($signed(A) < $signed(B))  ? 32'd1 : 32'd0; // blt  有符号
            `ALUOp_bge:  C = ($signed(A) >= $signed(B)) ? 32'd1 : 32'd0; // bge  有符号
            `ALUOp_bltu: C = ($unsigned(A) < $unsigned(B))  ? 32'd1 : 32'd0; // bltu 无符号
            `ALUOp_bgeu: C = ($unsigned(A) >= $unsigned(B)) ? 32'd1 : 32'd0; // bgeu 无符号
            `ALUOp_slt:  C = ($signed(A) < $signed(B))  ? 32'd1 : 32'd0; // slt  有符号比较写回
            `ALUOp_sltu: C = ($unsigned(A) < $unsigned(B)) ? 32'd1 : 32'd0; // sltu 无符号比较写回
            `ALUOp_xor:  C = A ^ B;                                      // xor/xori
            `ALUOp_or:   C = A | B;                                      // or/ori
            `ALUOp_and:  C = A & B;                                      // and/andi
            `ALUOp_sll:  C = A << B[4:0];                               // sll/slli：移位量低5位
            `ALUOp_srl:  C = $unsigned(A) >> B[4:0];                    // srl/srli：逻辑右移
            `ALUOp_sra:  C = $signed(A)  >>> B[4:0];                    // sra/srai：算术右移
            default:     C = A;
        endcase
    end

    // Zero 语义：
    //   B-type 比较指令 → C==1 表示条件成立，即 Zero=1 表示跳转
    //   beq(sub) / 其他 → C==0 表示相等，即 Zero=1 表示跳转
    assign Zero = (ALUOp == `ALUOp_bne  ||
                   ALUOp == `ALUOp_blt  ||
                   ALUOp == `ALUOp_bge  ||
                   ALUOp == `ALUOp_bltu ||
                   ALUOp == `ALUOp_bgeu) ? (C != 32'b0)
                                         : (C == 32'b0);

endmodule
