// ============================================================
//  alu.v  —  流水线 RISC-V CPU 算术逻辑单元（Final 扩展版）
//  作者：占锦翔
//  说明：与单周期 alu.v 相同逻辑，Zero 语义统一为"条件成立=1"
// ============================================================
`include "ctrl_encode_def.v"

module alu(
    input  signed [31:0] A,
    input  signed [31:0] B,
    input         [4:0]  ALUOp,
    output signed [31:0] C,
    output               Zero
);

    reg [31:0] C;

    always @(*) begin
        case (ALUOp)
            `ALUOp_lui:  C = B;
            `ALUOp_add:  C = A + B;
            `ALUOp_sub:  C = A - B;
            `ALUOp_bne:  C = (A != B)                   ? 32'd1 : 32'd0;
            `ALUOp_blt:  C = ($signed(A) < $signed(B))  ? 32'd1 : 32'd0;
            `ALUOp_bge:  C = ($signed(A) >= $signed(B)) ? 32'd1 : 32'd0;
            `ALUOp_bltu: C = ($unsigned(A) < $unsigned(B))  ? 32'd1 : 32'd0;
            `ALUOp_bgeu: C = ($unsigned(A) >= $unsigned(B)) ? 32'd1 : 32'd0;
            `ALUOp_slt:  C = ($signed(A) < $signed(B))     ? 32'd1 : 32'd0;
            `ALUOp_sltu: C = ($unsigned(A) < $unsigned(B)) ? 32'd1 : 32'd0;
            `ALUOp_xor:  C = A ^ B;
            `ALUOp_or:   C = A | B;
            `ALUOp_and:  C = A & B;
            `ALUOp_sll:  C = A << B[4:0];
            `ALUOp_srl:  C = $unsigned(A) >> B[4:0];
            `ALUOp_sra:  C = $signed(A)   >>> B[4:0];
            default:     C = A;
        endcase
    end

    // Zero：B-type 比较指令 C!=0 即条件成立；其余 C==0 为零标志
    assign Zero = (ALUOp == `ALUOp_bne  ||
                   ALUOp == `ALUOp_blt  ||
                   ALUOp == `ALUOp_bge  ||
                   ALUOp == `ALUOp_bltu ||
                   ALUOp == `ALUOp_bgeu) ? (C != 32'b0)
                                         : (C == 32'b0);

endmodule
