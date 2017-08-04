# TCL File Generated by Component Editor 13.1
# Thu Jan 16 23:22:07 CET 2014
# DO NOT MODIFY


# 
# driver_sound "driver_sound" v1.0
#  2014.01.16.23:22:07
# 
# 

# 
# request TCL package from ACDS 13.1
# 
package require -exact qsys 13.1


# 
# module driver_sound
# 
set_module_property DESCRIPTION ""
set_module_property NAME driver_sound
set_module_property VERSION 1.0
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property GROUP ao486
set_module_property AUTHOR ""
set_module_property DISPLAY_NAME driver_sound
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property ANALYZE_HDL AUTO
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false


# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL driver_sound
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file driver_sound.v VERILOG PATH driver_sound.v TOP_LEVEL_FILE


# 
# parameters
# 


# 
# display items
# 


# 
# connection point sound_slave
# 
add_interface sound_slave avalon end
set_interface_property sound_slave addressUnits WORDS
set_interface_property sound_slave associatedClock clock_sound
set_interface_property sound_slave associatedReset reset_sound
set_interface_property sound_slave bitsPerSymbol 8
set_interface_property sound_slave burstOnBurstBoundariesOnly false
set_interface_property sound_slave burstcountUnits WORDS
set_interface_property sound_slave explicitAddressSpan 0
set_interface_property sound_slave holdTime 0
set_interface_property sound_slave linewrapBursts false
set_interface_property sound_slave maximumPendingReadTransactions 0
set_interface_property sound_slave readLatency 0
set_interface_property sound_slave readWaitTime 1
set_interface_property sound_slave setupTime 0
set_interface_property sound_slave timingUnits Cycles
set_interface_property sound_slave writeWaitTime 0
set_interface_property sound_slave ENABLED true
set_interface_property sound_slave EXPORT_OF ""
set_interface_property sound_slave PORT_NAME_MAP ""
set_interface_property sound_slave CMSIS_SVD_VARIABLES ""
set_interface_property sound_slave SVD_ADDRESS_GROUP ""

add_interface_port sound_slave avs_writedata writedata Input 32
add_interface_port sound_slave avs_write write Input 1
set_interface_assignment sound_slave embeddedsw.configuration.isFlash 0
set_interface_assignment sound_slave embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment sound_slave embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment sound_slave embeddedsw.configuration.isPrintableDevice 0


# 
# connection point clock_sound
# 
add_interface clock_sound clock end
set_interface_property clock_sound clockRate 0
set_interface_property clock_sound ENABLED true
set_interface_property clock_sound EXPORT_OF ""
set_interface_property clock_sound PORT_NAME_MAP ""
set_interface_property clock_sound CMSIS_SVD_VARIABLES ""
set_interface_property clock_sound SVD_ADDRESS_GROUP ""

add_interface_port clock_sound clk_12 clk Input 1


# 
# connection point reset_sound
# 
add_interface reset_sound reset end
set_interface_property reset_sound associatedClock clock_sound
set_interface_property reset_sound synchronousEdges DEASSERT
set_interface_property reset_sound ENABLED true
set_interface_property reset_sound EXPORT_OF ""
set_interface_property reset_sound PORT_NAME_MAP ""
set_interface_property reset_sound CMSIS_SVD_VARIABLES ""
set_interface_property reset_sound SVD_ADDRESS_GROUP ""

add_interface_port reset_sound rst_n reset_n Input 1


# 
# connection point export_sound
# 
add_interface export_sound conduit end
set_interface_property export_sound associatedClock clock_sound
set_interface_property export_sound associatedReset reset_sound
set_interface_property export_sound ENABLED true
set_interface_property export_sound EXPORT_OF ""
set_interface_property export_sound PORT_NAME_MAP ""
set_interface_property export_sound CMSIS_SVD_VARIABLES ""
set_interface_property export_sound SVD_ADDRESS_GROUP ""

add_interface_port export_sound ac_sclk export Output 1
add_interface_port export_sound ac_sdat export Bidir 1
add_interface_port export_sound ac_xclk export Output 1
add_interface_port export_sound ac_bclk export Output 1
add_interface_port export_sound ac_dat export Output 1
add_interface_port export_sound ac_lr export Output 1
