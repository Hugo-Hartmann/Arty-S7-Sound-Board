-------------------------------------------------------------------------------
-- Title      : ADC_CS5343
-- Project    : Arty-S7-Sound-Board

-- Compatible modes (24-bit) :
-- MCLK/LRCK | SCLK/LRCK | MCLK/SCLK

-- 256       | 64        | 4         |
-- 512       | 64        | 8         | Single Speed Mode
-- 384       | 48, 64    | 8, 6      |
-- 768       | 48, 64    | 16, 12    |

-- 128       | 64        | 2         |
-- 256       | 64        | 4         | Double Speed Mode
-- 192       | 48, 64    | 4, 3      |
-- 384       | 48, 64    | 8, 6      |
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity ADC_CS5343 is
    port(
        -- Clk and reset
        clk                 : in  std_logic;                                -- Used as MCLK
        rst_n               : in  std_logic;                                -- Async

        -- Config
        i_mclk_lrck_ratio   : in  std_logic_vector(10 downto 0);    -- min 64, max 1152
        i_mclk_sclk_ratio   : in  std_logic_vector(5 downto 0);     -- min 2, max 32

        -- Data interface (One way control since ADC cannot be paused)
        o_data_out          : out std_logic_vector(47 downto 0);        -- Left Channel = 24 LSB, Right Channel = 24 MSB
        o_data_valid        : out std_logic;                            -- Valid signal to indicate output data is valid200

        -- I2S interface
        o_mclk              : out std_logic;
        o_sclk              : out std_logic;
        o_lrck              : out std_logic;
        i_data              : in  std_logic
        );
end ADC_CS5343;

architecture RTL of ADC_CS5343 is

    -- SCLK / LRCK Generation
    signal s_sclk_max       : std_logic_vector(5 downto 0);
    signal s_sclk_counter   : unsigned(5 downto 0);
    signal s_lrck_max       : std_logic_vector(10 downto 0);
    signal s_lrck_counter   : unsigned(10 downto 0);
    signal s_sclk           : std_logic;
    signal s_lrck           : std_logic;

    -- SCLK / LRCK Pipeline
    signal s_sclk_d         : std_logic;
    signal s_lrck_d         : std_logic;

    -- SCLK / LRCK Edge detection
    signal s_sclk_f_edge    : std_logic;                        -- Falling edge used to detect end of frame
    signal s_sclk_r_edge    : std_logic;                        -- Rising edge used to shift data in
    signal s_lrck_f_edge    : std_logic;                        -- Edge used to know right channel transfer ended
    signal s_lrck_r_edge    : std_logic;                        -- Edge used to know left channel transfer ended
    signal s_sclk_f_edge_d  : std_logic_vector(3 downto 0);     -- Edge delayed
    signal s_sclk_r_edge_d  : std_logic_vector(3 downto 0);     -- Edge delayed
    signal s_lrck_f_edge_d  : std_logic_vector(3 downto 0);     -- Edge used to know right channel transfer ended
    signal s_lrck_r_edge_d  : std_logic_vector(3 downto 0);     -- Edge used to know left channel transfer ended

    -- Data management
    signal s_end_of_frame   : std_logic;
    signal s_shift_counter  : unsigned(4 downto 0);
    signal s_shift_enable   : std_logic;
    signal s_data_shift_reg : std_logic_vector(47 downto 0);
    signal s_data           : std_logic;

begin

    --------------------------------------------------------------------------------
    -- Map ratio config to maximum used for counter (divide by 2)
    --------------------------------------------------------------------------------
    s_sclk_max  <= '0' & i_mclk_sclk_ratio(5 downto 1);
    s_lrck_max  <= '0' & i_mclk_lrck_ratio(10 downto 1);

    --------------------------------------------------------------------------------
    -- proc_gen_sclk_lrck : Generate SCLK and LRCK
    --------------------------------------------------------------------------------
    proc_gen_sclk_lrck : process(clk, rst_n)
    begin
        if(rst_n = '0') then
            s_sclk_counter  <= to_unsigned(0, s_sclk_counter'length);
            s_lrck_counter  <= to_unsigned(0, s_lrck_counter'length);
            s_sclk          <= '0';
            s_lrck          <= '0';
        elsif(rising_edge(clk)) then
            -- Toggle LRCK and SCLK to make sure they are synced (even in case of config update)
            if(s_lrck_counter <= 0) then
                s_lrck_counter  <= unsigned(s_lrck_max) - 1;
                s_sclk_counter  <= unsigned(s_sclk_max) - 1;
                s_lrck          <= NOT s_lrck;
                s_sclk          <= '0';         -- SCLK falling edge on LRCK toggle
            -- Toggle of SCLK
            elsif(s_sclk_counter <= 0) then
                s_lrck_counter  <= s_lrck_counter - 1;
                s_sclk_counter  <= unsigned(s_sclk_max) - 1;
                s_sclk          <= NOT s_sclk;
            else
                s_lrck_counter  <= s_lrck_counter - 1;
                s_sclk_counter  <= s_sclk_counter - 1;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- proc_reg_sclk_lrck : Register SCLK and LRCK to detect edges and align data with clk
    --------------------------------------------------------------------------------
    proc_reg_sclk_lrck : process(clk, rst_n)
    begin
        if(rst_n = '0') then
            s_sclk_d    <= '0';
            s_lrck_d    <= '0';
        elsif(rising_edge(clk)) then
            s_sclk_d    <= s_sclk;
            s_lrck_d    <= s_lrck;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Edge detection
    --------------------------------------------------------------------------------
    s_sclk_f_edge   <= '1' when(s_sclk = '0' and s_sclk_d = '1') else '0';
    s_sclk_r_edge   <= '1' when(s_sclk = '1' and s_sclk_d = '0') else '0';
    s_lrck_f_edge   <= '1' when(s_lrck = '0' and s_lrck_d = '1') else '0';
    s_lrck_r_edge   <= '1' when(s_lrck = '1' and s_lrck_d = '0') else '0';

    --------------------------------------------------------------------------------
    -- proc_delay_edges : Delay SCLK edges to align with buffer input
    --------------------------------------------------------------------------------
    proc_delay_edges : process(clk, rst_n)
    begin
        if(rst_n = '0') then
            s_sclk_f_edge_d     <= (others => '0');
            s_sclk_r_edge_d     <= (others => '0');
            s_lrck_f_edge_d     <= (others => '0');
            s_lrck_r_edge_d     <= (others => '0');
        elsif(rising_edge(clk)) then
            s_sclk_f_edge_d(0)  <= s_sclk_f_edge;
            s_sclk_r_edge_d(0)  <= s_sclk_r_edge;
            s_lrck_f_edge_d(0)  <= s_lrck_f_edge;
            s_lrck_r_edge_d(0)  <= s_lrck_r_edge;
            for idx in 0 to 2 loop
                s_sclk_f_edge_d(idx+1)  <= s_sclk_f_edge_d(idx);
                s_sclk_r_edge_d(idx+1)  <= s_sclk_r_edge_d(idx);
                s_lrck_f_edge_d(idx+1)  <= s_lrck_f_edge_d(idx);
                s_lrck_r_edge_d(idx+1)  <= s_lrck_r_edge_d(idx);
            end loop;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- proc_transfer_management : Manage bit shifting and transfer end based on LRCK edges
    --------------------------------------------------------------------------------
    proc_reg_data_in : process(clk, rst_n)
    begin
        if(rst_n = '0') then
            s_end_of_frame  <= '0';
            s_shift_enable  <= '0';
            o_data_valid    <= '0';
            o_data_out      <= (others => '0');
            s_shift_counter <= to_unsigned(0, s_shift_counter'length);
        elsif(rising_edge(clk)) then
            -- Prepare to reset shift counter and set end_of_frame flag
            if(s_lrck_f_edge_d(3) = '1') then
                s_end_of_frame  <= '1';
                s_shift_enable  <= '1';
            -- Prepare to reset shift counter
            elsif(s_lrck_r_edge_d(3) = '1') then
                s_shift_enable  <= '1';
            elsif(s_sclk_f_edge_d(3) ='1') then
                -- Next SCLK falling edge after LRCK falling edge is end of last frame
                if(s_end_of_frame = '1') then
                    o_data_valid    <= '1';
                    o_data_out      <= s_data_shift_reg;
                    s_end_of_frame  <= '0';
                end if;
                -- Shift counter is reset on SCLK falling edge following a LRCK edge
                if(s_shift_enable = '1') then
                    s_shift_enable  <= '0';
                    s_shift_counter <= to_unsigned(0, s_shift_counter'length);
                end if;
            -- Increase shift counter if 24 bits are not already received
            elsif(s_sclk_r_edge_d(3) = '1' and s_shift_counter < 24) then
                s_shift_counter <= s_shift_counter + 1;
            else
                o_data_valid    <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- proc_shift_data : Shift data to output
    --------------------------------------------------------------------------------
    proc_shift_data : process(clk, rst_n)
    begin
        if(rst_n = '0') then
            s_data_shift_reg    <= (others => '0');
        elsif(rising_edge(clk)) then
            -- Shift by 1 bit
            if(s_sclk_r_edge_d(3) = '1' and s_shift_counter < 24) then
                s_data_shift_reg    <= s_data_shift_reg(46 downto 0) & s_data;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Assign outputs using ODDR buffers
    --------------------------------------------------------------------------------
    inst_ODDR_MCLK : ODDR generic map(
       DDR_CLK_EDGE => "SAME_EDGE",
       INIT         => '0',
       SRTYPE       => "SYNC") -- Reset Type ("ASYNC" or "SYNC")
    port map (
       Q    => o_mclk,
       C    => clk,
       CE   => '1',
       D1   => '1',
       D2   => '0',
       R    => '0',
       S    => '0'
    );

    inst_ODDR_SCLK : ODDR generic map(
       DDR_CLK_EDGE => "SAME_EDGE",
       INIT         => '0',
       SRTYPE       => "SYNC") -- Reset Type ("ASYNC" or "SYNC")
    port map (
       Q    => o_sclk,
       C    => clk,
       CE   => '1',
       D1   => s_sclk_d,
       D2   => s_sclk_d,
       R    => '0',
       S    => '0'
    );

    inst_ODDR_LRCK : ODDR generic map(
       DDR_CLK_EDGE => "SAME_EDGE",
       INIT         => '0',
       SRTYPE       => "SYNC") -- Reset Type ("ASYNC" or "SYNC")
    port map (
       Q    => o_lrck,
       C    => clk,
       CE   => '1',
       D1   => s_lrck_d,
       D2   => s_lrck_d,
       R    => '0',
       S    => '0'
    );

    inst_IDDR_DATA : IDDR generic map(
       DDR_CLK_EDGE => "SAME_EDGE_PIPELINED",
       INIT_Q1      => '0',
       INIT_Q2      => '0',
       SRTYPE       => "SYNC") -- Reset Type ("ASYNC" or "SYNC")
    port map (
       Q1   => s_data,
       Q2   => open,
       C    => clk,
       CE   => '1',
       D    => i_data,
       R    => '0',
       S    => '0'
    );

end RTL;
