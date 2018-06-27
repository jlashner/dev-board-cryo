-------------------------------------------------------------------------------
-- File       : AppCore.vhd
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description:
-------------------------------------------------------------------------------
-- This file is part of 'DevBoard Common Platform'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'DevBoard Common Platform', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.SsiPkg.all;
use work.TimingPkg.all;
use work.AmcCarrierPkg.all;
use work.Jesd204bPkg.all;
use work.AppTopPkg.all;
use work.AppCorePkg.all;

-- Note: use single definition of entity in AppCore/rtl/AppCoreEntity.vhd

architecture Stub of AppCore is

   constant NUM_AXI_MASTERS_C : natural := 4;

   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXI_MASTERS_C, AXIL_BASE_ADDR_G, 28, 24);  -- [0x8FFFFFFF:0x80000000]

   constant AMC_INDEX_C : natural := 0;
   constant DSP_INDEX_C : natural := 1;
   constant RTM_INDEX_C : natural := 2;
   constant REG_INDEX_C : natural := 3;

   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);

   signal dacSigTrigArm   : sl;
   signal dacSigTrigDelay : slv(23 downto 0);

   signal enableStreams   : slv(7 downto 0);
   signal trigStream      : slv(7 downto 0);

   signal startRamp  : sl;
   signal selectRamp : sl;
   signal rampCnt    : slv(31 downto 0);

   signal s_dacValues  :  sampleDataVectorArray(1 downto 0, 9 downto 0);

   signal jesdClkVec : slv(7 downto 0) := (others => '0');
   signal jesdRstVec : slv(7 downto 0) := (others => '0');


   signal streamValid : slv(7 downto 0)  := (others => '0');
   signal streamIndex : Slv9Array(7 downto 0);
   signal streamData  : Slv16Array(7 downto 0);

begin
   ---------------------
   -- AXI-Lite Crossbar
   ---------------------
   U_XBAR : entity work.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         DEC_ERROR_RESP_G   => AXI_RESP_SLVERR_C,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXI_MASTERS_C,
         MASTERS_CONFIG_G   => AXI_CONFIG_C)
      port map (
         axiClk              => axilClk,
         axiClkRst           => axilRst,
         sAxiWriteMasters(0) => sAxilWriteMaster,
         sAxiWriteSlaves(0)  => sAxilWriteSlave,
         sAxiReadMasters(0)  => sAxilReadMaster,
         sAxiReadSlaves(0)   => sAxilReadSlave,
         mAxiWriteMasters    => axilWriteMasters,
         mAxiWriteSlaves     => axilWriteSlaves,
         mAxiReadMasters     => axilReadMasters,
         mAxiReadSlaves      => axilReadSlaves);

   MORE_MAPPING : 
   for i in 3 downto 0 generate

      jesdClkVec(i)   <= jesdClk(0);
      jesdRstVec(i)   <= jesdClk(0);

      jesdClkVec(i+4) <= jesdClk(1);
      jesdRstVec(i+4) <= jesdClk(1);

   end generate;


   RTM_SIM : entity work.RtmCryoSim
      generic map (
         TPD_G           => TPD_G,
         AXI_BASE_ADDR_G  => AXI_CONFIG_C(RTM_INDEX_C).baseAddr)
      port map (
         -- JESD clock and reset
         jesdClk         => jesdClk(0),
         jesdRst         => jesdRst(0),
         -- Digital I/O
         startRamp       => startRamp,
         selectRamp      => selectRamp,
         rampCnt         => rampCnt,
         -- AXI-Lite Interface
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(RTM_INDEX_C),
         axilReadSlave   => axilReadSlaves(RTM_INDEX_C),
         axilWriteMaster => axilWriteMasters(RTM_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(RTM_INDEX_C));

   ------------------
   -- Local Registers
   ------------------   
   U_REG : entity work.AppCoreReg
      generic map (
         TPD_G            => TPD_G)
      port map (
         -- Configuration/Status
         dacSigTrigArm   => dacSigTrigArm,
         dacSigTrigDelay => dacSigTrigDelay,
         enableStreams   => enableStreams,
         -- AXI-Lite Interface
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(REG_INDEX_C),
         axilReadSlave   => axilReadSlaves(REG_INDEX_C),
         axilWriteMaster => axilWriteMasters(REG_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(REG_INDEX_C));

   -----------------
   -- Trigger Module
   -----------------
   U_TRIG : entity work.AppCoreTrig
      generic map (
         TPD_G => TPD_G)
      port map (
         jesdClk         => jesdClk(0),
         jesdRst         => jesdRst(0),
         dacSigTrigArm   => dacSigTrigArm,
         dacSigTrigDelay => dacSigTrigDelay,
         dacSigStatus    => dacSigStatus(0),
         -- evrTrig         => evrTrig.trigPulse(0),
         evrTrig         => '0',        -- ignore EVR
         trigHw          => trigHw(0),
         freezeHw        => freezeHw(0));

   -----------------
   -- Trigger Module
   -----------------
   U_GEN_STREAM : 
   for i in 7 downto 0 generate

      trigStream(i) <= startRamp AND enableStreams(i);

      U_Stream : entity work.DummyCryoStream
         generic map (
            TPD_G     => TPD_G)
         port map (
            clk       => jesdClk(0),
            rst       => jesdRst(0),
            trig      => trigStream(i),
            dataValid => streamValid(i),
            dataIndex => streamIndex(i),
            data      => streamData(i));

   end generate;


   U_ProcDataFramer : entity work.AxisSysgenProcDataFramer
      generic map (
         BUILD_DSP_G => BUILD_DSP_G,
         TPD_G       => TPD_G)
      port map (
         -- Input timing interface (timingClk domain)
         timingClk       => timingClk,
         timingRst       => timingRst,
         timingTimestamp => timingBus.message.timestamp,
         -- Input Data Interface (jesdClk domain)
         jesdClk         => jesdClkVec,
         jesdRst         => jesdRstVec,
         dataValid       => streamValid,
         dataIndex       => streamIndex,
         data            => streamData,
         -- Output AXIS Interface (axisClk domain)
         axisClk         => axilClk,
         axisRst         => axilRst,
         axisMaster      => obAppDebugMaster,
         axisSlave       => obAppDebugSlave);

end architecture Stub;
