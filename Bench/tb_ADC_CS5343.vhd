-------------------------------------------------------------------------------
-- Title      : tb_ADC_CS5343
-- Project    : Arty-S7-Sound-Board
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;

entity tb_ADC_CS5343 is
end tb_ADC_CS5343;

architecture RTL of tb_ADC_CS5343 is

    -- Bench signals
    signal clk                  : std_logic := '0';
    signal rst_n                : std_logic;

    signal s_mclk_lrck_ratio    : std_logic_vector(10 downto 0);
    signal s_mclk_sclk_ratio    : std_logic_vector(5 downto 0);

    signal s_data_in            : std_logic_vector(47 downto 0) := X"F1111F_088880";
    signal s_data_ready         : std_logic;

    signal s_data_out           : std_logic_vector(47 downto 0) := X"F1111F_088880";
    signal s_data_valid         : std_logic;

    signal s_mclk               : std_logic;
    signal s_sclk               : std_logic;
    signal s_lrck               : std_logic;
    signal s_data               : std_logic;

begin

    --------------------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------------------
    inst_ADC_CS5343 : entity work.ADC_CS5343 port map (
        clk                 => clk,
        rst_n               => rst_n,
        i_mclk_lrck_ratio   => s_mclk_lrck_ratio,
        i_mclk_sclk_ratio   => s_mclk_sclk_ratio,
        o_data_out          => s_data_out,
        o_data_valid        => s_data_valid,
        o_mclk              => s_mclk,
        o_sclk              => s_sclk,
        o_lrck              => s_lrck,
        i_data              => s_data
    );

    --------------------------------------------------------------------------------
    -- DAC
    --------------------------------------------------------------------------------
    inst_DAC_CS4344 : entity work.DAC_CS4344 port map (
        clk                 => clk,
        rst_n               => rst_n,
        i_mclk_lrck_ratio   => s_mclk_lrck_ratio,
        i_mclk_sclk_ratio   => s_mclk_sclk_ratio,
        i_data_in           => s_data_in,
        o_data_ready        => s_data_ready,
        o_mclk              => open,
        o_sclk              => open,
        o_lrck              => open,
        o_data              => s_data
    );

    --------------------------------------------------------------------------------
    -- CLK
    --------------------------------------------------------------------------------
    process(clk)
    begin
        clk <= NOT clk after 10 ns;
    end process;

    --------------------------------------------------------------------------------
    -- RESET
    --------------------------------------------------------------------------------
    rst_n   <= '0', '1' after 100 ns;

    --------------------------------------------------------------------------------
    -- MAIN
    --------------------------------------------------------------------------------
    process
    begin
        s_mclk_lrck_ratio   <= std_logic_vector(to_unsigned(384, 11));
        s_mclk_sclk_ratio   <= std_logic_vector(to_unsigned(384/48, 6));
        wait for 50 us;

        s_mclk_lrck_ratio   <= std_logic_vector(to_unsigned(384, 11));
        s_mclk_sclk_ratio   <= std_logic_vector(to_unsigned(384/64, 6));
        wait for 50 us;

        assert false report "Simulation End" severity failure;
    end process;

end RTL;
