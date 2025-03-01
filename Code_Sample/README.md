### DESERIALIZER.vhd

The data are being transmitted/received to/from FPGA via UART in a serialized format.
Protobuf is utilized to serialize and deserialize different types of structured data, 
so that the hardware can recognize and distribute them to the appropriate hardware components.
The DESERIALIZER component has been implemented as an FSM at the hardware level in VHDL and distributes
the data to other hardware components on-the-fly or stores them in memory.

### weights.py

Provides the user with several mechanisms to determine the as-many-as 29x29 (841) coefficients to
increase convenience. The most popular patterns are the Moore and von Neumann neighborhood, while
additional neighborhood patterns are supported such as: Hash, L2/Euclidean, Circular and more. The tool also
supports mirror mode, where the user defines the neighborhood within the second quadrant (one-fourth of 841)
and it is then mirrored accross the remaining window.

### run_vivado.tcl

Runs Vivado's functionalities in batch mode using TCL commands. Compiles the design, generates the bit file
and programs the FPGA.
