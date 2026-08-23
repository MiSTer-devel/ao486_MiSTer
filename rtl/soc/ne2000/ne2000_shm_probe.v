// ne2000_shm_probe.v -- HPS<->FPGA shared-window probe for ao486.
//
// Phase 1 of NE2000_AO486_PLAN.md. Deliberately contains NO NE2000 logic: it
// exists only to answer the one question the whole transport rests on --
// "do the FPGA and the HPS address the same physical DDR bytes?" -- before any
// NIC behaviour depends on the answer. That question is exactly where the
// Minimig branch has been stuck (status & 0x7F00 == 0, CR = 0x00 forever).
//
// It gives a DOS program a window into the shared mailbox through the same
// eth_dma_* master the NE2000 core will use later:
//
//   base+0x8  W  window word address, low byte   (16-bit-word offset)
//   base+0x9  W  window word address, high byte
//   base+0xA  RW data low byte
//   base+0xB  RW data high byte
//   base+0xC  W  command: 1 = read, 2 = write
//             R  status:  bit0 busy, bit1 done, bit2 timeout
//   base+0xD  R  completion counter, low byte (advances on every transfer)
//
// Ports are byte-wide so DEBUG.EXE can drive them; the probe program uses them
// through a friendlier interface.
//
// A transfer that the mailbox never acknowledges is retired by TIMEOUT_CYCLES
// with the timeout bit set, so a dead transport reports itself instead of
// hanging the guest.

module ne2000_shm_probe
#(
    parameter TIMEOUT_CYCLES = 16'd50000
)
(
    input  wire        clk,
    input  wire        reset,

    // Byte-wide register interface (offsets 0x8..0xD of the probe aperture)
    input  wire  [3:0] io_address,
    input  wire        io_read,
    input  wire        io_write,
    input  wire  [7:0] io_writedata,
    output reg   [7:0] io_readdata,

    // Shared-memory transport master (to ne2000_ddr_mailbox)
    output reg         eth_dma_req,
    output reg         eth_dma_write,
    output reg  [15:1] eth_dma_addr,
    output reg  [15:0] eth_dma_wdata,
    output wire        eth_dma_wide,
    output wire [63:0] eth_dma_wdata64,
    output wire        eth_dma_uds,
    output wire        eth_dma_lds,
    input  wire        eth_dma_ready,
    input  wire [15:0] eth_dma_rdata
);

localparam [3:0] R_ADDR_LO = 4'h8;
localparam [3:0] R_ADDR_HI = 4'h9;
localparam [3:0] R_DATA_LO = 4'hA;
localparam [3:0] R_DATA_HI = 4'hB;
localparam [3:0] R_CMD     = 4'hC;
localparam [3:0] R_COUNT   = 4'hD;

assign eth_dma_wide    = 1'b0;          // single 16-bit lane per transfer
assign eth_dma_wdata64 = 64'h0;
assign eth_dma_uds     = 1'b0;          // active low: both bytes enabled
assign eth_dma_lds     = 1'b0;

reg [15:0] win_addr;                    // byte address inside the 64KB window
reg [15:0] data_reg;
reg        busy;
reg        done;
reg        timeout;
reg [7:0]  completions;
reg [15:0] watchdog;

always @(posedge clk) begin
    if (reset) begin
        win_addr      <= 16'h0000;
        data_reg      <= 16'h0000;
        busy          <= 1'b0;
        done          <= 1'b0;
        timeout       <= 1'b0;
        completions   <= 8'h00;
        watchdog      <= 16'd0;
        eth_dma_req   <= 1'b0;
        eth_dma_write <= 1'b0;
        eth_dma_addr  <= 15'h0000;
        eth_dma_wdata <= 16'h0000;
    end
    else begin
        if (busy) begin
            if (eth_dma_ready) begin
                // A read returns the window contents; a write just completes.
                if (!eth_dma_write) data_reg <= eth_dma_rdata;
                eth_dma_req <= 1'b0;
                busy        <= 1'b0;
                done        <= 1'b1;
                completions <= completions + 8'd1;
            end
            else if (watchdog == 16'd0) begin
                // Bounded escape -- a dead transport must report, not hang.
                eth_dma_req <= 1'b0;
                busy        <= 1'b0;
                done        <= 1'b1;
                timeout     <= 1'b1;
            end
            else begin
                watchdog <= watchdog - 16'd1;
            end
        end
        else if (io_write) begin
            case (io_address)
                R_ADDR_LO: win_addr[7:0]  <= io_writedata;
                R_ADDR_HI: win_addr[15:8] <= io_writedata;
                R_DATA_LO: data_reg[7:0]  <= io_writedata;
                R_DATA_HI: data_reg[15:8] <= io_writedata;
                R_CMD: begin
                    if (io_writedata[1:0] != 2'b00) begin
                        eth_dma_addr  <= win_addr[15:1];
                        eth_dma_wdata <= data_reg;
                        eth_dma_write <= io_writedata[1];
                        eth_dma_req   <= 1'b1;
                        busy          <= 1'b1;
                        done          <= 1'b0;
                        timeout       <= 1'b0;
                        watchdog      <= TIMEOUT_CYCLES;
                    end
                end
                default: ;
            endcase
        end
    end
end

always @(*) begin
    case (io_address)
        R_ADDR_LO: io_readdata = win_addr[7:0];
        R_ADDR_HI: io_readdata = win_addr[15:8];
        R_DATA_LO: io_readdata = data_reg[7:0];
        R_DATA_HI: io_readdata = data_reg[15:8];
        R_CMD:     io_readdata = {5'h00, timeout, done, busy};
        R_COUNT:   io_readdata = completions;
        default:   io_readdata = 8'hFF;
    endcase
end

/* verilator lint_off UNUSEDSIGNAL */
wire _unused = &{1'b0, io_read};
/* verilator lint_on UNUSEDSIGNAL */

endmodule
