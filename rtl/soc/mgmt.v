
module mgmt
(
	input             clk,

	input      [15:0] in_address,
	input             in_active,
	input             in_read,
	output     [15:0] in_readdata,
	input             in_write,
	input      [15:0] in_writedata,
	
	output reg  [7:0] out_address,
	input      [31:0] out_readdata,
	output reg        out_read,
	output reg        out_write,
	output reg [31:0] out_writedata
);

reg word;
always @(posedge clk) begin
	if(~in_active) word <= 0;
	else if(in_read | in_write) word <= ~word;
end

assign in_readdata = word ? readdata[31:16] : readdata[15:0];

reg [31:0] readdata;
reg [15:0] writedata;
always @(posedge clk) begin
	reg inc;
	
	out_read      <= in_read  & word;
	out_write     <= in_write & word;
	out_writedata <= {in_writedata, writedata};

	if(~in_active) begin
		out_address <= in_address[7:0];
		inc  <= 0;
	end
	
	if(in_read && word && ~&out_address) out_address <= out_address + 1'd1;
	readdata <= out_readdata;	

	if(in_write && ~word) begin
		if(inc && ~&out_address) out_address <= out_address + 1'd1;
		writedata <= in_writedata;
		inc <= 1;
	end
end

endmodule
