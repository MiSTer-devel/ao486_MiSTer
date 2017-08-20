/*
 * This file is subject to the terms and conditions of the BSD License. See
 * the file "LICENSE" in the main directory of this archive for more details.
 *
 * Copyright (C) 2014 Aleksander Osman
 */

module driver_sd
(
    input             clk,
    input             rst_n,
    
    //
    input      [2:0]  avs_address,
    input             avs_read,
    output reg [31:0] avs_readdata,
    input             avs_write,
    input      [31:0] avs_writedata,

    output reg        op_read,
    output reg        op_write,
    output            op_device,
    input             result_ok,
    input             result_error
);

reg  [31:0]  sd_address;
reg  [31:0]  avalon_address_base;

assign op_device = !avalon_address_base[11];

always @(*) begin
	case(avs_address)
		    0: avs_readdata = {29'd0, status[2:0]};
		1,2,3: avs_readdata = {29'd0, mutex };
		    4: avs_readdata = avalon_address_base;
		    5: avs_readdata = sd_address;
		    6: avs_readdata = sd_block_count;
		    7: avs_readdata = 0;
	endcase
end

reg [2:0] mutex;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                      mutex <= 3'd0;
    else if(mutex == 3'd0 && avs_address == 1 && avs_read) mutex <= 3'd1;
    else if(mutex == 3'd0 && avs_address == 2 && avs_read) mutex <= 3'd2;
    else if(mutex == 3'd0 && avs_address == 3 && avs_read) mutex <= 3'd3;
    else if(mutex < 3'd4 && (op_read || op_write))         mutex <= 3'd4;
    else if(result_ok || result_error)                     mutex <= 3'd0;
end

//------------------------------------------------------------------------------

wire operation_idle = ~(op_read) && ~(op_write);

localparam [1:0] CONTROL_READ   = 2'd2;
localparam [1:0] CONTROL_WRITE  = 2'd3;

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                                                                   op_read <= 0;
    else if(result_ok || result_error)                                                               op_read <= 0;
    else if(operation_idle && avs_write && avs_address == 3 && avs_writedata[1:0] == CONTROL_READ)   op_read <= 1;
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                                                                   op_write <= 0;
    else if(result_ok || result_error)                                                               op_write <= 0;
    else if(operation_idle && avs_write && avs_address == 3 && avs_writedata[1:0] == CONTROL_WRITE)  op_write <= 1;
end

//------------------------------------------------------------------------------

localparam [2:0] STATUS_IDLE    = 3'd2;
localparam [2:0] STATUS_READ    = 3'd3;
localparam [2:0] STATUS_WRITE   = 3'd4;
localparam [2:0] STATUS_ERROR   = 3'd5;

reg [2:0] status;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                                                                status <= STATUS_IDLE;
    else if(operation_idle && avs_write && avs_address == 3 && avs_writedata[1:0] == CONTROL_READ)   status <= STATUS_READ;
    else if(operation_idle && avs_write && avs_address == 3 && avs_writedata[1:0] == CONTROL_WRITE)  status <= STATUS_WRITE;
    else if(result_error)                                                                            status <= STATUS_ERROR;
    else if(result_ok)                                                                               status <= STATUS_IDLE;
end

//------------------------------------------------------------------------------

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                        avalon_address_base <= 32'd0;
    else if(operation_idle && avs_write && avs_address == 0) avalon_address_base <= avs_writedata;
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                        sd_address <= 32'd0;
    else if(operation_idle && avs_write && avs_address == 1) sd_address <= avs_writedata;
end

reg [31:0] sd_block_count;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                        sd_block_count <= 32'd0;
    else if(operation_idle && avs_write && avs_address == 2) sd_block_count <= avs_writedata;
end

endmodule
