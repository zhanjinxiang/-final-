`include "ctrl_encode_def.v"
module EXT( 
    input   [11:0]  iimm,
    input   [11:0]  simm,
    input   [11:0]  bimm,
    input   [19:0]  uimm,
    input   [19:0]  jimm,
    input   [5:0]   EXTOp,
    output  reg [31:0]  immout
);

always  @(*)
    case (EXTOp)
        `EXT_CTRL_ITYPE:  immout <= {{20{iimm[11]}}, iimm[11:0]};
        `EXT_CTRL_STYPE:  immout <= {{20{simm[11]}}, simm[11:0]};
        `EXT_CTRL_BTYPE:  immout <= {{19{bimm[11]}}, bimm[11:0], 1'b0};
        `EXT_CTRL_UTYPE:  immout <= {uimm[19:0], 12'b0};
        `EXT_CTRL_JTYPE:  immout <= {{21{jimm[19]}}, jimm[19:0], 1'b0};
        default:          immout <= 32'b0;
    endcase
       
endmodule
