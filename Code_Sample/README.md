### DESERIALIZER.vhd

The data are being trasmitted/received to/from FPGA via UART in a serialized format.
The protobuf is utilized to serialize and deserialize different types of structured data, 
in order for the hardware to recognize and distribute them to appropriate hardware components.
The desirializer has been implemented as a FSM on hardware level in VHDL.
