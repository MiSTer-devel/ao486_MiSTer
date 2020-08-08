// mgmt.v

// This file was auto-generated as a prototype implementation of a module
// created in component editor.  It ties off all outputs to ground and
// ignores all inputs.  It needs to be edited to make it do something
// useful.
// 
// This file will not be automatically regenerated.  You should check it in
// to your version control system if you want to keep it.

`timescale 1 ps / 1 ps
module mgmt (
	input             clk,            // clock.clk
	input      [15:0] in_address,     //    in.address
	input             in_active,      //      .active
	input             in_read,        //      .read
	output     [15:0] in_readdata,    //      .readdata
	input             in_write,       //      .write
	input      [15:0] in_writedata,   //      .writedata

	output     [3:0]  hdd0_address,   //  hdd0.address
	input      [31:0] hdd0_readdata,  //      .readdata
	output reg        hdd0_read,      //      .read
	output reg        hdd0_write,     //      .write
	output reg [31:0] hdd0_writedata, //      .writedata

	output     [3:0]  hdd1_address,   //  hdd1.address
	input      [31:0] hdd1_readdata,  //      .readdata
	output reg        hdd1_read,      //      .read
	output reg        hdd1_write,     //      .write
	output reg [31:0] hdd1_writedata, //      .writedata

	output     [3:0]  fdd0_address,   //  fdd0.address
	input      [31:0] fdd0_readdata,  //      .readdata
	output reg        fdd0_read,      //      .read
	output reg        fdd0_write,     //      .write
	output reg [31:0] fdd0_writedata, //      .writedata

	output     [7:0]  rtc_address,    //   rtc.address
	output reg        rtc_write,      //      .write
	output reg [7:0]  rtc_writedata   //      .writedata
);

reg word;
always @(posedge clk) begin
	if(~in_active) word <= 0;
	else if(in_read | in_write) word <= ~word;
end

assign in_readdata = word ? readdata[31:16] : readdata[15:0];

assign hdd0_address = addr[3:0];
assign hdd1_address = addr[3:0];
assign fdd0_address = addr[3:0];
assign rtc_address  = addr[7:0];

wire read  = in_read  & word;
wire write = in_write & word;

wire hdd0_cs = (in_address[15:8] == 8'hF0);
wire hdd1_cs = (in_address[15:8] == 8'hF1);
wire fdd0_cs = (in_address[15:8] == 8'hF2);
wire rtc_cs  = (in_address[15:8] == 8'hF4);

reg [31:0] readdata;
reg [15:0] writedata;
reg  [7:0] addr;
always @(posedge clk) begin
	reg inc;
	
	hdd0_read <= read & hdd0_cs;
	hdd1_read <= read & hdd1_cs;
	fdd0_read <= read & fdd0_cs;

	hdd0_write <= write & hdd0_cs;
	hdd1_write <= write & hdd1_cs;
	fdd0_write <= write & fdd0_cs;
	rtc_write  <= write & rtc_cs;

	hdd0_writedata <= {in_writedata, writedata};
	hdd1_writedata <= {in_writedata, writedata};
	fdd0_writedata <= {in_writedata, writedata};
	rtc_writedata  <= writedata[7:0];

	if(~in_active) begin
		addr <= in_address[7:0];
		inc  <= 0;
	end
	
	if(in_read && word && ~&addr) addr <= addr + 1'd1;
	readdata  <= hdd0_cs ? hdd0_readdata : hdd1_cs ? hdd1_readdata : fdd0_readdata;	

	if(in_write && ~word) begin
		if(inc && ~&addr) addr <= addr + 1'd1;
		writedata <= in_writedata;
		inc <= 1;
	end
end

endmodule
