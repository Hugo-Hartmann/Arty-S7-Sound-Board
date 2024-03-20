-------------------------------------------------------------------------------
-- Title      : DAC_CS4344
-- Project    : Arty-S7-Sound-Board
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity DAC_CS4344 is
    port(
        -- Clk and reset
        clk                 : in  std_logic;                                -- Used as MCLK
        rst_n               : in  std_logic;                                -- Async

        -- Config
        i_mclk_lrck_ratio   : in  std_logic_vector(10 downto 0);    -- min 64, max 1152
        i_mclk_sclk_ratio   : in  std_logic_vector(5 downto 0);     -- min 2, max 32

        -- Data interface (One way control since DAC cannot be paused)
        i_data_in           : in  std_logic_vector(47 downto 0);        -- Left Channel = 24 LSB, Right Channel = 24 MSB
        o_data_ready        : out std_logic;                            -- Ready signal to indicate input data has been consummed

        -- I2S interface
        o_mclk              : out std_logic;
        o_sclk              : out std_logic;
        o_lrck              : out std_logic;
        o_data              : out std_logic
        );
end DAC_CS4344;

architecture RTL of DAC_CS4344 is

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
    signal s_sclk_f_edge    : std_logic;        -- Only falling edge used to shift data out
    signal s_lrck_f_edge    : std_logic;        -- Edge used to init data transfer on left channel
    signal s_lrck_r_edge    : std_logic;        -- Edge used to init data transfer on right channel

    -- Data input register
    signal s_data_in_d      : std_logic_vector(47 downto 0);

    -- Data management
    signal s_data_shift_reg : std_logic_vector(23 downto 0);

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
    s_lrck_f_edge   <= '1' when(s_lrck = '0' and s_lrck_d = '1') else '0';
    s_lrck_r_edge   <= '1' when(s_lrck = '1' and s_lrck_d = '0') else '0';

    --------------------------------------------------------------------------------
    -- proc_reg_data_in : Register data input on LRCK falling edge
    --------------------------------------------------------------------------------
    proc_reg_data_in : process(clk, rst_n)
    begin
        if(rst_n = '0') then
            o_data_ready    <= '0';
            s_data_in_d     <= (others => '0');
        elsif(rising_edge(clk)) then
            if(s_lrck_f_edge = '1') then
                o_data_ready    <= '1';
                s_data_in_d     <= i_data_in;
            else
                o_data_ready    <= '0';
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
            -- Load new data LSB (left channel) and last bit of previous data (right channel)
            if(s_lrck_f_edge = '1') then
                s_data_shift_reg    <= s_data_in_d(24) & i_data_in(23 downto 1);
            -- Load registered data MSB (right channel) and last bit of previous data (left channel)
            elsif(s_lrck_r_edge = '1') then
                s_data_shift_reg    <= s_data_in_d(0) & s_data_in_d(47 downto 25);
            -- Shift by 1 bit
            elsif(s_sclk_f_edge = '1') then
                s_data_shift_reg    <= s_data_shift_reg(22 downto 0) & '0';
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

    inst_ODDR_DATA : ODDR generic map(
       DDR_CLK_EDGE => "SAME_EDGE",
       INIT         => '0',
       SRTYPE       => "SYNC") -- Reset Type ("ASYNC" or "SYNC")
    port map (
       Q    => o_data,
       C    => clk,
       CE   => '1',
       D1   => s_data_shift_reg(23),
       D2   => s_data_shift_reg(23),
       R    => '0',
       S    => '0'
    );

end RTL;
