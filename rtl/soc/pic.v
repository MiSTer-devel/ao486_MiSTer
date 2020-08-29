/*
 * Copyright (c) 2014, Aleksander Osman
 * Copyright (C) 2020, Alexey Melnikov
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module pic
(
	input               clk,
	input               rst_n,

	input               io_address,
	input               io_read,
	output reg  [7:0]   io_readdata,
	input               io_write,
	input       [7:0]   io_writedata,
	input               io_master_cs,
	input               io_slave_cs,

	//interrupt input
	input       [15:0]  interrupt_input,

	//interrupt output
	output              interrupt_do,
	output      [7:0]   interrupt_vector,
	input               interrupt_done
);

wire [7:0] mas_readdata;
wire [7:0] mas_vector;
wire       sla_active;

i8259 pic_mas
(
	.clk(clk),
	.rst_n(rst_n),

	.io_address(io_address),
	.io_read(io_read & io_master_cs),
	.io_readdata(mas_readdata),
	.io_write(io_write & io_master_cs),
	.io_writedata(io_writedata),

	.interrupt_input({interrupt_input[7:3],sla_int,interrupt_input[1:0]}),

	.slave_active(sla_active),

	.interrupt_do(interrupt_do),
	.interrupt_vector(mas_vector),
	.interrupt_done(interrupt_done)
);


wire [7:0] sla_readdata;
wire       sla_int;
wire [7:0] sla_vector;
wire       sla_select = sla_active && (mas_vector[2:0] == 2);

i8259 pic_sla
(
	.clk(clk),
	.rst_n(rst_n),

	.io_address(io_address),
	.io_read(io_read & io_slave_cs),
	.io_readdata(sla_readdata),
	.io_write(io_write & io_slave_cs),
	.io_writedata(io_writedata),

	.interrupt_input(interrupt_input[15:8]),

	.interrupt_do(sla_int),
	.interrupt_vector(sla_vector),
	.interrupt_done(sla_select & interrupt_done)
);

assign interrupt_vector = sla_select ? sla_vector : mas_vector;

always @(posedge clk) begin
	if(io_master_cs) io_readdata <= mas_readdata;
	else             io_readdata <= sla_readdata;
end

endmodule

module i8259
(
	input            clk,
	input            rst_n,

	input            io_address,
	input            io_read,
	output     [7:0] io_readdata,
	input            io_write,
	input      [7:0] io_writedata,

	//interrupt input
	input      [7:0] interrupt_input,

	output reg       slave_active,
	
	//interrupt output
	output reg       interrupt_do,
	output reg [7:0] interrupt_vector,
	input            interrupt_done
);

//------------------------------------------------------------------------------

reg io_read_last;
always @(posedge clk) begin if(rst_n == 1'b0) io_read_last <= 1'b0; else if(io_read_last) io_read_last <= 1'b0; else io_read_last <= io_read; end 
wire io_read_valid = io_read && io_read_last == 1'b0;

//------------------------------------------------------------------------------

reg [7:0] interrupt_last;
always @(posedge clk) begin
	if(rst_n == 1'b0)   interrupt_last <= 8'd0;
	else                interrupt_last <= interrupt_input;
end

//------------------------------------------------------------------------------

assign io_readdata =
    (polled)                                        ? { interrupt_do, 4'd0, irq_value } :
    (io_address == 1'b0 && read_reg_select == 1'b0) ? irr :
    (io_address == 1'b0 && read_reg_select == 1'b1) ? isr :
                                                      imr;
//------------------------------------------------------------------------------

wire init_icw1 = io_write && io_address == 1'b0 && io_writedata[4] == 1'b1;
wire init_icw2 = io_write && io_address == 1'b1 && in_init && init_byte_expected == 3'd2;
wire init_icw3 = io_write && io_address == 1'b1 && in_init && init_byte_expected == 3'd3;
wire init_icw4 = io_write && io_address == 1'b1 && in_init && init_byte_expected == 3'd4;

wire ocw1 = in_init == 1'b0 && io_write && io_address == 1'b1;
wire ocw2 = io_write && io_address == 1'b0 && io_writedata[4:3] == 2'b00;
wire ocw3 = io_write && io_address == 1'b0 && io_writedata[4:3] == 2'b01;

reg polled;
always @(posedge clk) begin
	if(rst_n == 1'b0)                polled <= 1'b0;
	else if(polled && io_read_valid) polled <= 1'b0;
	else if(ocw3)                    polled <= io_writedata[2];
end

reg read_reg_select;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                           read_reg_select <= 1'b0;
	else if(init_icw1)                                          read_reg_select <= 1'b0;
	else if(ocw3 && io_writedata[2] == 1'b0 && io_writedata[1]) read_reg_select <= io_writedata[0];
end

reg special_mask;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                           special_mask <= 1'd0;
	else if(init_icw1)                                          special_mask <= 1'd0;
	else if(ocw3 && io_writedata[2] == 1'b0 && io_writedata[6]) special_mask <= io_writedata[5];
end

reg in_init;
always @(posedge clk) begin
	if(rst_n == 1'b0)                      in_init <= 1'b0;
	else if(init_icw1)                     in_init <= 1'b1;
	else if(init_icw3 && ~init_requires_4) in_init <= 1'b0;
	else if(init_icw4)                     in_init <= 1'b0;
end

reg init_requires_4;
always @(posedge clk) begin
	if(rst_n == 1'b0)   init_requires_4 <= 1'b0;
	else if(init_icw1)  init_requires_4 <= io_writedata[0];
end

reg ltim;
always @(posedge clk) begin
	if(rst_n == 1'b0)   ltim <= 1'b0;
	else if(init_icw1)  ltim <= io_writedata[3];
end

reg [2:0] init_byte_expected;
always @(posedge clk) begin
	if(rst_n == 1'b0)                     init_byte_expected <= 3'd0;
	else if(init_icw1)                    init_byte_expected <= 3'd2;
	else if(init_icw2)                    init_byte_expected <= 3'd3;
	else if(init_icw3 && init_requires_4) init_byte_expected <= 3'd4;
end

reg [2:0] lowest_priority;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                               lowest_priority <= 3'd7;
	else if(init_icw1)                                              lowest_priority <= 3'd7;
	else if(ocw2 && io_writedata == 8'hA0)                          lowest_priority <= lowest_priority + 3'd1;  //rotate on non-specific EOI
	else if(ocw2 && { io_writedata[7:3], 3'b000 } == 8'hC0)         lowest_priority <= io_writedata[2:0];       //set priority
	else if(ocw2 && { io_writedata[7:3], 3'b000 } == 8'hE0)         lowest_priority <= io_writedata[2:0];       //rotate on specific EOI
	else if(acknowledge_not_spurious && auto_eoi && rotate_on_aeoi) lowest_priority <= lowest_priority + 3'd1;  //rotate on AEOI
end

reg [7:0] imr;
always @(posedge clk) begin
	if(rst_n == 1'b0)  imr <= 8'hFF;
	else if(init_icw1) imr <= 8'h00;
	else if(ocw1)      imr <= io_writedata;
end

wire [7:0] edge_detect = interrupt_input & ~interrupt_last;

reg [7:0] irr;
always @(posedge clk) begin
	if(rst_n == 1'b0)                 irr <= 8'h00;
	else if(init_icw1)                irr <= 8'h00;
	else if(acknowledge_not_spurious) irr <= (irr & interrupt_input & ~interrupt_vector_bits) | ((~ltim) ? edge_detect : interrupt_input);
	else                              irr <= (irr & interrupt_input)                          | ((~ltim) ? edge_detect : interrupt_input);
end

wire [7:0] writedata_mask = 8'h01 << io_writedata[2:0];

wire isr_clear = 
    (polled && io_read_valid) || //polling
    (ocw2 && (io_writedata == 8'h20 || io_writedata == 8'hA0)); //non-specific EOI or rotate on non-specific EOF
                                        
reg [7:0] isr;
always @(posedge clk) begin
	if(rst_n == 1'b0)                                       isr <= 8'h00;
	else if(init_icw1)                                      isr <= 8'h00;
	else if(ocw2 && { io_writedata[7:3], 3'b000 } == 8'h60) isr <= isr & ~writedata_mask;                     //clear on specific EOI
	else if(ocw2 && { io_writedata[7:3], 3'b000 } == 8'hE0) isr <= isr & ~writedata_mask;                     //clear on rotate on specific EOI
	else if(isr_clear)                                      isr <= isr & ~selectected_shifted_isr_first_bits; //clear on polling or non-specific EOI (with or without rotate)
	else if(acknowledge_not_spurious && ~auto_eoi)          isr <= isr | interrupt_vector_bits;               //set
end

reg [4:0] interrupt_offset;
always @(posedge clk) begin
	if(rst_n == 1'b0)   interrupt_offset <= 5'h0E;
	else if(init_icw2)  interrupt_offset <= io_writedata[7:3];
end

reg auto_eoi;
always @(posedge clk) begin
	if(rst_n == 1'b0)   auto_eoi <= 1'b0;
	else if(init_icw1)  auto_eoi <= 1'b0;
	else if(init_icw4)  auto_eoi <= io_writedata[1];
end

reg [7:0] irr_slave;
always @(posedge clk) begin
	if(rst_n == 1'b0)   irr_slave <= 8'h00;
	else if(init_icw3)  irr_slave <= io_writedata;
end

reg rotate_on_aeoi;
always @(posedge clk) begin
	if(rst_n == 1'b0)                          rotate_on_aeoi <= 1'b0;
	else if(init_icw1)                         rotate_on_aeoi <= 1'b0;
	else if(ocw2 && io_writedata[6:0] == 7'd0) rotate_on_aeoi <= io_writedata[7];
end

wire [7:0] selectected_prepare = irr & ~imr & ~isr;

wire [15:0] selectected_shifted = {selectected_prepare[0],selectected_prepare,selectected_prepare[7:1]} >> lowest_priority;
wire [15:0] selectected_shifted_isr = {isr[0],isr,isr[7:1]} >> lowest_priority;

wire [2:0] selectected_shifted_isr_first =
    (selectected_shifted_isr[0]) ? 3'd0 :
    (selectected_shifted_isr[1]) ? 3'd1 :
    (selectected_shifted_isr[2]) ? 3'd2 :
    (selectected_shifted_isr[3]) ? 3'd3 :
    (selectected_shifted_isr[4]) ? 3'd4 :
    (selectected_shifted_isr[5]) ? 3'd5 :
    (selectected_shifted_isr[6]) ? 3'd6 :
                                   3'd7;
    
wire [2:0] selectected_shifted_isr_first_norm = lowest_priority + selectected_shifted_isr_first + 3'd1;
wire [7:0] selectected_shifted_isr_first_bits = 8'h01 << selectected_shifted_isr_first_norm;
                                    
wire [2:0] selectected_index =
    (selectected_shifted[0]) ? 3'd0 :
    (selectected_shifted[1]) ? 3'd1 :
    (selectected_shifted[2]) ? 3'd2 :
    (selectected_shifted[3]) ? 3'd3 :
    (selectected_shifted[4]) ? 3'd4 :
    (selectected_shifted[5]) ? 3'd5 :
    (selectected_shifted[6]) ? 3'd6 :
                               3'd7;

wire irq = selectected_prepare != 8'd0 && (special_mask || selectected_index <= selectected_shifted_isr_first);

wire [2:0] irq_value = lowest_priority + selectected_index + 3'd1;

always @(posedge clk) begin
	if(rst_n == 1'b0)    interrupt_do <= 1'b0;
	else if(init_icw1)   interrupt_do <= 1'b0;
	else if(acknowledge) interrupt_do <= 1'b0;
	else if(irq)         interrupt_do <= 1'b1;
end

wire acknowledge_not_spurious = (polled && io_read_valid) || (interrupt_done && ~spurious);
wire acknowledge              = (polled && io_read_valid) || interrupt_done;

wire spurious_start = interrupt_do && ~interrupt_done && ~irq;

reg spurious;
always @(posedge clk) begin
	if(rst_n == 1'b0)           spurious <= 1'd0;
	else if(init_icw1)          spurious <= 1'b0;
	else if(spurious_start)     spurious <= 1'b1;
	else if(acknowledge || irq) spurious <= 1'b0;
end

always @(posedge clk) begin
	if(rst_n == 1'b0)            slave_active <= 1'b0;
	else if(init_icw1)           slave_active <= 1'b0;
	else if(acknowledge)         slave_active <= 1'b0;
	else if(irq || interrupt_do) slave_active <= irr_slave[irq_value];
end

always @(posedge clk) begin
	if(rst_n == 1'b0)            interrupt_vector <= 8'd0;
	else if(init_icw1)           interrupt_vector <= 8'd0;
	else if(irq || interrupt_do) interrupt_vector <= { interrupt_offset, irq_value };
end

wire [7:0] interrupt_vector_bits = 8'h01 << interrupt_vector[2:0];

endmodule
