
module iobus
(
	input             clk,
	input             reset,

	input             cpu_read_do,
	input      [15:0] cpu_read_address,
	input      [2:0]  cpu_read_length,
	output reg [31:0] cpu_read_data,
	output reg        cpu_read_done,
	input             cpu_write_do,
	input      [15:0] cpu_write_address,
	input      [2:0]  cpu_write_length,
	input      [31:0] cpu_write_data,
	output reg        cpu_write_done,

	output reg [15:0] bus_address,
	output reg        bus_write,
	output reg        bus_read,
	input             bus_io32,
	output reg  [2:0] bus_datasize,
	output reg [31:0] bus_writedata,
	input      [31:0] bus_readdata
);

localparam S_IDLE      = 0;
localparam S_WRITE     = 1;
localparam S_WRITE_CHK = 2;
localparam S_READ      = 3;
localparam S_READ_W    = 4;
localparam S_READ_CHK  = 5;

always @(posedge clk) begin
	reg [2:0] state;
	reg [1:0] cnt;

	cpu_read_done <= 0;
	cpu_write_done <= 0;
	bus_read <= 0;
	bus_write <= 0;

	case(state)
		S_IDLE:
			begin
				bus_address   <= cpu_write_do ? cpu_write_address : cpu_read_address;
				bus_datasize  <= cpu_write_do ? cpu_write_length  : cpu_read_length;
				bus_writedata <= cpu_write_data;
				cnt <= 0;

				if(cpu_read_do)  state <= S_READ;
				if(cpu_write_do) state <= S_WRITE;
			end

		S_WRITE:
			begin
				bus_write <= 1;
				state <= S_WRITE_CHK;
			end
		
		S_WRITE_CHK:
			begin
				bus_address   <= bus_address + 1'd1;
				bus_writedata <= bus_writedata >> 8;
				bus_datasize  <= bus_datasize - 1'd1;
				state <= S_WRITE;
				if(bus_datasize == 1 || bus_io32) begin
					cpu_write_done <= 1;
					state <= S_IDLE;
				end
			end

		S_READ:
			begin
				bus_read <= 1;
				state <= S_READ_W;
			end

		S_READ_W:
			state <= S_READ_CHK;

		S_READ_CHK:
			begin
				bus_address <= bus_address + 1'd1;
				cnt <= cnt + 1'd1;
				bus_datasize <= bus_datasize - 1'd1;
				cpu_read_data[{cnt, 3'b000} +:8] <= bus_readdata[7:0];
				state <= S_READ;

				if(bus_io32) cpu_read_data <= bus_readdata;

				if(bus_datasize == 1 || bus_io32) begin
					cpu_read_done <= 1;
					state <= S_IDLE;
				end
			end
	endcase
	
	if(reset) state <= S_IDLE;
end

endmodule
