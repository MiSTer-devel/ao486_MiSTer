/*
 * Copyright (c) 2014, Aleksander Osman
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

module sound(
    input               clk,
    input               clk_opl,
    input               rst_n,
    
    output              irq,
    
    //io slave 220h-22Fh
    input       [3:0]   io_address,
    input               io_read,
    output      [7:0]   io_readdata,
    input               io_write,
    input       [7:0]   io_writedata,
    
    //fm music io slave 388h-38Bh
    input       [1:0]   fm_address,
    input               fm_read,
    output      [7:0]   fm_readdata,
    input               fm_write,
    input       [7:0]   fm_writedata,
	input               fm_mode,

    //dma
    output              dma_soundblaster_req,
    input               dma_soundblaster_ack,
    input               dma_soundblaster_terminal,
    input       [7:0]   dma_soundblaster_readdata,
    output      [7:0]   dma_soundblaster_writedata,
    
    //sound output
    output     [15:0]   sample_l,
    output     [15:0]   sample_r,

    //mgmt slave
    /*
    0-255.[15:0]: cycles in period
    256.[12:0]:  cycles in 80us
    257.[9:0]:   cycles in 1 sample: 96000 Hz
    */
    input       [8:0]   mgmt_address,
    input               mgmt_write,
    input       [31:0]  mgmt_writedata
);

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------ dsp

wire [7:0] io_readdata_from_dsp;

wire       sample_from_dsp_disabled;
wire       sample_from_dsp_do;
wire [7:0] sample_from_dsp_value;

sound_dsp sound_dsp_inst(
    .clk                        (clk),
    .rst_n                      (rst_n),
    
    .irq                        (irq),                          //output
    
    //io slave 220h-22Fh
    .io_address                 (io_address),                   //input [3:0]
    .io_read                    (io_read),                      //input
    .io_readdata_from_dsp       (io_readdata_from_dsp),         //output [7:0]
    .io_write                   (io_write),                     //input
    .io_writedata               (io_writedata),                 //input [7:0]
    
    //dma
    .dma_soundblaster_req       (dma_soundblaster_req),         //output
    .dma_soundblaster_ack       (dma_soundblaster_ack),         //input
    .dma_soundblaster_terminal  (dma_soundblaster_terminal),    //input
    .dma_soundblaster_readdata  (dma_soundblaster_readdata),    //input [7:0]
    .dma_soundblaster_writedata (dma_soundblaster_writedata),   //output [7:0]
    
    //sample
    .sample_from_dsp_disabled   (sample_from_dsp_disabled),     //output
    .sample_from_dsp_do         (sample_from_dsp_do),           //output
    .sample_from_dsp_value      (sample_from_dsp_value),        //output [7:0] unsigned
    
    //mgmt slave
    /*
    0-255.[15:0]: cycles in period
    */
    .mgmt_address               (mgmt_address),                 //input [8:0]
    .mgmt_write                 (mgmt_write),                   //input
    .mgmt_writedata             (mgmt_writedata)                //input [31:0]
);

//------------------------------------------------------------------------------ opl

wire  [7:0] sb_readdata_from_opl;

wire        sample_from_opl;
wire [15:0] sample_from_opl_l;
wire [15:0] sample_from_opl_r;

reg [12:0] period_80us;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                               period_80us <= 2400;
    else if(mgmt_write && mgmt_address == 256)   period_80us <= mgmt_writedata[12:0];
end

wire  [7:0] opl_dout;

wire opl_we = (           io_address[2:1] == 0 && io_write)
           || (             fm_address[1] == 0 && fm_write)
           || (fm_mode && io_address[3:1] == 1 && io_write)
           || (fm_mode &&   fm_address[1] == 1 && fm_write);

opl3 #(50000000) opl
(
	.clk(clk),
	.clk_opl(clk_opl),
	.rst_n(rst_n),

	.period_80us(period_80us),

	.addr(io_write ? io_address[1:0] : fm_address),
	.din(io_write  ? io_writedata    : fm_writedata),
	.dout(opl_dout),
	.we(opl_we),
	.rd((io_read && (io_address == 8)) || (fm_read && !fm_address)),

	.sample_l(sample_from_opl_l),
	.sample_r(sample_from_opl_r)
);

assign sb_readdata_from_opl = (io_address == 8) ? opl_dout : 8'hFF;
assign fm_readdata          = !fm_address       ? opl_dout : 8'hFF;

//------------------------------------------------------------------------------ io_readdata

assign io_readdata = (io_address == 8 || io_address == 9) ? sb_readdata_from_opl : io_readdata_from_dsp;

//------------------------------------------------------------------------------

reg [15:0] sample_dsp;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                      sample_dsp <= 0;
    else if(sample_from_dsp_disabled)   sample_dsp <= 0;
    else if(sample_from_dsp_do)         sample_dsp <= {~sample_from_dsp_value[7], sample_from_dsp_value[6:0], sample_from_dsp_value};  //unsigned to signed
end

assign sample_l = {{2{sample_dsp[15]}}, sample_dsp[15:2]} + {sample_from_opl_l[15], sample_from_opl_l[15:1]};
assign sample_r = {{2{sample_dsp[15]}}, sample_dsp[15:2]} + {sample_from_opl_r[15], sample_from_opl_r[15:1]};

endmodule
