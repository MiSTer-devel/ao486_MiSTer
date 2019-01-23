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


//  This peripheral provides a direct windowing bridge function from its slave port
//  to its master port.  This allows the read/write transactions that appear at the
//  slave port to generate master transactions into a potentially much larger memory
//  map.  The mapping of the slave's window into the master's address map is provided
//  by one or more index registers, which are programmed thru the control slave
//  interface of this peripheral.  The slave port of this peripheral can provide
//  one or more sub-windows into the masters address map, each sub-window requires
//  its own index register to control the mapping of that sub-window into the master's
//  address map.
//
//  Two options added aug8_2012:
//  1) New parameter MASTER_ADDRESS_DEF specifies the reset default value for
//  window_index[0].  Default setting is 0, which is the same as the reset
//  value of the prior revision of this logic; users who switch to the current
//  rev should see no difference in operation.
//  2) New parameter in .tcl file allows disabling the slave control interface
//  entirely. Default setting is to enable the control interface, so again
//  users should see no difference in switching to this rev.
//  New feature allowed by these parameters is that the MASTER_ADDRESS_DEF
//  parameter can be set to define the mapping.  With the slave control
//  interface disabled, this provides a fixed mapping function for one window
//  only.
//
`timescale 1 ns / 1 ns

module altera_address_span_extender
    #(                                          // the parameterization requirements below is created and validated by the _hw.tcl script
        parameter DATA_WIDTH            = 32,   // valid widths 8, 16, 32, 64, 128, 256, 512, 1024
        parameter BYTEENABLE_WIDTH      = 4,    // valid widths DATA_WIDTH / 8
        parameter MASTER_ADDRESS_WIDTH  = 32,   // valid widths 32 or less until Qsys supports 64
        parameter SLAVE_ADDRESS_WIDTH   = 16,   // valid widths < ( MASTER_ADDRESS_WIDTH - SLAVE_ADDRESS_SHIFT ) )
        parameter SLAVE_ADDRESS_SHIFT   = 2,    // log2( BYTEENABLE_WIDTH )
        parameter BURSTCOUNT_WIDTH      = 1,    // valid widths < 32 , > 0
        parameter CNTL_ADDRESS_WIDTH    = 1,    // ( SUB_WINDOW_COUNT == 1 ) ? ( 1 ) : ( log2( SUB_WINDOW_COUNT ) )
        parameter SUB_WINDOW_COUNT      = 1,    // minimum count = 1 valid counts are 2^^N
        parameter MASTER_ADDRESS_DEF    = 64'h0 //reset value for window_index[0]
    )(
		input  wire                                      clk,                  // clock.clk
		input  wire                                      reset,                // reset.reset
        
		input  wire  [ ( SLAVE_ADDRESS_WIDTH - 1 ) : 0 ] avs_s0_address,       //    s0.address
		input  wire                                      avs_s0_read,          //      .read
		output wire           [ ( DATA_WIDTH - 1 ) : 0 ] avs_s0_readdata,      //      .readdata
		input  wire                                      avs_s0_write,         //      .write
		input  wire           [ ( DATA_WIDTH - 1 ) : 0 ] avs_s0_writedata,     //      .writedata
		output wire                                      avs_s0_readdatavalid, //      .readdatavalid
		output wire                                      avs_s0_waitrequest,   //      .waitrequest
		input  wire     [ ( BYTEENABLE_WIDTH - 1 ) : 0 ] avs_s0_byteenable,    //      .byteenable
		input  wire     [ ( BURSTCOUNT_WIDTH - 1 ) : 0 ] avs_s0_burstcount,    //      .burstcount
		
        output wire [ ( MASTER_ADDRESS_WIDTH - 1 ) : 0 ] avm_m0_address,       //    m0.address
		output wire                                      avm_m0_read,          //      .read
		input  wire                                      avm_m0_waitrequest,   //      .waitrequest
		input  wire           [ ( DATA_WIDTH - 1 ) : 0 ] avm_m0_readdata,      //      .readdata
		output wire                                      avm_m0_write,         //      .write
		output wire           [ ( DATA_WIDTH - 1 ) : 0 ] avm_m0_writedata,     //      .writedata
		input  wire                                      avm_m0_readdatavalid, //      .readdatavalid
		output wire     [ ( BYTEENABLE_WIDTH - 1 ) : 0 ] avm_m0_byteenable,    //      .byteenable
		output wire     [ ( BURSTCOUNT_WIDTH - 1 ) : 0 ] avm_m0_burstcount,    //      .burstcount

       	input  wire   [ ( CNTL_ADDRESS_WIDTH - 1 ) : 0 ] avs_cntl_address,     //  cntl.address
		input  wire                                      avs_cntl_read,        //      .read
		output wire                           [ 63 : 0 ] avs_cntl_readdata,    //      .readdata
		input  wire                                      avs_cntl_write,       //      .write
		input  wire                           [ 63 : 0 ] avs_cntl_writedata,   //      .writedata
		input  wire                           [  7 : 0 ] avs_cntl_byteenable   //      .byteenable
    );

    reg [ 63 : 0 ] window_index [ ( SUB_WINDOW_COUNT - 1 ) : 0 ];
    reg [ 63 : 0 ] readdata_p1;

    wire [ ( CNTL_ADDRESS_WIDTH - 1 ) : 0 ] index_address;

    wire [ 63 : 0 ] master_address_mask;
    wire [ 63 : 0 ] slave_address_anti_mask;
    wire [ 63 : 0 ] window_byte_address_mask;
    
    //
    // create a bit mask of the valid bits that our master interface can address
    //
    assign master_address_mask = (( 64'd1 << MASTER_ADDRESS_WIDTH ) - 1 );
    
    //
    // create an inverted bit mask of the valid bits that are addressed by our slave
    //
    generate
        if( SUB_WINDOW_COUNT == 1 ) begin
        
            assign slave_address_anti_mask = ~(( 64'd1 << ( SLAVE_ADDRESS_WIDTH + SLAVE_ADDRESS_SHIFT ) ) - 1 );
            
        end else begin
        
            assign slave_address_anti_mask = ~(( 64'd1 << ( SLAVE_ADDRESS_WIDTH + SLAVE_ADDRESS_SHIFT - CNTL_ADDRESS_WIDTH ) ) - 1 );
            
        end
    endgenerate

    //
    // AND the two masks together to produce a bit mask of the valid bits in our index register
    // we use this mask whenever we read or write the index registers to allow Quartus to
    // optimize unrequired logic out of the peripheral.
    //
    assign window_byte_address_mask = master_address_mask & slave_address_anti_mask;
    
    //
    // reads of the control registers are pipelined thru readdata_p1
    //
    assign avs_cntl_readdata = readdata_p1;

    //
    // this logic reads our control registers
    //
    generate
        if( SUB_WINDOW_COUNT == 1 ) begin
            
            always @ ( posedge clk or posedge reset ) begin
                if( reset ) begin
                
                    readdata_p1 <= 64'd0;
                    
                end else begin
                    readdata_p1 <= window_index[ 0 ] & window_byte_address_mask[ 63 : 0 ];
                end
            end
            
        end else begin
        
            always @ ( posedge clk or posedge reset ) begin
                if( reset ) begin
                
                    readdata_p1 <= 64'd0;
                    
                end else begin
                    readdata_p1 <= window_index[ avs_cntl_address ] & window_byte_address_mask[ 63 : 0 ];
                end
            end
            
        end
    endgenerate
    
    //
    // this logic performs byte maskable writes our control registers
    //
    generate
        if( SUB_WINDOW_COUNT == 1 ) begin
        
            always @ ( posedge clk or posedge reset ) begin
                if( reset ) begin
                    
                    for( int i = 0 ; i < SUB_WINDOW_COUNT ; i++ ) begin

                        window_index[ i ] <= MASTER_ADDRESS_DEF;
                    end

                end else begin
                    if( avs_cntl_write ) begin
                        if( avs_cntl_byteenable[ 0 ] == 1'b1 ) begin
                            window_index[ 0 ][ 7 : 0 ] <= avs_cntl_writedata[ 7 : 0 ] & window_byte_address_mask[ 7 : 0 ];
                        end
                        if( avs_cntl_byteenable[ 1 ] == 1'b1 ) begin
                            window_index[ 0 ][ 15 : 8 ] <= avs_cntl_writedata[ 15 : 8 ] & window_byte_address_mask[ 15 : 8 ];
                        end
                        if( avs_cntl_byteenable[ 2 ] == 1'b1 ) begin
                            window_index[ 0 ][ 23 : 16 ] <= avs_cntl_writedata[ 23 : 16 ] & window_byte_address_mask[ 23 : 16 ];
                        end
                        if( avs_cntl_byteenable[ 3 ] == 1'b1 ) begin
                            window_index[ 0 ][ 31 : 24 ] <= avs_cntl_writedata[ 31 : 24 ] & window_byte_address_mask[ 31 : 24 ];
                        end
                        if( avs_cntl_byteenable[ 4 ] == 1'b1 ) begin
                            window_index[ 0 ][ 39 : 32 ] <= avs_cntl_writedata[ 39 : 32 ] & window_byte_address_mask[ 39 : 32 ];
                        end
                        if( avs_cntl_byteenable[ 5 ] == 1'b1 ) begin
                            window_index[ 0 ][ 47 : 40 ] <= avs_cntl_writedata[ 47 : 40 ] & window_byte_address_mask[ 47 : 40 ];
                        end
                        if( avs_cntl_byteenable[ 6 ] == 1'b1 ) begin
                            window_index[ 0 ][ 55 : 48 ] <= avs_cntl_writedata[ 55 : 48 ] & window_byte_address_mask[ 55 : 48 ];
                        end
                        if( avs_cntl_byteenable[ 7 ] == 1'b1 ) begin
                            window_index[ 0 ][ 63 : 56 ] <= avs_cntl_writedata[ 63 : 56 ] & window_byte_address_mask[ 63 : 56 ];
                        end
                    end
                end
            end
            
        end else begin
        
            always @ ( posedge clk or posedge reset ) begin
                if( reset ) begin
                
                    for( int i = 0 ; i < SUB_WINDOW_COUNT ; i++ ) begin

                        if (i==0) window_index[i] <= MASTER_ADDRESS_DEF;
                        else window_index[ i ] <= 64'd0;
                    end
                        
                end else begin
                    if( avs_cntl_write ) begin
                        if( avs_cntl_byteenable[ 0 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 7 : 0 ] <= avs_cntl_writedata[ 7 : 0 ] & window_byte_address_mask[ 7 : 0 ];
                        end
                        if( avs_cntl_byteenable[ 1 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 15 : 8 ] <= avs_cntl_writedata[ 15 : 8 ] & window_byte_address_mask[ 15 : 8 ];
                        end
                        if( avs_cntl_byteenable[ 2 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 23 : 16 ] <= avs_cntl_writedata[ 23 : 16 ] & window_byte_address_mask[ 23 : 16 ];
                        end
                        if( avs_cntl_byteenable[ 3 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 31 : 24 ] <= avs_cntl_writedata[ 31 : 24 ] & window_byte_address_mask[ 31 : 24 ];
                        end
                        if( avs_cntl_byteenable[ 4 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 39 : 32 ] <= avs_cntl_writedata[ 39 : 32 ] & window_byte_address_mask[ 39 : 32 ];
                        end
                        if( avs_cntl_byteenable[ 5 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 47 : 40 ] <= avs_cntl_writedata[ 47 : 40 ] & window_byte_address_mask[ 47 : 40 ];
                        end
                        if( avs_cntl_byteenable[ 6 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 55 : 48 ] <= avs_cntl_writedata[ 55 : 48 ] & window_byte_address_mask[ 55 : 48 ];
                        end
                        if( avs_cntl_byteenable[ 7 ] == 1'b1 ) begin
                            window_index[ avs_cntl_address ][ 63 : 56 ] <= avs_cntl_writedata[ 63 : 56 ] & window_byte_address_mask[ 63 : 56 ];
                        end
                    end
                end
            end
        end
    endgenerate

    //
    // this logic merges the slave base address with the window index to produce the master byte address output
    //
    generate
        if( SUB_WINDOW_COUNT == 1 ) begin
        
            assign avm_m0_address = ( window_index[ 0 ][ ( MASTER_ADDRESS_WIDTH - 1 ) : 0 ] & window_byte_address_mask[ ( MASTER_ADDRESS_WIDTH - 1 ) : 0 ] ) | { avs_s0_address[ ( SLAVE_ADDRESS_WIDTH - 1 ) : 0 ], { SLAVE_ADDRESS_SHIFT{ 1'b0 } } };
            
        end else begin
            
            assign index_address = avs_s0_address[ ( SLAVE_ADDRESS_WIDTH - 1 ) : ( SLAVE_ADDRESS_WIDTH - CNTL_ADDRESS_WIDTH ) ];
            assign avm_m0_address = ( window_index[ index_address ][ ( MASTER_ADDRESS_WIDTH - 1 ) : 0 ] & window_byte_address_mask[ ( MASTER_ADDRESS_WIDTH - 1 ) : 0 ] ) | { avs_s0_address[ ( SLAVE_ADDRESS_WIDTH - CNTL_ADDRESS_WIDTH - 1 ) : 0 ], { SLAVE_ADDRESS_SHIFT{ 1'b0 } } };
            
        end
    endgenerate

    //
    // all other signals pass straight thru form the slave to the master
    //
	assign avs_s0_waitrequest = avm_m0_waitrequest;

	assign avs_s0_readdata = avm_m0_readdata;

	assign avs_s0_readdatavalid = avm_m0_readdatavalid;

	assign avm_m0_burstcount = avs_s0_burstcount;

	assign avm_m0_writedata = avs_s0_writedata;

	assign avm_m0_write = avs_s0_write;

	assign avm_m0_read = avs_s0_read;

	assign avm_m0_byteenable = avs_s0_byteenable;

endmodule
