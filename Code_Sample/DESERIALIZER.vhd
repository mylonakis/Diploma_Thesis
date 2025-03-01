----------------------------------------------------------------------------------
-- Company: Technical University of Crete
-- Engineer: Mylonakis Emmanouil
-- Create Date: 06/13/2023 11:18:14 AM 
-- Description: Protocol Buffers' Deserializer. FSM Implementation.
----------------------------------------------------------------------------------
--LIBRARY IEEE;
--USE IEEE.STD_LOGIC_1164.ALL;
--USE IEEE.NUMERIC_STD.ALL;
--package ARRAY_2D is
--    type WEIGHTS_ARRAY is array (natural range <>, natural range <>) of std_logic_vector(7 downto 0); -- Supports weights up to 255.
--end package;

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
--USE WORK.ARRAY_2D.ALL;


entity DESERIALIZER is
    GENERIC (
        CELL_SIZE: INTEGER := 4;	
		NEIGHBORHOOD_SIZE : INTEGER := 3);
    PORT (
        -- ===== Inputs ===== --
        clk : in std_logic; -- CLK running at 100MHz
		rst : in std_logic; -- High active sychronous reset.		
		-- --- From UART. --- --
		data_in : in std_logic_vector(7 DOWNTO 0); -- One byte input from UART.
		data_in_valid: in std_logic; -- Data valid from UART
		-- ===== Outputs ===== --
		-- === To FIFO === --
		FIFO_data : out std_logic_vector(7 DOWNTO 0); -- Output to FIFO.
		FIFO_valid: out std_logic; -- Data valid to FIFO.
		-- For Weights.
		weights_row : out std_logic_vector(NEIGHBORHOOD_SIZE*(32/CELL_SIZE)-1 downto 0); -- A row of weights. If CELL_SIZE=4, then 8bit weights else 4bit weights.
		valid_weights_row: out std_logic; -- Valid out when row has been completed.
		-- === To CA_ENGINE or CA_ENGINE Sychronizer. === --
		-- For Transitions Rule.
		-- BRAM signals.
		BRAM_addr: out std_logic_vector(13 downto 0);
        BRAM_data: out std_logic_vector(CELL_SIZE-1 downto 0);
        BRAM_we: out std_logic;
		-- MUX signals.
		otherwise: out std_logic_vector(CELL_SIZE-1 downto 0);
		addr_sel: out integer range 0 to 1;
		-- === To SPEED_CONTROLLER AND WRITE_BACK === --
		total_gens: out std_logic_vector(13 downto 0) -- Up to 16,383.
    ); 
end DESERIALIZER;

architecture Behavioral of DESERIALIZER is
 
 -- TLV (Tag-Length-Value) communications. IDLE/TAG: Waits for the very first byte (Tag) given by each group of data. (Grid, Weights or Rule.)
 -- Second control byte concerns the length of the following data(Length control signal).
 -- All data are expressed as little-endian bytes.
 -- IDLE states jumps to LENGTH state. In LENGTH state we count the total amount of following data and the we jump to the VALUE state.
 -- In VALUE, we read data as long as the length counter determines.
 -- Finally, we return to IDLE/TAG state waiting for the next group of data.
 -- Optional values do not have a LENGTH field.
type STATE is (RESET, TAG, LENGTH, VALUE_REPEATED, VALUE_OPTIONAL);
signal FSM_STATE : STATE;

 -- ======= FOR TAG STATE ======= --
 -- Well-known control signals.
constant tag_time_step: std_logic_vector(7 downto 0) := "00001000"; -- Hex=0x08, Decimal = 8
constant tag_weights: std_logic_vector(7 downto 0) := "00010010"; -- Hex=0x12, Decimal = 18
constant tag_bram: std_logic_vector(7 downto 0) := "00011010"; -- Hex=0x1a, Decimal = 26
constant tag_others: std_logic_vector(7 downto 0) := "00100000"; -- Hex=0x20, Decimal = 32
constant tag_addr_sel: std_logic_vector(7 downto 0) := "00101000"; -- Hex=0x28, Decimal = 40
constant tag_grid: std_logic_vector(7 downto 0) := "00110010"; -- Hex=0x32, Decimal = 50
-- The select of demultiplexer.
signal data_kind: integer range 0 to 6 := 0;

-- ======= FOR LENGHT STATE ======= --
-- Counts the number of the following data. Worst case senario is when we have a grid full of 255s, 
-- where 255 needs 2 bytes to be expressed as little endian. (1 continuation bit + 7 bits of usefull information).
-- 1920*1080*2 = 4147200 needs 22 bits.
signal tag_length: std_logic_vector(21 downto 0) := (others => '0');
signal total_bytes_received: integer range 0 to 4147201 := 0;
 -- Its more than enough. Counts the bytes for the currently received value.
signal bytes_counter: integer range 0 to 7 := 0;

-- ======= FOR VALUES ======= --
 -- '13 downton 0' is suitable because we receive 2 bytes in worst case senario.
-- data_out and data_out_valid
signal signal_data_out: std_logic_vector(13 downto 0) := (OTHERS => '0');
signal signal_data_out_valid: std_logic;

-- Extra for Weights
signal signal_weight: std_logic_vector(7 downto 0) := (OTHERS => '0');
signal signal_valid_weight: std_logic := '0';
signal weights_counter: INTEGER RANGE 0 TO NEIGHBORHOOD_SIZE-1 := NEIGHBORHOOD_SIZE-1;
--signal sig_w_x, sig_w_y, w_x, w_y: INTEGER RANGE 0 TO NEIGHBORHOOD_SIZE-1 := NEIGHBORHOOD_SIZE-1;
--signal sig_w_x, sig_w_y: INTEGER RANGE 0 TO NEIGHBORHOOD_SIZE-1 := NEIGHBORHOOD_SIZE-1;

-- Extra for total gens
signal signal_total_gens: std_logic_vector(13 downto 0) := (OTHERS => '0');
signal total_gens_valid: std_logic := '0';

-- BRAM's write address
signal write_address: integer RANGE 0 to 16383 := 16383;
-- Otherwise's case value.
signal signal_others: std_logic_vector(CELL_SIZE-1 downto 0) := (OTHERS => '0');
signal signal_others_valid: std_logic := '0';
-- MUX selections
signal signal_addr_sel: integer range 0 to 1;
signal signal_addr_sel_valid: std_logic := '0';

begin

    DESERIALIZE: PROCESS
    BEGIN
        
        WAIT UNTIL CLK'EVENT AND CLK = '1';
        
        -- Jump to reset state.
        if rst = '1' then
            FSM_STATE <= RESET;
        else
            case FSM_STATE is
            
            when RESET =>
                tag_length <= (others => '0');
                bytes_counter <= 0;
                total_bytes_received <= 0;
                data_kind <= 0;                
                signal_data_out <= (others => '0');
                signal_data_out_valid <= '0';
                weights_counter <= NEIGHBORHOOD_SIZE-1;
                write_address <= 16383;
                FSM_STATE <= TAG;
                
            when TAG => -- wait for a tag
                signal_data_out <= (others => '0');
                signal_data_out_valid <= '0';       
                tag_length <= (others => '0');                
                bytes_counter <= 0;
                total_bytes_received <= 0;
                data_kind <= 0;
                weights_counter <= NEIGHBORHOOD_SIZE-1;
                write_address <= 16383;                                          
                if data_in = tag_grid and data_in_valid = '1' then
                    data_kind <= 1;
                    FSM_STATE <= LENGTH;
                elsif data_in = tag_weights and data_in_valid = '1' then 
                    data_kind <= 2;
                    FSM_STATE <= LENGTH;    
                elsif data_in = tag_time_step and data_in_valid = '1' then
                    data_kind <= 3; -- Time step is 'optional' and does not have Length field. Jump immediately to VALUE state.
                    FSM_STATE <= VALUE_OPTIONAL;
                elsif data_in = tag_bram and data_in_valid = '1' then
                    data_kind <= 4;
                    FSM_STATE <= LENGTH;
                elsif data_in = tag_others and data_in_valid = '1' then
                    data_kind <= 5; -- Time step is 'optional' and does not have Length field. Jump immediately to VALUE state.
                    FSM_STATE <= VALUE_OPTIONAL;
                elsif data_in = tag_addr_sel and data_in_valid = '1' then
                    data_kind <= 6; -- Time step is 'optional' and does not have Length field. Jump immediately to VALUE state.
                    FSM_STATE <= VALUE_OPTIONAL;
                else
                    FSM_STATE <= TAG;
                end if;
            
            when LENGTH =>                
                if data_in_valid = '1' then
                    --MSB '1' continuation bit, '0' stop bit.
                    if data_in(7) = '1' then
                        tag_length(7*(bytes_counter+1)-1 downto 7*bytes_counter) <= data_in(6 downto 0);
                        bytes_counter <= bytes_counter + 1;
                        FSM_STATE <= LENGTH;
                    else                        
                        -- Worst case senario is 1920x1080x2 = "1 1111101 0010000 0000000"
                        -- Serialized as 10000000 10010000 11111101 0000001, so, the last byte = 00000001. Only data_in(0) contains usefull information.
                        if bytes_counter >= 3 then
                            tag_length(21) <= data_in(0);
                        else
                            tag_length(7*(bytes_counter+1)-1 downto 7*bytes_counter) <= data_in(6 downto 0);
                        end if;                 
                        bytes_counter <= 0;-- Getting it ready for VALUE state.
                        FSM_STATE <= VALUE_REPEATED;
                    end if;
                else
                    FSM_STATE <= LENGTH;
               end if;    
            
            when VALUE_REPEATED =>               
                -- Valid data from UART and last byte to be received.
                -- Also we are sure the the worst case senario is to have a value = 255. 2-byte in protocol buffers
                if data_in_valid = '1' and total_bytes_received = to_integer(unsigned(tag_length))-1 then
                    -- The last byte always has stop bit (MSB='0')
                    if bytes_counter = 1 then -- Previous byte had continuation bit.           
                        signal_data_out(13 downto 7) <= data_in(6 downto 0);
                    else
                        signal_data_out <= "0000000" & data_in(6 downto 0);
                    end if;                    
                    signal_data_out_valid <= '1'; -- Data are ready.               
                    
                    -- Update weights' counter
                    if weights_counter = NEIGHBORHOOD_SIZE-1 then
                         weights_counter <= 0;
                    else
                         weights_counter <= weights_counter + 1;
                    end if;
                    
                    -- Update BRAM's  writing address
                    if write_address = 16383 then
                        write_address <= 0;
                    else
                        write_address <= write_address + 1;
                    end if;
                                                                
                    FSM_STATE <= TAG; -- Jump back to wait the next TAG.
                elsif data_in_valid = '1' and total_bytes_received < to_integer(unsigned(tag_length))-1 then
                    if data_in(7) = '1' then -- Continuation bit.
                        signal_data_out(6 downto 0) <= data_in(6 downto 0);
                        signal_data_out_valid <= '0'; -- Yet to be ready.
                        bytes_counter <= 1;                        
                    else -- Stop bit.
                        if bytes_counter = 1 then -- Previous byte had continuation bit.           
                            signal_data_out(13 downto 7) <= data_in(6 downto 0);                                
                        else 
                            signal_data_out <= "0000000" & data_in(6 downto 0);                                
                        end if;
                        bytes_counter <= 0; -- Reset this counter. Counts bytes received for the current value.
                        signal_data_out_valid <= '1'; -- Now the data are ready.
                        total_bytes_received <= total_bytes_received + 1;                     
                      
                        -- Update weights' counter
                        if weights_counter = NEIGHBORHOOD_SIZE-1 then
                            weights_counter <= 0;
                        else
                            weights_counter <= weights_counter + 1;
                        end if;
                        -- Update BRAM's  writing address
                        if write_address = 16383 then
                            write_address <= 0;
                        else
                            write_address <= write_address + 1;
                        end if;	 
                    end if;                
                                
                   FSM_STATE <= VALUE_REPEATED;
                else -- Otherwise, wait valid data.
                    signal_data_out_valid <= '0';
                    FSM_STATE <= VALUE_REPEATED;
                end if;
            
            when VALUE_OPTIONAL =>
                --Valid data from UART and last byte to be received.
                -- We know that we are going to receive up to bytes.
                if data_in_valid = '1' then
                    -- The last byte always has stop bit (MSB='0')
                    if data_in(7) = '1' then -- Continuation bit.
                        signal_data_out(6 downto 0) <= data_in(6 downto 0);
                        signal_data_out_valid <= '0'; -- Yet to be ready.
                        bytes_counter <= 1;
                        FSM_STATE <= VALUE_OPTIONAL;
                    else -- Stop bit
                        if bytes_counter = 1 then -- Previous byte had continuation bit. 
                            signal_data_out(13 downto 7) <= data_in(6 downto 0);                                                      
                        else 
                            signal_data_out <= "0000000" & data_in(6 downto 0);                                
                        end if;
                        bytes_counter <= 0; -- Reset this counter. Counts bytes received for the current value.
                        signal_data_out_valid <= '1'; -- Now the data are ready.
                        FSM_STATE <= TAG;   
                    end if;
                else -- Otherwise, wait valid data.
                    signal_data_out_valid <= '0';
                    FSM_STATE <= VALUE_OPTIONAL;
                end if;
            end case;
     end if;
END PROCESS;             

-- Demultiplexer according to kind of data
-- That way we drive incoming data to the proper modules.
DEMUX: PROCESS(data_kind, signal_data_out, signal_data_out_valid, write_address)
BEGIN
    if data_kind = 1 then -- Send them to FIFO
        FIFO_data <= signal_data_out(7 downto 0);
        FIFO_valid <= signal_data_out_valid;
        -- Unset rest valid signals.
        signal_valid_weight <= '0';
	    total_gens_valid <= '0';
	    BRAM_we <= '0';
	    signal_others_valid <= '0';
	    signal_addr_sel_valid <= '0'; 
    elsif data_kind = 2 then -- Weights.
        signal_weight <= signal_data_out(7 downto 0);      
		signal_valid_weight <= signal_data_out_valid;
        -- Unset rest valid signals.
        FIFO_valid <= '0';
	    total_gens_valid <= '0';
	    BRAM_we <= '0';
	    signal_others_valid <= '0';
	    signal_addr_sel_valid <= '0';
    elsif data_kind = 3 then -- For time step.
        signal_total_gens <= signal_data_out;
		total_gens_valid <= signal_data_out_valid;
		-- Unset rest valid signals.
		FIFO_valid <= '0';
	    signal_valid_weight <= '0';
	    BRAM_we <= '0';
	    signal_others_valid <= '0';
	    signal_addr_sel_valid <= '0';
	elsif data_kind = 4 then -- For time step.
        BRAM_data <= signal_data_out(CELL_SIZE-1 downto 0);
		BRAM_we <= signal_data_out_valid;
		BRAM_addr <= std_logic_vector(to_unsigned(write_address, BRAM_addr'length));
		-- Unset rest valid signals.
		FIFO_valid <= '0';
	    signal_valid_weight <= '0';
	    total_gens_valid <= '0';
	    signal_others_valid <= '0';
	    signal_addr_sel_valid <= '0';
	elsif data_kind = 5 then
	   signal_others <= signal_data_out(CELL_SIZE-1 downto 0);
	   signal_others_valid <= signal_data_out_valid;
	   -- Unset rest valid signals.
	   FIFO_valid <= '0';
	   signal_valid_weight <= '0';
	   total_gens_valid <= '0';
	   BRAM_we <= '0';
	   signal_addr_sel_valid <= '0';
	elsif data_kind = 6 then
	   signal_addr_sel <= to_integer(unsigned(signal_data_out));
	   signal_addr_sel_valid <= signal_data_out_valid;
	   -- Unset rest valid signals.
	   FIFO_valid <= '0';
	   signal_valid_weight <= '0';
	   total_gens_valid <= '0';
	   BRAM_we <= '0';
	   signal_others_valid <= '0';
    else
        -- To Init FIFO.
        FIFO_data <= (others => '0');
        FIFO_valid <= '0';
        -- For Weights
        signal_weight <= (others => '0');
        signal_valid_weight <= '0';
       -- w_x <= 0;
        --w_y <= 0;
        -- For Time Steps
        signal_total_gens <= (others => '0');
		total_gens_valid <= '0';
		-- To BRAM		
        BRAM_data <= (others => '0');
		BRAM_we <= '0';
		BRAM_addr <= (others => '0');
		-- To MUXes
		signal_others <= (others => '0');
		signal_others_valid <= '0';
		signal_addr_sel <= 0;
	    signal_addr_sel_valid <= '0';
    end if;
        
END PROCESS;

WEIGHTS_ROW_OUTPUT : PROCESS
BEGIN
    WAIT UNTIL RISING_EDGE(CLK);
    if signal_valid_weight = '1' and weights_counter = NEIGHBORHOOD_SIZE-1 then
        weights_row((32/CELL_SIZE)*(weights_counter+1)-1 downto (32/CELL_SIZE)*weights_counter) <= signal_weight((32/CELL_SIZE)-1 downto 0);
        valid_weights_row <= '1';
    elsif signal_valid_weight = '1' and weights_counter < NEIGHBORHOOD_SIZE-1 then
        weights_row((32/CELL_SIZE)*(weights_counter+1)-1 downto (32/CELL_SIZE)*weights_counter) <= signal_weight((32/CELL_SIZE)-1 downto 0);
        valid_weights_row <= '0';   
    else
        valid_weights_row <= '0';
    end if; 
END PROCESS;


REG_TOTAL_GENS : PROCESS
BEGIN
    WAIT UNTIL RISING_EDGE(CLK);
    if total_gens_valid = '1' then
        total_gens <= signal_total_gens;
    end if; 
END PROCESS;

REG_OTHERS : PROCESS
BEGIN
    WAIT UNTIL RISING_EDGE(CLK);
    if signal_others_valid = '1' then
        otherwise <= signal_others;
    end if; 
END PROCESS;

REG_ADDR_SEL : PROCESS
BEGIN
    WAIT UNTIL RISING_EDGE(CLK);
    if signal_addr_sel_valid = '1' then
        addr_sel <= signal_addr_sel;
    end if; 
END PROCESS;

end Behavioral;
