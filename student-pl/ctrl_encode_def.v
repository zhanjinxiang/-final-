// ============================================================
//  ctrl_encode_def.v  —  流水线 CPU 使用的宏定义（Final 版）
//  与单周期版本完全一致，统一引用
// ============================================================
`timescale 1ns/1ns

// NPC 控制信号（单周期用 3 位，流水线 ctrl.v 输出 5 位，含条件位）
`define NPC_PLUS4   3'b000
`define NPC_BRANCH  3'b001
`define NPC_JUMP    3'b010
`define NPC_JALR    3'b100

// EXT CTRL
`define EXT_CTRL_ITYPE_SHAMT 6'b100000
`define EXT_CTRL_ITYPE  6'b010000
`define EXT_CTRL_STYPE  6'b001000
`define EXT_CTRL_BTYPE  6'b000100
`define EXT_CTRL_UTYPE  6'b000010
`define EXT_CTRL_JTYPE  6'b000001

// 寄存器写回数据选择
`define WDSel_FromALU 2'b00
`define WDSel_FromMEM 2'b01
`define WDSel_FromPC  2'b10

// ALUOp 编码
`define ALUOp_nop   5'b00000
`define ALUOp_lui   5'b00001
`define ALUOp_auipc 5'b00010
`define ALUOp_add   5'b00011
`define ALUOp_sub   5'b00100
`define ALUOp_bne   5'b00101
`define ALUOp_blt   5'b00110
`define ALUOp_bge   5'b00111
`define ALUOp_bltu  5'b01000
`define ALUOp_bgeu  5'b01001
`define ALUOp_slt   5'b01010
`define ALUOp_sltu  5'b01011
`define ALUOp_xor   5'b01100
`define ALUOp_or    5'b01101
`define ALUOp_and   5'b01110
`define ALUOp_sll   5'b01111
`define ALUOp_srl   5'b10000
`define ALUOp_sra   5'b10001

// 数据存储器访问类型
`define dm_word              3'b000
`define dm_halfword          3'b001
`define dm_halfword_unsigned 3'b010
`define dm_byte              3'b011
`define dm_byte_unsigned     3'b100
