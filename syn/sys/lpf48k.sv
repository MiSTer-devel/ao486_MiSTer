//   low pass filter
//   Revision 1.00
// 
// Copyright (c) 2008 Takayuki Hara.
// All rights reserved.
// 
// Redistribution and use of this source code or any derivative works, are 
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, 
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright 
//    notice, this list of conditions and the following disclaimer in the 
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial 
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED 
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//
//	LPF (cut off 48kHz at 3.58MHz)

module lpf48k #(parameter MSB = 15)
(
   input          RESET,
   input          CLK,
   input          CE,
	input          ENABLE,

   input  [MSB:0] IDATA,
   output [MSB:0] ODATA
);

wire [7:0] LPF_TAP_DATA[0:71] =
'{
	8'h51, 8'h07, 8'h07, 8'h08, 8'h08, 8'h08, 8'h09, 8'h09,
	8'h09, 8'h0A, 8'h0A, 8'h0A, 8'h0A, 8'h0B, 8'h0B, 8'h0B,
	8'h0B, 8'h0C, 8'h0C, 8'h0C, 8'h0C, 8'h0D, 8'h0D, 8'h0D,
	8'h0D, 8'h0D, 8'h0D, 8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0E,
	8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0E,
	8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0E, 8'h0D, 8'h0D, 8'h0D,
	8'h0D, 8'h0D, 8'h0D, 8'h0C, 8'h0C, 8'h0C, 8'h0C, 8'h0B,
	8'h0B, 8'h0B, 8'h0B, 8'h0A, 8'h0A, 8'h0A, 8'h0A, 8'h09,
	8'h09, 8'h09, 8'h08, 8'h08, 8'h08, 8'h07, 8'h07, 8'h51
};

reg      [7:0] FF_ADDR = 0;
reg [MSB+10:0] FF_INTEG = 0;
wire [MSB+8:0] W_DATA;
wire           W_ADDR_END;

assign W_ADDR_END = ((FF_ADDR == 71));

reg [MSB:0] OUT;

assign ODATA = ENABLE ? OUT : IDATA;

always @(posedge RESET or posedge CLK) begin
	if (RESET) FF_ADDR <= 0;
	else 
	begin
		if (CE) begin
			if (W_ADDR_END) FF_ADDR <= 0;
				else FF_ADDR <= FF_ADDR + 1'd1;
		end
	end
end

assign W_DATA = LPF_TAP_DATA[FF_ADDR] * IDATA;

always @(posedge RESET or posedge CLK) begin
	if (RESET) FF_INTEG <= 0;
	else 
	begin
		if (CE) begin
			if (W_ADDR_END) FF_INTEG <= 0;
				else FF_INTEG <= FF_INTEG + W_DATA;
		end
	end
end

always @(posedge RESET or posedge CLK) begin
	if (RESET) OUT <= 0;
	else
	begin
		if (CE && W_ADDR_END) OUT <= FF_INTEG[MSB + 10:10];
	end
end

endmodule
