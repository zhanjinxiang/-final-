// ============================================================
//  EXT.v  —  单周期 RISC-V CPU 立即数扩展模块（Final 版）
//  作者：占锦翔
//  说明：支持 I/S/B/U/J 五种立即数格式的符号扩展
// ============================================================
`include "ctrl_encode_def.v"

module EXT(
    input  [11:0] iimm,    // I-type: instr[31:20]
    input  [11:0] simm,    // S-type: {instr[31:25], instr[11:7]}
    input  [11:0] bimm,    // B-type: {instr[31], instr[7], instr[30:25], instr[11:8]}
    input  [19:0] uimm,    // U-type: instr[31:12]
    input  [19:0] jimm,    // J-type: {instr[31], instr[19:12], instr[20], instr[30:21]}
    input  [5:0]  EXTOp,
    output reg [31:0] immout
);

    always @(*) begin
        case (EXTOp)
            // I-type：12位有符号扩展到32位（slli/srli/srai 的 shamt 也走此路径，取 [4:0]）
            `EXT_CTRL_ITYPE: immout = {{20{iimm[11]}}, iimm[11:0]};

            // S-type：12位有符号扩展
            `EXT_CTRL_STYPE: immout = {{20{simm[11]}}, simm[11:0]};

            // B-type：12位有符号扩展后左移1位（最低位补0，对应字节对齐偏移）
            `EXT_CTRL_BTYPE: immout = {{19{bimm[11]}}, bimm[11:0], 1'b0};

            // U-type：20位立即数置于 [31:12]，低12位补0
            `EXT_CTRL_UTYPE: immout = {uimm[19:0], 12'b0};

            // J-type：20位有符号扩展后左移1位
            `EXT_CTRL_JTYPE: immout = {{11{jimm[19]}}, jimm[19:0], 1'b0};

            default: immout = 32'b0;
        endcase
    end

endmodule
