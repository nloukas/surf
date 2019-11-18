-------------------------------------------------------------------------------
-- Title      : SSI Protocol: https://confluence.slac.stanford.edu/x/0oyfD
-------------------------------------------------------------------------------
-- File       : SsiFifoTb.vhd
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Simulation Testbed for testing the SsiFifo module
-------------------------------------------------------------------------------
-- This file is part of 'SLAC Firmware Standard Library'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC Firmware Standard Library', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;


library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;
use surf.EthMacPkg.all;

entity SsiFifoTb is end SsiFifoTb;

architecture testbed of SsiFifoTb is

   -- Constants
   constant SLOW_CLK_PERIOD_C  : time             := 3.2 ns;
   constant FAST_CLK_PERIOD_C  : time             := 3.2 ns; --SLOW_CLK_PERIOD_C/3.14;
   constant TPD_C              : time             := 0.5 ns;--FAST_CLK_PERIOD_C/4;
   constant STATUS_CNT_WIDTH_C : natural          := 32;
   constant TX_PACKET_LENGTH_C : slv(31 downto 0) := toSlv(100, 32);
   constant NUMBER_PACKET_C    : slv(31 downto 0) := toSlv(4096, 32);

   -- FIFO configurations
   constant MEMORY_TYPE_C       : string  := "block";
   constant CASCADE_SIZE_C      : natural := 1;
   constant FIFO_ADDR_WIDTH_C   : natural := 9;
   constant FIFO_PAUSE_THRESH_C : natural := 2**8;

   -- PRBS Configuration
   constant PRBS_SEED_SIZE_C : natural      := 32;
   constant PRBS_TAPS_C      : NaturalArray := (0 => 31, 1 => 6, 2 => 2, 3 => 1);
   constant FORCE_EOFE_C     : sl           := '0';  -- Forces an error (testing tUser field MUX-ing)

   -- AXI Stream Configurations
   constant AXI_STREAM_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 8,
      TDEST_BITS_C  => 8,
      TID_BITS_C    => 8,
      TKEEP_MODE_C  => TKEEP_COMP_C,
      TUSER_BITS_C  => 2,
      TUSER_MODE_C  => TUSER_FIRST_LAST_C);
   
   constant AXI_PIPE_STAGES_C   : natural             := 0;

   -- Signals
   signal fastClk : sl := '0';
   signal fastRst : sl := '1';

   signal slowClk : sl := '0';
   signal slowRst : sl := '1';

   signal dropWrite  : sl := '0';
   signal dropFrame  : sl := '0';
   signal passedSlow : sl := '0';
   signal failedSlow : sl := '0';
   signal failedFast : sl := '0';

   signal updated         : sl := '0';
   signal errMissedPacket : sl := '0';
   signal errLength       : sl := '0';
   signal errDataBus      : sl := '0';
   signal errEofe         : sl := '0';

   signal errWordCnt : slv(31 downto 0) := (others => '0');
   signal errbitCnt  : slv(31 downto 0) := (others => '0');
   signal cnt        : slv(31 downto 0) := (others => '0');

   signal ibMaster : AxiStreamMasterType;
   signal ibSlave  : AxiStreamSlaveType;
   signal ssiFifoMaster : AxiStreamMasterType;
   signal ssiFifoSlave : AxiStreamSlaveType;
   signal obMaster : AxiStreamMasterType;
   signal obSlave  : AxiStreamSlaveType;

begin

   ---------------------------------------
   -- Generate fast clocks and fast resets
   ---------------------------------------
   ClkRst_Fast : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => FAST_CLK_PERIOD_C,
         RST_START_DELAY_G => 0 ns,     -- Wait this long into simulation before asserting reset
         RST_HOLD_TIME_G   => 200 ns)   -- Hold reset for this long)
      port map (
         clkP => fastClk,
         clkN => open,
         rst  => fastRst,
         rstL => open); 

   ClkRst_Slow : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => SLOW_CLK_PERIOD_C,
         RST_START_DELAY_G => 0 ns,     -- Wait this long into simulation before asserting reset
         RST_HOLD_TIME_G   => 200 ns)   -- Hold reset for this long)
      port map (
         clkP => slowClk,
         clkN => open,
         rst  => slowRst,
         rstL => open);          

   --------------
   -- Data Source
   --------------
   SsiPrbsTx_Inst : entity surf.SsiPrbsTx
      generic map (
         -- General Configurations
         TPD_G                      => TPD_C,
         -- FIFO configurations
         MEMORY_TYPE_G              => MEMORY_TYPE_C,
         GEN_SYNC_FIFO_G            => true,
         CASCADE_SIZE_G             => CASCADE_SIZE_C,
         FIFO_ADDR_WIDTH_G          => FIFO_ADDR_WIDTH_C,
         FIFO_PAUSE_THRESH_G        => FIFO_PAUSE_THRESH_C,
         -- PRBS Configurations
         PRBS_SEED_SIZE_G           => PRBS_SEED_SIZE_C,
         PRBS_TAPS_G                => PRBS_TAPS_C,
         -- AXI Stream Configurations
         MASTER_AXI_STREAM_CONFIG_G => AXI_STREAM_CONFIG_C,
         MASTER_AXI_PIPE_STAGES_G   => AXI_PIPE_STAGES_C)        
      port map (
         -- Master Port (mAxisClk)
         mAxisClk     => fastClk,
         mAxisRst     => fastRst,
         mAxisMaster  => obMaster,
         mAxisSlave   => obSlave,
         -- Trigger Signal (locClk domain)
         locClk       => fastClk,
         locRst       => fastRst,
         trig         => '1',
         packetLength => TX_PACKET_LENGTH_C,
         forceEofe    => FORCE_EOFE_C,
         busy         => open,
         tDest        => X"12",
         tId          => X"34");

   U_AxiStreamPacketizer_1 : entity surf.AxiStreamPacketizer
      generic map (
         TPD_G                => TPD_C,
         MAX_PACKET_BYTES_C   => 1400,
         INPUT_PIPE_STAGES_G  => 1,
         OUTPUT_PIPE_STAGES_G => 1)
      port map (
         axisClk     => fastClk,                 -- [in]
         axisRst     => fastRst,                 -- [in]
         sAxisMaster => obMaster,      -- [in]
         sAxisSlave  => obSlave,       -- [out]
         mAxisMaster => ssiFifoMaster,  -- [out]
         mAxisSlave  => ssiFifoSlave);  -- [in]
   ----------------------------   
   -- Data Filter (Test Module)
   ----------------------------
   U_AxiStreamFifo_PacketOut : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_C,
         PIPE_STAGES_G       => 0,
         SLAVE_READY_EN_G    => true,
         VALID_THOLD_G       => 1,
         -- FIFO configurations
         MEMORY_TYPE_G       => "distributed",
         GEN_SYNC_FIFO_G     => true,
         CASCADE_SIZE_G      => 1,
         FIFO_ADDR_WIDTH_G   => 4,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => AXI_STREAM_CONFIG_C,
         MASTER_AXI_CONFIG_G => EMAC_AXIS_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => fastClk,
         sAxisRst    => fastRst,
         sAxisMaster => ssiFifoMaster,
         sAxisSlave  => ssiFifoSlave,
         -- Master Port
         mAxisClk    => fastRst,
         mAxisRst    => fastRst,
         mAxisMaster => ibMaster,
         mAxisSlave  => ibSlave); 

--    SsiFifo_Inst : entity surf.SsiFifo
--       generic map (
--          -- General Configurations
--          TPD_G               => TPD_C,
--          PIPE_STAGES_G       => AXI_PIPE_STAGES_C,
--          EN_FRAME_FILTER_G   => true,
--          VALID_THOLD_G       => 1,
--          -- FIFO configurations
--          MEMORY_TYPE_G       => MEMORY_TYPE_C,
--          GEN_SYNC_FIFO_G     => false,
--          CASCADE_SIZE_G      => CASCADE_SIZE_C,
--          FIFO_ADDR_WIDTH_G   => FIFO_ADDR_WIDTH_C,
--          FIFO_PAUSE_THRESH_G => FIFO_PAUSE_THRESH_C,
--          -- AXI Stream Port Configurations
--          SLAVE_AXI_CONFIG_G  => AXI_STREAM_CONFIG_C,
--          MASTER_AXI_CONFIG_G => AXI_STREAM_CONFIG_C)
--       port map (
--          -- Slave Port
--          sAxisClk       => fastClk,
--          sAxisRst       => fastRst,
--          sAxisMaster    => ssiFifoMaster,
--          sAxisSlave     => ssiFifoSlave,
--          sAxisCtrl      => open,
--          sAxisDropWrite => dropWrite,
--          sAxisTermFrame => dropFrame,
--          -- Master Port
--          mAxisClk       => slowClk,
--          mAxisRst       => slowRst,
--          mAxisMaster    => ibMaster,
--          mAxisSlave     => ibSlave);

   ibSlave <= AXI_STREAM_SLAVE_FORCE_C;

--    process(fastClk)
--    begin
--       if rising_edge(fastClk) then
--          if fastRst = '1' then
--             failedFast <= '0' after TPD_C;
--          else
--             -- Check for dropped word error
--             if dropWrite = '1' then
--                failedFast <= '1' after TPD_C;
--             end if;
--             -- Check for dropped frame error
--             if dropFrame = '1' then
--                failedFast <= '1' after TPD_C;
--             end if;
--          end if;
--       end if;
--    end process;

--    process(failedFast, failedSlow, passedSlow)
--    begin
--       if (failedFast = '1') or (failedSlow = '1') then
--          assert false
--             report "Simulation Failed!" severity failure;
--       end if;
--       if passedSlow = '1' then
--          assert false
--             report "Simulation Passed!" severity failure;
--       end if;
--    end process;

   ------------
   -- Data Sink
   ------------
--    SsiPrbsRx_Inst : entity surf.SsiPrbsRx
--       generic map (
--          -- General Configurations
--          TPD_G                      => TPD_C,
--          STATUS_CNT_WIDTH_G         => STATUS_CNT_WIDTH_C,
--          -- FIFO Configurations
--          MEMORY_TYPE_G              => MEMORY_TYPE_C,
--          GEN_SYNC_FIFO_G            => true,
--          CASCADE_SIZE_G             => CASCADE_SIZE_C,
--          FIFO_ADDR_WIDTH_G          => FIFO_ADDR_WIDTH_C,
--          FIFO_PAUSE_THRESH_G        => FIFO_PAUSE_THRESH_C,
--          -- PRBS Configurations
--          PRBS_SEED_SIZE_G           => PRBS_SEED_SIZE_C,
--          PRBS_TAPS_G                => PRBS_TAPS_C,
--          -- AXI Stream Configurations
--          SLAVE_AXI_STREAM_CONFIG_G  => AXI_STREAM_CONFIG_C,
--          SLAVE_AXI_PIPE_STAGES_G    => AXI_PIPE_STAGES_C,
--          MASTER_AXI_STREAM_CONFIG_G => ssiAxiStreamConfig(4),  -- unused
--          MASTER_AXI_PIPE_STAGES_G   => 0)                      -- unused
--       port map (
--          -- Streaming RX Data Interface (sAxisClk domain) 
--          sAxisClk        => slowClk,
--          sAxisRst        => slowRst,
--          sAxisMaster     => ibMaster,
--          sAxisSlave      => ibSlave,
--          sAxisCtrl       => open,
--          -- Optional: Streaming TX Data Interface (mAxisClk domain)
--          mAxisClk        => slowClk,
--          mAxisRst        => slowRst,
--          mAxisMaster     => open,
--          mAxisSlave      => AXI_STREAM_SLAVE_FORCE_C,
--          -- Optional: AXI-Lite Register Interface (axiClk domain)
--          axiClk          => slowClk,
--          axiRst          => slowRst,
--          axiReadMaster   => AXI_LITE_READ_MASTER_INIT_C,
--          axiReadSlave    => open,
--          axiWriteMaster  => AXI_LITE_WRITE_MASTER_INIT_C,
--          -- Error Detection Signals (sAxisClk domain)
--          updatedResults  => updated,
--          busy            => open,
--          errMissedPacket => errMissedPacket,
--          errLength       => errLength,
--          errDataBus      => errDataBus,
--          errEofe         => errEofe,
--          errWordCnt      => errWordCnt,
--          errbitCnt       => errbitCnt,
--          packetRate      => open,
--          packetLength    => open);     

--    process(slowClk)
--    begin
--       if rising_edge(slowClk) then
--          if slowRst = '1' then
--             failedSlow <= '0' after TPD_C;
--             passedSlow <= '0' after TPD_C;
--          elsif updated = '1' then
--             -- Check for missed packet error
--             if errMissedPacket = '1' then
--                failedSlow <= '1' after TPD_C;
--             end if;
--             -- Check for packet length error
--             if errLength = '1' then
--                failedSlow <= '1' after TPD_C;
--             end if;
--             -- Check for packet data bus error
--             if errDataBus = '1' then
--                failedSlow <= '1' after TPD_C;
--             end if;
--             -- Check for EOFE error
--             if errEofe = '1' then
--                failedSlow <= '1' after TPD_C;
--             end if;
--             -- Check for word error
--             if errWordCnt /= 0 then
--                failedSlow <= '1' after TPD_C;
--             end if;
--             -- Check for bit error
--             if errbitCnt /= 0 then
--                failedSlow <= '1' after TPD_C;
--             end if;
--             -- Check the counter
--             if cnt = NUMBER_PACKET_C then
--                passedSlow <= '1' after TPD_C;
--             else
--                -- Increment the counter
--                cnt <= cnt + 1 after TPD_C;
--             end if;
--          end if;
--       end if;
--    end process;

end testbed;
