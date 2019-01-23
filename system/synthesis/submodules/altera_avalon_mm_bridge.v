// (C) 2001-2017 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel MegaCore Function License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// $Id: //acds/rel/17.0std/ip/merlin/altera_avalon_mm_bridge/altera_avalon_mm_bridge.v#1 $
// $Revision: #1 $
// $Date: 2017/01/22 $
// $Author: swbranch $
// --------------------------------------
// Avalon-MM pipeline bridge
//
// Optionally registers Avalon-MM command and response signals
// --------------------------------------

`timescale 1 ns / 1 ns
module altera_avalon_mm_bridge
#(
    parameter DATA_WIDTH           = 32,
    parameter SYMBOL_WIDTH         = 8,
    parameter RESPONSE_WIDTH       = 2,
    parameter HDL_ADDR_WIDTH       = 10,
    parameter BURSTCOUNT_WIDTH     = 1,

    parameter PIPELINE_COMMAND     = 1,
    parameter PIPELINE_RESPONSE    = 1,

    // --------------------------------------
    // Derived parameters
    // --------------------------------------
    parameter BYTEEN_WIDTH = DATA_WIDTH / SYMBOL_WIDTH
)
(
    input                         clk,
    input                         reset,

    output                        s0_waitrequest,
    output [DATA_WIDTH-1:0]       s0_readdata,
    output                        s0_readdatavalid,
    output [RESPONSE_WIDTH-1:0]   s0_response,
    input  [BURSTCOUNT_WIDTH-1:0] s0_burstcount,
    input  [DATA_WIDTH-1:0]       s0_writedata,
    input  [HDL_ADDR_WIDTH-1:0]   s0_address, 
    input                         s0_write, 
    input                         s0_read, 
    input  [BYTEEN_WIDTH-1:0]     s0_byteenable, 
    input                         s0_debugaccess,

    input                         m0_waitrequest,
    input  [DATA_WIDTH-1:0]       m0_readdata,
    input                         m0_readdatavalid,
    input  [RESPONSE_WIDTH-1:0]   m0_response,
    output [BURSTCOUNT_WIDTH-1:0] m0_burstcount,
    output [DATA_WIDTH-1:0]       m0_writedata,
    output [HDL_ADDR_WIDTH-1:0]   m0_address, 
    output                        m0_write, 
    output                        m0_read, 
    output [BYTEEN_WIDTH-1:0]     m0_byteenable,
    output                        m0_debugaccess
);
    // --------------------------------------
    // Registers & signals
    // --------------------------------------
    reg [BURSTCOUNT_WIDTH-1:0]   cmd_burstcount;
    reg [DATA_WIDTH-1:0]         cmd_writedata;
    reg [HDL_ADDR_WIDTH-1:0]     cmd_address; 
    reg                          cmd_write;  
    reg                          cmd_read;  
    reg [BYTEEN_WIDTH-1:0]       cmd_byteenable;
    wire                         cmd_waitrequest;
    reg                          cmd_debugaccess;

    reg [BURSTCOUNT_WIDTH-1:0]   wr_burstcount;
    reg [DATA_WIDTH-1:0]         wr_writedata;
    reg [HDL_ADDR_WIDTH-1:0]     wr_address; 
    reg                          wr_write;  
    reg                          wr_read;  
    reg [BYTEEN_WIDTH-1:0]       wr_byteenable;
    reg                          wr_debugaccess;

    reg [BURSTCOUNT_WIDTH-1:0]   wr_reg_burstcount;
    reg [DATA_WIDTH-1:0]         wr_reg_writedata;
    reg [HDL_ADDR_WIDTH-1:0]     wr_reg_address; 
    reg                          wr_reg_write;  
    reg                          wr_reg_read;  
    reg [BYTEEN_WIDTH-1:0]       wr_reg_byteenable;
    reg                          wr_reg_waitrequest;
    reg                          wr_reg_debugaccess;

    reg                          use_reg;
    wire                         wait_rise;

    reg [DATA_WIDTH-1:0]         rsp_readdata;
    reg                          rsp_readdatavalid;
    reg [RESPONSE_WIDTH-1:0]     rsp_response;   

    // --------------------------------------
    // Command pipeline
    //
    // Registers all command signals, including waitrequest
    // --------------------------------------
    generate if (PIPELINE_COMMAND == 1) begin

        // --------------------------------------
        // Waitrequest Pipeline Stage
        //
        // Output waitrequest is delayed by one cycle, which means
        // that a master will see waitrequest assertions one cycle 
        // too late.
        //
        // Solution: buffer the command when waitrequest transitions
        // from low->high. As an optimization, we can safely assume 
        // waitrequest is low by default because downstream logic
        // in the bridge ensures this.
        //
        // Note: this implementation buffers idle cycles should 
        // waitrequest transition on such cycles. This is a potential
        // cause for throughput loss, but ye olde pipeline bridge did
        // the same for years and no one complained. Not buffering idle
        // cycles costs logic on the waitrequest path.
        // --------------------------------------
        assign s0_waitrequest = wr_reg_waitrequest;
        assign wait_rise      = ~wr_reg_waitrequest & cmd_waitrequest;
     
        always @(posedge clk, posedge reset) begin
            if (reset) begin
                wr_reg_waitrequest <= 1'b1;
                // --------------------------------------
                // Bit of trickiness here, deserving of a long comment.
                //
                // On the first cycle after reset, the pass-through
                // must not be used or downstream logic may sample
                // the same command twice because of the delay in
                // transmitting a falling waitrequest.
                //
                // Using the registered command works on the condition
                // that downstream logic deasserts waitrequest
                // immediately after reset, which is true of the 
                // next stage in this bridge.
                // --------------------------------------
                use_reg            <= 1'b1;

                wr_reg_burstcount <= 1'b1;
                wr_reg_writedata  <= 0;
                wr_reg_byteenable <= {BYTEEN_WIDTH{1'b1}};
                wr_reg_address    <= 0;
                wr_reg_write      <= 1'b0;
                wr_reg_read       <= 1'b0;
                wr_reg_debugaccess <= 1'b0;
            end else begin
                wr_reg_waitrequest <= cmd_waitrequest;

                if (wait_rise) begin
                    wr_reg_writedata  <= s0_writedata;
                    wr_reg_byteenable <= s0_byteenable;
                    wr_reg_address    <= s0_address;
                    wr_reg_write      <= s0_write;
                    wr_reg_read       <= s0_read;
                    wr_reg_burstcount <= s0_burstcount;
                    wr_reg_debugaccess <= s0_debugaccess;
                end

                // stop using the buffer when waitrequest is low
                if (~cmd_waitrequest)
                     use_reg <= 1'b0;
                else if (wait_rise) begin
                    use_reg <= 1'b1;
                end     

            end
        end
     
        always @* begin
            wr_burstcount  =  s0_burstcount;
            wr_writedata   =  s0_writedata;
            wr_address     =  s0_address;
            wr_write       =  s0_write;
            wr_read        =  s0_read;
            wr_byteenable  =  s0_byteenable;
            wr_debugaccess =  s0_debugaccess;
     
            if (use_reg) begin
                wr_burstcount  =  wr_reg_burstcount;
                wr_writedata   =  wr_reg_writedata;
                wr_address     =  wr_reg_address;
                wr_write       =  wr_reg_write;
                wr_read        =  wr_reg_read;
                wr_byteenable  =  wr_reg_byteenable;
                wr_debugaccess =  wr_reg_debugaccess;
            end
        end
     
        // --------------------------------------
        // Master-Slave Signal Pipeline Stage 
        //
        // One notable detail is that cmd_waitrequest is deasserted
        // when this stage is idle. This allows us to make logic
        // optimizations in the waitrequest pipeline stage.
        // 
        // Also note that cmd_waitrequest is deasserted during reset,
        // which is not spec-compliant, but is ok for an internal
        // signal.
        // --------------------------------------
        wire no_command;
        assign no_command      = ~(cmd_read || cmd_write);
        assign cmd_waitrequest = m0_waitrequest & ~no_command;
     
        always @(posedge clk, posedge reset) begin
            if (reset) begin
                cmd_burstcount <= 1'b1;
                cmd_writedata  <= 0;
                cmd_byteenable <= {BYTEEN_WIDTH{1'b1}};
                cmd_address    <= 0;
                cmd_write      <= 1'b0;
                cmd_read       <= 1'b0;
                cmd_debugaccess <= 1'b0;
            end 
            else begin 
                if (~cmd_waitrequest) begin
                    cmd_writedata  <= wr_writedata;
                    cmd_byteenable <= wr_byteenable;
                    cmd_address    <= wr_address;
                    cmd_write      <= wr_write;
                    cmd_read       <= wr_read;
                    cmd_burstcount <= wr_burstcount;
                    cmd_debugaccess <= wr_debugaccess;
                end
            end
        end

    end  // conditional command pipeline
    else begin

        assign s0_waitrequest   = m0_waitrequest;

        always @* begin
            cmd_burstcount   = s0_burstcount;
            cmd_writedata    = s0_writedata;
            cmd_address      = s0_address;
            cmd_write        = s0_write;
            cmd_read         = s0_read;
            cmd_byteenable   = s0_byteenable;
            cmd_debugaccess  = s0_debugaccess;
        end

    end
    endgenerate

    assign m0_burstcount    = cmd_burstcount;
    assign m0_writedata     = cmd_writedata;
    assign m0_address       = cmd_address;
    assign m0_write         = cmd_write;
    assign m0_read          = cmd_read;
    assign m0_byteenable    = cmd_byteenable;
    assign m0_debugaccess   = cmd_debugaccess;

    // --------------------------------------
    // Response pipeline
    //
    // Registers all response signals
    // --------------------------------------
    generate if (PIPELINE_RESPONSE == 1) begin

        always @(posedge clk, posedge reset) begin
            if (reset) begin
                rsp_readdatavalid <= 1'b0;
                rsp_readdata      <= 0;
                rsp_response      <= 0;               
            end 
            else begin
                rsp_readdatavalid <= m0_readdatavalid;
                rsp_readdata      <= m0_readdata;
                rsp_response      <= m0_response;               
            end
        end

    end  // conditional response pipeline
    else begin

        always @* begin
            rsp_readdatavalid = m0_readdatavalid;
            rsp_readdata      = m0_readdata;
            rsp_response      = m0_response;           
        end
    end
    endgenerate

    assign s0_readdatavalid = rsp_readdatavalid;
    assign s0_readdata      = rsp_readdata;
    assign s0_response      = rsp_response;   

endmodule
