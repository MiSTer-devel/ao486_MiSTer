// reset_source.v

// This file was auto-generated as a prototype implementation of a module
// created in component editor.  It ties off all outputs to ground and
// ignores all inputs.  It needs to be edited to make it do something
// useful.
// 
// This file will not be automatically regenerated.  You should check it in
// to your version control system if you want to keep it.

`timescale 1 ps / 1 ps
module reset_source
(
	input  wire  clk,        //      clock.clk
	input  wire  reset_hps,  //  reset_hps.reset
	output wire  reset_sys,  //  reset_sys.reset
	output wire  reset_cold, // reset_cold.reset
	input  wire  cold_req,   //  reset_ctl.cold_req
	output wire  reset,      //           .reset
	input  wire  reset_req,  //           .reset_req
	input  wire  warm_req,   //           .warm_req
	output wire  reset_warm  // reset_warm.reset
);

assign reset_cold = cold_req;
assign reset_warm = warm_req;

assign reset      = reset_sys;
assign reset_sys  = sys_reset | reset_hps | reset_req;

reg  sys_reset = 1;
always @(posedge clk) begin
	integer timeout = 0;
	reg reset_lock = 0;

	reset_lock <= reset_lock | cold_req;

	if(timeout < 2000000) begin
		sys_reset <= 1;
		timeout <= timeout + 1;
		reset_lock <= 0;
	end
	else begin 
		sys_reset <= reset_lock;
	end
end

endmodule
