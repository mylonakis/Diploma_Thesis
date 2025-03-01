### DESERIALIZER.vhd

The data are being transmitted/received to/from FPGA via UART in a serialized format.
Protobuf is utilized to serialize and deserialize different types of structured data, 
so that the hardware to recognize and distribute them to appropriate hardware components.
The DESERIALIZER component has been implemented as a FSM at the hardware level in VHDL and distributes
the data to other hardware component on-the-fly or stores them in memory.
