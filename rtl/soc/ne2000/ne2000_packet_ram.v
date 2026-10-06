// ne2000_packet_ram.v -- extracted from Minimig ethernet.v
// (apolkosnik/Minimig-AGA_MiSTer, branch Ethernet_shmem2, commit 9598b936;
// GPL).  Kept one module per file to
// avoid the MULTITOP lint error reported in finding BF-3.
//
// (Do not start a comment line with the word "verilator" -- that is parsed as a
// lint pragma.)



// True dual-port packet RAM (M10K).  Port A = background FSM (writes the RX
// ring / reads the TX buffer); Port B = CPU data-port (reads the RX ring /
// writes the TX buffer during upload).  Independent ports let the Amiga PIO-read
// the ring while the bg fills it, with no single-port serialization, re-arm, or
// deadlock.  The bg (port A) and CPU (port B) target different ring regions
// concurrently (bg at CURR, CPU behind BNRY; bg RX pages vs CPU TX pages), so
// same-address simultaneous writes don't occur in normal operation.
module ne2000_packet_ram (
    input  wire        clk,
    // Port A -- background FSM
    input  wire [12:0] addr_a,
    input  wire        wren_a,
    input  wire [1:0]  byteena_a,
    input  wire [15:0] wdata_a,
    output reg  [15:0] q_a,
    // Port B -- CPU data-port
    input  wire [12:0] addr_b,
    input  wire        wren_b,
    input  wire [1:0]  byteena_b,
    input  wire [15:0] wdata_b,
    output reg  [15:0] q_b
);
    // Per-byte-lane true-dual-port inference (the proven dpram_be pattern): each
    // 8-bit lane gets its own port-A and port-B always block so Quartus maps it
    // to a true-dual-port M10K.  no_rw_check = read-during-write to the same
    // address is don't-care (the bg and CPU access different ring regions).
    (* ramstyle = "no_rw_check, M10K" *) reg [7:0] mem_l [0:8191];
    (* ramstyle = "no_rw_check, M10K" *) reg [7:0] mem_u [0:8191];

    // Low byte
    always @(posedge clk) begin
        if (wren_a & byteena_a[0]) mem_l[addr_a] <= wdata_a[7:0];
        q_a[7:0] <= mem_l[addr_a];
    end
    always @(posedge clk) begin
        if (wren_b & byteena_b[0]) mem_l[addr_b] <= wdata_b[7:0];
        q_b[7:0] <= mem_l[addr_b];
    end
    // High byte
    always @(posedge clk) begin
        if (wren_a & byteena_a[1]) mem_u[addr_a] <= wdata_a[15:8];
        q_a[15:8] <= mem_u[addr_a];
    end
    always @(posedge clk) begin
        if (wren_b & byteena_b[1]) mem_u[addr_b] <= wdata_b[15:8];
        q_b[15:8] <= mem_u[addr_b];
    end
endmodule
