# ================================================================================
#
# Build ID Verilog Module Script
# Jeff Wiencrot - 8/1/2011
#
# Generates a Verilog module that contains a timestamp,
# from the current build. These values are available from the build_date, build_time,
# physical_address, and host_name output ports of the build_id module in the build_id.v
# Verilog source file.
#
# ================================================================================

proc generateBuildID_Verilog {} {

	# Get the timestamp (see: http://www.altera.com/support/examples/tcl/tcl-date-time-stamp.html)
	set buildDate [ clock format [ clock seconds ] -format %y%m%d ]
	set buildTime [ clock format [ clock seconds ] -format %H%M%S ]

	# Create a Verilog file for output
	set outputFileName "build_id.v"
	set outputFile [open $outputFileName "w"]

	# Output the Verilog source
	puts $outputFile "`define BUILD_DATE \"$buildDate\""
	puts $outputFile "`define BUILD_TIME \"$buildTime\""
	close $outputFile

	# Send confirmation message to the Messages window
	post_message "Generated build identification Verilog module: [pwd]/$outputFileName"
	post_message "Date:             $buildDate"
	post_message "Time:             $buildTime"
}

# Comment out this line to prevent the process from automatically executing when the file is sourced:
generateBuildID_Verilog