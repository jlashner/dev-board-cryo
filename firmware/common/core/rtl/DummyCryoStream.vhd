-------------------------------------------------------------------------------
-- File       : DummyCryoStream.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2018-06-20
-- Last update: 2018-06-20
-------------------------------------------------------------------------------
-- Description: Dummy data producer for cryo streaming interface
--
-- trig in kicks off frame.  
--    dataValid for 512 samples, dataIndex 0...511
--    data increment at clock rate
-------------------------------------------------------------------------------
-- This file is part of 'LCLS2 Common Carrier Core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'LCLS2 Common Carrier Core', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

use work.StdRtlPkg.all;

entity DummyCryoStream is
   generic (
      TPD_G : time := 1 ns);
   port (
      -- Clock and Reset
      clk        : in  sl;
      rst        : in  sl;
      -- Trigger (Flux ramp reset)
      trig       : in  sl;
      -- SYSGEN Interface
      dataValid  : out  sl;
      dataIndex  : out  slv(8 downto 0);
      data       : out  slv(15 downto 0);
      -- counter
      counter    : out slv(31 downto 0);
      counterRst : in  sl);
end DummyCryoStream;

architecture rtl of DummyCryoStream is

   constant SOF_CNT_C : slv(8 downto 0) := (others => '0');
   constant EOF_CNT_C : slv(8 downto 0) := (others => '1');

   type StateType is (
      IDLE_S,
      DATA_S);

   type RegType is record
      dataValid  : sl;
      dataIndex  : slv(8 downto 0);
      data       : slv(15 downto 0);
      counter    : slv(31 downto 0);
      state      : StateType;
   end record;

   constant REG_INIT_C : RegType := (
      dataValid  => '0',
      dataIndex  => (others => '0'),
      data       => (others => '0'),
      counter    => (others => '0'),
      state      => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal counterRstSync : sl;

begin

   U_SyncRst : entity work.Synchronizer
   generic map (
      TPD_G => TPD_G)
   port map (
      clk     => clk,
      dataIn  => counterRst,
      dataOut => counterRstSync);

   comb : process (r, rst, trig, counterRstSync) is
      variable v : RegType;
   begin
      -- Latch the current value
      v := r;

      -- increment data every clock (307.2 MHz for cryo)
      v.data := r.data + '1';

      -- State Machine
      case (r.state) is
         ----------------------------------------------------------------------
         when IDLE_S =>
            -- Reset
            v.dataIndex := (others => '0');
            if (trig = '1') then
               v.state     := DATA_S;
               v.dataValid := '1';
               v.counter   := r.counter + 1;
            end if;
         ----------------------------------------------------------------------
         when DATA_S =>
            v.dataIndex := r.dataIndex + 1;
            if ( r.dataIndex = EOF_CNT_C ) then
               v.state     := IDLE_S;
               v.dataValid := '0';
            end if;
         ----------------------------------------------------------------------
         end case;

      -- Synchronous Reset
      if (rst = '1') then
         v := REG_INIT_C;
      end if;

      if (counterRstSync = '1') then
         v.counter := (others => '0');
      end if;

      -- Register the variable for next clock cycle
      rin       <= v;

      -- Outputs
      dataIndex     <= r.dataIndex;
      dataValid     <= r.dataValid;
      data          <= r.data;
      counter       <= r.counter;
   end process comb;

   seq : process (clk) is
   begin
      if (rising_edge(clk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
