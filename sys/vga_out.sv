
module vga_out
(
	input         clk,
	input         ypbpr_en,

	input         hsync,
	input         vsync,
	input         csync,

	input  [23:0] din,
	output [23:0] dout,

	output reg    hsync_o,
	output reg    vsync_o,
	output reg    csync_o
);

wire [5:0] red   = din[23:18];
wire [5:0] green = din[15:10];
wire [5:0] blue  = din[7:2];

// http://marsee101.blog19.fc2.com/blog-entry-2311.html
// Y  =  16 + 0.257*R + 0.504*G + 0.098*B (Y  =  0.299*R + 0.587*G + 0.114*B)
// Pb = 128 - 0.148*R - 0.291*G + 0.439*B (Pb = -0.169*R - 0.331*G + 0.500*B)
// Pr = 128 + 0.439*R - 0.368*G - 0.071*B (Pr =  0.500*R - 0.419*G - 0.081*B)

reg [18:0] y_2, pb_2, pr_2;
reg  [7:0] y, pb, pr;
reg [23:0] din2, din3;
reg hsync2, vsync2, csync2;
always @(posedge clk) begin
	y_2  <= 19'd04096 + ({red, 8'd0} + {red, 3'd0}) + ({green, 9'd0} + {green, 2'd0}) + ({blue, 6'd0} + {blue, 5'd0} + {blue, 2'd0});
	pb_2 <= 19'd32768 - ({red, 7'd0} + {red, 4'd0} + {red, 3'd0}) - ({green, 8'd0} + {green, 5'd0} + {green, 3'd0}) + ({blue, 8'd0} + {blue, 7'd0} + {blue, 6'd0});
	pr_2 <= 19'd32768 + ({red, 8'd0} + {red, 7'd0} + {red, 6'd0}) - ({green, 8'd0} + {green, 6'd0} + {green, 5'd0} + {green, 4'd0} + {green, 3'd0}) - ({blue, 6'd0} + {blue , 3'd0});

	y  <= ( y_2[18] ||  !y_2[17:12]) ? 8'd16 : (y_2[17:8] > 235) ? 8'd235 :  y_2[15:8];
	pb <= (pb_2[18] || !pb_2[17:12]) ? 8'd16 : (&pb_2[17:12])    ? 8'd240 : pb_2[15:8];
	pr <= (pr_2[18] || !pr_2[17:12]) ? 8'd16 : (&pr_2[17:12])    ? 8'd240 : pr_2[15:8];

	hsync_o <= hsync2; hsync2 <= hsync;
	vsync_o <= vsync2; vsync2 <= vsync;
	csync_o <= csync2; csync2 <= csync;

	din2 <= din;
	din3 <= din2;
end

assign dout = ypbpr_en ? {pr, y, pb} : din3;

endmodule
