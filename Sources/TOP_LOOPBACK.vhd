-------------------------------------------------------------------------------
-- Title      : TOP_LOOPBACK
-- Project    : Arty-S7-Sound-Board

-- Basic loopback from ADC to DAC
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity TOP_LOOPBACK is
    port(
        -- Clk
        clk_12mhz       : in  std_logic;

        -- LED
        o_led0          : out std_logic;

        ------- Audio interface -----------------
        o_dac_i2s_mclk  : out std_logic;
        o_dac_i2s_lrck  : out std_logic;
        o_dac_i2s_sclk  : out std_logic;
        o_dac_i2s_data  : out std_logic;
        o_adc_i2s_mclk  : out std_logic;
        o_adc_i2s_lrck  : out std_logic;
        o_adc_i2s_sclk  : out std_logic;
        i_adc_i2s_data  : in  std_logic
        );
end TOP_LOOPBACK;

architecture RTL of TOP_LOOPBACK is

    signal s_data   : std_logic_vector(47 downto 0);

    signal clk      : std_logic;
    signal clk_fb   : std_logic;
    signal rst_n    : std_logic;

begin

    MMCME2_BASE_inst : MMCME2_BASE
    generic map (
       BANDWIDTH => "OPTIMIZED",  -- Jitter programming (OPTIMIZED, HIGH, LOW)
       CLKFBOUT_MULT_F => 63.750,    -- Multiply value for all CLKOUT (2.000-64.000).
       CLKFBOUT_PHASE => 0.0,     -- Phase offset in degrees of CLKFB (-360.000-360.000).
       CLKIN1_PERIOD => 83.333,      -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
       -- CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
       CLKOUT1_DIVIDE => 1,
       CLKOUT2_DIVIDE => 1,
       CLKOUT3_DIVIDE => 1,
       CLKOUT4_DIVIDE => 1,
       CLKOUT5_DIVIDE => 1,
       CLKOUT6_DIVIDE => 1,
       CLKOUT0_DIVIDE_F => 21.250,   -- Divide amount for CLKOUT0 (1.000-128.000).
       -- CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
       CLKOUT0_DUTY_CYCLE => 0.5,
       CLKOUT1_DUTY_CYCLE => 0.5,
       CLKOUT2_DUTY_CYCLE => 0.5,
       CLKOUT3_DUTY_CYCLE => 0.5,
       CLKOUT4_DUTY_CYCLE => 0.5,
       CLKOUT5_DUTY_CYCLE => 0.5,
       CLKOUT6_DUTY_CYCLE => 0.5,
       -- CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
       CLKOUT0_PHASE => 0.0,
       CLKOUT1_PHASE => 0.0,
       CLKOUT2_PHASE => 0.0,
       CLKOUT3_PHASE => 0.0,
       CLKOUT4_PHASE => 0.0,
       CLKOUT5_PHASE => 0.0,
       CLKOUT6_PHASE => 0.0,
       CLKOUT4_CASCADE => FALSE,  -- Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
       DIVCLK_DIVIDE => 1,        -- Master division value (1-106)
       REF_JITTER1 => 0.0,        -- Reference input jitter in UI (0.000-0.999).
       STARTUP_WAIT => FALSE      -- Delays DONE until MMCM is locked (FALSE, TRUE)
    )
    port map (
       -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
       CLKOUT0 => clk,     -- 1-bit output: CLKOUT0
       CLKOUT0B => open,   -- 1-bit output: Inverted CLKOUT0
       CLKOUT1 => open,     -- 1-bit output: CLKOUT1
       CLKOUT1B => open,   -- 1-bit output: Inverted CLKOUT1
       CLKOUT2 => open,     -- 1-bit output: CLKOUT2
       CLKOUT2B => open,   -- 1-bit output: Inverted CLKOUT2
       CLKOUT3 => open,     -- 1-bit output: CLKOUT3
       CLKOUT3B => open,   -- 1-bit output: Inverted CLKOUT3
       CLKOUT4 => open,     -- 1-bit output: CLKOUT4
       CLKOUT5 => open,     -- 1-bit output: CLKOUT5
       CLKOUT6 => open,     -- 1-bit output: CLKOUT6
       -- Feedback Clocks: 1-bit (each) output: Clock feedback ports
       CLKFBOUT => clk_fb,   -- 1-bit output: Feedback clock
       CLKFBOUTB => open, -- 1-bit output: Inverted CLKFBOUT
       -- Status Ports: 1-bit (each) output: MMCM status ports
       LOCKED => rst_n,       -- 1-bit output: LOCK
       -- Clock Inputs: 1-bit (each) input: Clock input
       CLKIN1 => clk_12mhz,       -- 1-bit input: Clock
       -- Control Ports: 1-bit (each) input: MMCM control ports
       PWRDWN => '0',       -- 1-bit input: Power-down
       RST => '0',             -- 1-bit input: Reset
       -- Feedback Clocks: 1-bit (each) input: Clock feedback ports
       CLKFBIN => clk_fb      -- 1-bit input: Feedback clock
    );

    --------------------------------------------------------------------------------
    -- ADC
    --------------------------------------------------------------------------------
    inst_ADC_CS5343 : entity work.ADC_CS5343 port map (
        clk                 => clk,
        rst_n               => rst_n,
        i_mclk_lrck_ratio   => "00110000000",
        i_mclk_sclk_ratio   => "001000",
        o_data_out          => s_data,
        o_data_valid        => open,
        o_mclk              => o_adc_i2s_mclk,
        o_sclk              => o_adc_i2s_sclk,
        o_lrck              => o_adc_i2s_lrck,
        i_data              => i_adc_i2s_data
    );

    --------------------------------------------------------------------------------
    -- DAC
    --------------------------------------------------------------------------------
    inst_DAC_CS4344 : entity work.DAC_CS4344 port map (
        clk                 => clk,
        rst_n               => rst_n,
        i_mclk_lrck_ratio   => "00110000000",
        i_mclk_sclk_ratio   => "001000",
        i_data_in           => s_data,
        o_data_ready        => open,
        o_mclk              => o_dac_i2s_mclk,
        o_sclk              => o_dac_i2s_sclk,
        o_lrck              => o_dac_i2s_lrck,
        o_data              => o_dac_i2s_data
    );

    o_led0  <= '1';

end RTL;
