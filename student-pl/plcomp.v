`include "ctrl_encode_def.v"
module plcomp(clk, rstn);
  input             clk, rstn;
   
   wire [31:0]    instr;
   wire [31:0]    PC;
   wire           MemWrite;
   wire           MemRead;
   wire [31:0]    dm_addr, dm_din, dm_dout;
   wire [2:0] DMType;
   
   wire reset;
   assign reset = rstn;
   
   PLCPU U_PLCPU(
         .clk(clk),
         .reset(reset),
         .inst_in(instr),
         .Data_in(dm_dout),
         .mem_w(MemWrite),
         .mem_r(MemRead),
         .PC_out(PC),
         .Addr_out(dm_addr),
         .Data_out(dm_din)
         );
   
   dm  U_DM(
         .clk(clk),
         .DMWr(MemWrite),
         .DMRe(MemRead),
         .addr(dm_addr),
         .din(dm_din),
         .dout(dm_dout)
         );
         
   im    U_imem ( 
      .addr(PC[31:2]),
      .dout(instr)
   );
endmodule
