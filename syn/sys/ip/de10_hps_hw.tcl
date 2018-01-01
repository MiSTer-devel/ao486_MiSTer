# (C) 2001-2017 Intel Corporation. All rights reserved.
# Your use of Intel Corporation's design tools, logic functions and other 
# software and tools, and its AMPP partner logic functions, and any output 
# files any of the foregoing (including device programming or simulation 
# files), and any associated documentation or information are expressly subject 
# to the terms and conditions of the Intel Program License Subscription 
# Agreement, Intel MegaCore Function License Agreement, or other applicable 
# license agreement, including, without limitation, that your use is for the 
# sole purpose of programming logic devices manufactured by Intel and sold by 
# Intel or its authorized distributors.  Please refer to the applicable 
# agreement for further details.


# This IP is modified standard Altera HPS IP.
# Direct DDR3 SDRAM access has been removed since it won't work together with HPS DDR3 SDRAM access.
# FPGA access the memory through MPFE (FPGA2SDRAM bridge).
# By removing direct DDR3 SDRAM access synthesis time has been reduced by 3 times!


package require -exact qsys 12.0
package require -exact altera_terp 1.0
package require quartus::advanced_wysiwyg

set_module_property NAME altera_hps_lite
set_module_property VERSION 17.0
set_module_property AUTHOR "Altera Corporation/Sorgelig"                
set_module_property SUPPORTED_DEVICE_FAMILIES {CYCLONEV ARRIAV}

set_module_property DISPLAY_NAME "DE10-nano Hard Processor System"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true

add_documentation_link "HPS User Guide for Cyclone V" "http://www.altera.com/literature/hb/cyclone-v/cv_5v4.pdf"
add_documentation_link "HPS User Guide for Arria V"   "http://www.altera.com/literature/hb/arria-v/av_5v4.pdf"

set alt_mem_if_tcl_libs_dir "$env(QUARTUS_ROOTDIR)/../ip/altera/alt_mem_if/alt_mem_if_tcl_packages"
if {[lsearch -exact $auto_path $alt_mem_if_tcl_libs_dir] == -1} {                                                                                           
	lappend auto_path $alt_mem_if_tcl_libs_dir
} 

package require alt_mem_if::gui::system_info

source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/util/constants.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/util/procedures.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/util/pin_mux.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/util/pin_mux_db.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/util/locations.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/util/ui.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/clocks.tcl
source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/clock_manager.tcl

proc add_storage_parameter {name { default_value {} } } {
    add_parameter $name string $default_value ""
    set_parameter_property $name derived true
    set_parameter_property $name visible false   
}

proc add_reset_parameters {} {
    set group_name "Resets"
    add_display_item "FPGA Interfaces" $group_name "group" ""

    add_parameter           S2FCLK_COLDRST_Enable boolean false ""
    set_parameter_property  S2FCLK_COLDRST_Enable display_name "Enable HPS-to-FPGA cold reset output"
    set_parameter_property  S2FCLK_COLDRST_Enable group $group_name
    
    add_parameter           S2FCLK_PENDINGRST_Enable boolean false ""
    set_parameter_property  S2FCLK_PENDINGRST_Enable display_name "Enable HPS warm reset handshake signals"
    set_parameter_property  S2FCLK_PENDINGRST_Enable group $group_name

    add_parameter           F2SCLK_DBGRST_Enable boolean false ""
    set_parameter_property  F2SCLK_DBGRST_Enable display_name "Enable FPGA-to-HPS debug reset request"
    set_parameter_property  F2SCLK_DBGRST_Enable group $group_name
    
    add_parameter           F2SCLK_WARMRST_Enable boolean false ""
    set_parameter_property  F2SCLK_WARMRST_Enable display_name "Enable FPGA-to-HPS warm reset request"
    set_parameter_property  F2SCLK_WARMRST_Enable group $group_name
    
    add_parameter           F2SCLK_COLDRST_Enable boolean false ""
    set_parameter_property  F2SCLK_COLDRST_Enable display_name "Enable FPGA-to-HPS cold reset request"
    set_parameter_property  F2SCLK_COLDRST_Enable group $group_name

}

proc list_h2f_interrupt_groups {} {
    return {
	"CAN"      "CLOCKPERIPHERAL" "CTI"
	"DMA"      "EMAC"            "FPGAMANAGER" 
	"GPIO"     "I2CEMAC"         "I2CPERIPHERAL"
	"L4TIMER"  "NAND"            "OSCTIMER"
	"QSPI"     "SDMMC"           "SPIMASTER"
	"SPISLAVE" "UART" 	     "USB"
	"WATCHDOG"       
    }
}

proc get_h2f_interrupt_descriptions {data_ref} {
    upvar 1 $data_ref data
    array set data {
	"DMA"             "Enable DMA interrupts"
	"EMAC"            "Enable EMAC interrupts (for EMAC0 and EMAC1)"
	"USB"             "Enable USB interrupts"
	"CAN"             "Enable CAN interrupts"
	"SDMMC"           "Enable SD/MMC interrupt"
	"NAND"		  "Enable NAND interrupt"
	"QSPI"		  "Enable Quad SPI interrupt"
	"SPIMASTER"	  "Enable SPI master interrupts"
	"SPISLAVE"	  "Enable SPI slave interrupts"
	"I2CPERIPHERAL"   "Enable I2C peripheral interrupts (for I2C0 and I2C1)"
	"I2CEMAC"	  "Enable I2C-EMAC interrupts (for I2C2 and I2C3)"
	"UART" 		  "Enable UART interrupts"
	"GPIO"		  "Enable GPIO interrupts"
	"L4TIMER"	  "Enable L4 timer interrupts"
	"OSCTIMER"	  "Enable OSC timer interrupts"
	"WATCHDOG"	  "Enable watchdog interrupts"
	"CLOCKPERIPHERAL" "Enable clock peripheral interrupts"
	"FPGAMANAGER" 	  "Enable FPGA manager interrupt"
	"CTI"             "Enable CTI interrupts"
    }
}

proc load_h2f_interrupt_table {functions_by_group_ref
			       width_by_function_ref
			       inverted_by_function_ref} {
    upvar 1 $functions_by_group_ref   functions_by_group
    upvar 1 $width_by_function_ref    width_by_function
    upvar 1 $inverted_by_function_ref inverted_by_function
    array set functions_by_group {
 	"DMA"             {"dma"       "dma_abort"        }
	"EMAC"            {"emac0"     "emac1"            }
	"USB"             {"usb0"      "usb1"             }
	"CAN"             {"can0"      "can1"             }
	"SDMMC"           {"sdmmc"                        }
	"NAND"		  {"nand"                         }
	"QSPI"		  {"qspi"                         }
	"SPIMASTER"	  {"spi0"      "spi1"             }
	"SPISLAVE"	  {"spi2"      "spi3"             }
	"I2CPERIPHERAL"   {"i2c0"      "i2c1"             }
	"I2CEMAC"	  {"i2c_emac0" "i2c_emac1"        }
	"UART" 		  {"uart0"     "uart1"            }
	"GPIO"		  {"gpio0"     "gpio1"     "gpio2"}
	"L4TIMER"	  {"l4sp0"     "l4sp1"            }
	"OSCTIMER"	  {"osc0"      "osc1"             }
	"WATCHDOG"	  {"wdog0"     "wdog1"            }
	"CLOCKPERIPHERAL" {"clkmgr"    "mpuwakeup"        }
	"FPGAMANAGER" 	  {"fpga_man"                     }
	"CTI"             {"cti"                          }
    }
    array set width_by_function {
	"dma"        8
	"cti"        2
    }
    array set inverted_by_function {
	"cti" 1
    }
}

proc add_interrupt_parameters {} {
    set top_group_name "Interrupts"
    add_display_item "FPGA Interfaces" $top_group_name "group" ""
    
    #    add_display_item $group_name "f2h_interrupts_label" "text" "FPGA-to-HPS"
    add_parameter            F2SINTERRUPT_Enable   boolean        false
    set_parameter_property   F2SINTERRUPT_Enable   enabled        true
    set_parameter_property   F2SINTERRUPT_Enable   display_name   "Enable FPGA-to-HPS Interrupts"
    set_parameter_property   F2SINTERRUPT_Enable   group          $top_group_name 
    
    set inner_group_name "HPS-to-FPGA"
    add_display_item $top_group_name $inner_group_name "group" ""
    get_h2f_interrupt_descriptions descriptions_by_group
    set interrupt_groups [list_h2f_interrupt_groups]
    foreach interrupt_group $interrupt_groups {
	set parameter "S2FINTERRUPT_${interrupt_group}_Enable"
	add_parameter          $parameter boolean      false
	set_parameter_property $parameter enabled      true
	set_parameter_property $parameter display_name $descriptions_by_group($interrupt_group)
	set_parameter_property $parameter group        $inner_group_name
    }
}

proc add_dma_parameters {} {
    set group_name "DMA Peripheral Request"
    add_display_item "FPGA Interfaces" $group_name "group" ""
    add_display_item $group_name "DMA Table" "group" "table"

    add_parameter           DMA_PeriphId_DERIVED string_list {0 1 2 3 4 5 6 7}
    set_parameter_property  DMA_PeriphId_DERIVED display_name "Peripheral Request ID"
    set_parameter_property  DMA_PeriphId_DERIVED derived true
    set_parameter_property  DMA_PeriphId_DERIVED display_hint "FIXED_SIZE"
    set_parameter_property  DMA_PeriphId_DERIVED group "DMA Table"
 
    add_parameter           DMA_Enable string_list {"No" "No" "No" "No" "No" "No" "No" "No"}
    set_parameter_property  DMA_Enable allowed_ranges {"Yes" "No"}
    set_parameter_property  DMA_Enable display_name "Enabled"
    set_parameter_property  DMA_Enable display_hint "FIXED_SIZE"
    set_parameter_property  DMA_Enable group "DMA Table"
}
                                                     
proc range_from_zero {end} {
    set result [list]
    for {set i 0} {$i <= $end} {incr i} {
	lappend result $i
    }
    return $result
}

proc create_generic_parameters {} {
	
	::alt_mem_if::util::hwtcl_utils::_add_parameter SYS_INFO_DEVICE_FAMILY STRING "" 
	set_parameter_property SYS_INFO_DEVICE_FAMILY SYSTEM_INFO DEVICE_FAMILY
	set_parameter_property SYS_INFO_DEVICE_FAMILY VISIBLE FALSE
	
	::alt_mem_if::util::hwtcl_utils::_add_parameter DEVICE_FAMILY STRING "" 
	set_parameter_property DEVICE_FAMILY DERIVED true
	set_parameter_property DEVICE_FAMILY VISIBLE FALSE

	return 1
}

create_generic_parameters

add_display_item "" "FPGA Interfaces"  "group" "tab"   
add_display_item "" "Peripheral Pins"    "group" "tab"                        
add_display_item "" "HPS Clocks" "group" "tab" 
add_clock_tab "HPS Clocks"

add_display_item "FPGA Interfaces" "General"          "group" ""
                                                                  
add_parameter            MPU_EVENTS_Enable  boolean        true
set_parameter_property   MPU_EVENTS_Enable  display_name   "Enable MPU standby and event signals"
set_parameter_property   MPU_EVENTS_Enable  description    "Enables elaboration of the mpu_events interface."
set_parameter_property   MPU_EVENTS_Enable  group          "General"

add_parameter            GP_Enable   boolean        false
set_parameter_property   GP_Enable   display_name   "Enable general purpose signals"
set_parameter_property   GP_Enable   description    "Enables elaboration of interface h2f_gp."
set_parameter_property   GP_Enable   group          "General"

add_parameter            DEBUGAPB_Enable  boolean       false
set_parameter_property   DEBUGAPB_Enable  display_name  "Enable Debug APB interface"
set_parameter_property   DEBUGAPB_Enable  description   "Enables elaboration of Debug APB interfaces."
set_parameter_property   DEBUGAPB_Enable  group         "General"

add_parameter            STM_Enable   boolean        false
set_parameter_property   STM_Enable   display_name   "Enable System Trace Macrocell hardware events"
set_parameter_property   STM_Enable   description    "Enables elaboration of interface stm_hwevents."
set_parameter_property   STM_Enable   group          "General"

add_parameter            CTI_Enable   boolean        false
set_parameter_property   CTI_Enable   display_name   "Enable FPGA Cross Trigger Interface"
set_parameter_property   CTI_Enable   description    "Enables elaboration of interface cti_trigger, cti_clk_in."
set_parameter_property   CTI_Enable   group          "General"

add_parameter            TPIUFPGA_Enable   boolean        false
set_parameter_property   TPIUFPGA_Enable   display_name   "Enable FPGA Trace Port Interface Unit"
set_parameter_property   TPIUFPGA_Enable   description    "Enables elaboration of TPIU FPGA interfaces."
set_parameter_property   TPIUFPGA_Enable   group          "General"

add_parameter            TPIUFPGA_alt   boolean        false
set_parameter_property   TPIUFPGA_alt   display_name   "Enable FPGA Trace Port Alternate FPGA Interface"
set_parameter_property   TPIUFPGA_alt   description    "When the trace port is enabled, it creates an interface compatible with the Arria 10 Trace Interface. (This just moves the clock_in port into the same conduit)"
set_parameter_property   TPIUFPGA_alt   group          "General"
set_parameter_property   TPIUFPGA_alt   enabled        false


add_parameter            BOOTFROMFPGA_Enable   boolean        false
set_parameter_property   BOOTFROMFPGA_Enable   enabled        true
set_parameter_property   BOOTFROMFPGA_Enable   display_name   "Enable boot from fpga signals"
set_parameter_property   BOOTFROMFPGA_Enable   description    "Enables elaboration of interface boot_from_fpga."
set_parameter_property   BOOTFROMFPGA_Enable   group          "General"

add_parameter            TEST_Enable  boolean        false
set_parameter_property   TEST_Enable  enabled        true
set_parameter_property   TEST_Enable  display_name   "Enable Test Interface"
set_parameter_property   TEST_Enable  group          "General"

add_parameter            HLGPI_Enable  boolean        false
set_parameter_property   HLGPI_Enable  enabled        true
set_parameter_property   HLGPI_Enable  display_name   "Enable HLGPI Interface"
set_parameter_property   HLGPI_Enable  group          "General"

add_display_item "FPGA Interfaces" "Boot and Clock Selection" "group" ""
add_parameter            BSEL_EN      boolean        false
set_parameter_property   BSEL_EN      enabled        true
set_parameter_property   BSEL_EN      display_name   "Enable boot selection from FPGA"
set_parameter_property   BSEL_EN      group          "Boot and Clock Selection"
set_parameter_property   BSEL_EN      visible        false
set_parameter_property   BSEL_EN      enabled        false

add_parameter            BSEL         integer 1
set_parameter_property   BSEL         allowed_ranges {"1:FPGA" "2:NAND Flash (1.8v)" "3:NAND Flash (3.0v)" "4:SD/MMC External Transceiver (1.8v)" "5:SD/MMC Internal Transceiver (3.0v)" "6:Quad SPI Flash (1.8v)" "7:Quad SPI Flash (3.0v)"}
set_parameter_property   BSEL         display_name   "Boot selection from FPGA"
set_parameter_property   BSEL         group          "Boot and Clock Selection"
set_parameter_property   BSEL         visible        false
set_parameter_property   BSEL         enabled        false

add_parameter            CSEL_EN      boolean        false
set_parameter_property   CSEL_EN      enabled        true
set_parameter_property   CSEL_EN      display_name   "Enable clock selection from FPGA"
set_parameter_property   CSEL_EN      group          "Boot and Clock Selection"
set_parameter_property   CSEL_EN      visible        false
set_parameter_property   CSEL_EN      enabled        false

add_parameter            CSEL         integer 0
set_parameter_property   CSEL         allowed_ranges {"0:CSEL_0" "1:CSEL_1" "2:CSEL_2" "3:CSEL_3"}
set_parameter_property   CSEL         display_name   "Clock selection from FPGA"
set_parameter_property   CSEL         group          "Boot and Clock Selection"
set_parameter_property   CSEL         visible        false
set_parameter_property   CSEL         enabled        false

add_display_item "FPGA Interfaces"   "AXI Bridges" "group" ""
add_parameter            F2S_Width  integer 2
set_parameter_property   F2S_Width  allowed_ranges {"0:Unused" "1:32-bit" "2:64-bit" "3:128-bit"}
set_parameter_property   F2S_Width  display_name   "FPGA-to-HPS interface width"
set_parameter_property   F2S_Width  hdl_parameter  true
set_parameter_property   F2S_Width  group          "AXI Bridges"

add_parameter            S2F_Width  integer 2
set_parameter_property   S2F_Width  allowed_ranges {"0:Unused" "1:32-bit" "2:64-bit" "3:128-bit"}
set_parameter_property   S2F_Width  display_name   "HPS-to-FPGA interface width"
set_parameter_property   S2F_Width  hdl_parameter  true
set_parameter_property   S2F_Width  group          "AXI Bridges"

add_parameter            LWH2F_Enable string true
set_parameter_property   LWH2F_Enable display_name "Lightweight HPS-to-FPGA interface width"
set_parameter_property   LWH2F_Enable description  "The lightweight HPS-to-FPGA bridge provides a secondary, fixed-width, smaller address space, lower-performance master interface to the FPGA fabric. Use the lightweight HPS-to-FPGA bridge for high-latency, low-bandwidth traffic, such as memory-mapped register accesses of FPGA peripherals. This approach diverts traffic from the high-performance HPS-to-FPGA bridge, which can improve overall performance."
set_parameter_property   LWH2F_Enable allowed_ranges {"true:32-bit" "false:Unused"}
set_parameter_property   LWH2F_Enable group "AXI Bridges"


set group_name "FPGA-to-HPS SDRAM Interface"
add_display_item "FPGA Interfaces" $group_name "group" ""
add_display_item $group_name "f2sdram_label" "text" "Click the '+' and '-' buttons to add and remove FPGA-to-HPS SDRAM ports."
set table_name "F2SDRAM Settings"
add_display_item $group_name $table_name "group" "table"

add_parameter            F2SDRAM_Name_DERIVED   string_list   {"f2h_sdram0"}
set_parameter_property   F2SDRAM_Name_DERIVED   derived       true
set_parameter_property   F2SDRAM_Name_DERIVED   display_name  "Name"
set_parameter_property   F2SDRAM_Name_DERIVED   group         $table_name

add_parameter            F2SDRAM_Type   string_list  [list [F2HSDRAM_AXI3]]
set_parameter_property   F2SDRAM_Type   allowed_ranges [list [F2HSDRAM_AXI3] [F2HSDRAM_AVM] [F2HSDRAM_AVM_WRITEONLY] [F2HSDRAM_AVM_READONLY]]
set_parameter_property   F2SDRAM_Type   display_name   "Type"
set_parameter_property   F2SDRAM_Type   group          $table_name

add_parameter                 F2SDRAM_Width   integer_list   {"64"}
set_parameter_property        F2SDRAM_Width   allowed_ranges "32,64,128,256"
set_parameter_property        F2SDRAM_Width   display_name   "Width"
set_parameter_property        F2SDRAM_Width   group          $table_name
set_parameter_update_callback F2SDRAM_Width on_altered_f2sdram_width
# TODO: f2sdram derived parameters for resource counts in the table
# TODO: f2sdram derived parameters for remaining resources, not a part of the table

add_storage_parameter  F2SDRAM_Width_Last_Size 1
add_storage_parameter  F2SDRAM_CMD_PORT_USED 0
add_storage_parameter  F2SDRAM_WR_PORT_USED 0
add_storage_parameter  F2SDRAM_RD_PORT_USED 0
add_storage_parameter  F2SDRAM_RST_PORT_USED 0
set_parameter_property F2SDRAM_Width_Last_Size group $group_name
set_parameter_property F2SDRAM_CMD_PORT_USED   group $group_name
set_parameter_property F2SDRAM_WR_PORT_USED    group $group_name
set_parameter_property F2SDRAM_RD_PORT_USED    group $group_name
set_parameter_property F2SDRAM_RST_PORT_USED    group $group_name

#Parameter to export Bonding_out signal from fpga2sdram Atom 
add_parameter		BONDING_OUT_ENABLED	boolean		false
set_parameter_property	BONDING_OUT_ENABLED	display_name	"Enable BONDING-OUT signals"
set_parameter_property	BONDING_OUT_ENABLED	group		$group_name
set_parameter_property	BONDING_OUT_ENABLED	enabled		false
set_parameter_property	BONDING_OUT_ENABLED	visible		false


proc on_altered_f2sdram_width { param } {
    set old_size [get_parameter_value F2SDRAM_Width_Last_Size]
    set current_value [get_parameter_value F2SDRAM_Width]
    set current_size  [llength $current_value]
    
    if {$current_size == $old_size + 1} { ;# look for case of newly added row
	set last_element_index [expr {$current_size - 1}]
	set new_value [lreplace $current_value $last_element_index $last_element_index "64"]
	set_parameter_value F2SDRAM_Width $new_value
    }
}

add_reset_parameters

add_dma_parameters

add_interrupt_parameters

    set group_name "EMAC ptp interface"
    add_display_item "FPGA Interfaces" $group_name     "group" ""

    add_parameter            EMAC0_PTP  boolean        false
    set_parameter_property   EMAC0_PTP  display_name   "Enable EMAC0 Precision Time Protocol (PTP) FPGA Interface"
    set_parameter_property   EMAC0_PTP  hdl_parameter  false
    set_parameter_property   EMAC0_PTP  enabled        false
    set_parameter_property   EMAC0_PTP  group          $group_name
    set_parameter_property   EMAC0_PTP  description    "When the EMAC is connected to the HPS IO via the Pinmux, the IEEE 1588 Precision Time Protocol (PTP) interface can be accessed through the FPGA. When the EMAC connects to the FPGA, the PTP signals are always available."

    add_parameter            EMAC1_PTP  boolean        false
    set_parameter_property   EMAC1_PTP  display_name   "Enable EMAC1 Precision Time Protocol (PTP) FPGA Interface"
    set_parameter_property   EMAC1_PTP  hdl_parameter  false
    set_parameter_property   EMAC1_PTP  enabled        false
    set_parameter_property   EMAC1_PTP  group          $group_name
    set_parameter_property   EMAC1_PTP  description    "When the EMAC is connected to the HPS IO via the Pinmux, the IEEE 1588 Precision Time Protocol (PTP) interface can be accessed through the FPGA. When the EMAC connects to the FPGA, the PTP signals are always available."


proc make_mode_display_name {peripheral} {
    set default_suffix "mode"
    array set custom_suffix_by_peripheral {
	USB0 "PHY interface mode"
	USB1 "PHY interface mode"
    }
    if {[info exists custom_suffix_by_peripheral($peripheral)]} {
	set suffix $custom_suffix_by_peripheral($peripheral)
    } else {
	set suffix $default_suffix
    }
    
    set display_name "${peripheral} ${suffix}"
    return $display_name
}

proc add_peripheral_pin_muxing_parameters {} {
    set TOP_LEVEL_GROUP_NAME "Peripheral Pins"    
                                                                     
    
    foreach group_name [list_group_names] {
	add_display_item $TOP_LEVEL_GROUP_NAME $group_name "group" ""
	
	foreach peripheral_name [peripherals_in_group $group_name] {
	    set pin_muxing_param_name "${peripheral_name}_PinMuxing"
	    set mode_param_name       "${peripheral_name}_Mode"             
	    add_parameter                 $pin_muxing_param_name  string [UNUSED_MUX_VALUE]
	    set_parameter_property        $pin_muxing_param_name  enabled          false
	    set_parameter_property        $pin_muxing_param_name  display_name     "${peripheral_name} pin"
	    set_parameter_property        $pin_muxing_param_name  allowed_ranges   [UNUSED_MUX_VALUE]
	    set_parameter_property        $pin_muxing_param_name  group            $group_name
	    set_parameter_update_callback $pin_muxing_param_name  on_altered_peripheral_pin_muxing $peripheral_name
	    
	    set mode_display_name [make_mode_display_name $peripheral_name]
	    add_parameter            $mode_param_name        string [NA_MODE_VALUE]
	    set_parameter_property   $mode_param_name        enabled          false
	    set_parameter_property   $mode_param_name        display_name     $mode_display_name
	    set_parameter_property   $mode_param_name        allowed_ranges   [NA_MODE_VALUE]
	    set_parameter_property   $mode_param_name        group            $group_name

	    if {[string match "*EMAC*" $peripheral_name]} {
		set_parameter_update_callback $mode_param_name on_emac_mode_switch_internal $peripheral_name
	    }
	}
    }
}
add_peripheral_pin_muxing_parameters

proc add_gpio_parameters {} {
    set TOP_LEVEL_GROUP_NAME "Peripheral Pins"
    set group_name "Peripherals Mux Table"
    set table_name "Conflict Table"
    
    add_display_item $TOP_LEVEL_GROUP_NAME $group_name "group" ""
    #add_display_item $group_name $table_name "group" "table"

    add_parameter           Customer_Pin_Name_DERIVED  string_list {}
    set_parameter_property  Customer_Pin_Name_DERIVED  display_name "Pin Name"
    set_parameter_property  Customer_Pin_Name_DERIVED  derived true
    set_parameter_property  Customer_Pin_Name_DERIVED  display_hint "FIXED_SIZE"
    set_parameter_property Customer_Pin_Name_DERIVED visible false
   # set_parameter_property  Customer_Pin_Name_DERIVED  group $table_name 
       
    add_parameter           GPIO_Conflict_DERIVED string_list {}
    set_parameter_property  GPIO_Conflict_DERIVED display_name "Used by"
    set_parameter_property  GPIO_Conflict_DERIVED derived true
    set_parameter_property  GPIO_Conflict_DERIVED display_hint "FIXED_SIZE"
    set_parameter_property GPIO_Conflict_DERIVED visible false
    #set_parameter_property  GPIO_Conflict_DERIVED group $table_name

    add_parameter           GPIO_Name_DERIVED string_list {}
    set_parameter_property  GPIO_Name_DERIVED display_name "GPIO"
    set_parameter_property  GPIO_Name_DERIVED derived true
    set_parameter_property  GPIO_Name_DERIVED display_hint "FIXED_SIZE"
     set_parameter_property GPIO_Name_DERIVED visible false
    #set_parameter_property  GPIO_Name_DERIVED group $table_name
    
    # TODO: change?
    set max_possible_gpio_options 100
    set enable_list [list]
    for {set i 0} {$i < $max_possible_gpio_options} {incr i} {
	lappend enable_list "No"
    }
 
    add_parameter           GPIO_Enable string_list $enable_list
    set_parameter_property  GPIO_Enable allowed_ranges {"Yes" "No"}
    set_parameter_property  GPIO_Enable display_name "GPIO Enabled"
       set_parameter_property GPIO_Enable visible false
  #  set_parameter_property  GPIO_Enable group $table_name

    add_parameter           LOANIO_Name_DERIVED string_list {}
    set_parameter_property  LOANIO_Name_DERIVED display_name "Loan I/O"
    set_parameter_property  LOANIO_Name_DERIVED derived true
    set_parameter_property  LOANIO_Name_DERIVED display_hint "FIXED_SIZE"
    set_parameter_property LOANIO_Name_DERIVED visible false  

    add_parameter           GPIO_Pin_Used_DERIVED boolean false
    set_parameter_property  GPIO_Pin_Used_DERIVED display_name "GPIO Pin Used"
    set_parameter_property  GPIO_Pin_Used_DERIVED derived true
    set_parameter_property  GPIO_Pin_Used_DERIVED display_hint "GPIO Pin Used"
    set_parameter_property  GPIO_Pin_Used_DERIVED visible false

    add_parameter           LOANIO_Enable string_list $enable_list
    set_parameter_property  LOANIO_Enable allowed_ranges {"Yes" "No"}
    set_parameter_property  LOANIO_Enable display_name "Loan I/O Enabled"
    set_parameter_property LOANIO_Enable visible false
    #set_parameter_property  LOANIO_Enable group $table_name

    

}
add_gpio_parameters

proc add_reset_parameters {} {
    set group_name "Resets"
    add_display_item "FPGA Interfaces" $group_name "group" ""

    add_parameter           S2FCLK_COLDRST_Enable boolean false ""
    set_parameter_property  S2FCLK_COLDRST_Enable display_name "Enable HPS-to-FPGA cold reset output"
    set_parameter_property  S2FCLK_COLDRST_Enable group $group_name
    
    add_parameter           S2FCLK_PENDINGRST_Enable boolean false ""
    set_parameter_property  S2FCLK_PENDINGRST_Enable display_name "Enable HPS warm reset handshake signals"
    set_parameter_property  S2FCLK_PENDINGRST_Enable group $group_name

    add_parameter           F2SCLK_DBGRST_Enable boolean false ""
    set_parameter_property  F2SCLK_DBGRST_Enable display_name "Enable FPGA-to-HPS debug reset request"
    set_parameter_property  F2SCLK_DBGRST_Enable group $group_name
    
    add_parameter           F2SCLK_WARMRST_Enable boolean false ""
    set_parameter_property  F2SCLK_WARMRST_Enable display_name "Enable FPGA-to-HPS warm reset request"
    set_parameter_property  F2SCLK_WARMRST_Enable group $group_name
    
    add_parameter           F2SCLK_COLDRST_Enable boolean false ""
    set_parameter_property  F2SCLK_COLDRST_Enable display_name "Enable FPGA-to-HPS cold reset request"                                                  
    set_parameter_property  F2SCLK_COLDRST_Enable group $group_name

}                                                              
                                                                                                        
proc add_java_gui_parameters {} {                                                                                
    set TOP_LEVEL_GROUP_NAME "Peripheral Pins"
    set group_name "Peripherals Mux Table"   
    
    add_display_item $TOP_LEVEL_GROUP_NAME $group_name "group" ""
   # add_display_item $group_name the_widget "group" ""
      
    add_parameter           JAVA_CONFLICT_PIN string_list {}
    set_parameter_property  JAVA_CONFLICT_PIN derived true
    set_parameter_property  JAVA_CONFLICT_PIN visible false
    
    
    add_parameter           JAVA_GUI_PIN_LIST string_list {}
    set_parameter_property  JAVA_GUI_PIN_LIST derived true
    set_parameter_property  JAVA_GUI_PIN_LIST visible false
       
     set peripherals [list_peripheral_names]  
     set widget_parameter [list \
     Customer_Pin_Name_DERIVED Customer_Pin_Name_DERIVED \
     GPIO_Name_DERIVED GPIO_Name_DERIVED \
     LOANIO_Name_DERIVED LOANIO_Name_DERIVED \
     LOANIO_Enable LOANIO_Enable \
     GPIO_Enable GPIO_Enable \
     JAVA_CONFLICT_PIN GUI_Conflict_Pins_List \
     JAVA_GUI_PIN_LIST GUI_GPIO_Pins_List]        
     
    foreach peripheral_name $peripherals {        
    	 add_parameter "JAVA_${peripheral_name}_DATA"  string ""
    	 set_parameter_property "JAVA_${peripheral_name}_DATA"  derived true
    	 set_parameter_property "JAVA_${peripheral_name}_DATA"  visible false 
                                                                           
    	lappend widget_parameter "JAVA_${peripheral_name}_DATA" 
    	lappend widget_parameter "${peripheral_name}_pin_muxing" 
    	lappend widget_parameter "${peripheral_name}_PinMuxing"
    	lappend widget_parameter "${peripheral_name}_PinMuxing"
    	lappend widget_parameter "${peripheral_name}_Mode"  
    	lappend widget_parameter "${peripheral_name}_Mode"  
    }                                       
      
    add_display_item $group_name the_widget "group"                                                    
    set_display_item_property the_widget widget [list ../widget/pin_mux_widget.jar Altera_hps_widget]      
    set_display_item_property the_widget widget_parameter_map $widget_parameter                                                           
}                                                                                                           
                                                             
add_java_gui_parameters                    

##############################################
# Clocks!
#
# All clock enable parameters go here.
# Clock frequency parameters also go here. All
# the parameters need to be declared regardless
# of whether the clock will be exercised.
# 
# Validation logic will enable/show frequency
# parameters based on whether the actual clock
# is being elaborated.
#
# There are four categories of clocks in this
# component: inputs on SoC I/O
#            outputs on SoC I/O
#            inputs on FPGA pins
#            outputs on FPGA pins              
#
# Inputs on SoC I/O have user-input parameters
# so the data can be consumed by downstream
# embedded software tools.
# Outputs on SoC I/O need not have frequency
# information recorded.
# Inputs on FPGA pins have system info parameters
# so the data can be consumed by downstream
# embedded software tools.
# Outputs on FPGA pins have user input parameters
# to be consumed by Quartus via SDC.
#
##############################################
proc add_clock_parameters {} {
    set TOP_LEVEL_GROUP_NAME "Input Clocks"                     
                                                             
    set group_name "User Clocks"
    add_display_item $TOP_LEVEL_GROUP_NAME $group_name "group" "" 

    # fake group
    set group_name "FPGA Interface Clocks"
    add_display_item $TOP_LEVEL_GROUP_NAME $group_name "group" ""
    
    foreach interface {
	f2h_axi_clock           h2f_axi_clock           h2f_lw_axi_clock
	f2h_sdram0_clock        f2h_sdram1_clock        f2h_sdram2_clock    
	f2h_sdram3_clock        f2h_sdram4_clock        f2h_sdram5_clock
	h2f_cti_clock           h2f_tpiu_clock_in       h2f_debug_apb_clock
    } {
	set parameter "[string toupper ${interface}]_FREQ"
	add_parameter          $parameter integer 100 ""
	set_parameter_property $parameter display_name  "${interface} clock frequency"
	set_parameter_property $parameter system_info_type "CLOCK_RATE"
	set_parameter_property $parameter system_info_arg $interface
	set_parameter_property $parameter visible false               
	set_parameter_property $parameter group $group_name
    }

    set peripherals [list_peripheral_names]

    # TODO: Remove the following for 12.0
    set group_name "Peripheral FPGA Clocks"
    add_display_item $TOP_LEVEL_GROUP_NAME $group_name "group" ""
    
    # Add parameter explicitly for cross-emac ptp since it doesn't belong to a single peripheral
    set parameter [form_peripheral_fpga_input_clock_frequency_parameter emac_ptp_ref_clock]
    add_parameter          $parameter integer 100 ""
    set_parameter_property $parameter display_name  "EMAC emac_ptp_ref_clock clock frequency"
    set_parameter_property $parameter group $group_name
    set_parameter_property $parameter system_info_type "CLOCK_RATE"
    set_parameter_property $parameter system_info_arg emac_ptp_ref_clock
    set_parameter_property $parameter visible false
    
    foreach peripheral $peripherals {
	set clocks [get_peripheral_fpga_input_clocks $peripheral]
	foreach clock $clocks {
	    set parameter [form_peripheral_fpga_input_clock_frequency_parameter $clock]
	    add_parameter          $parameter integer 100 ""
	    set_parameter_property $parameter display_name  "${peripheral} ${clock} clock frequency"
	    set_parameter_property $parameter group $group_name
	    set_parameter_property $parameter system_info_type "CLOCK_RATE"
	    set_parameter_property $parameter system_info_arg $clock
	    set_parameter_property $parameter visible false
	}
	
	set clocks [get_peripheral_fpga_output_clocks $peripheral]
	foreach clock $clocks {
	    set parameter [form_peripheral_fpga_output_clock_frequency_parameter $clock]
		if { [string match "*emac?_md*" $clock]} {
	    	add_parameter          $parameter float 2.5 ""
		} elseif { [string match "*emac?_gtx_clk*" $clock] } {
            add_parameter          $parameter integer 125 ""
		} else {
	    	add_parameter          $parameter integer 100 ""
            if { [string compare $peripheral "SDIO" ] == 0 } {
	        	set_parameter_property $parameter visible false
            }
        }
    	set_parameter_property $parameter display_name  "${peripheral} ${clock} clock frequency"
    	set_parameter_property $parameter group $group_name
    	set_parameter_property $parameter units Megahertz
    	set_parameter_property $parameter allowedRanges {1:1000}
		}

    }
}
add_clock_parameters

add_parameter          hps_device_family string "" ""
set_parameter_property hps_device_family derived true
set_parameter_property hps_device_family visible false

add_parameter	        device_name string "" ""
set_parameter_property 	device_name system_info {DEVICE}
set_parameter_property	device_name visible false

add_parameter          quartus_ini_hps_ip_enable_all_peripheral_fpga_interfaces boolean "" ""
set_parameter_property quartus_ini_hps_ip_enable_all_peripheral_fpga_interfaces system_info_type quartus_ini 
set_parameter_property quartus_ini_hps_ip_enable_all_peripheral_fpga_interfaces system_info_arg  hps_ip_enable_all_peripheral_fpga_interfaces
set_parameter_property quartus_ini_hps_ip_enable_all_peripheral_fpga_interfaces visible false

add_parameter          quartus_ini_hps_ip_enable_emac0_peripheral_fpga_interface boolean "" ""
set_parameter_property quartus_ini_hps_ip_enable_emac0_peripheral_fpga_interface system_info_type quartus_ini
set_parameter_property quartus_ini_hps_ip_enable_emac0_peripheral_fpga_interface system_info_arg  hps_ip_enable_emac0_peripheral_fpga_interface
set_parameter_property quartus_ini_hps_ip_enable_emac0_peripheral_fpga_interface visible false

add_parameter          quartus_ini_hps_ip_enable_test_interface boolean "" ""
set_parameter_property quartus_ini_hps_ip_enable_test_interface system_info_type quartus_ini
set_parameter_property quartus_ini_hps_ip_enable_test_interface system_info_arg  hps_ip_enable_test_interface
set_parameter_property quartus_ini_hps_ip_enable_test_interface visible false

add_parameter          quartus_ini_hps_ip_fast_f2sdram_sim_model boolean "" ""
set_parameter_property quartus_ini_hps_ip_fast_f2sdram_sim_model system_info_type quartus_ini
set_parameter_property quartus_ini_hps_ip_fast_f2sdram_sim_model system_info_arg  hps_ip_fast_f2sdram_sim_model
set_parameter_property quartus_ini_hps_ip_fast_f2sdram_sim_model visible false

add_parameter          quartus_ini_hps_ip_suppress_sdram_synth boolean "" ""
set_parameter_property quartus_ini_hps_ip_suppress_sdram_synth system_info_type quartus_ini
set_parameter_property quartus_ini_hps_ip_suppress_sdram_synth system_info_arg  hps_ip_suppress_sdram_synth
set_parameter_property quartus_ini_hps_ip_suppress_sdram_synth visible false

add_parameter          quartus_ini_hps_ip_enable_low_speed_serial_fpga_interfaces boolean "" ""
set_parameter_property quartus_ini_hps_ip_enable_low_speed_serial_fpga_interfaces system_info_type quartus_ini
set_parameter_property quartus_ini_hps_ip_enable_low_speed_serial_fpga_interfaces system_info_arg  hps_ip_enable_low_speed_serial_fpga_interfaces
set_parameter_property quartus_ini_hps_ip_enable_low_speed_serial_fpga_interfaces visible false

add_parameter          quartus_ini_hps_ip_enable_bsel_csel boolean "" ""
set_parameter_property quartus_ini_hps_ip_enable_bsel_csel system_info_type quartus_ini
set_parameter_property quartus_ini_hps_ip_enable_bsel_csel system_info_arg  hps_ip_enable_bsel_csel
set_parameter_property quartus_ini_hps_ip_enable_bsel_csel visible false

add_parameter          quartus_ini_hps_ip_f2sdram_bonding_out boolean "" ""
set_parameter_property quartus_ini_hps_ip_f2sdram_bonding_out system_info_type 	quartus_ini 
set_parameter_property quartus_ini_hps_ip_f2sdram_bonding_out system_info_arg  hps_ip_enable_f2sdram_bonding_out
set_parameter_property quartus_ini_hps_ip_f2sdram_bonding_out visible false


add_parameter          quartus_ini_hps_emif_pll boolean "" ""
set_parameter_property quartus_ini_hps_emif_pll system_info_type quartus_ini 
set_parameter_property quartus_ini_hps_emif_pll system_info_arg  hps_emif_pll
set_parameter_property quartus_ini_hps_emif_pll visible false


proc load_test_iface_definition {} {
    set csv_file $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/test_iface.csv

    set data [list]
    set count 0
    csv_foreach_row $csv_file cols {
	incr count
	if {$count == 1} {
	    continue
	}
	
	lassign_trimmed $cols port width dir
	lappend data $port $width $dir
    }
    return $data
}
add_storage_parameter test_iface_definition [load_test_iface_definition]

# order of interfaces per peripheral should be kept
# order of ports per interface should be kept
proc load_periph_ifaces_db {} {
    set interfaces_file $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/fpga_peripheral_interfaces.csv
    set peripherals_file $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/fpga_peripheral_atoms.csv
    set ports_file $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/fpga_interface_ports.csv
    set pins_file $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/fpga_port_pins.csv
    set bfm_types_file $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_hps/fpga_bfm_types.csv

    # peripherals and interfaces
    set peripherals([ORDERED_NAMES]) [list]
    funset interface_ports
    set count 0
    set PERIPHERAL_INTERFACES_PROPERTIES_COLUMNS_START 4
    csv_foreach_row $interfaces_file cols {
	incr count
	# skip header
	if {$count == 1} {
	    set ordered_names [list]
	    set length [llength $cols]
	    for {set col $PERIPHERAL_INTERFACES_PROPERTIES_COLUMNS_START} {$col < $length} {incr col} {
		set col_value [lindex $cols $col]
		if {$col_value != ""} {
		    set property_to_col($col_value) $col
		    lappend ordered_names $col_value
		}
	    }
	    set property_to_col([ORDERED_NAMES]) $ordered_names
	    continue
	}
	
	set peripheral_name [string trim [lindex $cols 0]]
	set interface_name  [string trim [lindex $cols 1]]
	set type            [string trim [lindex $cols 2]]
	set dir             [string trim [lindex $cols 3]]
	
	funset peripheral
	if {[info exists peripherals($peripheral_name)]} {
	    array set peripheral $peripherals($peripheral_name)
	} else {
	    funset interfaces
	    set interfaces([ORDERED_NAMES]) [list]
	    set peripheral(interfaces) [array get interfaces]
	    set ordered_names $peripherals([ORDERED_NAMES])
	    lappend ordered_names $peripheral_name
	    set peripherals([ORDERED_NAMES]) $ordered_names
	}
	funset interfaces
	array set interfaces $peripheral(interfaces)
	set ordered_names $interfaces([ORDERED_NAMES])
	lappend ordered_names $interface_name
	set interfaces([ORDERED_NAMES]) $ordered_names
	funset interface
	set interface(type) $type
	set interface(direction) $dir
	funset properties
	foreach property $property_to_col([ORDERED_NAMES]) {
	    set col $property_to_col($property)
	    set property_value [lindex $cols $col]

	    if {$property_value != ""} {
		# Add Meta Property
		if { [string compare [string index ${property} 0] "@" ] == 0 } {
		    set interface(${property}) ${property_value}
		} else {                                 
		    set properties($property) $property_value
		}
	    }
	}                                                                      

	set interface(properties)         [array get properties]
                                                                      
	set interfaces($interface_name)   [array get interface]	
	set peripheral(interfaces)        [array get interfaces]
	set peripherals($peripheral_name) [array get peripheral]
	
	funset ports
	set ports([ORDERED_NAMES]) [list]
	set interface_ports($interface_name) [array get ports]
    }
    set count 0
    csv_foreach_row $peripherals_file cols {  ;# peripheral atom and location table
	incr count
	
	# skip header
	if {$count == 1} {
	    continue
	}
	
	set peripheral_name      [string trim [lindex $cols 0]]
	set atom_name            [string trim [lindex $cols 1]]
	
	funset peripheral
	if {[info exists peripherals($peripheral_name)]} {
	    array set peripheral $peripherals($peripheral_name)
	} else {
	    # Assume that if a peripheral hasn't be recognized until now, we won't be using it
	    continue
	}
	set peripheral(atom_name)           $atom_name
	set peripherals($peripheral_name)   [array get peripheral]
    }    
    add_parameter          DB_periph_ifaces string [array get peripherals] ""
    set_parameter_property DB_periph_ifaces derived true
    set_parameter_property DB_periph_ifaces visible false
    
    set p [array get peripherals]
    send_message debug "DB_periph_ifaces: ${p}"
    
    # ports
    array set ports_to_pins {}
    #    # prepopulate interface_ports with names of interfaces that are known
    #    foreach {peripheral_name peripheral_string} [array get peripherals] {
    #	array set peripheral_array $peripheral_string
    #	foreach interface_name [array names peripheral_array] {
    #	    set interface_ports($interface_name) {}
    #	}
    #    }
    set count 0
    csv_foreach_row $ports_file cols {
	incr count
	
	# skip header
	if {$count == 1} continue
	
	set interface_name   [string trim [lindex $cols 0]]
	set port_name        [string trim [lindex $cols 1]]
	set role             [string trim [lindex $cols 2]]
	set dir              [string trim [lindex $cols 3]]
	set atom_signal_name [string trim [lindex $cols 4]]

	funset interface
	array set interface $interface_ports($interface_name)
	set ordered_names $interface([ORDERED_NAMES])
	lappend ordered_names $port_name
	set interface([ORDERED_NAMES]) $ordered_names
	
	funset port
	set port(role) $role
	set port(direction) $dir
	set port(atom_signal_name) $atom_signal_name
	set interface($port_name) [array get port]
	set interface_ports($interface_name) [array get interface]
	
	set ports_to_pins($port_name) {}
    }
    add_parameter          DB_iface_ports string [array get interface_ports] ""
    set_parameter_property DB_iface_ports derived true
    set_parameter_property DB_iface_ports visible false
    
    set p [array get interface_ports]
    send_message debug "DB_iface_ports: ${p}"
    
    # peripheral signals to ports
    set count 0
    csv_foreach_row $pins_file cols {
	incr count
	
	# skip header
	if {$count == 1} continue
	
	set peripheral_name [string trim [lindex $cols 0]]
	set pin_name        [string trim [lindex $cols 1]]
	set port_name       [string trim [lindex $cols 2]]
	
	set is_multibit_signal [regexp {^([a-zA-Z0-9_]+)\[([0-9]+)\]} $port_name match real_name bit]
	if {$is_multibit_signal == 0} {
	    set bit 0
	} else {
	    set port_name $real_name
	}
	
	if {[info exists ports_to_pins($port_name)] == 0} {
	    send_message error "Peripheral ${peripheral_name} signal ${pin_name} is defined but corresponding FPGA signal ${port_name}\[${bit}\] is not"
	} else {
	    funset port
	    array set port $ports_to_pins($port_name)
	    
	    if {[info exists port($bit)]} {
		# collision!
		send_message error "Signal ${port_name}\[${bit}\] is having original assignment ${peripheral_name}.${port($bit)} replaced with ${peripheral_name}.${pin_name}"
	    }
	    set port($bit) $pin_name
	    set ports_to_pins($port_name) [array get port]
	}
    }
    add_parameter          DB_port_pins string [array get ports_to_pins] ""
    set_parameter_property DB_port_pins derived true
    set_parameter_property DB_port_pins visible false

    set p [array get ports_to_pins]
    send_message debug "DB_port_pins: ${p}"

    # bfm types
    set count 0
    funset bfm_types
    csv_foreach_row $bfm_types_file cols {
	incr count
	
	# skip header
	if {$count == 1} continue
	
	set bfm_type_name [string trim [lindex $cols 0]]
	set property_name [string trim [lindex $cols 1]]
	set value         [string trim [lindex $cols 2]]

	if {[info exists bfm_types($bfm_type_name)] == 0} {
	    set bfm_types($bfm_type_name) {}
	}
	funset bfm_type
	array set bfm_type $bfm_types($bfm_type_name)
	set bfm_type($property_name) $value
	set bfm_types($bfm_type_name) [array get bfm_type]
    }
    add_parameter          DB_bfm_types string [array get bfm_types] ""
    set_parameter_property DB_bfm_types derived true
    set_parameter_property DB_bfm_types visible false
    # TODO: what to do so that mode information on a peripheral.pin basis can be used for elaboration???
}

# only run during class creation
load_periph_ifaces_db

#######################
##### Composition #####
#######################

namespace eval ::fpga_interfaces {
    source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_interface_generator/api.tcl
}

namespace eval ::hps_io {
    namespace eval internal {
	source $env(QUARTUS_ROOTDIR)/../ip/altera/hps/altera_interface_generator/api.tcl
    }
    variable pins
    
    proc add_peripheral {peripheral_name atom_name location} {
	internal::add_module_instance $peripheral_name $atom_name $location
    }
    
    # oe used in tristate output and inout
    # out used in output and inout
    # in used in input and inout
    proc add_pin {peripheral_name pin_name dir location in_port out_port oe_port} {
	variable pins
	lappend  pins [list $peripheral_name $pin_name $dir $location $in_port $out_port $oe_port]
    }
    
    proc process_pins {} {
	variable pins

	set interface_name "hps_io"
	set hps_io_interface_created 0
	funset ports_used ;# set of inst/ports used
	funset port_wire  ;# map of ports to aliased wires
	foreach pin $pins { ;# Check for multiple uses of the same port and create wires for those cases
	    lassign $pin peripheral_name pin_name dir location in_port out_port oe_port
	    
	    # check to see if port is used multiple times
	    foreach port_part [list $in_port $out_port $oe_port] {
		if {$port_part != "" && [info exists ports_used($port_part)]} {
		    # Assume only outputs will be used multiple times. Inputs would be an error
		    if {[info exists port_wire($port_part)] == 0} {
			set port_wire($port_part) [internal::allocate_wire]
			# Drive new wire with port
			internal::set_wire_port_fragments $port_wire($port_part) driven_by $port_part
		    }
		}
		set ports_used($port_part) 1
	    }
	}
	
	set qip [list]
	foreach pin $pins {
	    lassign $pin peripheral_name pin_name dir location in_port out_port oe_port
	    foreach port_part_ref {in_port out_port oe_port} { ;# Replace ports with wires if needed
		set port_part [set $port_part_ref]
		if {[info exists port_wire($port_part)]} {
		    set $port_part_ref [internal::wire_tofragment $port_wire($port_part)]
		}
	    }

	    # Hook things up
	    set instance_name [string tolower $peripheral_name] ;# is this necessary???
	    if {$hps_io_interface_created == 0} {
		set hps_io_interface_created 1
		internal::add_interface $interface_name conduit input
	    }
	    set export_signal_name "hps_io_${instance_name}_${pin_name}"
	    internal::add_interface_port $interface_name $export_signal_name $export_signal_name $dir 1
	    if {[string compare $dir "input"] == 0} {
			internal::set_port_fragments $interface_name $export_signal_name $in_port
			internal::add_raw_sdc_constraint "set_false_path -from \[get_ports ${interface_name}_${export_signal_name}\] -to *"
	    } elseif {[string compare $dir "output"] == 0} {
		if {[string compare $oe_port "" ] == 0} {
			internal::set_port_fragments $interface_name $export_signal_name $out_port
			internal::add_raw_sdc_constraint "set_false_path -from * -to \[get_ports ${interface_name}_${export_signal_name}\]"
		} else {
			internal::set_port_tristate_output $interface_name $export_signal_name $out_port $oe_port
			internal::add_raw_sdc_constraint "set_false_path -from * -to \[get_ports ${interface_name}_${export_signal_name}\]"
		}
	    } else {
			internal::set_port_fragments $interface_name $export_signal_name $in_port
			internal::set_port_tristate_output $interface_name $export_signal_name $out_port $oe_port
			internal::add_raw_sdc_constraint "set_false_path -from \[get_ports ${interface_name}_${export_signal_name}\] -to *"
			internal::add_raw_sdc_constraint "set_false_path -from * -to \[get_ports ${interface_name}_${export_signal_name}\]"
	    }
	    set path_to_pin "hps_io|border|${export_signal_name}\[0\]"
	    set location_assignment "set_instance_assignment -name HPS_LOCATION ${location} -entity %entityName% -to ${path_to_pin}"
	    lappend qip $location_assignment
	}
	set_qip_strings $qip
    }
    
    proc init {} {
	internal::init
	variable pins [list]
    }
    
    proc serialize {var_name} {
	upvar 1 $var_name data
	process_pins
	internal::serialize data
    }
}

set_module_property composition_callback compose

proc compose {} {
    # synchronize device families between the EMIF and HPS parameter sets
    set_parameter_value hps_device_family [get_parameter_value SYS_INFO_DEVICE_FAMILY]
    fpga_interfaces::init
    fpga_interfaces::set_bfm_types [array get DB_bfm_types]
    
    hps_io::init
    validate
    elab 0

    update_hps_to_fpga_clock_frequency_parameters


    fpga_interfaces::serialize fpga_interfaces_data

    add_instance fpga_interfaces altera_interface_generator
    set_instance_parameter_value fpga_interfaces interfaceDefinition [array get fpga_interfaces_data]
    
    expose_border fpga_interfaces $fpga_interfaces_data(interfaces)

    declare_cmsis_svd $fpga_interfaces_data(interfaces)

    clear_array temp_array
}

proc logicalview_dtg {} {

    set hard_peripheral_logical_view_dir $::env(QUARTUS_ROOTDIR)/../ip/altera/hps/hard_peripheral_logical_view

    source "$hard_peripheral_logical_view_dir/common/hps_utils.tcl"

    source "$hard_peripheral_logical_view_dir/hps_periphs/hps_periphs.tcl"

    set f2h_present [ expr [ get_parameter_value F2S_Width ] != 0]
    set h2f_present [ expr [ get_parameter_value S2F_Width ] != 0]
    set F2S_Width [ get_parameter_value F2S_Width ]
    set S2F_Width [ get_parameter_value S2F_Width ]
    set h2f_lw_present [ expr [ string compare [ get_parameter_value LWH2F_Enable ] "true" ] == 0 ]
    set LWH2F_Enable [ get_parameter_value LWH2F_Enable ]
    set device_family [get_parameter_value SYS_INFO_DEVICE_FAMILY]

    # Need to add whole bunch of device tree generation parameters here (dtg)
    # Getting whether is it single or dual core by checking the device family. List of single core:
    # Cyclone V SE                                                                          
    regsub "^.* V" $device_family "" se_family
    regsub " " $se_family "" se_family
   
    set number_of_a9 0
    if { [string toupper $se_family] == "SE"} {
        set number_of_a9 1
    } else {
        set number_of_a9 2                                                                  
    }

    set F2SDRAM_Width [get_parameter_value F2SDRAM_Width]
    set F2SDRAM_Type [get_parameter_value F2SDRAM_Type]
    set quartus_ini_hps_ip_f2sdram_bonding_out  [get_parameter_value quartus_ini_hps_ip_f2sdram_bonding_out]
    set BONDING_OUT_ENABLED [get_parameter_value BONDING_OUT_ENABLED]
    add_instance clk_0 hps_clk_src
    hps_utils_add_instance_clk_reset clk_0 bridges hps_bridge_avalon
    set_instance_parameter_value bridges F2S_Width $F2S_Width
    set_instance_parameter_value bridges S2F_Width $S2F_Width
    set_instance_parameter_value bridges BONDING_OUT_ENABLED $BONDING_OUT_ENABLED
    set_instance_parameter_value bridges LWH2F_Enable $LWH2F_Enable
    set_instance_parameter_value bridges quartus_ini_hps_ip_f2sdram_bonding_out $quartus_ini_hps_ip_f2sdram_bonding_out 
    add_interface h2f_reset reset output
    set_interface_property h2f_reset EXPORT_OF bridges.h2f_reset
    set_interface_property h2f_reset PORT_NAME_MAP "h2f_rst_n h2f_rst_n"

    set rows [llength $F2SDRAM_Width]
    set type_list $F2SDRAM_Type  
    set append_type_list ""
    set append_type_width ""
    set total_command_port 0
    set total_write_port 0
    set total_read_port 0
    if {$rows > 0} {
        for {set i 0} {${i} < $rows} {incr i} {           
            set type_choice  [lindex $type_list  $i]
            set type_width  [lindex $F2SDRAM_Width  $i]
            if { [string compare $type_choice [F2HSDRAM_AVM]] == 0 } {
                set type_id 1
                set total_command_port [expr $total_command_port + 1]
                if {$type_width == 128} {
                    set total_write_port [expr $total_write_port + 2]
                    set total_read_port [expr $total_read_port + 2]
                } elseif {$type_width == 256 } {
                    set total_write_port [expr $total_write_port + 4]
                    set total_read_port [expr $total_read_port + 4]
                } else {
                    set total_write_port [expr $total_write_port + 1]
                    set total_read_port [expr $total_read_port + 1]
                }
            } elseif { [string compare $type_choice [F2HSDRAM_AVM_WRITEONLY]] == 0 } {
                set type_id 2
                set total_command_port [expr $total_command_port + 1]
                if {$type_width == 128} {
                    set total_write_port [expr $total_write_port + 2]
                } elseif {$type_width == 256 } {
                    set total_write_port [expr $total_write_port + 4]
                } else {
                    set total_write_port [expr $total_write_port + 1]
                }
            } elseif { [string compare $type_choice [F2HSDRAM_AVM_READONLY]] == 0 } {    
                set type_id 3
                set total_command_port [expr $total_command_port + 1]
                if {$type_width == 128} {
                    set total_read_port [expr $total_read_port + 2]
                } elseif {$type_width == 256 } {
                    set total_read_port [expr $total_read_port + 4]
                } else {
                    set total_read_port [expr $total_read_port + 1]
                }         
            } else {
                set type_id 0
                if { [ expr $total_command_port % 2 ] } {
                    incr total_command_port 1
                }
                set total_command_port [expr $total_command_port + 2]
                if {$type_width == 128} {
                    set total_write_port [expr $total_write_port + 2]
                    set total_read_port [expr $total_read_port + 2]
                } elseif {$type_width == 256 } {
                    set total_write_port [expr $total_write_port + 4]
                    set total_read_port [expr $total_read_port + 4]
                } else {
                    set total_write_port [expr $total_write_port + 1]
                    set total_read_port [expr $total_read_port + 1]
                }
            }
            
            if {$total_command_port > 6} {
                if {$type_id == 0} {
                    send_message error "No command ports available to allocate AXI Interface f2h_sdram${i}"
                } else {
                    send_message error "No command ports available to allocate Avalon-MM Interface f2h_sdram${i}"    
                }
            }
            if {$total_read_port > 4} {
                if {$type_id == 0} {
                    send_message error "No read ports available to allocate AXI Interface f2h_sdram${i}"
                } else {
                    send_message error "No read ports available to allocate Avalon-MM Interface f2h_sdram${i}"    
                }
            }
            if {$total_write_port > 4} {
                if {$type_id == 0} {
                    send_message error "No write ports available to allocate AXI Interface f2h_sdram${i}"
                } else {
                    send_message error "No write ports available to allocate Avalon-MM Interface f2h_sdram${i}"    
                }
            }
            if {$total_command_port < 7 && $total_write_port < 5 && $total_read_port < 5} {
                lappend append_type_list $type_id
                lappend append_type_width $type_width
            }
        }
    }
    set_instance_parameter_value bridges F2SDRAM_Type $append_type_list
    set_instance_parameter_value bridges F2SDRAM_Width $append_type_width
    set total_command_port 0
    set total_write_port 0
    set total_read_port 0
    set bonding_out_signal [expr { [string compare [get_parameter_value BONDING_OUT_ENABLED] "true"] == 0} && {[string compare [get_parameter_value quartus_ini_hps_ip_f2sdram_bonding_out] "true"] == 0}]

    if {$rows > 0} {
        for {set i 0} {${i} < $rows} {incr i} {           
           
            set type_choice  [lindex $type_list  $i]
            set type_width  [lindex $F2SDRAM_Width  $i]

            if { [string compare $type_choice [F2HSDRAM_AVM]] == 0 } {
                set type "avalon"
                set total_command_port [expr $total_command_port + 1]
                if {$type_width == 128} {
                    set total_write_port [expr $total_write_port + 2]
                    set total_read_port [expr $total_read_port + 2]
                } elseif {$type_width == 256 } {
                    set total_write_port [expr $total_write_port + 4]
                    set total_read_port [expr $total_read_port + 4]
                } else {
                    set total_write_port [expr $total_write_port + 1]
                    set total_read_port [expr $total_read_port + 1]
                }
                set sdram_data "f2h_sdram${i}_ADDRESS f2h_sdram${i}_ADDRESS f2h_sdram${i}_BURSTCOUNT f2h_sdram${i}_BURSTCOUNT f2h_sdram${i}_WAITREQUEST f2h_sdram${i}_WAITREQUEST f2h_sdram${i}_READDATA f2h_sdram${i}_READDATA f2h_sdram${i}_READDATAVALID f2h_sdram${i}_READDATAVALID f2h_sdram${i}_READ f2h_sdram${i}_READ f2h_sdram${i}_WRITEDATA f2h_sdram${i}_WRITEDATA f2h_sdram${i}_BYTEENABLE f2h_sdram${i}_BYTEENABLE f2h_sdram${i}_WRITE f2h_sdram${i}_WRITE"
            } elseif { [string compare $type_choice [F2HSDRAM_AVM_WRITEONLY]] == 0 } {
                set type "avalon"
                set total_command_port [expr $total_command_port + 1]
                if {$type_width == 128} {
                    set total_write_port [expr $total_write_port + 2]
                } elseif {$type_width == 256 } {
                    set total_write_port [expr $total_write_port + 4]
                } else {
                    set total_write_port [expr $total_write_port + 1]
                }
                set sdram_data "f2h_sdram${i}_ADDRESS f2h_sdram${i}_ADDRESS f2h_sdram${i}_BURSTCOUNT f2h_sdram${i}_BURSTCOUNT f2h_sdram${i}_WAITREQUEST f2h_sdram${i}_WAITREQUEST f2h_sdram${i}_WRITEDATA f2h_sdram${i}_WRITEDATA f2h_sdram${i}_BYTEENABLE f2h_sdram${i}_BYTEENABLE f2h_sdram${i}_WRITE f2h_sdram${i}_WRITE"
            } elseif { [string compare $type_choice [F2HSDRAM_AVM_READONLY]] == 0 } {    
                set type "avalon"                  
                set total_command_port [expr $total_command_port + 1]
                if {$type_width == 128} {
                    set total_read_port [expr $total_read_port + 2]
                } elseif {$type_width == 256 } {
                    set total_read_port [expr $total_read_port + 4]
                } else {
                    set total_read_port [expr $total_read_port + 1]
                }
                set sdram_data "f2h_sdram${i}_ADDRESS f2h_sdram${i}_ADDRESS f2h_sdram${i}_BURSTCOUNT f2h_sdram${i}_BURSTCOUNT f2h_sdram${i}_WAITREQUEST f2h_sdram${i}_WAITREQUEST f2h_sdram${i}_READDATA f2h_sdram${i}_READDATA f2h_sdram${i}_READDATAVALID f2h_sdram${i}_READDATAVALID f2h_sdram${i}_READ f2h_sdram${i}_READ"
            } else {
                set type "axi"
                if { [ expr $total_command_port % 2 ] } {
                    incr total_command_port 1
                }
                set total_command_port [expr $total_command_port + 2]
                if {$type_width == 128} {
                    set total_write_port [expr $total_write_port + 2]
                    set total_read_port [expr $total_read_port + 2]
                } elseif {$type_width == 256 } {
                    set total_write_port [expr $total_write_port + 4]
                    set total_read_port [expr $total_read_port + 4]
                } else {
                    set total_write_port [expr $total_write_port + 1]
                    set total_read_port [expr $total_read_port + 1]
                }
                set sdram_data "f2h_sdram${i}_ARADDR f2h_sdram${i}_ARADDR   f2h_sdram${i}_ARLEN f2h_sdram${i}_ARLEN f2h_sdram${i}_ARID f2h_sdram${i}_ARID f2h_sdram${i}_ARSIZE f2h_sdram${i}_ARSIZE f2h_sdram${i}_ARBURST f2h_sdram${i}_ARBURST f2h_sdram${i}_ARLOCK f2h_sdram${i}_ARLOCK f2h_sdram${i}_ARPROT f2h_sdram${i}_ARPROT f2h_sdram${i}_ARVALID f2h_sdram${i}_ARVALID f2h_sdram${i}_ARCACHE f2h_sdram${i}_ARCACHE f2h_sdram${i}_AWADDR f2h_sdram${i}_AWADDR f2h_sdram${i}_AWLEN f2h_sdram${i}_AWLEN f2h_sdram${i}_AWID f2h_sdram${i}_AWID f2h_sdram${i}_AWSIZE f2h_sdram${i}_AWSIZE f2h_sdram${i}_AWBURST f2h_sdram${i}_AWBURST f2h_sdram${i}_AWLOCK f2h_sdram${i}_AWLOCK f2h_sdram${i}_AWPROT f2h_sdram${i}_AWPROT f2h_sdram${i}_AWVALID f2h_sdram${i}_AWVALID f2h_sdram${i}_AWCACHE f2h_sdram${i}_AWCACHE f2h_sdram${i}_BRESP f2h_sdram${i}_BRESP f2h_sdram${i}_BID f2h_sdram${i}_BID f2h_sdram${i}_BVALID f2h_sdram${i}_BVALID f2h_sdram${i}_BREADY f2h_sdram${i}_BREADY f2h_sdram${i}_ARREADY f2h_sdram${i}_ARREADY f2h_sdram${i}_AWREADY f2h_sdram${i}_AWREADY f2h_sdram${i}_RREADY f2h_sdram${i}_RREADY f2h_sdram${i}_RDATA f2h_sdram${i}_RDATA f2h_sdram${i}_RRESP f2h_sdram${i}_RRESP f2h_sdram${i}_RLAST f2h_sdram${i}_RLAST f2h_sdram${i}_RID f2h_sdram${i}_RID f2h_sdram${i}_RVALID f2h_sdram${i}_RVALID f2h_sdram${i}_WLAST f2h_sdram${i}_WLAST f2h_sdram${i}_WVALID f2h_sdram${i}_WVALID f2h_sdram${i}_WDATA f2h_sdram${i}_WDATA f2h_sdram${i}_WSTRB f2h_sdram${i}_WSTRB f2h_sdram${i}_WREADY f2h_sdram${i}_WREADY f2h_sdram${i}_WID f2h_sdram${i}_WID"
            }

            if {$total_command_port > 6 || $total_write_port > 4 || $total_read_port > 4} {
                break
            }
            add_interface f2h_sdram${i}_clock clock Input
            set_interface_property f2h_sdram${i}_clock EXPORT_OF bridges.f2h_sdram${i}_clock
            set_interface_property f2h_sdram${i}_clock PORT_NAME_MAP "f2h_sdram${i}_clk f2h_sdram${i}_clk"
            add_interface f2h_sdram${i}_data $type slave
            set_interface_property f2h_sdram${i}_data EXPORT_OF bridges.f2h_sdram${i}_data
            set_interface_property f2h_sdram${i}_data PORT_NAME_MAP "$sdram_data"	    
        }

	if $bonding_out_signal {
	    set bon_out_signal "f2h_sdram_BONOUT_1 f2h_sdram_BONOUT_1 	  f2h_sdram_BONOUT_2 f2h_sdram_BONOUT_2" 	
	    add_interface f2h_sdram_bon_out conduit Output
	    set_interface_property f2h_sdram_bon_out EXPORT_OF bridges.f2h_sdram_bon_out
            set_interface_property f2h_sdram_bon_out PORT_NAME_MAP "$bon_out_signal"
   	}

    }

    set declared_svd_file 0
    set svd_path [file join $::env(QUARTUS_ROOTDIR) .. ip altera hps altera_hps altera_hps.svd]
    if { $h2f_present } {
        hps_utils_add_slave_interface arm_a9_0.altera_axi_master bridges.axi_h2f {0xc0000000}
        if { $number_of_a9 > 1 } {
            hps_utils_add_slave_interface arm_a9_1.altera_axi_master bridges.axi_h2f {0xc0000000}
        }
        
        add_interface h2f_axi_clock clock Input
        set_interface_property h2f_axi_clock EXPORT_OF bridges.h2f_axi_clock
        set_interface_property h2f_axi_clock PORT_NAME_MAP "h2f_axi_clk h2f_axi_clk"
        
        add_interface h2f_axi_master axi master
        set_interface_property h2f_axi_master EXPORT_OF bridges.h2f
        set_interface_property h2f_axi_master PORT_NAME_MAP "h2f_AWID h2f_AWID h2f_AWADDR h2f_AWADDR h2f_AWLEN h2f_AWLEN h2f_AWSIZE h2f_AWSIZE h2f_AWBURST h2f_AWBURST h2f_AWLOCK h2f_AWLOCK h2f_AWCACHE h2f_AWCACHE h2f_AWPROT h2f_AWPROT h2f_AWVALID h2f_AWVALID h2f_AWREADY h2f_AWREADY h2f_WID h2f_WID h2f_WDATA h2f_WDATA h2f_WSTRB h2f_WSTRB h2f_WLAST h2f_WLAST h2f_WVALID h2f_WVALID h2f_WREADY h2f_WREADY h2f_BID h2f_BID h2f_BRESP h2f_BRESP h2f_BVALID h2f_BVALID h2f_BREADY h2f_BREADY h2f_ARID h2f_ARID h2f_ARADDR h2f_ARADDR h2f_ARLEN h2f_ARLEN h2f_ARSIZE h2f_ARSIZE h2f_ARBURST h2f_ARBURST h2f_ARLOCK h2f_ARLOCK h2f_ARCACHE h2f_ARCACHE h2f_ARPROT h2f_ARPROT h2f_ARVALID h2f_ARVALID h2f_ARREADY h2f_ARREADY h2f_RID h2f_RID h2f_RDATA h2f_RDATA h2f_RRESP h2f_RRESP h2f_RLAST h2f_RLAST h2f_RVALID h2f_RVALID h2f_RREADY h2f_RREADY"
        set_interface_property h2f_axi_master SVD_ADDRESS_GROUP  "hps"
        set_interface_property h2f_axi_master SVD_ADDRESS_OFFSET 0xC0000000
        if {!$declared_svd_file} {
            set_interface_property h2f_axi_master CMSIS_SVD_FILE $svd_path
            set declared_svd_file 1
        }
    }
    
    if { $f2h_present } {
        add_interface f2h_axi_clock clock Input
        set_interface_property f2h_axi_clock EXPORT_OF bridges.f2h_axi_clock
        set_interface_property f2h_axi_clock PORT_NAME_MAP "f2h_axi_clk f2h_axi_clk"
        
        add_interface f2h_axi_slave axi slave
        set_interface_property f2h_axi_slave EXPORT_OF bridges.f2h
        set_interface_property f2h_axi_slave PORT_NAME_MAP "f2h_AWID f2h_AWID f2h_AWADDR f2h_AWADDR f2h_AWLEN f2h_AWLEN f2h_AWSIZE f2h_AWSIZE f2h_AWBURST f2h_AWBURST f2h_AWLOCK f2h_AWLOCK f2h_AWCACHE f2h_AWCACHE f2h_AWPROT f2h_AWPROT f2h_AWVALID f2h_AWVALID f2h_AWREADY f2h_AWREADY f2h_AWUSER f2h_AWUSER f2h_WID f2h_WID f2h_WDATA f2h_WDATA f2h_WSTRB f2h_WSTRB f2h_WLAST f2h_WLAST f2h_WVALID f2h_WVALID f2h_WREADY f2h_WREADY f2h_BID f2h_BID f2h_BRESP f2h_BRESP f2h_BVALID f2h_BVALID f2h_BREADY f2h_BREADY f2h_ARID f2h_ARID f2h_ARADDR f2h_ARADDR f2h_ARLEN f2h_ARLEN f2h_ARSIZE f2h_ARSIZE f2h_ARBURST f2h_ARBURST f2h_ARLOCK f2h_ARLOCK f2h_ARCACHE f2h_ARCACHE f2h_ARPROT f2h_ARPROT f2h_ARVALID f2h_ARVALID f2h_ARREADY f2h_ARREADY f2h_ARUSER f2h_ARUSER f2h_RID f2h_RID f2h_RDATA f2h_RDATA f2h_RRESP f2h_RRESP f2h_RLAST f2h_RLAST f2h_RVALID f2h_RVALID f2h_RREADY f2h_RREADY"
    }
    
    if { $h2f_lw_present } {
        hps_utils_add_slave_interface arm_a9_0.altera_axi_master bridges.axi_h2f_lw {0xff200000}
        if { $number_of_a9 > 1 } {
            hps_utils_add_slave_interface arm_a9_1.altera_axi_master bridges.axi_h2f_lw {0xff200000}
        }
        
        add_interface h2f_lw_axi_clock clock Input
        set_interface_property h2f_lw_axi_clock EXPORT_OF bridges.h2f_lw_axi_clock
        set_interface_property h2f_lw_axi_clock PORT_NAME_MAP "h2f_lw_axi_clk h2f_lw_axi_clk"
        
        add_interface h2f_lw_axi_master axi start
        set_interface_property h2f_lw_axi_master EXPORT_OF bridges.h2f_lw
        set_interface_property h2f_lw_axi_master PORT_NAME_MAP "h2f_lw_AWID h2f_lw_AWID h2f_lw_AWADDR h2f_lw_AWADDR h2f_lw_AWLEN h2f_lw_AWLEN h2f_lw_AWSIZE h2f_lw_AWSIZE h2f_lw_AWBURST h2f_lw_AWBURST h2f_lw_AWLOCK h2f_lw_AWLOCK h2f_lw_AWCACHE h2f_lw_AWCACHE h2f_lw_AWPROT h2f_lw_AWPROT h2f_lw_AWVALID h2f_lw_AWVALID h2f_lw_AWREADY h2f_lw_AWREADY h2f_lw_WID h2f_lw_WID h2f_lw_WDATA h2f_lw_WDATA h2f_lw_WSTRB h2f_lw_WSTRB h2f_lw_WLAST h2f_lw_WLAST h2f_lw_WVALID h2f_lw_WVALID h2f_lw_WREADY h2f_lw_WREADY h2f_lw_BID h2f_lw_BID h2f_lw_BRESP h2f_lw_BRESP h2f_lw_BVALID h2f_lw_BVALID h2f_lw_BREADY h2f_lw_BREADY h2f_lw_ARID h2f_lw_ARID h2f_lw_ARADDR h2f_lw_ARADDR h2f_lw_ARLEN h2f_lw_ARLEN h2f_lw_ARSIZE h2f_lw_ARSIZE h2f_lw_ARBURST h2f_lw_ARBURST h2f_lw_ARLOCK h2f_lw_ARLOCK h2f_lw_ARCACHE h2f_lw_ARCACHE h2f_lw_ARPROT h2f_lw_ARPROT h2f_lw_ARVALID h2f_lw_ARVALID h2f_lw_ARREADY h2f_lw_ARREADY h2f_lw_RID h2f_lw_RID h2f_lw_RDATA h2f_lw_RDATA h2f_lw_RRESP h2f_lw_RRESP h2f_lw_RLAST h2f_lw_RLAST h2f_lw_RVALID h2f_lw_RVALID h2f_lw_RREADY h2f_lw_RREADY"
        set_interface_property h2f_lw_axi_master SVD_ADDRESS_GROUP  "hps"
        set_interface_property h2f_lw_axi_master SVD_ADDRESS_OFFSET 0xFF200000
        if {!$declared_svd_file} {
            set_interface_property h2f_lw_axi_master CMSIS_SVD_FILE $svd_path
            set declared_svd_file 1
        }
    }

    if {!$declared_svd_file} {
        set_module_assignment "cmsis.svd.file"   $svd_path
        set_module_assignment "cmsis.svd.suffix" "hps"
    }

    clocks_logicalview_dtg
    
    if { $number_of_a9 > 0 } {
        hps_utils_add_instance_clk_reset clk_0 arm_a9_0 arm_a9
    }
    
    if { $number_of_a9 > 1 } {
        hps_utils_add_instance_clk_reset clk_0 arm_a9_1 arm_a9
    }
    

    hps_instantiate_arm_gic_0 $number_of_a9
    
    hps_instantiate_L2 $number_of_a9
    
    hps_instantiate_dma $number_of_a9
    
    hps_instantiate_sysmgr $number_of_a9
    
    hps_instantiate_clkmgr $number_of_a9

    hps_instantiate_rstmgr $number_of_a9
    
    hps_instantiate_fpgamgr $number_of_a9
    
    hps_instantiate_uart0 $number_of_a9 "UART0_PinMuxing" [get_parameter_value l4_sp_clk_mhz]
    
    hps_instantiate_uart1 $number_of_a9 "UART1_PinMuxing" [get_parameter_value l4_sp_clk_mhz]
    
    hps_instantiate_timer0 $number_of_a9
    
    hps_instantiate_timer1 $number_of_a9
    
    hps_instantiate_timer2 $number_of_a9
    
    hps_instantiate_timer3 $number_of_a9
    
    hps_instantiate_wd_timer0 $number_of_a9
    
    hps_instantiate_wd_timer1 $number_of_a9
    
    hps_instantiate_gpio0 $number_of_a9
    
    hps_instantiate_gpio1 $number_of_a9
    
    hps_instantiate_gpio2 $number_of_a9
    
    hps_instantiate_i2c0 $number_of_a9 "I2C0_PinMuxing"
    
    hps_instantiate_i2c1 $number_of_a9 "I2C1_PinMuxing"
    
    hps_instantiate_i2c2 $number_of_a9 "I2C2_PinMuxing"
    
    hps_instantiate_i2c3 $number_of_a9 "I2C3_PinMuxing"
    
    hps_instantiate_nand0 $number_of_a9 "NAND_PinMuxing"
    
    hps_instantiate_spim0 $number_of_a9 "SPIM0_PinMuxing"
    
    hps_instantiate_spim1 $number_of_a9 "SPIM1_PinMuxing"
    
    hps_instantiate_qspi $number_of_a9 "QSPI_PinMuxing"
    
    hps_instantiate_sdmmc $number_of_a9 "SDIO_PinMuxing"
    
    hps_instantiate_usb0 $number_of_a9 "USB0_PinMuxing"
    
    hps_instantiate_usb1 $number_of_a9 "USB1_PinMuxing"
    
    hps_instantiate_gmac0 $number_of_a9 "EMAC0_PinMuxing"
    
    hps_instantiate_gmac1 $number_of_a9 "EMAC1_PinMuxing"

    hps_instantiate_dcan0 $number_of_a9 "CAN0_PinMuxing"
    
    hps_instantiate_dcan1 $number_of_a9 "CAN1_PinMuxing"

    hps_instantiate_l3regs $number_of_a9

    hps_instantiate_sdrctl $number_of_a9

    hps_instantiate_axi_ocram $number_of_a9

    hps_instantiate_axi_sdram $number_of_a9
    
    hps_instantiate_timer $number_of_a9

    hps_instantiate_scu $number_of_a9
    
    add_connection arm_gic_0.arm_gic_ppi timer.interrupt_sender
    set_connection_parameter_value arm_gic_0.arm_gic_ppi/timer.interrupt_sender irqNumber 13
    
    if { $f2h_present } {
        hps_utils_add_slave_interface bridges.axi_f2h arm_gic_0.axi_slave0 {0xfffed000}
        hps_utils_add_slave_interface bridges.axi_f2h arm_gic_0.axi_slave1 {0xfffec100}
        hps_utils_add_slave_interface bridges.axi_f2h L2.axi_slave0 {0xfffef000}
        hps_utils_add_slave_interface bridges.axi_f2h dma.axi_slave0 {0xffe01000}
        hps_utils_add_slave_interface bridges.axi_f2h sysmgr.axi_slave0 {0xffd08000}
        hps_utils_add_slave_interface bridges.axi_f2h clkmgr.axi_slave0 {0xffd04000}
        hps_utils_add_slave_interface bridges.axi_f2h rstmgr.axi_slave0 {0xffd05000}
        hps_utils_add_slave_interface bridges.axi_f2h fpgamgr.axi_slave0 {0xff706000}
        hps_utils_add_slave_interface bridges.axi_f2h fpgamgr.axi_slave1 {0xffb90000}
        hps_utils_add_slave_interface bridges.axi_f2h uart0.axi_slave0 {0xffc02000}
        hps_utils_add_slave_interface bridges.axi_f2h uart1.axi_slave0 {0xffc03000}
        hps_utils_add_slave_interface bridges.axi_f2h timer0.axi_slave0 {0xffc08000}
        hps_utils_add_slave_interface bridges.axi_f2h timer1.axi_slave0 {0xffc09000}
        hps_utils_add_slave_interface bridges.axi_f2h timer2.axi_slave0 [hps_timer2_base]
        hps_utils_add_slave_interface bridges.axi_f2h timer3.axi_slave0 [hps_timer3_base]
        hps_utils_add_slave_interface bridges.axi_f2h gpio0.axi_slave0 {0xff708000}
        hps_utils_add_slave_interface bridges.axi_f2h gpio1.axi_slave0 {0xff709000}
        hps_utils_add_slave_interface bridges.axi_f2h gpio2.axi_slave0 {0xff70a000}
        hps_utils_add_slave_interface bridges.axi_f2h i2c0.axi_slave0 {0xffc04000}
        hps_utils_add_slave_interface bridges.axi_f2h i2c1.axi_slave0 {0xffc05000}
        hps_utils_add_slave_interface bridges.axi_f2h i2c2.axi_slave0 {0xffc06000}
        hps_utils_add_slave_interface bridges.axi_f2h i2c3.axi_slave0 {0xffc07000}
        hps_utils_add_slave_interface bridges.axi_f2h nand0.axi_slave0 {0xff900000}
        hps_utils_add_slave_interface bridges.axi_f2h nand0.axi_slave1 {0xffb80000}
        hps_utils_add_slave_interface bridges.axi_f2h spim0.axi_slave0 [hps_spim0_base]
        hps_utils_add_slave_interface bridges.axi_f2h spim1.axi_slave0 [hps_spim1_base]
        hps_utils_add_slave_interface bridges.axi_f2h qspi.axi_slave0 {0xff705000}
        hps_utils_add_slave_interface bridges.axi_f2h qspi.axi_slave1 {0xffa00000}
        hps_utils_add_slave_interface bridges.axi_f2h sdmmc.axi_slave0 {0xff704000}
        hps_utils_add_slave_interface bridges.axi_f2h usb0.axi_slave0 {0xffb00000}
        hps_utils_add_slave_interface bridges.axi_f2h usb1.axi_slave0 {0xffb40000}
        hps_utils_add_slave_interface bridges.axi_f2h gmac0.axi_slave0 {0xff700000}
        hps_utils_add_slave_interface bridges.axi_f2h gmac1.axi_slave0 {0xff702000}
        hps_utils_add_slave_interface bridges.axi_f2h axi_ocram.axi_slave0 {0xffff0000}
        hps_utils_add_slave_interface bridges.axi_f2h axi_sdram.axi_slave0 [hps_sdram_base]
        hps_utils_add_slave_interface bridges.axi_f2h timer.axi_slave0 {0xfffec600}
        hps_utils_add_slave_interface bridges.axi_f2h dcan0.axi_slave0 [hps_dcan0_base]
        hps_utils_add_slave_interface bridges.axi_f2h dcan1.axi_slave0 [hps_dcan1_base]
        hps_utils_add_slave_interface bridges.axi_f2h l3regs.axi_slave0 [hps_l3regs_base]
        hps_utils_add_slave_interface bridges.axi_f2h sdrctl.axi_slave0 [hps_sdrctl_base]
    }

    ##### F2H #####
    if [is_enabled F2SINTERRUPT_Enable] {
	set any_interrupt_enabled 1
	set iname "f2h_irq"
	set pname "f2h_irq"
	    add_interface      "${iname}0"  interrupt receiver
	    set_interface_property f2h_irq0 EXPORT_OF arm_gic_0.f2h_irq_0_irq_rx_offset_40
	    set_interface_property f2h_irq0 PORT_NAME_MAP "f2h_irq_p0 irq_siq_40"

	    add_interface      "${iname}1"  interrupt receiver
	    set_interface_property f2h_irq1 EXPORT_OF arm_gic_0.f2h_irq_32_irq_rx_offset_72
	    set_interface_property f2h_irq1 PORT_NAME_MAP "f2h_irq_p1 irq_siq_72"
    }
}

set_module_property OPAQUE_ADDRESS_MAP false
set_module_property STRUCTURAL_COMPOSITION_CALLBACK compose_logicalview
proc compose_logicalview {} {
    # synchronize device families between the EMIF and HPS parameter sets
    set_parameter_value hps_device_family [get_parameter_value SYS_INFO_DEVICE_FAMILY]
    fpga_interfaces::init
    fpga_interfaces::set_bfm_types [array get DB_bfm_types]
    
    hps_io::init
    validate
    elab 1

    update_hps_to_fpga_clock_frequency_parameters


    fpga_interfaces::serialize fpga_interfaces_data

    add_instance fpga_interfaces altera_interface_generator
    set_instance_parameter_value fpga_interfaces interfaceDefinition [array get fpga_interfaces_data]
    
    expose_border fpga_interfaces $fpga_interfaces_data(interfaces)

    #declare_cmsis_svd $fpga_interfaces_data(interfaces)

    logicalview_dtg
}

proc declare_cmsis_svd {interfaces_str} {
    array set interfaces $interfaces_str
    set interface_names $interfaces([ORDERED_NAMES])
    
    set h2f_exists   0
    set lwh2f_exists 0
    foreach interface_name $interface_names {
	if {[string compare $interface_name "h2f_axi_master"] == 0} {
	    set h2f_exists   1
	} elseif {[string compare $interface_name "h2f_lw_axi_master"] == 0} {
	    set lwh2f_exists 1
	}
    }
    
    set svd_path [file join $::env(QUARTUS_ROOTDIR) .. ip altera hps altera_hps altera_hps.svd]
    set address_group hps
    set declared_svd_file 0

    if {$h2f_exists} {
	if {!$declared_svd_file} {
	    set_interface_property h2f_axi_master CMSIS_SVD_FILE $svd_path
	    set declared_svd_file 1
	}
	set_interface_property h2f_axi_master SVD_ADDRESS_GROUP  $address_group
	set_interface_property h2f_axi_master SVD_ADDRESS_OFFSET 0xC0000000
    }
    if {$lwh2f_exists} {
	if {!$declared_svd_file} {
	    set_interface_property h2f_lw_axi_master CMSIS_SVD_FILE $svd_path
	    set declared_svd_file 1
	}
	set_interface_property h2f_lw_axi_master SVD_ADDRESS_GROUP  $address_group
	set_interface_property h2f_lw_axi_master SVD_ADDRESS_OFFSET 0xFF200000
    }
    if {!$declared_svd_file} {
	set_module_assignment "cmsis.svd.file"   $svd_path
	set_module_assignment "cmsis.svd.suffix" $address_group
    }
}


######################
##### Validation #####
######################

proc validate {} {
    set device_family [get_parameter_value hps_device_family]
    set device [get_device]
    ensure_pin_muxing_data $device_family
    update_table_derived_parameters

    validate_F2SDRAM
    update_S2F_CLK_mux_options
    update_pin_muxing_ui $device_family 

    # funset placement_by_pin
    validate_pin_muxing $device_family placement_by_pin
    update_gpio_ui placement_by_pin

    validate_TEST

    validate_interrupt $device_family
    
    validate_clocks

}

proc validate_TEST {} {
    set ini [get_parameter_value quartus_ini_hps_ip_enable_test_interface]
    set_parameter_property TEST_Enable visible $ini
}

proc hide_param { paramName hide} {

}
proc update_hps_to_fpga_clock_frequency_parameters {} {
    set u0 [get_parameter_value S2FCLK_USER0CLK_Enable]
    set u1 [get_parameter_value S2FCLK_USER1CLK_Enable]
    #set u2 [get_parameter_value S2FCLK_USER2CLK_Enable]

    for { set i 0 } { $i < 2 } { incr i } {
	set_parameter_property "S2FCLK_USER${i}CLK_FREQ" enabled [expr "\$u${i}"]

	if { [string compare true [expr "\$u${i}"] ] == 0 } {
	    fpga_interfaces::set_interface_property "h2f_user${i}_clock" clockRateKnown true
	    fpga_interfaces::set_interface_property "h2f_user${i}_clock" clockRate [expr [get_parameter_value "S2FCLK_USER${i}CLK_FREQ"] * 1000000 ]
	}
    }
}

proc update_table_derived_parameters {} {
    update_f2sdram_names
    update_dma_peripheral_ids
}

proc update_f2sdram_names {} {
    set num_rows [llength [get_parameter_value F2SDRAM_Width]]
    set names [list]
    
    for {set index 0} {$index < $num_rows} {incr index} {
	set name "f2h_sdram${index}"
	lappend names $name
    }
    set_parameter_value F2SDRAM_Name_DERIVED ${names}
}

proc update_dma_peripheral_ids {} {
    set periph_id_list {0 1 2 3 4 5 6 7}
    set_parameter_value DMA_PeriphId_DERIVED $periph_id_list
}

proc is_enabled {parameter} {
    if { [string compare [get_parameter_value $parameter] "true" ] == 0 } {
	return 1
    } else {
	return 0
    }
}

proc validate_F2SDRAM {} {
    set type_list  [get_parameter_value F2SDRAM_Type]
    set width_list [get_parameter_value F2SDRAM_Width]
    set rows [llength $width_list]

    set command_ports_bit 0
    set read_ports_bit    0
    set write_ports_bit   0

    set command_ports_mask 0
    set read_ports_mask    0
    set write_ports_mask   0
    set reset_ports_mask   0
    
    for {set index 0} {${index} < ${rows}} {incr index} {
	# check for invalid combinations of type/width
	set mytype  [lindex $type_list  $index]
	set mywidth [lindex $width_list $index]
	
	if {$mywidth < 64} {
	    send_message warning "Setting the slave port width of interface <b>f2h_sdram${index}</b> to ${mywidth} results in bandwidth under-utilization.  Altera recommends you set the interface data width to 64-bit or greater."
	}

	# count used ports
	# command
	if { [string compare $mytype [F2HSDRAM_AXI3]] == 0 } {
	    if { [ expr $command_ports_bit % 2 ] } {
	        incr command_ports_bit 1
	    }
	    set command_ports_mask [ expr $command_ports_mask | ( 3 << $command_ports_bit) ]
	    incr command_ports_bit 2
	} else {
	    set command_ports_mask [ expr $command_ports_mask | ( 1 << $command_ports_bit) ]
	    incr command_ports_bit 1
	}
	
	# read
	if {$mytype != [F2HSDRAM_AVM_WRITEONLY]} {
	    if {$mywidth <= 64} {
	    set read_ports_mask [ expr $read_ports_mask | ( 1 << $read_ports_bit) ]
		incr read_ports_bit 1
	    } elseif {$mywidth == 128} {
	    set read_ports_mask [ expr $read_ports_mask | ( 3 << $read_ports_bit) ]
		incr read_ports_bit 2
	    } else {
	    set read_ports_mask [ expr $read_ports_mask | ( 15 << $read_ports_bit) ]
		incr read_ports_bit 4
	    }
	}

	# write
	if {$mytype != [F2HSDRAM_AVM_READONLY]} {
	    if {$mywidth <= 64} {
	    set write_ports_mask [ expr $write_ports_mask | ( 1 << $write_ports_bit) ]
		incr write_ports_bit 1
	    } elseif {$mywidth == 128} {
	    set write_ports_mask [ expr $write_ports_mask | ( 3 << $write_ports_bit) ]
		incr write_ports_bit 2
	    } else {
	    set write_ports_mask [ expr $write_ports_mask | ( 15 << $write_ports_bit) ]
		incr write_ports_bit 4
	    }
	}
	
	# reset
	set reset_ports_mask [ expr ($command_ports_mask << 8) | ($write_ports_mask << 4) | ($read_ports_mask) ]
	
    }
    # check for port over-use
    if {$command_ports_bit > 6} {
	send_message error "The current FPGA to SDRAM configuration is using more command ports than are available."
    }
    if {$read_ports_bit > 4} {
	send_message error "The current FPGA to SDRAM configuration is using more read ports than are available."
    }
    if {$write_ports_bit > 4} {
	send_message error "The current FPGA to SDRAM configuration is using more write ports than are available."
    }

    # Store ports used & number of elements to determine when new rows are added
    set_parameter_value F2SDRAM_Width_Last_Size $rows
    set_parameter_value F2SDRAM_CMD_PORT_USED   [ format "0x%X" $command_ports_mask ]
    set_parameter_value F2SDRAM_RD_PORT_USED    [ format "0x%X" $read_ports_mask ]
    set_parameter_value F2SDRAM_WR_PORT_USED    [ format "0x%X" $write_ports_mask ]
    set_parameter_value F2SDRAM_RST_PORT_USED   [ format "0x%X" $reset_ports_mask ]

    # Bonding_out signals will be exported if f2sdram selected
    if { ${rows} > 0 } {
    	set param [get_parameter_value quartus_ini_hps_ip_f2sdram_bonding_out]
    	set_parameter_property BONDING_OUT_ENABLED visible $param
    	set_parameter_property BONDING_OUT_ENABLED enabled $param
    } else {
    	set_parameter_property BONDING_OUT_ENABLED enabled false
    }

}

proc update_S2F_CLK_mux_options {} {
    # TODO: retrieve mux options
    # TODO: set allowed_ranges on muxes
}

proc dec2bin {i} {
    set res {}
    while {$i>0} {
        set res [ expr {$i%2} ]$res
        set i [expr {$i/2}]
    }
    if {$res == {}} {
        set res 0
    }
    return $res
}

#####################################################################
#
# Gets valid modes for a peripheral with a given pin muxing option.
# Parameters: * peripheral_ref: name of an array pointing to the
#                               Peripheral HPS I/O Data
#
# Update parameter value with label 
proc get_valid_modes {peripheral_name pin_muxing_option peripheral_ref fpga_available} {
#####################################################################
    upvar 1 $peripheral_ref peripheral
    
    if {[info exists peripheral(pin_sets)]} {
	array set pin_sets $peripheral(pin_sets)
    }
    
    if {[info exists pin_sets($pin_muxing_option)]} {
	array set pin_set $pin_sets($pin_muxing_option)
	set pin_set_modes $pin_set(valid_modes)
	if {[string match -nocase "trace"  $peripheral_name]} {
	    set valid_modes [list "HPS:8-bit Data" "HPSx4:4-bit Data"]
	} elseif {[string match -nocase "usb*"  $peripheral_name]} {
	    set valid_modes [list "SDR:SDR with PHY clock output mode" "SDR without external clock:SDR with PHY clock input mode"]
	} else {
	    set valid_modes [lsort -ascii -increasing $pin_set_modes]
	}
    } elseif {$fpga_available && [string compare $pin_muxing_option [FPGA_MUX_VALUE]] == 0} {
	set valid_modes [list "Full"]
    } else {
	set valid_modes [list [NA_MODE_VALUE]]
    }
    return $valid_modes
}

proc is_peripheral_low_speed_serial_interface {peripheral_name} {
    if {[string match -nocase "i2c*"  $peripheral_name] ||
	[string match -nocase "can*"  $peripheral_name] ||
	[string match -nocase "spi*"  $peripheral_name] ||
	[string match -nocase "uart*" $peripheral_name]
    } {
	return 1
    }
    return 0
}

# updates the _PinMuxing and _Mode parameter allowed ranges
# -uses a data structure to keep track of choices
# -allowed ranges can come from FPGA Peripheral Interfaces or IOs
# -when a pin muxing option is selected, the mode allowed ranges are
#  set according to what's specified from the source (FPGA or pin i/o)
proc update_pin_muxing_ui {device_family} {
    
    set peripheral_names [list_peripheral_names]
    foreach peripheral $peripheral_names {
	
	get_peripheral_parameter_valid_ranges hps_ip_pin_muxing_model $peripheral\
	    selected_pin_muxing_option pin_muxing_options mode_options
	
	set pin_muxing_param_name [format [PIN_MUX_PARAM_FORMAT] $peripheral]
	set mode_param_name [format [MODE_PARAM_FORMAT] $peripheral]
	
	set pin_muxing_options [lsort -ascii $pin_muxing_options]
	set pin_muxing_options [linsert $pin_muxing_options 0 [UNUSED_MUX_VALUE]]
	set_parameter_property $pin_muxing_param_name enabled true
	set_parameter_property $pin_muxing_param_name visible true
	set_parameter_property $pin_muxing_param_name allowed_ranges $pin_muxing_options
	set_parameter_property $mode_param_name       visible true
	

	set selected_mode_option [get_parameter_value $mode_param_name]
	
	# Disable I2C parameters so they can only be changed by altering EMAC parameters
	# in the HPS IP GUI
	if {([string compare $peripheral "I2C2" ] == 0  || [string compare $peripheral "I2C3" ] == 0)
	    && [string match "*EMAC*" $selected_mode_option]} {
	    set_parameter_property $pin_muxing_param_name enabled false
	    set_parameter_property $mode_param_name       enabled false                                  
	} else {
	    set_parameter_property $mode_param_name enabled true
	}
	set_parameter_property $mode_param_name allowed_ranges $mode_options
	
	# Disabled peripherals that not supported by certain device family
        if {[check_device_family_equivalence $device_family ARRIAV]} {
            foreach excluded_peripheral [ARRIAV_EXCLUDED_PERIPHRERALS] {
                if {[string compare $excluded_peripheral $peripheral] == 0} { 
                    set_parameter_property $pin_muxing_param_name enabled false
	            set_parameter_property $pin_muxing_param_name visible false
	            set_parameter_property $mode_param_name       enabled false
	            set_parameter_property $mode_param_name       visible false
                }
            }
        }
    }
    
    # Only show I2C's "Used by EMACx" modes when EMAC is using I2C
    if {[is_pin_mux_data_available hps_ip_pin_muxing_model]} {
	foreach emac {EMAC0 EMAC1} {
	    set emac_pin_set [get_parameter_value [format [PIN_MUX_PARAM_FORMAT] $emac]]
	    set emac_mode    [get_parameter_value [format    [MODE_PARAM_FORMAT] $emac]]

	    funset i2c_name
	    get_linked_peripheral hps_ip_pin_muxing_model $emac $emac_pin_set\
		i2c_name i2c_pin_set i2c_mode
	    
	    if {[info exists i2c_name] && ![string match "*${i2c_name}*" $emac_mode]} {
		# remove EMAC mode
		set i2c_mode_param  [format [MODE_PARAM_FORMAT] $i2c_name]
		set i2c_valid_modes [get_parameter_property $i2c_mode_param ALLOWED_RANGES]
		
		set new_i2c_valid_modes [list]
		foreach mode $i2c_valid_modes {
		    if {![string match "*${emac}*" $mode]} {
			lappend new_i2c_valid_modes $mode
		    }
		}
		set_parameter_property $i2c_mode_param ALLOWED_RANGES $new_i2c_valid_modes
	    }
	}
    }
}

proc validate_interrupt {device_family} {
    set interrupt_groups [list_h2f_interrupt_groups]
    set excluded "CAN"
    foreach interrupt_group $interrupt_groups {
	set parameter "S2FINTERRUPT_${interrupt_group}_Enable"		
	set_parameter_property $parameter enabled      true
	set_parameter_property $parameter visible      true
	if {[check_device_family_equivalence $device_family ARRIAV] && [string compare $excluded $interrupt_group] == 0} {
			set_parameter_property $parameter enabled      false
			set_parameter_property $parameter visible      false
    	}
    }
}

proc update_gpio_ui {placement_by_pin_ref} {
    upvar 1 $placement_by_pin_ref placement_by_pin
    # TODO: caching of what needs to be updated?
    set customer_pin_names  [list]
    set gpio_names          [list]
    set loanio_names        [list]
    set conflicts           [list]

    set customer_pin_names [hps_ip_pin_muxing_model::get_customer_pin_names]
    
    foreach_gpio_entry hps_ip_pin_muxing_model\
	entry gpio_index gpio_name pin gplin_used gplin_select\
    {
	lappend gpio_names $gpio_name

	set conflict ""
	if {[info exists placement_by_pin($pin)]} {
	    set conflict [join $placement_by_pin($pin) ", "]
	}
	lappend conflicts $conflict
    }
    foreach_loan_io_entry hps_ip_pin_muxing_model\
	entry loanio_index loanio_name pin gplin_used gplin_select\
    {
	lappend loanio_names $loanio_name                
    }             
    set_parameter_value Customer_Pin_Name_DERIVED $customer_pin_names
    set_parameter_value GPIO_Name_DERIVED         $gpio_names
    set_parameter_value LOANIO_Name_DERIVED       $loanio_names
    set_parameter_value GPIO_Conflict_DERIVED     $conflicts
}

proc peripheral_to_wys_atom_name {device_family peripheral} {
    set generic_atom_name [hps_io_peripheral_to_generic_atom_name $peripheral]
    set wys_atom_name [generic_atom_to_wys_atom $device_family $generic_atom_name]
    return $wys_atom_name
}

# TODO: deal with going out of bounds (gpio_index > 70)
proc gpio_index_to_gpio_port_index {gpio_index} {
    set group      [expr {$gpio_index / 29}]
    set port_index [expr {$gpio_index % 29}]

    set result [list $group $port_index]
    return $result
}

                                     

proc validate_pin_muxing {device_family placement_by_pin_ref} {
    upvar 1 $placement_by_pin_ref placement_by_pin

    # see which pins are being used more than once
    # peripherals
    funset pin_to_peripheral ;# pin names to peripheral that is occupying
    funset conflict_pin_list ;
    
    foreach peripheral_name [list_peripheral_names] {
	set pins_used 0
	set mapping_msg "Peripheral $peripheral_name pin mapping:"
	set comma " "
	set periph_inst [string tolower "${peripheral_name}_inst"]
	foreach_used_peripheral_pin hps_ip_pin_muxing_model $peripheral_name\
	    signal_name\
	    map\
	    pin\
	    location\
	    mux_select\
	{
	    # Validate
	    set entry_exists [info exists pin_to_peripheral($pin)]
	    if {$entry_exists == 1} {
		set conflicting_peripheral $pin_to_peripheral($pin)
		# only emit an error once per unique pair of conflicting peripherals
		if {[info exists known_conflicts($conflicting_peripheral)] == 0} {
		    set known_conflicts($conflicting_peripheral) 1
		    # TODO: more detailed error message e.g. which pins? explicitly say the bank and modes?
		    send_message error "Refer to the Peripherals Mux Table for more details. The selected peripherals '$conflicting_peripheral' and '$peripheral_name' are conflicting. "	 
		}
		set conflict_pin_list($pin) 1
	    } else {
		set pin_to_peripheral($pin) $peripheral_name
	    }
	    
	    # Render pins
	    lassign $map in_port out_port oe_port
	    set goes_out 0
	    set goes_in 0

	    # by default, all signals are assumed to be from the same instance
	    if {$in_port != ""} {
		set in_port "${periph_inst}:${in_port}"
		set goes_in 1
	    }
	    if {$out_port != ""} {
		set out_port "${periph_inst}:${out_port}"
		set goes_out 1
	    }
	    if {$oe_port != ""} {
		set oe_port "${periph_inst}:${oe_port}"
		set goes_out 1
	    }

	    if {$goes_in && $goes_out} {
		set dir bidir
	    } elseif {$goes_out} {
		set dir output
	    } else {
		set dir input
	    } 
	    
	    hps_io::add_pin $periph_inst $signal_name $dir $location $in_port $out_port $oe_port

	    if {[info exists placement_by_pin($pin)] == 0} {             
		set placement_by_pin($pin) [list]          
	    }
	    lappend placement_by_pin($pin) "${peripheral_name}.${signal_name}"

	    set mapping_msg "${mapping_msg}${comma}${signal_name}:${pin}"
	    set comma ", "
	    set pins_used 1
	}
	if {$pins_used} {
	    # send_message info $mapping_msg
	    set wys_atom_name [peripheral_to_wys_atom_name $device_family $peripheral_name]
	    set location [locations::get_hps_io_peripheral_location $peripheral_name]
	    hps_io::add_peripheral ${periph_inst} $wys_atom_name $location
	}
    }
    
    # HLGPI input only pins
    set hlgpi_pins [hps_ip_pin_muxing_model::get_hlgpi_pins]
    set hlgpi_count [llength $hlgpi_pins]
    set wys_atom_name [peripheral_to_wys_atom_name $device_family "GPIO"]
    set periph_inst "gpio_inst"
    set gpio_unused 1
    set device [get_device]
    
    if { [ string range $device 0 3 ] == "5CSE" && [ string range $device 8 9 ] == "19" } {
    	send_message info "HLGPI is not available for Device $device (484 pins)"    
        set_parameter_property   HLGPI_Enable      enabled        false
    } else {
        set_parameter_property   HLGPI_Enable      enabled        true
    }
    
    if { [is_enabled HLGPI_Enable] && [get_parameter_property HLGPI_Enable enabled] } {
        for {set hlgpi_pin_index 0} {$hlgpi_pin_index < $hlgpi_count} {incr hlgpi_pin_index} {    
            # HLGPI connected to gpio[26:13]
            set gpio_port_index [ expr {$hlgpi_pin_index + 13} ]     
            set hlgpi_pin       [ lindex $hlgpi_pins $hlgpi_pin_index]
        	
            if {$gpio_unused} {
                set atom_location [locations::get_hps_io_peripheral_location "GPIO"]
                hps_io::add_peripheral ${periph_inst} $wys_atom_name $atom_location
                set gpio_unused 0
            }
            
            set signal_name "HLGPI${hlgpi_pin_index}"
            set pin_location [::pin_mux_db::get_location_of_pin $hlgpi_pin]
            set in_port  "${periph_inst}:GPIO2_PORTA_I($gpio_port_index:$gpio_port_index)"
            set out_port ""
            set oe_port  ""
          
            hps_io::add_pin ${periph_inst} $signal_name input $pin_location $in_port $out_port $oe_port
        }
    }
                                                  
    # gpio
    funset gpio_port_placement_set ;# set of gpio ports that are being used
    set enable_list [get_parameter_value GPIO_Enable]
    set wys_atom_name [peripheral_to_wys_atom_name $device_family "GPIO"]
    set periph_inst "gpio_inst"
    
    # check and set GPIO_Pin_Used_DERIVED parameter 
    set_parameter_value GPIO_Pin_Used_DERIVED false
    
    foreach_gpio_entry hps_ip_pin_muxing_model\
	entry gpio_index gpio_name pin gplin_used gplin_select\
    {
	set enabled 0                          
	set enable_value  [lindex $enable_list $entry]
	if { [string compare $enable_value "Yes" ] == 0 } {
	    set enabled 1
	}
	if {$enabled} {
	    set entry_exists [info exists pin_to_peripheral($pin)]
	    if {$entry_exists} {
		set conflicting_peripheral $pin_to_peripheral($pin)
		send_message error "Refer to the Peripherals Mux Table for more details. The selected peripheral '$conflicting_peripheral' and '${gpio_name}' are conflicting."
		set conflict_pin_list($pin) 1
	    } else {
		set pin_to_peripheral($pin) $gpio_name
	    }

	    if {[info exists gpio_port_placement_set($gpio_index)]} {
		send_message error "Refer to the Peripherals Mux Table for more details. GPIO${gpio_index} cannot be used twice."
		set conflict_pin_list($pin) 1
	    } else {
		set gpio_port_placement_set($gpio_index) 1
	    }
	    
	    if {$gpio_unused} {
		set atom_location [locations::get_hps_io_peripheral_location "GPIO"]
		hps_io::add_peripheral ${periph_inst} $wys_atom_name $atom_location
		set gpio_unused 0
	    }
	    
	    lassign [gpio_index_to_gpio_port_index $gpio_index] gpio_group gpio_port_index
	    set in_port  "${periph_inst}:GPIO${gpio_group}_PORTA_I($gpio_port_index:$gpio_port_index)"
	    set out_port "${periph_inst}:GPIO${gpio_group}_PORTA_O($gpio_port_index:$gpio_port_index)"
	    set oe_port  "${periph_inst}:GPIO${gpio_group}_PORTA_OE($gpio_port_index:$gpio_port_index)"

	    set pin_location [::pin_mux_db::get_location_of_pin $pin]
	    hps_io::add_pin $periph_inst $gpio_name bidir $pin_location $in_port $out_port $oe_port
	    
	    # set GPIO_Pin_Used_DERIVED to true if GPIO pins used 
	    set_parameter_value GPIO_Pin_Used_DERIVED true
	}
    }
    
    # loan i/o
    set enable_list [get_parameter_value LOANIO_Enable]
    set loanio_used 0
    set loanio_count 0
    foreach_loan_io_entry hps_ip_pin_muxing_model\
        entry loanio_index loanio_name pin gplin_used gplin_select\
    {
        if {$loanio_count < $loanio_index} {
    	set loanio_count $loanio_index
        }
        set enabled 0
        set enable_value  [lindex $enable_list $entry]
        if { [string compare $enable_value "Yes" ] == 0 } {
    	set enabled 1
        }
        
        if {$enabled} {
    	set entry_exists [info exists pin_to_peripheral($pin)]
    	if {$entry_exists} {
    	    set conflicting_peripheral $pin_to_peripheral($pin)
    	    send_message error "Refer to the Peripherals Mux Table for more details. The selected peripheral for '$conflicting_peripheral' and '${loanio_name}' are conflicting."
    	    set conflict_pin_list($pin) 1
    	} else {
    	    set pin_to_peripheral($pin) $loanio_name
    	}
    
    	if {[info exists gpio_port_placement_set($loanio_index)]} {
    	    send_message error "Refer to the Peripherals Mux Table for more details. GPIO${loanio_index} cannot be used twice."
    	    set conflict_pin_list($pin) 1
    	} else {
    	    set gpio_port_placement_set($loanio_index) 1
    	}
    	
    	set loanio_used 1
    	if {$gpio_unused} {
    	    set atom_location [locations::get_hps_io_peripheral_location "GPIO"]
    	    hps_io::add_peripheral ${periph_inst} $wys_atom_name $atom_location
    	    set gpio_unused 0
    	}
    	
    	lassign [gpio_index_to_gpio_port_index $loanio_index] gpio_group gpio_port_index
    	set in_port  "${periph_inst}:GPIO${gpio_group}_PORTA_I($gpio_port_index:$gpio_port_index)"
    	set out_port "${periph_inst}:GPIO${gpio_group}_PORTA_O($gpio_port_index:$gpio_port_index)"
    	set oe_port  "${periph_inst}:GPIO${gpio_group}_PORTA_OE($gpio_port_index:$gpio_port_index)"
    	
    	set pin_location [::pin_mux_db::get_location_of_pin $pin]
    	hps_io::add_pin $periph_inst $loanio_name bidir $pin_location $in_port $out_port $oe_port
    	
        }
    }     
    incr loanio_count ;# count is one greater than the highest index
    if $loanio_used {
        set wys_atom_name [peripheral_to_wys_atom_name $device_family "LOANIO"]
        set location {}
        set periph_inst "loan_io_inst"
        set iface_name  "h2f_loan_io"
        set z           "h2f_loan_"
        fpga_interfaces::add_module_instance ${periph_inst} $wys_atom_name $location
        fpga_interfaces::add_interface       $iface_name conduit Input
        set pin_muxing   [get_parameter_value pin_muxing]
        fpga_interfaces::add_interface_port  $iface_name "${z}in"  in  Output ${loanio_count}  $periph_inst loanio_in
        fpga_interfaces::add_interface_port  $iface_name "${z}out" out Input  ${loanio_count}  $periph_inst loanio_out
        fpga_interfaces::add_interface_port  $iface_name "${z}oe"  oe  Input  ${loanio_count}  $periph_inst loanio_oe
        
        # add loanIO to GPIO atom connection
        set loanio_periph_inst  "loan_io_inst"
        set loanio_iface_name   "loanio_gpio"
        set loanio_z            "loanio_gpio_"
        set gpio_periph_inst    "gpio_inst"
        set gpio_iface_name     "gpio_loanio"
        set gpio_z              "gpio_loanio_"
        set gpio_port_size 29
        set start_index 0
        
        if {$gpio_unused} {
            set gpio_wys_atom_name [peripheral_to_wys_atom_name $device_family "GPIO"]
            set gpio_atom_location [locations::get_hps_io_peripheral_location "GPIO"]
            hps_io::add_peripheral ${gpio_periph_inst} ${gpio_wys_atom_name} ${gpio_atom_location}
            set gpio_unused 0
        }
        
        fpga_interfaces::add_interface       $loanio_iface_name conduit Input "NO_EXPORT"
        ::hps_io::internal::add_interface $gpio_iface_name conduit Output "NO_EXPORT"
        
        for {set i 0} {$i <= 2} {incr i} {
            if {[expr ($loanio_count - $start_index)] < $gpio_port_size} {
                set gpio_port_size [expr ($loanio_count - $start_index)]
            }
            set end_index   [expr ($start_index + $gpio_port_size - 1)]
            
            fpga_interfaces::add_interface_port  $loanio_iface_name "${loanio_z}loanio${i}_i"  "loanio${i}_i"  Input  ${gpio_port_size}
            fpga_interfaces::add_interface_port  $loanio_iface_name "${loanio_z}loanio${i}_oe" "loanio${i}_oe" Output ${gpio_port_size}
            fpga_interfaces::add_interface_port  $loanio_iface_name "${loanio_z}loanio${i}_o"  "loanio${i}_o"  Output ${gpio_port_size}
            
            fpga_interfaces::set_port_fragments  $loanio_iface_name "${loanio_z}loanio${i}_i"  "${loanio_periph_inst}:GPIO_IN($end_index:$start_index)"
            fpga_interfaces::set_port_fragments  $loanio_iface_name "${loanio_z}loanio${i}_oe" "${loanio_periph_inst}:GPIO_OE($end_index:$start_index)"
            fpga_interfaces::set_port_fragments  $loanio_iface_name "${loanio_z}loanio${i}_o"  "${loanio_periph_inst}:GPIO_OUT($end_index:$start_index)"
            
            ::hps_io::internal::add_interface_port  $gpio_iface_name "${gpio_z}loanio${i}_i"  "loanio${i}_i"  Output ${gpio_port_size}  $gpio_periph_inst "LOANIO${i}_I"
            ::hps_io::internal::add_interface_port  $gpio_iface_name "${gpio_z}loanio${i}_oe" "loanio${i}_oe" Input ${gpio_port_size}   $gpio_periph_inst  "LOANIO${i}_OE"
            ::hps_io::internal::add_interface_port  $gpio_iface_name "${gpio_z}loanio${i}_o"  "loanio${i}_o"  Input  ${gpio_port_size}  $gpio_periph_inst "LOANIO${i}_O"
            
            set start_index [expr ($end_index + 1)]
        }
    }
     set conflicts           [list]
    set pins           [list]
    foreach_gpio_entry hps_ip_pin_muxing_model\
    entry gpio_index gpio_name pin gplin_used gplin_select\
    {
        set entry_exists [info exists conflict_pin_list($pin)]
        if {$entry_exists} {
            set conflict "Yes"
        } else {                              
            set conflict "No"
        }
        lappend conflicts $conflict
        lappend pins $pin
    }
   set_parameter_value JAVA_CONFLICT_PIN $conflicts
  set_parameter_value JAVA_GUI_PIN_LIST $pins
}
                                                                                     
#####################################################
#
# Sets a valid mode for the peripheral when its pin
# muxing option changes. Will try to retain the
# original mode if available.
#                                                                                                                                            
proc on_altered_peripheral_pin_muxing {peripheral_name} {
#####################################################
    set mode_param_name       "${peripheral_name}_Mode"
    set mode_option       [get_parameter_value $mode_param_name]                  

    get_peripheral_parameter_valid_ranges hps_ip_pin_muxing_model $peripheral_name\
	selected_pin_muxing_option pin_muxing_options new_valid_modes   
    
    # filter the label name of the parameter value if exist
    if {[lsearch $new_valid_modes $mode_option] == -1} {
	regsub ":.*" [lindex $new_valid_modes 0] "" new_mode_option
    } else {
	set new_mode_option $mode_option
    }
    set_parameter_value $mode_param_name $new_mode_option
    
    if {[string match "*EMAC*" $peripheral_name]} {
	on_emac_mode_switch_internal $peripheral_name
    }
}

# Adds the pin muxing model argument
proc on_emac_mode_switch_internal {peripheral_name} {
    on_emac_mode_switch hps_ip_pin_muxing_model $peripheral_name
}

proc validate_and_update_ddr {} {
    set desired_operational_freq [get_parameter_value DDR_DesiredFreq]
    if {$desired_operational_freq < 0.0} {
	send_message error "The operational frequency of the DDR Controller cannot be negative."
    } else {
	send_message warning "The recommended DDR Controller clock frequency and phase shift information is not correct."

	set_parameter_value DDR_PLLC0RecommendedFreq_DERIVED $desired_operational_freq
	set_parameter_value DDR_PLLC1RecommendedFreq_DERIVED [expr $desired_operational_freq * 2.0]
	set_parameter_value DDR_PLLC2RecommendedFreq_DERIVED $desired_operational_freq
	set_parameter_value DDR_PLLC3RecommendedFreq_DERIVED $desired_operational_freq

	set_parameter_value DDR_PLLC0RecommendedPhase_DERIVED 0.0
	set_parameter_value DDR_PLLC1RecommendedPhase_DERIVED 1.0
	set_parameter_value DDR_PLLC2RecommendedPhase_DERIVED 2.0
	set_parameter_value DDR_PLLC3RecommendedPhase_DERIVED 3.0
    }

    for {set index 0} {${index} < 4} {incr index} {
	set p_name "DDR_PLLC${index}ActualFreq"
	set value [get_parameter_value $p_name]
	if {$value < 0.0} {
	    send_message error "DDR PLL Output C${index} cannot have a negative clock frequency."
	}

	set p_name "DDR_PLLC${index}ActualPhase"
	set value [get_parameter_value $p_name]
	if {$value < 0.0} {
	    send_message error "DDR PLL Output C${index} cannot have a negative clock phase shift."
	}
    }
}


######################
##### Elaboration #####
######################

proc elab {logical_view} {
    # TODO: add RTL information for each
    set device_family [get_parameter_value hps_device_family]

    elab_clocks_resets		  $device_family
    
    elab_MPU_EVENTS               $device_family
    elab_DEBUGAPB                 $device_family
    elab_STM                      $device_family
    elab_CTI			  $device_family
    elab_TPIUFPGA                 $device_family
    elab_GP			  $device_family
    elab_BOOTFROMFPGA		  $device_family
    
    if {$logical_view == 0} {
        elab_F2S			  $device_family
        elab_LWH2F			  $device_family
        elab_S2F			  $device_family
        elab_F2SDRAM		  $device_family
        
    }

    elab_DMA			  $device_family
    elab_INTERRUPTS		  $device_family $logical_view

    elab_emac_ptp          $device_family

    elab_TEST                     $device_family

    # Handle Special Case EMAC signal... ptp_ref_clk
    set emac0_pin_mux_param_name [format [PIN_MUX_PARAM_FORMAT] EMAC0]
    set emac1_pin_mux_param_name [format [PIN_MUX_PARAM_FORMAT] EMAC1]
    set emac0_pin_mux_value [get_parameter_value $emac0_pin_mux_param_name]
    set emac1_pin_mux_value [get_parameter_value $emac1_pin_mux_param_name]
    set emac0_pin_mux_allowed_ranges [get_parameter_property $emac0_pin_mux_param_name allowed_ranges]
    set emac1_pin_mux_allowed_ranges [get_parameter_property $emac1_pin_mux_param_name allowed_ranges]

    set emac0_ptp_enabled [expr {[string compare $emac0_pin_mux_value [FPGA_MUX_VALUE]] == 0 && [lsearch $emac0_pin_mux_allowed_ranges [FPGA_MUX_VALUE]] != -1}]
    set emac1_ptp_enabled [expr {[string compare $emac1_pin_mux_value [FPGA_MUX_VALUE]] == 0 && [lsearch $emac1_pin_mux_allowed_ranges [FPGA_MUX_VALUE]] != -1}]
    
    set emac0_io_enabled [expr {[string compare $emac0_pin_mux_value "HPS I/O Set 0"] == 0 && [lsearch $emac0_pin_mux_allowed_ranges "HPS I/O Set 0"] != -1}]
    set emac1_io_enabled [expr {[string compare $emac1_pin_mux_value "HPS I/O Set 0"] == 0 && [lsearch $emac1_pin_mux_allowed_ranges "HPS I/O Set 0"] != -1}]
    
    set emac0_ptp           [get_parameter_value EMAC0_PTP]
    set emac1_ptp           [get_parameter_value EMAC1_PTP]
    
    if {$emac0_ptp &&  $emac0_io_enabled} {
        set emac0_ptp_enabled 1
    }
    if {$emac1_ptp &&  $emac1_io_enabled} {
        set emac1_ptp_enabled 1
    }
    
    if {$emac0_ptp_enabled || $emac1_ptp_enabled } {
        set instance_name clocks_resets
        fpga_interfaces::add_interface      emac_ptp_ref_clock                    clock  Input
        fpga_interfaces::add_interface_port emac_ptp_ref_clock  emac_ptp_ref_clk  clk    Input  1     $instance_name ptp_ref_clk
    }

    # TODO: elab peripherals that mux signals to the fpga
    elab_FPGA_Peripheral_Signals  $device_family

	set_parameter_value DEVICE_FAMILY [get_parameter_value SYS_INFO_DEVICE_FAMILY]
}

proc elab_MPU_EVENTS {device_family} {
    if [is_enabled MPU_EVENTS_Enable] {
	set instance_name mpu_events
	set atom_name hps_interface_mpu_event_standby
	set location [locations::get_fpga_location $instance_name $atom_name]
	
	set iface_name "h2f_mpu_events"
	set z          "h2f_mpu_"
	fpga_interfaces::add_interface       $iface_name conduit Input
	fpga_interfaces::add_interface_port  $iface_name ${z}eventi      eventi      Input  1  $instance_name eventi
	fpga_interfaces::add_interface_port  $iface_name ${z}evento      evento      Output 1  $instance_name evento
	fpga_interfaces::add_interface_port  $iface_name ${z}standbywfe  standbywfe  Output 2  $instance_name standbywfe
	fpga_interfaces::add_interface_port  $iface_name ${z}standbywfi  standbywfi  Output 2  $instance_name standbywfi

	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

proc elab_DEBUGAPB {device_family} {
    set instance_name debug_apb
    set atom_name hps_interface_dbg_apb
    set location [locations::get_fpga_location $instance_name $atom_name]
    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    
    if [is_enabled DEBUGAPB_Enable] {
	set clock_name "h2f_debug_apb_clock"
	fpga_interfaces::add_interface       $clock_name clock Input
	fpga_interfaces::add_interface_port  $clock_name "h2f_dbg_apb_clk"  clk Input 1 $instance_name P_CLK

	set reset_name "h2f_debug_apb_reset"
	fpga_interfaces::add_interface           $reset_name reset Output
	fpga_interfaces::add_interface_port      $reset_name "h2f_dbg_apb_rst_n"  reset_n Output 1 $instance_name P_RESET_N
	fpga_interfaces::set_interface_property  $reset_name associatedClock $clock_name
	
	set iface_name "h2f_debug_apb"
	set z          "h2f_dbg_apb_"
	fpga_interfaces::add_interface               $iface_name apb master
	fpga_interfaces::add_interface_port  $iface_name "${z}PADDR"           paddr           Output 18 $instance_name P_ADDR
	fpga_interfaces::add_interface_port  $iface_name "${z}PADDR31"         paddr31         Output 1  $instance_name P_ADDR_31
	fpga_interfaces::add_interface_port  $iface_name "${z}PENABLE"         penable         Output 1  $instance_name P_ENABLE
	fpga_interfaces::add_interface_port  $iface_name "${z}PRDATA"          prdata          Input  32 $instance_name P_RDATA
	fpga_interfaces::add_interface_port  $iface_name "${z}PREADY"          pready          Input  1  $instance_name P_READY
	fpga_interfaces::add_interface_port  $iface_name "${z}PSEL"            psel            Output 1  $instance_name P_SEL
	fpga_interfaces::add_interface_port  $iface_name "${z}PSLVERR"         pslverr         Input  1  $instance_name P_SLV_ERR
	fpga_interfaces::add_interface_port  $iface_name "${z}PWDATA"          pwdata          Output 32 $instance_name P_WDATA
	fpga_interfaces::add_interface_port  $iface_name "${z}PWRITE"          pwrite          Output 1  $instance_name P_WRITE
	fpga_interfaces::set_interface_property      $iface_name associatedClock $clock_name
	fpga_interfaces::set_interface_property      $iface_name associatedReset $reset_name

	set iface_name "h2f_debug_apb_sideband"
	set z          "h2f_dbg_apb_"
	fpga_interfaces::add_interface       $iface_name conduit Input
	fpga_interfaces::add_interface_port  $iface_name "${z}PCLKEN"          pclken          Input  1  $instance_name P_CLK_EN
	fpga_interfaces::add_interface_port  $iface_name "${z}DBG_APB_DISABLE" dbg_apb_disable Input  1  $instance_name DBG_APB_DISABLE
	fpga_interfaces::set_interface_property      $iface_name associatedClock $clock_name
	fpga_interfaces::set_interface_property      $iface_name associatedReset $reset_name

    } else {
	# Tie low when FPGA debug apb not being used
	fpga_interfaces::set_instance_port_termination ${instance_name} "P_CLK_EN" 1 0 0:0 0
	fpga_interfaces::set_instance_port_termination ${instance_name} "DBG_APB_DISABLE" 1 0 0:0 0
    }
}

proc elab_STM {device_family} {
    if [is_enabled STM_Enable] {
	set instance_name stm_event
	set atom_name hps_interface_stm_event
	set location [locations::get_fpga_location $instance_name $atom_name]
	
	fpga_interfaces::add_interface       f2h_stm_hw_events conduit Input
	fpga_interfaces::add_interface_port  f2h_stm_hw_events f2h_stm_hwevents stm_hwevents Input 28  $instance_name stm_event

	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

proc elab_CTI {device_family} {
    set instance_name cross_trigger_interface
    set atom_name hps_interface_cross_trigger
    set location [locations::get_fpga_location $instance_name $atom_name]

    if [is_enabled CTI_Enable] {
	set iface_name "h2f_cti"
	set z          "h2f_cti_"
	fpga_interfaces::add_interface          $iface_name conduit Input
	fpga_interfaces::add_interface_port     $iface_name ${z}trig_in         trig_in         Input  8 $instance_name trig_in
	fpga_interfaces::add_interface_port     $iface_name ${z}trig_in_ack     trig_in_ack     Output 8 $instance_name trig_inack
	fpga_interfaces::add_interface_port     $iface_name ${z}trig_out        trig_out        Output 8 $instance_name trig_out
	fpga_interfaces::add_interface_port     $iface_name ${z}trig_out_ack    trig_out_ack    Input  8 $instance_name trig_outack
	# case:105603 hide asicctl output signal
	# fpga_interfaces::add_interface_port     $iface_name ${z}asicctl         asicctl         Output 8 $instance_name asicctl
	fpga_interfaces::add_interface_port     $iface_name ${z}fpga_clk_en     fpga_clk_en Input  1 $instance_name clk_en
	fpga_interfaces::set_interface_property $iface_name associatedClock h2f_cti_clock
	fpga_interfaces::set_interface_property $iface_name associatedReset h2f_reset

	fpga_interfaces::add_interface       h2f_cti_clock  clock Input
	fpga_interfaces::add_interface_port  h2f_cti_clock  h2f_cti_clk clk Input 1                 $instance_name clk

	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

proc elab_TPIUFPGA {device_family} {
    set instance_name tpiu
    set atom_name hps_interface_tpiu_trace
    set location [locations::get_fpga_location $instance_name $atom_name]

    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location

    if { [string compare [get_parameter_value TPIUFPGA_Enable] "true" ] == 0 } {
    	set_parameter_property   TPIUFPGA_alt   enabled        true
	set iface_name "h2f_tpiu"
	set z          "h2f_tpiu_"
	fpga_interfaces::add_interface       $iface_name conduit input
	fpga_interfaces::add_interface_port  $iface_name ${z}clk_ctl   clk_ctl  Input  1  $instance_name traceclk_ctl
	fpga_interfaces::add_interface_port  $iface_name ${z}data      data     Output 32 $instance_name trace_data
    	
    	# case 245159
    	if {[string compare [get_parameter_value TPIUFPGA_alt] "true" ] == 0} {
	    fpga_interfaces::add_interface_port  $iface_name ${z}clkin    clkin      Input  1  $instance_name traceclkin
    	} else {
	    set iface_name "h2f_tpiu_clock_in"
	    fpga_interfaces::add_interface       $iface_name clock input
	    fpga_interfaces::add_interface_port  $iface_name ${z}clk_in    clk      Input  1  $instance_name traceclkin
	}

	set clock_in_rate [get_parameter_value H2F_TPIU_CLOCK_IN_FREQ]
	set clock_rate [expr {$clock_in_rate / 2}]
	set iface_name "h2f_tpiu_clock"
       	fpga_interfaces::add_interface          $iface_name clock output
	fpga_interfaces::add_interface_port     $iface_name ${z}clk       clk      Output 1  $instance_name traceclk
	fpga_interfaces::set_interface_property $iface_name clockRateKnown true
	fpga_interfaces::set_interface_property $iface_name clockRate $clock_rate

	add_clock_constraint_if_valid $clock_rate "*|fpga_interfaces|${instance_name}|traceclk"

    } else {
    	set_parameter_property   TPIUFPGA_alt   enabled        false
	fpga_interfaces::set_instance_port_termination ${instance_name} "traceclk_ctl" 1 1 0:0 1
    }
}

proc elab_GP {device_family} {
    if [is_enabled GP_Enable] {
	set instance_name h2f_gp
	set atom_name hps_interface_mpu_general_purpose
	set location [locations::get_fpga_location $instance_name $atom_name]
	
	set iface_name "h2f_gp"
	set z          "h2f_gp_"
	fpga_interfaces::add_interface       $iface_name  conduit Input
	fpga_interfaces::add_interface_port  $iface_name  ${z}in   gp_in  Input  32  $instance_name gp_in
	fpga_interfaces::add_interface_port  $iface_name  ${z}out  gp_out Output 32  $instance_name gp_out

	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

proc elab_BOOTFROMFPGA {device_family} {
    set instance_name boot_from_fpga
    set atom_name hps_interface_boot_from_fpga
    set location [locations::get_fpga_location $instance_name $atom_name]
    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    
    set bsel_en               [expr { [string compare [get_parameter_value BSEL_EN] "true" ] == 0 } ]
    set bsel                  [get_parameter_value BSEL]
    set csel_en               [expr { [string compare [get_parameter_value CSEL_EN] "true" ] == 0 } ]
    set csel                  [get_parameter_value CSEL]
    set boot_from_fpga_enable [expr { [string compare [get_parameter_value BOOTFROMFPGA_Enable] "true" ] == 0 } ]            
    set ini_string            [get_parameter_value quartus_ini_hps_ip_enable_bsel_csel]
    set ini_enabled           [expr { [string compare $ini_string "true" ] == 0 } ]
                                                                                                  
    # force disable bsel/csel by default
    if {!$ini_enabled} {
	set bsel_en 0
	set bsel    1                                                                            
	set csel_en 0
	set csel    1
    }

    # when INI enabled, the controls should appear in the GUI
    foreach parameter {BSEL BSEL_EN CSEL CSEL_EN} {
	set_parameter_property $parameter visible $ini_string
	set_parameter_property $parameter enabled $ini_string
    }
    
    fpga_interfaces::set_instance_port_termination ${instance_name} "bsel" 3 0 2:0 $bsel
    fpga_interfaces::set_instance_port_termination ${instance_name} "csel" 2 0 1:0 $csel
    
    if {$bsel_en} {
        fpga_interfaces::set_instance_port_termination ${instance_name} "bsel_en" 1 0 0:0 1
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "bsel_en" 1 0 0:0 0
    }

    if {$csel_en} {
	fpga_interfaces::set_instance_port_termination ${instance_name} "csel_en" 1 0 0:0 1
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "csel_en" 1 0 0:0 0
    }
    
    if {$boot_from_fpga_enable} {
	set iface_name "f2h_boot_from_fpga"
	set z          "f2h_boot_from_fpga_"
	fpga_interfaces::add_interface       $iface_name  conduit Input
	fpga_interfaces::add_interface_port  $iface_name  "${z}ready"       boot_from_fpga_ready       Input 1  $instance_name boot_from_fpga_ready
	fpga_interfaces::add_interface_port  $iface_name  "${z}on_failure"  boot_from_fpga_on_failure  Input 1  $instance_name boot_from_fpga_on_failure
    } else {
        fpga_interfaces::set_instance_port_termination ${instance_name} "boot_from_fpga_ready" 1 0 0:0 0
        fpga_interfaces::set_instance_port_termination ${instance_name} "boot_from_fpga_on_failure" 1 0 0:0 0
    }
    
    if {$boot_from_fpga_enable} {
        send_message info "Ensure that valid Cortex A9 boot code is available to the HPS system when enabling boot from FPGA and h2f_axi_master interface is connecting to slave component start at address 0x0."
    }
    
    if {$bsel_en && $bsel == 1 && !$boot_from_fpga_enable} {
        send_message warning "Boot from FPGA ready must be enabled to correctly boot from the FPGA." 
    } 
}


proc elab_F2S {device_family} {
    set instance_name fpga2hps
    set atom_name hps_interface_fpga2hps
    set location [locations::get_fpga_location $instance_name $atom_name]
    set termination_value 3

    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    
    set addr_width 32
    set width [get_parameter_value F2S_Width]
    if {$width > 0} {
	set data_width 32
	set strb_width 4
	set termination_value 0
	if {$width == 2} {
	    set data_width 64
	    set strb_width 8
	    set termination_value 1
	} elseif {$width == 3} {
	    set data_width 128
	    set strb_width 16
	    set termination_value 2
	}

	set clock_name "f2h_axi_clock"
	fpga_interfaces::add_interface       $clock_name   clock              Input
	fpga_interfaces::add_interface_port  $clock_name   f2h_axi_clk        clk      Input  1    $instance_name clk
	
	set iface_name "f2h_axi_slave"
	set z          "f2h_"
   
	fpga_interfaces::add_interface               $iface_name axi slave
	fpga_interfaces::set_interface_property      $iface_name associatedClock $clock_name
	fpga_interfaces::set_interface_property      $iface_name associatedReset h2f_reset
	fpga_interfaces::set_interface_property      $iface_name readAcceptanceCapability 8
	fpga_interfaces::set_interface_property      $iface_name writeAcceptanceCapability 8
	fpga_interfaces::set_interface_property      $iface_name combinedAcceptanceCapability 16
	fpga_interfaces::set_interface_property      $iface_name readDataReorderingDepth 16
	fpga_interfaces::set_interface_meta_property $iface_name data_width $data_width
	fpga_interfaces::set_interface_meta_property $iface_name address_width $addr_width

	fpga_interfaces::add_interface_port  $iface_name ${z}AWID     awid     Input  8           $instance_name awid
	fpga_interfaces::add_interface_port  $iface_name ${z}AWADDR   awaddr   Input  $addr_width $instance_name awaddr
	fpga_interfaces::add_interface_port  $iface_name ${z}AWLEN    awlen    Input  4           $instance_name awlen
	fpga_interfaces::add_interface_port  $iface_name ${z}AWSIZE   awsize   Input  3           $instance_name awsize
	fpga_interfaces::add_interface_port  $iface_name ${z}AWBURST  awburst  Input  2           $instance_name awburst
	fpga_interfaces::add_interface_port  $iface_name ${z}AWLOCK   awlock   Input  2           $instance_name awlock
	fpga_interfaces::add_interface_port  $iface_name ${z}AWCACHE  awcache  Input  4           $instance_name awcache
	fpga_interfaces::add_interface_port  $iface_name ${z}AWPROT   awprot   Input  3           $instance_name awprot
	fpga_interfaces::add_interface_port  $iface_name ${z}AWVALID  awvalid  Input  1           $instance_name awvalid
	fpga_interfaces::add_interface_port  $iface_name ${z}AWREADY  awready  Output 1           $instance_name awready
	fpga_interfaces::add_interface_port  $iface_name ${z}AWUSER   awuser   Input  5           $instance_name awuser

	fpga_interfaces::add_interface_port  $iface_name ${z}WID      wid      Input  8           $instance_name wid
	fpga_interfaces::add_interface_port  $iface_name ${z}WDATA    wdata    Input  $data_width $instance_name wdata
	fpga_interfaces::add_interface_port  $iface_name ${z}WSTRB    wstrb    Input  $strb_width $instance_name wstrb
	fpga_interfaces::add_interface_port  $iface_name ${z}WLAST    wlast    Input  1           $instance_name wlast
	fpga_interfaces::add_interface_port  $iface_name ${z}WVALID   wvalid   Input  1           $instance_name wvalid
	fpga_interfaces::add_interface_port  $iface_name ${z}WREADY   wready   Output 1           $instance_name wready

	fpga_interfaces::add_interface_port  $iface_name ${z}BID      bid      Output 8           $instance_name bid
	fpga_interfaces::add_interface_port  $iface_name ${z}BRESP    bresp    Output 2           $instance_name bresp
	fpga_interfaces::add_interface_port  $iface_name ${z}BVALID   bvalid   Output 1           $instance_name bvalid
	fpga_interfaces::add_interface_port  $iface_name ${z}BREADY   bready   Input  1           $instance_name bready


	fpga_interfaces::add_interface_port  $iface_name ${z}ARID     arid     Input  8           $instance_name arid
	fpga_interfaces::add_interface_port  $iface_name ${z}ARADDR   araddr   Input  $addr_width $instance_name araddr
	fpga_interfaces::add_interface_port  $iface_name ${z}ARLEN    arlen    Input  4           $instance_name arlen
	fpga_interfaces::add_interface_port  $iface_name ${z}ARSIZE   arsize   Input  3           $instance_name arsize
	fpga_interfaces::add_interface_port  $iface_name ${z}ARBURST  arburst  Input  2           $instance_name arburst
	fpga_interfaces::add_interface_port  $iface_name ${z}ARLOCK   arlock   Input  2           $instance_name arlock
	fpga_interfaces::add_interface_port  $iface_name ${z}ARCACHE  arcache  Input  4           $instance_name arcache
	fpga_interfaces::add_interface_port  $iface_name ${z}ARPROT   arprot   Input  3           $instance_name arprot
	fpga_interfaces::add_interface_port  $iface_name ${z}ARVALID  arvalid  Input  1           $instance_name arvalid
	fpga_interfaces::add_interface_port  $iface_name ${z}ARREADY  arready  Output 1           $instance_name arready
	fpga_interfaces::add_interface_port  $iface_name ${z}ARUSER   aruser   Input  5           $instance_name aruser

	fpga_interfaces::add_interface_port  $iface_name ${z}RID      rid      Output 8           $instance_name rid
	fpga_interfaces::add_interface_port  $iface_name ${z}RDATA    rdata    Output $data_width $instance_name rdata
	fpga_interfaces::add_interface_port  $iface_name ${z}RRESP    rresp    Output 2           $instance_name rresp
	fpga_interfaces::add_interface_port  $iface_name ${z}RLAST    rlast    Output 1           $instance_name rlast
	fpga_interfaces::add_interface_port  $iface_name ${z}RVALID   rvalid   Output 1           $instance_name rvalid
	fpga_interfaces::add_interface_port  $iface_name ${z}RREADY   rready   Input  1           $instance_name rready
    }
    fpga_interfaces::set_instance_port_termination ${instance_name} "port_size_config" 2 0  1:0 $termination_value
}

proc elab_S2F {device_family} {
    set instance_name hps2fpga
    set atom_name hps_interface_hps2fpga
    set location [locations::get_fpga_location $instance_name $atom_name]
    set termination_value 3
    
    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location

    set addr_width 30
    set id_width   12
    set width [get_parameter_value S2F_Width]
    if {$width > 0} {
	set data_width 32
	set strb_width 4
	set termination_value 0

	if {$width == 2} {
	    set data_width 64
	    set strb_width 8
	    set termination_value 1

	} elseif {$width == 3} {
	    set data_width 128
	    set strb_width 16
	    set termination_value 2
	}

	set clock_name "h2f_axi_clock"
	fpga_interfaces::add_interface      $clock_name    clock              Input
	fpga_interfaces::add_interface_port $clock_name    h2f_axi_clk        clk      Input  1     $instance_name clk
   
	set iface_name "h2f_axi_master"
	set z          "h2f_"
	
	fpga_interfaces::add_interface               $iface_name  axi master
	fpga_interfaces::set_interface_property      $iface_name associatedClock $clock_name
	fpga_interfaces::set_interface_property      $iface_name associatedReset h2f_reset
	fpga_interfaces::set_interface_property      $iface_name readIssuingCapability 8
	fpga_interfaces::set_interface_property      $iface_name writeIssuingCapability 8
	fpga_interfaces::set_interface_property      $iface_name combinedIssuingCapability 16
	
#	set svd_path [file join $::env(QUARTUS_ROOTDIR) .. ip altera hps altera_hps golden_ref_design_CMSIS_1_1_to_arm_v2.svd]
#	send_message info "REMOVE! SVD_PATH = $svd_path"
#	fpga_interfaces::set_interface_property      $iface_name CMSIS_SVD_FILE     $svd_path
#	fpga_interfaces::set_interface_property      $iface_name SVD_ADDRESS_GROUP  hps
#	fpga_interfaces::set_interface_property      $iface_name SVD_ADDRESS_OFFSET [expr {0xC0000000}]
	fpga_interfaces::set_interface_meta_property $iface_name data_width $data_width
	fpga_interfaces::set_interface_meta_property $iface_name address_width $addr_width
	fpga_interfaces::set_interface_meta_property $iface_name id_width $id_width
	
	fpga_interfaces::add_interface_port $iface_name  ${z}AWID     awid     Output $id_width   $instance_name awid
	fpga_interfaces::add_interface_port $iface_name  ${z}AWADDR   awaddr   Output $addr_width $instance_name awaddr
	fpga_interfaces::add_interface_port $iface_name  ${z}AWLEN    awlen    Output 4           $instance_name awlen
	fpga_interfaces::add_interface_port $iface_name  ${z}AWSIZE   awsize   Output 3           $instance_name awsize
	fpga_interfaces::add_interface_port $iface_name  ${z}AWBURST  awburst  Output 2           $instance_name awburst
	fpga_interfaces::add_interface_port $iface_name  ${z}AWLOCK   awlock   Output 2           $instance_name awlock
	fpga_interfaces::add_interface_port $iface_name  ${z}AWCACHE  awcache  Output 4           $instance_name awcache
	fpga_interfaces::add_interface_port $iface_name  ${z}AWPROT   awprot   Output 3           $instance_name awprot
	fpga_interfaces::add_interface_port $iface_name  ${z}AWVALID  awvalid  Output 1           $instance_name awvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}AWREADY  awready  Input  1           $instance_name awready

	fpga_interfaces::add_interface_port $iface_name  ${z}WID      wid      Output $id_width   $instance_name wid
	fpga_interfaces::add_interface_port $iface_name  ${z}WDATA    wdata    Output $data_width $instance_name wdata
	fpga_interfaces::add_interface_port $iface_name  ${z}WSTRB    wstrb    Output $strb_width $instance_name wstrb
	fpga_interfaces::add_interface_port $iface_name  ${z}WLAST    wlast    Output 1           $instance_name wlast
	fpga_interfaces::add_interface_port $iface_name  ${z}WVALID   wvalid   Output 1           $instance_name wvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}WREADY   wready   Input  1           $instance_name wready

	fpga_interfaces::add_interface_port $iface_name  ${z}BID      bid      Input  $id_width   $instance_name bid
	fpga_interfaces::add_interface_port $iface_name  ${z}BRESP    bresp    Input  2           $instance_name bresp
	fpga_interfaces::add_interface_port $iface_name  ${z}BVALID   bvalid   Input  1           $instance_name bvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}BREADY   bready   Output 1           $instance_name bready

	fpga_interfaces::add_interface_port $iface_name  ${z}ARID     arid     Output $id_width   $instance_name arid
	fpga_interfaces::add_interface_port $iface_name  ${z}ARADDR   araddr   Output $addr_width $instance_name araddr
	fpga_interfaces::add_interface_port $iface_name  ${z}ARLEN    arlen    Output 4           $instance_name arlen
	fpga_interfaces::add_interface_port $iface_name  ${z}ARSIZE   arsize   Output 3           $instance_name arsize
	fpga_interfaces::add_interface_port $iface_name  ${z}ARBURST  arburst  Output 2           $instance_name arburst
	fpga_interfaces::add_interface_port $iface_name  ${z}ARLOCK   arlock   Output 2           $instance_name arlock
	fpga_interfaces::add_interface_port $iface_name  ${z}ARCACHE  arcache  Output 4           $instance_name arcache
	fpga_interfaces::add_interface_port $iface_name  ${z}ARPROT   arprot   Output 3           $instance_name arprot
	fpga_interfaces::add_interface_port $iface_name  ${z}ARVALID  arvalid  Output 1           $instance_name arvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}ARREADY  arready  Input  1           $instance_name arready

	fpga_interfaces::add_interface_port $iface_name  ${z}RID      rid      Input  $id_width   $instance_name rid
	fpga_interfaces::add_interface_port $iface_name  ${z}RDATA    rdata    Input  $data_width $instance_name rdata
	fpga_interfaces::add_interface_port $iface_name  ${z}RRESP    rresp    Input  2           $instance_name rresp
	fpga_interfaces::add_interface_port $iface_name  ${z}RLAST    rlast    Input  1           $instance_name rlast
	fpga_interfaces::add_interface_port $iface_name  ${z}RVALID   rvalid   Input  1           $instance_name rvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}RREADY   rready   Output 1           $instance_name rready
       
    }
    fpga_interfaces::set_instance_port_termination ${instance_name} "port_size_config" 2 0  1:0 $termination_value
}

proc elab_LWH2F {device_family} {
    set instance_name hps2fpga_light_weight
    set atom_name hps_interface_hps2fpga_light_weight
    set location [locations::get_fpga_location $instance_name $atom_name]
    
    if [is_enabled LWH2F_Enable] {
	set addr_width 21
	set data_width 32
	set strb_width 4
	set id_width   12
	set clock_name "h2f_lw_axi_clock"
	fpga_interfaces::add_interface      $clock_name    clock              Input
	fpga_interfaces::add_interface_port $clock_name    h2f_lw_axi_clk     clk      Input  1     $instance_name clk
   
	set iface_name "h2f_lw_axi_master"
	set z "h2f_lw_"
	fpga_interfaces::add_interface               $iface_name axi master
#	fpga_interfaces::set_interface_property      $iface_name SVD_ADDRESS_GROUP  hps
#	fpga_interfaces::set_interface_property      $iface_name SVD_ADDRESS_OFFSET [expr {0xFC000000}]
	fpga_interfaces::set_interface_property      $iface_name associatedClock $clock_name
	fpga_interfaces::set_interface_property      $iface_name associatedReset h2f_reset
	fpga_interfaces::set_interface_property      $iface_name readIssuingCapability 8
	fpga_interfaces::set_interface_property      $iface_name writeIssuingCapability 8
	fpga_interfaces::set_interface_property      $iface_name combinedIssuingCapability 16
	fpga_interfaces::set_interface_meta_property $iface_name data_width $data_width
	fpga_interfaces::set_interface_meta_property $iface_name address_width $addr_width
	fpga_interfaces::set_interface_meta_property $iface_name id_width $id_width
	
	fpga_interfaces::add_interface_port $iface_name  ${z}AWID     awid     Output $id_width   $instance_name awid
	fpga_interfaces::add_interface_port $iface_name  ${z}AWADDR   awaddr   Output $addr_width $instance_name awaddr
	fpga_interfaces::add_interface_port $iface_name  ${z}AWLEN    awlen    Output 4           $instance_name awlen
	fpga_interfaces::add_interface_port $iface_name  ${z}AWSIZE   awsize   Output 3           $instance_name awsize
	fpga_interfaces::add_interface_port $iface_name  ${z}AWBURST  awburst  Output 2           $instance_name awburst
	fpga_interfaces::add_interface_port $iface_name  ${z}AWLOCK   awlock   Output 2           $instance_name awlock
	fpga_interfaces::add_interface_port $iface_name  ${z}AWCACHE  awcache  Output 4           $instance_name awcache
	fpga_interfaces::add_interface_port $iface_name  ${z}AWPROT   awprot   Output 3           $instance_name awprot
	fpga_interfaces::add_interface_port $iface_name  ${z}AWVALID  awvalid  Output 1           $instance_name awvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}AWREADY  awready  Input  1           $instance_name awready

	fpga_interfaces::add_interface_port $iface_name  ${z}WID      wid      Output $id_width   $instance_name wid
	fpga_interfaces::add_interface_port $iface_name  ${z}WDATA    wdata    Output $data_width $instance_name wdata
	fpga_interfaces::add_interface_port $iface_name  ${z}WSTRB    wstrb    Output $strb_width $instance_name wstrb
	fpga_interfaces::add_interface_port $iface_name  ${z}WLAST    wlast    Output 1           $instance_name wlast
	fpga_interfaces::add_interface_port $iface_name  ${z}WVALID   wvalid   Output 1           $instance_name wvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}WREADY   wready   Input  1           $instance_name wready

	fpga_interfaces::add_interface_port $iface_name  ${z}BID      bid      Input  $id_width   $instance_name bid
	fpga_interfaces::add_interface_port $iface_name  ${z}BRESP    bresp    Input  2           $instance_name bresp
	fpga_interfaces::add_interface_port $iface_name  ${z}BVALID   bvalid   Input  1           $instance_name bvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}BREADY   bready   Output 1           $instance_name bready

	fpga_interfaces::add_interface_port $iface_name  ${z}ARID     arid     Output $id_width   $instance_name arid
	fpga_interfaces::add_interface_port $iface_name  ${z}ARADDR   araddr   Output $addr_width $instance_name araddr
	fpga_interfaces::add_interface_port $iface_name  ${z}ARLEN    arlen    Output 4           $instance_name arlen
	fpga_interfaces::add_interface_port $iface_name  ${z}ARSIZE   arsize   Output 3           $instance_name arsize
	fpga_interfaces::add_interface_port $iface_name  ${z}ARBURST  arburst  Output 2           $instance_name arburst
	fpga_interfaces::add_interface_port $iface_name  ${z}ARLOCK   arlock   Output 2           $instance_name arlock
	fpga_interfaces::add_interface_port $iface_name  ${z}ARCACHE  arcache  Output 4           $instance_name arcache
	fpga_interfaces::add_interface_port $iface_name  ${z}ARPROT   arprot   Output 3           $instance_name arprot
	fpga_interfaces::add_interface_port $iface_name  ${z}ARVALID  arvalid  Output 1           $instance_name arvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}ARREADY  arready  Input  1           $instance_name arready

	fpga_interfaces::add_interface_port $iface_name  ${z}RID      rid      Input  $id_width   $instance_name rid
	fpga_interfaces::add_interface_port $iface_name  ${z}RDATA    rdata    Input  $data_width $instance_name rdata
	fpga_interfaces::add_interface_port $iface_name  ${z}RRESP    rresp    Input  2           $instance_name rresp
	fpga_interfaces::add_interface_port $iface_name  ${z}RLAST    rlast    Input  1           $instance_name rlast
	fpga_interfaces::add_interface_port $iface_name  ${z}RVALID   rvalid   Input  1           $instance_name rvalid
	fpga_interfaces::add_interface_port $iface_name  ${z}RREADY   rready   Output 1           $instance_name rready

	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

proc elab_F2SDRAM {device_family} {
    f2sdram::init_registers

    set instance_name f2sdram
    set atom_name hps_interface_fpga2sdram
    set location [locations::get_fpga_location $instance_name $atom_name]
    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]

    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location

    set use_fast_sim_model [expr { [string compare [get_parameter_value quartus_ini_hps_ip_fast_f2sdram_sim_model] "true" ] == 0 }]
    set bonding_out_signal [expr { [string compare [get_parameter_value BONDING_OUT_ENABLED] "true"] == 0} && {[string compare [get_parameter_value quartus_ini_hps_ip_f2sdram_bonding_out] "true"] == 0}]
        #newly added
    set width_list [get_parameter_value F2SDRAM_Width]
    set rows [llength $width_list]
    if {$rows > 0} {
	# TODO: move outside of 'if' once registers are rendered
	

	set type_list [get_parameter_value F2SDRAM_Type]
	for {set i 0} {${i} < $rows} {incr i} {
	    set width [lindex $width_list $i]
	    set type_choice  [lindex $type_list  $i]

	    set type "axi"
	    set type_id 0
	    if { [string compare $type_choice [F2HSDRAM_AVM]] == 0 } {
		set type "avalon"
		set type_id 1
	    } elseif { [string compare $type_choice [F2HSDRAM_AVM_WRITEONLY]] == 0 } {
		set type "avalon"
		set type_id 2
	    } elseif { [string compare $type_choice [F2HSDRAM_AVM_READONLY]] == 0 } {    
		set type "avalon"                                              
		set type_id 3                                              
	    }
                                                                    
	    set sim_is_synth [expr !$use_fast_sim_model]
	    
	    # To make sure bonding_out_signal only being added once even thought there are more than one f2sdram
   	    if {$i == 0 } {
		set bonding_out_signal [expr { [string compare [get_parameter_value BONDING_OUT_ENABLED] "true"] == 0} && {[string compare [get_parameter_value quartus_ini_hps_ip_f2sdram_bonding_out] "true"] == 0}] 
	    } else {
		set bonding_out_signal 0
	    }

	    f2sdram::add_port registers $i $type_id $width $instance_name $sim_is_synth $bonding_out_signal
	}
        f2sdram::add_sdc $use_fast_sim_model
        fpga_interfaces::set_property IMPLEMENT_F2SDRAM_MEMORY_BACKED_SIM $use_fast_sim_model
	
    }
    # write the registers out
    f2sdram::render_registers registers $instance_name
}

proc elab_clocks_resets {device_family} {
    set instance_name clocks_resets
    set atom_name hps_interface_clocks_resets
    set location [locations::get_fpga_location $instance_name $atom_name]
    
    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location

    fpga_interfaces::add_interface          h2f_reset             reset    Output
    fpga_interfaces::add_interface_port     h2f_reset  h2f_rst_n  reset_n  Output  1     $instance_name
    fpga_interfaces::set_interface_property h2f_reset  synchronousEdges  none
    fpga_interfaces::set_interface_property h2f_reset associatedResetSinks none

    if [is_enabled S2FCLK_COLDRST_Enable] {    
	fpga_interfaces::add_interface          h2f_cold_reset      reset               Output
	fpga_interfaces::add_interface_port     h2f_cold_reset      h2f_cold_rst_n      reset_n  Output  1     $instance_name
	fpga_interfaces::set_interface_property h2f_cold_reset      synchronousEdges    none
	fpga_interfaces::set_interface_property h2f_cold_reset      associatedResetSinks none
    }

    if [is_enabled F2SCLK_COLDRST_Enable] {
	fpga_interfaces::add_interface          f2h_cold_reset_req  reset               Input
	fpga_interfaces::add_interface_port     f2h_cold_reset_req  f2h_cold_rst_req_n  reset_n  Input   1     $instance_name
	fpga_interfaces::set_interface_property f2h_cold_reset_req  synchronousEdges    none
	fpga_interfaces::set_interface_property h2f_reset associatedResetSinks f2h_cold_reset_req
	if [is_enabled S2FCLK_COLDRST_Enable] {
	    fpga_interfaces::set_interface_property h2f_cold_reset      associatedResetSinks f2h_cold_reset_req
	}
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "f2h_cold_rst_req_n" 1 1 0:0 1
    }

    if [is_enabled S2FCLK_PENDINGRST_Enable] {
	fpga_interfaces::add_interface          h2f_warm_reset_handshake conduit               Output
	fpga_interfaces::add_interface_port     h2f_warm_reset_handshake h2f_pending_rst_req_n h2f_pending_rst_req_n  Output  1     $instance_name
	fpga_interfaces::add_interface_port     h2f_warm_reset_handshake f2h_pending_rst_ack_n f2h_pending_rst_ack_n  Input   1     $instance_name f2h_pending_rst_ack
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "f2h_pending_rst_ack" 1 1 0:0 1
    }
	
    if [is_enabled F2SCLK_DBGRST_Enable] {
	fpga_interfaces::add_interface          f2h_debug_reset_req                     reset    Input
	fpga_interfaces::add_interface_port     f2h_debug_reset_req  f2h_dbg_rst_req_n  reset_n  Input  1     $instance_name
	fpga_interfaces::set_interface_property f2h_debug_reset_req  synchronousEdges   none
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "f2h_dbg_rst_req_n" 1 1 0:0 1
    }

    if [is_enabled F2SCLK_WARMRST_Enable] {
	fpga_interfaces::add_interface          f2h_warm_reset_req                      reset    Input
	fpga_interfaces::add_interface_port     f2h_warm_reset_req  f2h_warm_rst_req_n  reset_n  Input  1     $instance_name
	fpga_interfaces::set_interface_property f2h_warm_reset_req  synchronousEdges    none

	if [is_enabled F2SCLK_COLDRST_Enable] {
	    fpga_interfaces::set_interface_property h2f_reset associatedResetSinks {f2h_warm_reset_req f2h_cold_reset_req}
	} else {
	    fpga_interfaces::set_interface_property h2f_reset associatedResetSinks {f2h_warm_reset_req}
	}
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "f2h_warm_rst_req_n" 1 1 0:0 1
    }

    if [is_enabled S2FCLK_USER0CLK_Enable] {
	fpga_interfaces::add_interface          h2f_user0_clock                 clock  Output
	fpga_interfaces::add_interface_port     h2f_user0_clock  h2f_user0_clk  clk    Output  1     $instance_name
	set frequency [get_parameter_value S2FCLK_USER0CLK_FREQ]
	set frequency [expr {$frequency * [MHZ_TO_HZ]}]
	fpga_interfaces::set_interface_property h2f_user0_clock clockRateKnown true
	fpga_interfaces::set_interface_property h2f_user0_clock clockRate      $frequency
	add_clock_constraint_if_valid $frequency "*|fpga_interfaces|${instance_name}|h2f_user0_clk"
    }
    
    if [is_enabled S2FCLK_USER1CLK_Enable] {
	fpga_interfaces::add_interface          h2f_user1_clock                 clock  Output
	fpga_interfaces::add_interface_port     h2f_user1_clock  h2f_user1_clk  clk    Output  1     $instance_name
	set frequency [get_parameter_value S2FCLK_USER1CLK_FREQ]
	set frequency [expr {$frequency * [MHZ_TO_HZ]}]
	fpga_interfaces::set_interface_property h2f_user1_clock clockRateKnown true
	fpga_interfaces::set_interface_property h2f_user1_clock clockRate      $frequency
	add_clock_constraint_if_valid $frequency "*|fpga_interfaces|${instance_name}|h2f_user1_clk"
    }
	
    set_parameter_property S2FCLK_USER2CLK enabled false
	
    if [is_enabled F2SCLK_PERIPHCLK_Enable] {    
	fpga_interfaces::add_interface          f2h_periph_ref_clock                      clock  Input
	fpga_interfaces::add_interface_port     f2h_periph_ref_clock  f2h_periph_ref_clk  clk    Input  1     $instance_name
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "f2h_periph_ref_clk" 1 0
    }

	
    if [is_enabled F2SCLK_SDRAMCLK_Enable] {
	fpga_interfaces::add_interface          f2h_sdram_ref_clock                     clock  Input
	fpga_interfaces::add_interface_port     f2h_sdram_ref_clock  f2h_sdram_ref_clk  clk    Input  1     $instance_name
    } else {
	fpga_interfaces::set_instance_port_termination ${instance_name} "f2h_sdram_ref_clk" 1 0
    }
}

# Elaborate peripheral request interfaces for the fpga and
# the clk/reset per pair
# TODO: Make sure the DMA RTL contains the wrapper
proc elab_DMA {device_family} {
    set instance_name dma
    set atom_name hps_interface_dma
    set location [locations::get_fpga_location $instance_name $atom_name]
    
    set can_message 0
    set available_list [get_parameter_value DMA_Enable]
    if {[llength $available_list] > 0} {
	set dma_used 0
	set periph_id 0
	foreach entry $available_list {
	    if {[string compare $entry "Yes" ] == 0} {
		elab_DMA_entry $periph_id $instance_name
		set dma_used 1
		if {$periph_id >= 4} {
		    set can_message 1
		}
	    }
	    incr periph_id
	}
	if $dma_used {
	    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
	}
	if $can_message {
	    send_message info "DMA Peripheral Request Interfaces 4-7 may be consumed by an HPS CAN Controller"
	}
    }
}

proc elab_DMA_make_conduit_name {periph_id} {
    return "f2h_dma_req${periph_id}"
}

proc elab_DMA_entry {periph_id instance_name} {
    set iname [elab_DMA_make_conduit_name $periph_id]
    set atom_signal_prefix "channel${periph_id}"
    fpga_interfaces::add_interface      $iname conduit Output
    fpga_interfaces::add_interface_port $iname "${iname}_req"    "dma_req"    Input  1  $instance_name  ${atom_signal_prefix}_req
    fpga_interfaces::add_interface_port $iname "${iname}_single" "dma_single" Input  1  $instance_name  ${atom_signal_prefix}_single
    fpga_interfaces::add_interface_port $iname "${iname}_ack"    "dma_ack"    Output 1  $instance_name  ${atom_signal_prefix}_xx_ack
}


proc elab_emac_ptp {device_family} {
    # added for case http://fogbugz.altera.com/default.asp?307450 
    for {set i 0} {$i < 2} {incr i} {
        set emac_fpga_enabled   false
        set emac_io_enabled     false

        set emac_pin_mux_value [get_parameter_value EMAC${i}_PinMuxing]
        set emac_ptp           [get_parameter_value EMAC${i}_PTP]

        if {[string compare $emac_pin_mux_value [FPGA_MUX_VALUE]] == 0} {
            set emac_fpga_enabled true
        }
        if {[string compare $emac_pin_mux_value "HPS I/O Set 0"]   == 0} {
            set emac_io_enabled   true
        }
        
        set_parameter_property   EMAC${i}_PTP  enabled        $emac_io_enabled
        
        if {$emac_io_enabled && $emac_ptp } {
            set instance_name  peripheral_emac${i}
            set atom_name      hps_interface_peripheral_emac
            set wys_atom_name  arriav_hps_interface_peripheral_emac
            set location       [locations::get_fpga_location $instance_name $atom_name]
            
            set iface_name    "emac${i}"

            fpga_interfaces::add_interface       $iface_name conduit input
            fpga_interfaces::add_interface_port  $iface_name emac${i}_ptp_aux_ts_trig_i  ptp_aux_ts_trig_i  Input  1  $instance_name ptp_aux_ts_trig_i
            fpga_interfaces::add_interface_port  $iface_name emac${i}_ptp_pps_o          ptp_pps_o          Output 1  $instance_name ptp_pps_o

            
            fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
        }
        
    }
}

proc elab_INTERRUPTS {device_family logical_view} {
    set instance_name interrupts
    set atom_name hps_interface_interrupts
    set location [locations::get_fpga_location $instance_name $atom_name]
    set any_interrupt_enabled 0

    ##### F2H #####
    if [is_enabled F2SINTERRUPT_Enable] {
	set any_interrupt_enabled 1
	set iname "f2h_irq"
	set pname "f2h_irq"
	if { $logical_view == 0 } {
	    fpga_interfaces::add_interface      "${iname}0"  interrupt receiver
	    fpga_interfaces::add_interface_port "${iname}0" "${pname}_p0"    irq Input 32
	    fpga_interfaces::set_port_fragments "${iname}0" "${pname}_p0" "${instance_name}:irq(31:0)" 
	    
	    fpga_interfaces::add_interface      "${iname}1"  interrupt receiver
	    fpga_interfaces::add_interface_port "${iname}1" "${pname}_p1"    irq Input 32
	    fpga_interfaces::set_port_fragments "${iname}1" "${pname}_p1" "${instance_name}:irq(63:32)"
	}
    }

    ##### H2F #####
    load_h2f_interrupt_table\
	functions_by_group width_by_function inverted_by_function

    set interrupt_groups [list_h2f_interrupt_groups]
    foreach group $interrupt_groups {
	set parameter "S2FINTERRUPT_${group}_Enable"
	set enabled [is_enabled $parameter]

	if {!$enabled} {
	    continue
	}
	set any_interrupt_enabled 1
	
	foreach function $functions_by_group($group) {
	    set width 1
	    if {[info exists width_by_function($function)]} {
		set width $width_by_function($function)
	    }
	    
	    set suffix ""
	    set inverted [info exists inverted_by_function($function)]
	    if {$inverted} {
		set suffix "_n"
	    }
	    
	    #skip fpga_interfaces interrupt declaration for uart 
	    if { ($logical_view == 1) && (
	         $function == "uart0" || 
	         $function == "uart1" )} {
	    	    continue
	    }
	    
	    set prefix    "h2f_${function}_"
	    set interface "${prefix}interrupt"
	    set port      "${prefix}irq"
	    
	    if {$width > 1} { ;# for buses, use index in interface/port names
		for {set i 0} {$i < $width} {incr i} {
		    set indexed_interface "${interface}${i}"
		    set indexed_port      "${port}${i}${suffix}"
		    fpga_interfaces::add_interface\
			$indexed_interface interrupt sender
		    fpga_interfaces::add_interface_port\
			$indexed_interface $indexed_port irq Output 1\
			$instance_name $indexed_port
		}
	    } else {
		set port "$port${suffix}"
		fpga_interfaces::add_interface\
		    $interface interrupt sender
		fpga_interfaces::add_interface_port\
		    $interface $port irq Output 1  $instance_name $port
	    }
	}
    }
    
    if {$any_interrupt_enabled}  {
	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
        fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

proc elab_TEST {device_family} {
    set parameter_enabled [expr {[string compare [get_parameter_value TEST_Enable] "true" ] == 0}]
    set ini_enabled       [expr {[string compare [get_parameter_value quartus_ini_hps_ip_enable_test_interface] "true" ] == 0}]
    
    if {$parameter_enabled && $ini_enabled} {
	set instance_name test_interface
	set atom_name hps_interface_test
	set location [locations::get_fpga_location $instance_name $atom_name]
	
	set iname "test"
	set z     "test_"
	
	set data [get_parameter_value test_iface_definition]
	
	fpga_interfaces::add_interface      $iname  conduit input
	foreach {port width dir} $data {
	    fpga_interfaces::add_interface_port $iname "${z}${port}" $port $dir $width $instance_name $port
	}

	set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
    }
}

# TODO: Mode usage data
proc elab_FPGA_Peripheral_Signals {device_family} {
    # disable and hide all parameters related to fpga outputs
    set emac0_fpga [get_parameter_value quartus_ini_hps_ip_enable_emac0_peripheral_fpga_interface]
    set lssis_fpga [get_parameter_value quartus_ini_hps_ip_enable_low_speed_serial_fpga_interfaces]
    set all_fpga   "true"

    set peripherals [list_peripheral_names]
    foreach peripheral $peripherals {
	if { [string compare $peripheral "SDIO" ] == 0 } {
	    continue
	}
	set visible false
	if {[string compare $all_fpga "true" ] == 0} {
	    set visible true
	} elseif {[string compare $emac0_fpga "true" ] == 0 && [string compare -nocase $peripheral "emac0"] == 0} {
	    set visible true
	} elseif {[string compare $lssis_fpga "true" ] == 0 && [is_peripheral_low_speed_serial_interface $peripheral_name]} {
	    set visible true
	}
	if {[string compare -nocase $peripheral "emac0" ] == 0 || [string compare -nocase $peripheral "emac1" ] == 0} {
	    set visible true
	}
	set clocks [get_peripheral_fpga_output_clocks $peripheral]
	foreach clock $clocks {
	    set parameter [form_peripheral_fpga_output_clock_frequency_parameter $clock]
	    set_parameter_property $parameter enabled  false
	    set_parameter_property $parameter visible  $visible
	    set clock_output_set($clock) 1
	}

	set clocks [get_peripheral_fpga_input_clocks $peripheral]
	foreach clock $clocks {
	    set clock_input_set($clock) 1
	}
    }

    array set fpga_ifaces [get_parameter_value DB_periph_ifaces]
    array set iface_ports [get_parameter_value DB_iface_ports]
    array set port_pins   [get_parameter_value DB_port_pins]
    foreach peripheral_name $fpga_ifaces([ORDERED_NAMES]) { ;# Peripherals
	set pin_mux_param_name [format [PIN_MUX_PARAM_FORMAT] $peripheral_name]
	set pin_mux_value  [get_parameter_value    $pin_mux_param_name]
	set allowed_ranges [get_parameter_property $pin_mux_param_name allowed_ranges]

	if {[string compare $pin_mux_value [FPGA_MUX_VALUE]] == 0 && [lsearch $allowed_ranges [FPGA_MUX_VALUE]] != -1} {
	    funset peripheral
	    array set peripheral $fpga_ifaces($peripheral_name)
	    funset interfaces
	    array set interfaces $peripheral(interfaces)
	    
	    set instance_name [invent_peripheral_instance_name $peripheral_name]

	    foreach interface_name $interfaces([ORDERED_NAMES]) { ;# Interfaces
		funset interface
		array set interface $interfaces($interface_name)
		fpga_interfaces::add_interface $interface_name $interface(type) $interface(direction)
		foreach {property_key property_value} $interface(properties) {
		    fpga_interfaces::set_interface_property $interface_name $property_key $property_value
		}
		#send_message info "NEA: peripheral_name $peripheral_name interface_name $interface_name "
		
		if { [string match "EMAC?" $peripheral_name] && [string match  "*x_reset" $interface_name ] } {
		    fpga_interfaces::set_interface_property $interface_name associatedResetSinks none
		}

		foreach {meta_property} [array names interface] {
		    # Meta Property if leading with an @
		    if {[string compare [string index ${meta_property} 0] "@"] == 0} {
			fpga_interfaces::set_interface_meta_property $interface_name [string replace ${meta_property} 0 0] $interface($meta_property)
		    }
		}

		set once_per_clock 1
		funset ports
		array set ports $iface_ports($interface_name)
		foreach port_name $ports([ORDERED_NAMES]) { ;# Ports
		    funset port
		    array set port $ports($port_name)
		    
		    # TODO: determine width based on pins available via mode
		    set width [calculate_port_width $port_pins($port_name)]

		    fpga_interfaces::add_interface_port $interface_name $port_name $port(role) $port(direction) $width $instance_name $port(atom_signal_name)
		    
		    set frequency 0
		    # enable and show clock frequency parameters for outputs
		    if {[info exists clock_output_set($interface_name)]} {
			set parameter [form_peripheral_fpga_output_clock_frequency_parameter $interface_name]
			set_parameter_property $parameter enabled  true
			set frequency [get_parameter_value $parameter]
			set frequency [expr {$frequency * [MHZ_TO_HZ]}]
			fpga_interfaces::set_interface_property $interface_name clockRateKnown true
			fpga_interfaces::set_interface_property $interface_name clockRate      $frequency
		    }
		    
		    if {[string compare -nocase $interface(type) "clock"] == 0 && $once_per_clock} {
			set once_per_clock 0
			add_clock_constraint_if_valid $frequency "*|fpga_interfaces|${instance_name}|[string tolower $port(atom_signal_name)]"
		    }
		}
	    }
	    
	    # device-specific atom
	    set atom_name     $peripheral(atom_name)
	    set wys_atom_name [generic_atom_to_wys_atom $device_family $atom_name]
	    set location [locations::get_fpga_location $peripheral_name $atom_name]

	    fpga_interfaces::add_module_instance $instance_name $wys_atom_name $location
	}
    }
}

# derives the WYS (device family-specific) atom name from the generic one
proc generic_atom_to_wys_atom {device_family atom_name} {
    # TODO: base this on a table of data instead of on code
    set result ""
    if {[check_device_family_equivalence $device_family CYCLONEV]} {
	set result "cyclonev_${atom_name}"
    } elseif {[check_device_family_equivalence $device_family ARRIAV]} {
	set result "arriav_${atom_name}"
		}
    return $result
}

# invents an instance name from the peripheral's name
# assumes that the instance name is the same across a peripheral
proc invent_peripheral_instance_name {peripheral_name} {
    return "peripheral_[string tolower $peripheral_name]"
}

# TODO: do width calculation at db load time so we don't do it every elaboration!
#       then make it accessible by a mode to width array for every peripheral with fpga periph interface
# TODO: also validate the static data, checking if the mode signals make sense aka only contiguous, 0-indexed mappings
proc calculate_port_width {pin_array_string} {
    array set pins $pin_array_string
    # TODO: -do we need to be able to support ports that don't start with pins at 0?
    #       -e.g. pins D0-D7 are indexed 0-7. if want D4-D7, can we do indexes 4-7?
    #       -for now, no!
    set bit_index 0
    while {[info exists pins($bit_index)]} {
	incr bit_index
    }
    return $bit_index
}

proc pin_to_bank {pin} {
    set io_index [string first "IO" $pin]
    return [string range $pin 0 [expr {$io_index - 1}]]
}

proc sort_pins {pins} {
    set pin_suffixes [list]
    foreach pin $pins {
	set io_index [string first "IO" $pin]
	set suffix_start [expr {$io_index + 2}]
	set length [string length $pin]
	set suffix [string range $pin $suffix_start [expr {$length - 1}]]
	lappend pin_suffixes $suffix
    }
    set result [list]
    set indices [lsort-indices -increasing -integer $pin_suffixes]
    foreach index $indices {
	lappend result [lindex $pins $index]
    }
    return $result
}

proc set_peripheral_pin_muxing_description {peripheral_name pin_muxing_description mode_description} {
    set parameter "[string toupper $peripheral_name]_PinMuxing"
    set_display_item_property $parameter DESCRIPTION $pin_muxing_description

    set parameter "[string toupper $peripheral_name]_Mode"
    set_display_item_property $parameter DESCRIPTION $mode_description
}

# Expects same set of keys between both parameters
proc create_pin_muxing_description_table_html {signals_by_option_str pins_by_option_str} {
    array set pins_by_option $pins_by_option_str

    set options [list]
    foreach {option signals} $signals_by_option_str {
	lappend options $option

	set pins $pins_by_option($option)
	
	foreach signal $signals pin $pins {
	    set key "${option}.${signal}"
	    set pins_by_option_and_signal($key) $pin
	    set signal_set($signal) 1
	}
    }
    
    set sorted_signals [lsort -increasing -ascii [array names signal_set]]
    set sorted_options [lsort -increasing -ascii $options]
    
    set ALIGN_CENTER {align="center"}

    set html "<table border=\"1\"><tr><td></td>" ;# start of table, first row cell empty for signal column
    foreach option $sorted_options {
	set html "${html}<th $ALIGN_CENTER>${option}</th>"
    }
    set html "${html}</tr>"
    foreach signal $sorted_signals {
	set html "${html}<tr><th $ALIGN_CENTER>${signal}</th>" ;# new row w/ first cell (header) being the signal name
	foreach option $sorted_options {
	    set key "${option}.${signal}"
	    if {[info exists pins_by_option_and_signal($key)]} {
		set pin $pins_by_option_and_signal($key)
	    } else {
		set pin ""
	    }
	    set html "${html}<td $ALIGN_CENTER>${pin}</td>"
	}
	set html "${html}</tr>"
    }
    set html "${html}</table>"
    return $html
}

proc create_mode_description_table_html {signals_by_mode_str} {
    set modes [list]
    
    foreach {mode signals} $signals_by_mode_str {
	lappend modes $mode
	foreach signal $signals {
	    set key "${mode}.${signal}"
	    set membership_by_mode_and_signal($key) 1
	    set signal_set($signal) 1
	}
    }
    
    set sorted_signals [lsort -increasing -ascii [array names signal_set]]
    set sorted_modes   [lsort -increasing -ascii $modes]
    
    set ALIGN_CENTER {align="center"}
    
    set html "<table border=\"1\"><tr><td></td>" ;# start of table, first row cell empty for signal column
    foreach mode $sorted_modes {
	set html "${html}<th $ALIGN_CENTER>${mode}</th>"
    }
    set html "${html}</tr>"
    foreach signal $sorted_signals {
	set html "${html}<tr><th $ALIGN_CENTER>${signal}</th>" ;# new row w/ first cell (header) being the signal name

	foreach mode $sorted_modes {
	    set key "${mode}.${signal}"
	    if {[info exists membership_by_mode_and_signal($key)]} {
		set member_marker "X"
	    } else {
		set member_marker ""
	    }
	    set html "${html}<td $ALIGN_CENTER>${member_marker}</td>"
	}
	set html "${html}</tr>"
    }
    set html "${html}</table>"
    return $html
}

proc get_quartus_edition {} {
    set code {
	set version ""
	regexp {([a-zA-Z]+) (Edition|Version)$} $quartus(version) total version
	return $version
    }
    set safe_code [string map {\n ; \t ""} $code]
    set package_name "advanced_device"
    set result [lindex [run_quartus_tcl_command "${package_name}:${safe_code}"] 0]
    return $result
}

proc is_soc_device {device} {
    return [::pin_mux_db::verify_soc_device $device]
}

proc set_peripheral_pin_muxing_descriptions {peripherals_ref} {
    upvar 1 $peripherals_ref peripherals

    foreach peripheral_name [array names peripherals] {
	set signals_by_option [list]
	set pins_by_option    [list]
	
	funset peripheral
	array set peripheral $peripherals($peripheral_name)
	funset pin_sets
	array set pin_sets $peripheral(pin_sets)
	
	foreach pin_set_name [array names pin_sets] {
	    funset pin_set
	    array set pin_set $pin_sets($pin_set_name)
	    set signals $pin_set(signals)
	    lappend signals_by_option $pin_set_name $signals
	    set pins $pin_set(pins)
	    lappend pins_by_option $pin_set_name $pins
	}
	set signals_by_mode $peripheral(signals_by_mode)

	set table_html [create_pin_muxing_description_table_html $signals_by_option $pins_by_option]
	set pin_muxing_description ""
	
	set table_html [create_mode_description_table_html $signals_by_mode]
	set mode_description "Signal Membership Per Mode Usage Option: <br />${table_html}"
	set_peripheral_pin_muxing_description $peripheral_name $pin_muxing_description $mode_description
    }
}

# Add pin muxing details to soc_io peripheral/signal data
add_storage_parameter pin_muxing {}
add_storage_parameter pin_muxing_check ""
proc ensure_pin_muxing_data {device_family} {
    if {[check_device_family_equivalence $device_family [get_module_property SUPPORTED_DEVICE_FAMILIES]] == 0} {
	return
    }
    
    set device [get_device]

    if {![is_soc_device $device]} {
	send_message error "Selected device '${device}' is not an SoC device. Please choose a valid SoC device to use the Hard Processor System."
	return
    }

    set device_configuration "${device_family}+${device}"

  set old_device_configuration [get_parameter_value pin_muxing_check]
  if {$old_device_configuration == $device_configuration} {
	return
  }
    
    set load_rc [::pin_mux_db::load $device]
    if {!$load_rc} {                           
	send_message error "The pin information for the Hard Processor System could not be determined. Please check whether your edition of Quartus Prime supports the selected device."
	return          
    }              
    locations::load $device    
                                                      
    load_peripherals_pin_muxing_model pin_muxing_peripherals
    set_peripheral_pin_muxing_descriptions pin_muxing_peripherals
                                   
    set gpio_pins [::pin_mux_db::get_gpio_pins]
    set loanio_pins [::pin_mux_db::get_loan_io_pins]        
    set customer_pin_names [::pin_mux_db::get_customer_pin_names]
    set hlgpi_pins [::pin_mux_db::get_hlgpi_pins]
                                                     
    set pin_muxing [list [array get pin_muxing_peripherals] $gpio_pins $loanio_pins $customer_pin_names $hlgpi_pins]
    set_parameter_value pin_muxing $pin_muxing
    set_parameter_value pin_muxing_check $device_configuration
      
    ####  update pin_muxing data to use in java GUI  ####
        set pinmux_peripherals [array get pin_muxing_peripherals]
        array set periph_key_value $pinmux_peripherals  
        
        foreach {key value} [array get periph_key_value] {
        	set_parameter_value JAVA_${key}_DATA "$key \{$value\}"            
        }                                                   
}  
 
proc get_device {} {

    set device_name [get_parameter_value device_name]
    return $device_name
}

proc construct_hps_parameter_map {} {
    set parameters [get_parameters]
    foreach parameter $parameters {
	set value [get_parameter_value $parameter]
	set result($parameter) $value
    }
    return [array get result]
}

################################################################################
# Implements interface of util/pin_mux.tcl
#                                                          
namespace eval hps_ip_pin_muxing_model {
################################################################################
    proc get_peripherals_model {} {
	set pin_muxing [get_parameter_value pin_muxing]
	set peripherals [lindex $pin_muxing 0]
	return $peripherals
    }
    proc get_emac0_fpga_ini {} {
 	return [is_enabled quartus_ini_hps_ip_enable_emac0_peripheral_fpga_interface]
    }
    proc get_lssis_fpga_ini {} {
 	return [is_enabled quartus_ini_hps_ip_enable_low_speed_serial_fpga_interfaces]
    }
    proc get_all_fpga_ini {} {
 	return [is_enabled quartus_ini_hps_ip_enable_all_peripheral_fpga_interfaces] 
    }
    proc get_peripheral_pin_muxing_selection {peripheral_name} {
	set pin_muxing_param_name [format [PIN_MUX_PARAM_FORMAT] $peripheral_name]
	set selection [get_parameter_value $pin_muxing_param_name]
	return $selection
    }
    proc get_peripheral_mode_selection {peripheral_name} {
	set mode_param_name [format [MODE_PARAM_FORMAT] $peripheral_name]
	set selection [get_parameter_value $mode_param_name]
	return $selection
    }
    proc get_gpio_pins {} {
	set pin_muxing [get_parameter_value pin_muxing] 
	set pins [lindex $pin_muxing 1] 
	return $pins
    }
    proc get_loanio_pins {} {
	set pin_muxing [get_parameter_value pin_muxing]
	set pins [lindex $pin_muxing 2]
	return $pins
    }
    proc get_customer_pin_names {} {
	set pin_muxing [get_parameter_value pin_muxing]                                                                
	set pins [lindex $pin_muxing 3]
	return $pins
    }
    proc get_hlgpi_pins {} {
	set pin_muxing [get_parameter_value pin_muxing]                                                                
	set pins [lindex $pin_muxing 4]
	return $pins
    }
    proc get_unsupported_peripheral {peripheral_name} {
	set device_family [get_parameter_value hps_device_family]
	set skip 0
	if {[check_device_family_equivalence $device_family ARRIAV]} {
            foreach excluded_peripheral [ARRIAV_EXCLUDED_PERIPHRERALS] {
                if {[string compare $excluded_peripheral $peripheral_name] == 0} { 
                    set skip 1 
                }
            }
        }
	return $skip
    }
}


## Add documentation links for user guide and/or release notes
add_documentation_link "User Guide" https://www.altera.com/products/soc/overview.html
