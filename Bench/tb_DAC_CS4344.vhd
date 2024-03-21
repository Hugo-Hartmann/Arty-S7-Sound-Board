-------------------------------------------------------------------------------
-- Title      : tb_DAC_CS4344
-- Project    : Arty-S7-Sound-Board
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;

entity tb_DAC_CS4344 is
end tb_DAC_CS4344;

architecture RTL of tb_DAC_CS4344 is

    -- Bench signals
    signal clk                  : std_logic := '0';
    signal rst_n                : std_logic;

    signal s_mclk_lrck_ratio    : std_logic_vector(10 downto 0);
    signal s_mclk_sclk_ratio    : std_logic_vector(5 downto 0);

    signal s_data_in            : std_logic_vector(47 downto 0) := X"F1111F_088880";
    signal s_data_ready         : std_logic;

    signal s_mclk               : std_logic;
    signal s_sclk               : std_logic;
    signal s_lrck               : std_logic;
    signal s_data               : std_logic;

begin

    --------------------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------------------
    inst_DAC_CS4344 : entity work.DAC_CS4344 port map (
        clk                 => clk,
        rst_n               => rst_n,
        i_mclk_lrck_ratio   => s_mclk_lrck_ratio,
        i_mclk_sclk_ratio   => s_mclk_sclk_ratio,
        i_data_in           => s_data_in,
        o_data_ready        => s_data_ready,
        o_mclk              => s_mclk,
        o_sclk              => s_sclk,
        o_lrck              => s_lrck,
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

        s_mclk_lrck_ratio   <= std_logic_vector(to_unsigned(1152, 11));
        s_mclk_sclk_ratio   <= std_logic_vector(to_unsigned(1152/72, 6));
        wait for 100 us;

        assert false report "Simulation End" severity failure;
    end process;

end RTL;
