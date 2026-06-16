`include "ctrl_encode_def.v"
module sccomp(clk, rstn, reg_sel, reg_data);
   input          clk, rstn; 
   input [4:0]    reg_sel;
   output [31:0]  reg_data;
   
   wire [31:0]    instr;
   wire [31:0]    PC;
   wire           MemWrite;
   wire [31:0]    dm_addr, dm_din, dm_dout;
   
   wire reset;
   assign reset = rstn;
   
   // instantiation of single-cycle CPU   
   SCCPU U_SCCPU(
         .clk(clk),
         .reset(reset),
         .inst_in(instr),
         .Data_in(dm_dout),
         .mem_w(MemWrite),
         .PC_out(PC),
         .Addr_out(dm_addr),
         .Data_out(dm_din),
         .reg_sel(reg_sel),
         .reg_data(reg_data)
         );
   
   dm    U_DM(
         .clk(clk),
         .DMWr(MemWrite),
         .addr(dm_addr),
         .din(dm_din),
         .dout(dm_dout)
         );
         
   im    U_imem ( 
         .addr(PC[31:2]),
         .dout(instr)
         );
endmodule
