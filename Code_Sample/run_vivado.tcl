# Author: Mylonakis Emmanouil.
# Description: Integrated TCL commands of the Vivado. 
#              compile{}-> Synthesize, Implmentation and Bitstream Generation.
#			   program_device{} -> Loads bit file into the FPGA.

# ====================== Procedures ====================== #

# Compile, Synthesize, Implementation and derive bit file in non-project mode.
proc compile {path_bit} {
	set_part xc7a100tcsg324-1

	# Define output directory for bit file.
	set outputDir $path_bit

	# Setup design source files.	
	# Read VHDL files.
	read_vhdl -library xil_defaultlib [glob design/vhdl/*.vhd]	
	# Read VHDL 2008 files.
	read_vhdl -library xil_defaultlib -vhdl2008 [glob design/vhdl_2008/*.vhd]
	
	# Create XCI file when reading core container files (.xcix)
	# set_property coreContainer.alwaysCreateXCI 1 [current_project]
	
	# Read IP files.
	read_ip [glob design/ip/clk_wiz_0/*.xcix]
	read_ip [glob design/ip/clk_wiz_1/*.xcix]
	read_ip [glob design/ip/FIFO_4_32/*.xcix]
	read_ip [glob design/ip/FIFO_8_32/*.xcix]
	read_ip [glob design/ip/FIFO_32_128/*.xcix]
	read_ip [glob design/ip/GRAPHICS_FIFO/*.xcix]
	read_ip [glob design/ip/LINE_BUFFER_4b/*.xcix]
	read_ip [glob design/ip/LINE_BUFFER_8B/*.xcix]
	read_ip design/ip/mig_7series_0/mig_7series_0.xci

	# Generate output products for MIG CONTROLLER and synthesize it.
	generate_target {synthesis, implementation} [get_ips mig_7series_0]
	synth_ip [get_ips mig_7series_0]

	# Read constraints (xdc files).
	read_xdc [glob design/constraints/*.xdc]
	
	# Timing Constraints aren't being used during synthesis.
	set_property used_in_synthesis false [get_files  design/constraints/My_Timing_Constraints.xdc]

	# Synthesizes the design.
	synth_design -top TOP_LEVEL -flatten_hierarchy none -part xc7a100tcsg324-1

	# Performs high-level design optimization. 
	opt_design
	# Places the design.
	place_design
	# Performs physical logic optimization to improve timing or routability.
	phys_opt_design
	# Routes the design.
	route_design
	# Generates the bitstream.
	write_bitstream -force $outputDir

	
}

# Program FPGA with a specific bit file (path_bit).
proc program_device {path_bit} {
	# Open Hardware Manager.
	open_hw_manager
	# Connect to the hardware server.
	connect_hw_server
	# Connect to the hardware target (FPGA).
	open_hw_target
	# Set Properties according to the target.
	set_property PROBES.FILE {} [get_hw_devices]
	set_property FULL_PROBES.FILE {} [get_hw_devices]
	# Set the path of the bit file and associate it with the FPGA.
	set_property PROGRAM.FILE $path_bit [get_hw_devices]
	# Program the FPGA.
	program_hw_devices [get_hw_devices]
}


# ====================== Drive Code ====================== #
# This TCL script receives arguments like:
# argv[0] for specifing a procedure. (compile or program)
# argv[1] is an optimal argument for the path.

set oper [lindex $argv 0]
set path [lindex $argv 1]

if { [string equal $oper program] } {
	puts [program_device $path]
}

if { [string equal $oper compile] } {
	puts [compile $path]
}
