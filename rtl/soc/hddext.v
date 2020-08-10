
module hddext
(
    input               clk,
    input               rst_n,
    
    //avalon slave
    input       [2:0]   io_address,
    input               io_read,
    output reg  [7:0]   io_readdata,
    input               io_write,
    input       [7:0]   io_writedata,
    
    //ide shared port 0x3F6
    output              ide_3f6_read,
    input       [7:0]   ide_3f6_readdata,
    output              ide_3f6_write,
    output      [7:0]   ide_3f6_writedata
);

reg io_read_last;
always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) io_read_last <= 1'b0;
	else if(io_read_last) io_read_last <= 1'b0;
	else io_read_last <= io_read;
end 

wire io_read_valid = io_read && io_read_last == 1'b0;

assign ide_3f6_read      = io_read_valid && io_address == 3'd6;
assign ide_3f6_write     = io_write && io_address == 3'd6;
assign ide_3f6_writedata = io_writedata;

wire [7:0] io_readdata_prepare = 
    (io_address == 3'd6)?   ide_3f6_readdata :
                            8'hFF;
							
always @(posedge clk) io_readdata <= io_readdata_prepare;

endmodule
