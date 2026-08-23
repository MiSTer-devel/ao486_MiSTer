// ne2000_issp.v -- Altera in-system-probe debug stub, extracted from Minimig
// ethernet.v.  Instantiated only under `ifdef ETH_DEBUG_ISSP; NOT part of the
// default ao486 build.


/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
module ne2000_issp
#(
    parameter PROBE_WIDTH = 128,
    parameter SOURCE_WIDTH = 2,
    parameter INSTANCE_ID = "ETHDBG"
)
(
    input  wire                    clk,
    input  wire [PROBE_WIDTH-1:0]  probe,
    output wire [SOURCE_WIDTH-1:0] source
);

`ifdef ALTERA_RESERVED_QIS
    altsource_probe altsource_probe_component (
        .probe(probe),
        .source(source),
        .source_clk(clk),
        .source_ena(1'b1)
        // synopsys translate_off
        ,
        .clr(),
        .ena(),
        .ir_in(),
        .ir_out(),
        .jtag_state_cdr(),
        .jtag_state_cir(),
        .jtag_state_e1dr(),
        .jtag_state_sdr(),
        .jtag_state_tlr(),
        .jtag_state_udr(),
        .jtag_state_uir(),
        .raw_tck(),
        .tdi(),
        .tdo(),
        .usr1()
        // synopsys translate_on
    );
    defparam
        altsource_probe_component.enable_metastability = "NO",
        altsource_probe_component.instance_id = INSTANCE_ID,
        altsource_probe_component.probe_width = PROBE_WIDTH,
        altsource_probe_component.sld_auto_instance_index = "YES",
        altsource_probe_component.source_initial_value = "0",
        altsource_probe_component.source_width = SOURCE_WIDTH;
`elsif SYNTHESIS
    altsource_probe altsource_probe_component (
        .probe(probe),
        .source(source),
        .source_clk(clk),
        .source_ena(1'b1)
        // synopsys translate_off
        ,
        .clr(),
        .ena(),
        .ir_in(),
        .ir_out(),
        .jtag_state_cdr(),
        .jtag_state_cir(),
        .jtag_state_e1dr(),
        .jtag_state_sdr(),
        .jtag_state_tlr(),
        .jtag_state_udr(),
        .jtag_state_uir(),
        .raw_tck(),
        .tdi(),
        .tdo(),
        .usr1()
        // synopsys translate_on
    );
    defparam
        altsource_probe_component.enable_metastability = "NO",
        altsource_probe_component.instance_id = INSTANCE_ID,
        altsource_probe_component.probe_width = PROBE_WIDTH,
        altsource_probe_component.sld_auto_instance_index = "YES",
        altsource_probe_component.source_initial_value = "0",
        altsource_probe_component.source_width = SOURCE_WIDTH;
`else
    assign source = {SOURCE_WIDTH{1'b0}};
`endif

endmodule
