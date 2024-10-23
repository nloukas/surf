-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: SGMII Ethernet over LVDS
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

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.EthMacPkg.all;
use surf.GigEthPkg.all;

entity GigEthLvdsUltraScale is
   generic (
      TPD_G         : time                := 1 ns;
      JUMBO_G       : boolean             := true;
      PAUSE_EN_G    : boolean             := true;
      ROCEV2_EN_G   : boolean             := false;
      -- AXI-Lite Configurations
      EN_AXIL_REG_G : boolean             := false;
      -- AXI Streaming Configurations
      AXIS_CONFIG_G : AxiStreamConfigType := EMAC_AXIS_CONFIG_C);
   port (
      -- Local Configurations
      localMac        : in  slv(47 downto 0)       := MAC_ADDR_INIT_C;
      -- Streaming DMA Interface
      dmaClk          : in  sl;
      dmaRst          : in  sl;
      dmaIbMaster     : out AxiStreamMasterType;
      dmaIbSlave      : in  AxiStreamSlaveType;
      dmaObMaster     : in  AxiStreamMasterType;
      dmaObSlave      : out AxiStreamSlaveType;
      -- Slave AXI-Lite Interface
      axilClk         : in  sl                     := '0';
      axilRst         : in  sl                     := '0';
      axilReadMaster  : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
      axilWriteSlave  : out AxiLiteWriteSlaveType;
      -- Speed selection
      speed_is_10_100 : in  sl                     := '0';
      speed_is_100    : in  sl                     := '0';
      -- PHY + MAC signals
      extRst          : in  sl;
      ethClk          : out sl;
      ethRst          : out sl;
      phyReady        : out sl;
      sigDet          : in  sl                     := '1';
      -- SGMII / LVDS Ports
      sgmiiClkP       : in  sl;         -- 625 MHz
      sgmiiClkN       : in  sl;         -- 625 MHz
      sgmiiTxP        : out sl;
      sgmiiTxN        : out sl;
      sgmiiRxP        : in  sl;
      sgmiiRxN        : in  sl);
end GigEthLvdsUltraScale;

architecture mapping of GigEthLvdsUltraScale is

   component GigEthLvdsUltraScaleCore
      port (
         txp_0                  : out std_logic;
         txn_0                  : out std_logic;
         rxp_0                  : in  std_logic;
         rxn_0                  : in  std_logic;
         signal_detect_0        : in  std_logic;
         gmii_txd_0             : in  std_logic_vector (7 downto 0);
         gmii_tx_en_0           : in  std_logic;
         gmii_tx_er_0           : in  std_logic;
         gmii_rxd_0             : out std_logic_vector (7 downto 0);
         gmii_rx_dv_0           : out std_logic;
         gmii_rx_er_0           : out std_logic;
         gmii_isolate_0         : out std_logic;
         sgmii_clk_r_0          : out std_logic;
         sgmii_clk_f_0          : out std_logic;
         sgmii_clk_en_0         : out std_logic;
         speed_is_10_100_0      : in  std_logic;
         speed_is_100_0         : in  std_logic;
         status_vector_0        : out std_logic_vector (15 downto 0);
         configuration_vector_0 : in  std_logic_vector (4 downto 0);
         refclk625_p            : in  std_logic;
         refclk625_n            : in  std_logic;
         clk125_out             : out std_logic;
         clk312_out             : out std_logic;
         rst_125_out            : out std_logic;
         tx_logic_reset         : out std_logic;
         rx_logic_reset         : out std_logic;
         rx_locked              : out std_logic;
         tx_locked              : out std_logic;
         tx_bsc_rst_out         : out std_logic;
         rx_bsc_rst_out         : out std_logic;
         tx_bs_rst_out          : out std_logic;
         rx_bs_rst_out          : out std_logic;
         tx_rst_dly_out         : out std_logic;
         rx_rst_dly_out         : out std_logic;
         tx_bsc_en_vtc_out      : out std_logic;
         rx_bsc_en_vtc_out      : out std_logic;
         tx_bs_en_vtc_out       : out std_logic;
         rx_bs_en_vtc_out       : out std_logic;
         riu_clk_out            : out std_logic;
         riu_addr_out           : out std_logic_vector (5 downto 0);
         riu_wr_data_out        : out std_logic_vector (15 downto 0);
         riu_wr_en_out          : out std_logic;
         riu_nibble_sel_out     : out std_logic_vector (1 downto 0);
         riu_rddata_3           : in  std_logic_vector (15 downto 0);
         riu_valid_3            : in  std_logic;
         riu_prsnt_3            : in  std_logic;
         riu_rddata_2           : in  std_logic_vector (15 downto 0);
         riu_valid_2            : in  std_logic;
         riu_prsnt_2            : in  std_logic;
         riu_rddata_1           : in  std_logic_vector (15 downto 0);
         riu_valid_1            : in  std_logic;
         riu_prsnt_1            : in  std_logic;
         rx_btval_3             : out std_logic_vector (8 downto 0);
         rx_btval_2             : out std_logic_vector (8 downto 0);
         rx_btval_1             : out std_logic_vector (8 downto 0);
         tx_dly_rdy_1           : in  std_logic;
         rx_dly_rdy_1           : in  std_logic;
         rx_vtc_rdy_1           : in  std_logic;
         tx_vtc_rdy_1           : in  std_logic;
         tx_dly_rdy_2           : in  std_logic;
         rx_dly_rdy_2           : in  std_logic;
         rx_vtc_rdy_2           : in  std_logic;
         tx_vtc_rdy_2           : in  std_logic;
         tx_dly_rdy_3           : in  std_logic;
         rx_dly_rdy_3           : in  std_logic;
         rx_vtc_rdy_3           : in  std_logic;
         tx_vtc_rdy_3           : in  std_logic;
         tx_pll_clk_out         : out std_logic;
         rx_pll_clk_out         : out std_logic;
         tx_rdclk_out           : out std_logic;
         reset                  : in  std_logic
         );
   end component;

   signal config : GigEthConfigType;
   signal status : GigEthStatusType;

   signal mAxiReadMaster  : AxiLiteReadMasterType;
   signal mAxiReadSlave   : AxiLiteReadSlaveType;
   signal mAxiWriteMaster : AxiLiteWriteMasterType;
   signal mAxiWriteSlave  : AxiLiteWriteSlaveType;

   signal gmiiTxd  : slv(7 downto 0);
   signal gmiiTxEn : sl;
   signal gmiiTxEr : sl;

   signal gmiiRxd  : slv(7 downto 0);
   signal gmiiRxDv : sl;
   signal gmiiRxEr : sl;

   signal sysClk125En : sl;
   signal sysClk125   : sl;
   signal sysRst125   : sl;
   signal areset      : sl;

begin

   ethClk <= sysClk125;
   ethRst <= sysRst125;

   areset <= extRst or config.softRst;

   ------------------
   -- Synchronization
   ------------------
   U_AxiLiteAsync : entity surf.AxiLiteAsync
      generic map (
         TPD_G => TPD_G)
      port map (
         -- Slave Port
         sAxiClk         => axilClk,
         sAxiClkRst      => axilRst,
         sAxiReadMaster  => axilReadMaster,
         sAxiReadSlave   => axilReadSlave,
         sAxiWriteMaster => axilWriteMaster,
         sAxiWriteSlave  => axilWriteSlave,
         -- Master Port
         mAxiClk         => sysClk125,
         mAxiClkRst      => sysRst125,
         mAxiReadMaster  => mAxiReadMaster,
         mAxiReadSlave   => mAxiReadSlave,
         mAxiWriteMaster => mAxiWriteMaster,
         mAxiWriteSlave  => mAxiWriteSlave);

   --------------------
   -- Ethernet MAC core
   --------------------
   U_MAC : entity surf.EthMacTop
      generic map (
         TPD_G           => TPD_G,
         JUMBO_G         => JUMBO_G,
         PAUSE_EN_G      => PAUSE_EN_G,
         PAUSE_512BITS_G => PAUSE_512BITS_C,
         ROCEV2_EN_G     => ROCEV2_EN_G,
         PHY_TYPE_G      => "GMII",
         PRIM_CONFIG_G   => AXIS_CONFIG_G)
      port map (
         -- Primary Interface
         primClk         => dmaClk,
         primRst         => dmaRst,
         ibMacPrimMaster => dmaObMaster,
         ibMacPrimSlave  => dmaObSlave,
         obMacPrimMaster => dmaIbMaster,
         obMacPrimSlave  => dmaIbSlave,
         -- Ethernet Interface
         ethClkEn        => sysClk125En,
         ethClk          => sysClk125,
         ethRst          => sysRst125,
         ethConfig       => config.macConfig,
         ethStatus       => status.macStatus,
         phyReady        => status.phyReady,
         -- GMII PHY Interface
         gmiiRxDv        => gmiiRxDv,
         gmiiRxEr        => gmiiRxEr,
         gmiiRxd         => gmiiRxd,
         gmiiTxEn        => gmiiTxEn,
         gmiiTxEr        => gmiiTxEr,
         gmiiTxd         => gmiiTxd);

   ------------------
   -- gmii - sgmii
   ------------------
   U_GigEthLvdsUltraScaleCore : GigEthLvdsUltraScaleCore
      port map (
         -- Clocks and Resets
         refclk625_p            => sgmiiClkP,
         refclk625_n            => sgmiiClkN,
         clk125_out             => sysClk125,
         clk312_out             => open,
         reset                  => areset,
         rst_125_out            => sysRst125,
         sgmii_clk_r_0          => open,
         sgmii_clk_f_0          => open,
         sgmii_clk_en_0         => sysClk125En,
         -- MGT Ports
         txp_0                  => sgmiiTxP,
         txn_0                  => sgmiiTxN,
         rxp_0                  => sgmiiRxP,
         rxn_0                  => sgmiiRxN,
         -- PHY Interface
         gmii_txd_0             => gmiiTxd,
         gmii_tx_en_0           => gmiiTxEn,
         gmii_tx_er_0           => gmiiTxEr,
         gmii_rxd_0             => gmiiRxd,
         gmii_rx_dv_0           => gmiiRxDv,
         gmii_rx_er_0           => gmiiRxEr,
         gmii_isolate_0         => open,
         -- Configuration and Status
         configuration_vector_0 => config.coreConfig,
         status_vector_0        => status.coreStatus,
         speed_is_10_100_0      => speed_is_10_100,
         speed_is_100_0         => speed_is_100,
         signal_detect_0        => sigDet,
         -- Unused ports
         tx_dly_rdy_1           => '1',
         rx_dly_rdy_1           => '1',
         tx_vtc_rdy_1           => '1',
         rx_vtc_rdy_1           => '1',
         tx_dly_rdy_2           => '1',
         rx_dly_rdy_2           => '1',
         tx_vtc_rdy_2           => '1',
         rx_vtc_rdy_2           => '1',
         tx_dly_rdy_3           => '1',
         rx_dly_rdy_3           => '1',
         tx_vtc_rdy_3           => '1',
         rx_vtc_rdy_3           => '1',
         tx_logic_reset         => open,
         rx_logic_reset         => open,
         rx_locked              => open,
         tx_locked              => open,
         tx_bsc_rst_out         => open,
         rx_bsc_rst_out         => open,
         tx_bs_rst_out          => open,
         rx_bs_rst_out          => open,
         tx_rst_dly_out         => open,
         rx_rst_dly_out         => open,
         tx_bsc_en_vtc_out      => open,
         rx_bsc_en_vtc_out      => open,
         tx_bs_en_vtc_out       => open,
         rx_bs_en_vtc_out       => open,
         riu_clk_out            => open,
         riu_wr_en_out          => open,
         tx_pll_clk_out         => open,
         rx_pll_clk_out         => open,
         tx_rdclk_out           => open,
         riu_addr_out           => open,
         riu_wr_data_out        => open,
         riu_nibble_sel_out     => open,
         rx_btval_1             => open,
         rx_btval_2             => open,
         rx_btval_3             => open,
         riu_valid_3            => '0',
         riu_valid_2            => '0',
         riu_valid_1            => '0',
         riu_prsnt_1            => '0',
         riu_prsnt_2            => '0',
         riu_prsnt_3            => '0',
         riu_rddata_3           => (others => '0'),
         riu_rddata_1           => (others => '0'),
         riu_rddata_2           => (others => '0'));

   status.phyReady <= status.coreStatus(0);
   phyReady        <= status.phyReady;

   --------------------------------
   -- Configuration/Status Register
   --------------------------------
   U_GigEthReg : entity surf.GigEthReg
      generic map (
         TPD_G        => TPD_G,
         EN_AXI_REG_G => EN_AXIL_REG_G)
      port map (
         -- Local Configurations
         localMac       => localMac,
         -- Clocks and resets
         clk            => sysClk125,
         rst            => sysRst125,
         -- AXI-Lite Register Interface
         axiReadMaster  => mAxiReadMaster,
         axiReadSlave   => mAxiReadSlave,
         axiWriteMaster => mAxiWriteMaster,
         axiWriteSlave  => mAxiWriteSlave,
         -- Configuration and Status Interface
         config         => config,
         status         => status);

end mapping;
