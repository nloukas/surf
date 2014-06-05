-------------------------------------------------------------------------------
-- Title      : AXI Stream FIFO / Re-sizer
-- Project    : General Purpose Core
-------------------------------------------------------------------------------
-- File       : AxiStreamFifo.vhd
-- Author     : Ryan Herbst, rherbst@slac.stanford.edu
-- Created    : 2014-04-25
-- Last update: 2014-05-27
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description:
-- Block to serve as an async FIFO for AXI Streams. This block also allows the
-- bus to be compress/expanded, allowing different standard sizes on each side
-- of the FIFO. Re-sizing is always little endian. 
-------------------------------------------------------------------------------
-- Copyright (c) 2014 by Ryan Herbst. All rights reserved.
-------------------------------------------------------------------------------
-- Modification history:
-- 04/25/2014: created.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;

entity AxiStreamFifo is
   generic (

      -- General Configurations
      TPD_G            : time                       := 1 ns;
      PIPE_STAGES_G    : natural range 0 to 16      := 0;
      SLAVE_READY_EN_G : boolean                    := true;
      VALID_THOLD_G    : integer range 1 to (2**24) := 1; -- =1 = normal operation
                                                          -- >1 = only when frame ready
      -- FIFO configurations
      BRAM_EN_G           : boolean                    := true;
      XIL_DEVICE_G        : string                     := "7SERIES";
      USE_BUILT_IN_G      : boolean                    := false;
      GEN_SYNC_FIFO_G     : boolean                    := false;
      ALTERA_SYN_G        : boolean                    := false;
      ALTERA_RAM_G        : string                     := "M9K";
      CASCADE_SIZE_G      : integer range 1 to (2**24) := 1;
      FIFO_ADDR_WIDTH_G   : integer range 4 to 48      := 9;
      FIFO_FIXED_THRESH_G : boolean                    := true;
      FIFO_PAUSE_THRESH_G : integer range 1 to (2**24) := 500;

      -- AXI Stream Port Configurations
      SLAVE_AXI_CONFIG_G  : AxiStreamConfigType := AXI_STREAM_CONFIG_INIT_C;
      MASTER_AXI_CONFIG_G : AxiStreamConfigType := AXI_STREAM_CONFIG_INIT_C
      );
   port (

      -- Slave Port
      sAxisClk    : in  sl;
      sAxisRst    : in  sl;
      sAxisMaster : in  AxiStreamMasterType;
      sAxisSlave  : out AxiStreamSlaveType;
      sAxisCtrl   : out AxiStreamCtrlType;

      -- FIFO status & config , synchronous to sAxisClk
      fifoPauseThresh : in slv(FIFO_ADDR_WIDTH_G-1 downto 0) := (others => '1');

      -- Master Port
      mAxisClk    : in  sl;
      mAxisRst    : in  sl;
      mAxisMaster : out AxiStreamMasterType;
      mAxisSlave  : in  AxiStreamSlaveType);
end AxiStreamFifo;

architecture rtl of AxiStreamFifo is

   -- Configure FIFO widths
   constant DATA_BYTES_C : integer := ite(SLAVE_AXI_CONFIG_G.TDATA_BYTES_C > MASTER_AXI_CONFIG_G.TDATA_BYTES_C,
                                          SLAVE_AXI_CONFIG_G.TDATA_BYTES_C, MASTER_AXI_CONFIG_G.TDATA_BYTES_C);

   constant DATA_BITS_C : integer := (DATA_BYTES_C * 8);

   constant KEEP_MODE_C : TKeepModeType := SLAVE_AXI_CONFIG_G.TKEEP_MODE_C;
   constant KEEP_BITS_C : integer       := ite(KEEP_MODE_C = TKEEP_NORMAL_C, DATA_BYTES_C,
                                           ite(KEEP_MODE_C = TKEEP_COMP_C,   bitSize(DATA_BYTES_C-1), 0));

   constant USER_MODE_C : TUserModeType := SLAVE_AXI_CONFIG_G.TUSER_MODE_C;
   constant USER_BITS_C : integer       := SLAVE_AXI_CONFIG_G.TUSER_BITS_C;
   constant USER_TOT_C  : integer       := ite(USER_MODE_C = TUSER_FIRST_LAST_C, USER_BITS_C*2, 
                                           ite(USER_MODE_C = TUSER_LAST_C, USER_BITS_C,
                                           DATA_BYTES_C * USER_BITS_C));

   constant STRB_BITS_C : integer := ite(SLAVE_AXI_CONFIG_G.TSTRB_EN_C, DATA_BYTES_C, 0);
   constant DEST_BITS_C : integer := SLAVE_AXI_CONFIG_G.TDEST_BITS_C;
   constant ID_BITS_C   : integer := SLAVE_AXI_CONFIG_G.TID_BITS_C;

   constant FIFO_BITS_C : integer := 1 + DATA_BITS_C + KEEP_BITS_C + USER_TOT_C + STRB_BITS_C + DEST_BITS_C + ID_BITS_C;

   constant WR_BYTES_C : integer := SLAVE_AXI_CONFIG_G.TDATA_BYTES_C;
   constant RD_BYTES_C : integer := MASTER_AXI_CONFIG_G.TDATA_BYTES_C;

   -- Convert record to slv
   function iAxiToSlv (din : AxiStreamMasterType) return slv is
      variable retValue : slv(FIFO_BITS_C-1 downto 0);
      variable i        : integer;
   begin

      -- init, pass last
      retValue(0) := din.tLast;
      i := 1;

      -- Pack data
      retValue((DATA_BITS_C+i)-1 downto i) := din.tData(DATA_BITS_C-1 downto 0);
      i                                    := i + DATA_BITS_C;

      -- Pack keep
      if KEEP_MODE_C = TKEEP_NORMAL_C then
         retValue((KEEP_BITS_C+i)-1 downto i) := din.tKeep(KEEP_BITS_C-1 downto 0);
      elsif KEEP_MODE_C = TKEEP_COMP_C then
         retValue((KEEP_BITS_C+i)-1 downto i) := onesCount(din.tKeep(DATA_BYTES_C-1 downto 1)); -- Assume lsb is present
      end if;
      i := i + KEEP_BITS_C;

      -- Pack user bits
      if USER_MODE_C = TUSER_FIRST_LAST_C then
         retValue((USER_BITS_C+i)-1 downto i) := axiStreamGetUserField ( SLAVE_AXI_CONFIG_G,din,0); -- First byte
         i := i + USER_BITS_C;

         retValue((USER_BITS_C+i)-1 downto i) := axiStreamGetUserField ( SLAVE_AXI_CONFIG_G,din,-1); -- Last valid
         i := i + USER_BITS_C;

      elsif USER_MODE_C = TUSER_LAST_C then
         retValue((USER_BITS_C+i)-1 downto i) := axiStreamGetUserField ( SLAVE_AXI_CONFIG_G,din,-1); -- Last valid
         i := i + USER_BITS_C;

      else
         retValue((USER_TOT_C+i)-1 downto i) := din.tUser(USER_TOT_C-1 downto 0);
         i := i + USER_TOT_C;
      end if;

      -- Strobe is optional
      if STRB_BITS_C > 0 then
         retValue((STRB_BITS_C+i)-1 downto i) := din.tStrb(STRB_BITS_C-1 downto 0);
         i                                    := i + STRB_BITS_C;
      end if;

      -- Dest is optional
      if DEST_BITS_C > 0 then
         retValue((DEST_BITS_C+i)-1 downto i) := din.tDest(DEST_BITS_C-1 downto 0);
         i                                    := i + DEST_BITS_C;
      end if;

      -- Id is optional
      if ID_BITS_C > 0 then
         retValue((ID_BITS_C+i)-1 downto i) := din.tId(ID_BITS_C-1 downto 0);
         i                                  := i + ID_BITS_C;
      end if;

      return(retValue);

   end function;

   -- Convert slv to record
   procedure iSlvToAxi (din     : in    slv(FIFO_BITS_C-1 downto 0);
                        valid   : in    sl;
                        master  : inout AxiStreamMasterType;
                        byteCnt : inout integer) is
      variable i, j : integer;
   begin

      master  := AXI_STREAM_MASTER_INIT_C;

      -- Set valid, 
      master.tValid := valid;
      master.tLast  := din(0);
      i := 1;

      -- Get data
      master.tData(DATA_BITS_C-1 downto 0) := din((DATA_BITS_C+i)-1 downto i);
      i                                    := i + DATA_BITS_C;

      -- Get keep bits
      if KEEP_MODE_C = TKEEP_NORMAL_C then
         byteCnt := DATA_BYTES_C;
         master.tKeep(KEEP_BITS_C-1 downto 0) := din((KEEP_BITS_C+i)-1 downto i);
      elsif KEEP_MODE_C = TKEEP_COMP_C then
         byteCnt := conv_integer(din((KEEP_BITS_C+i)-1 downto i)) + 1;
         master.tKeep(DATA_BYTES_C-1 downto 0) := (others => '0');
         master.tKeep(byteCnt-1 downto 0)      := (others => '1');
      else
         byteCnt := DATA_BYTES_C;
      end if;
      i := i + KEEP_BITS_C;

      -- get user bits
      if USER_MODE_C = TUSER_FIRST_LAST_C then
         axiStreamSetUserField ( SLAVE_AXI_CONFIG_G, master, din((USER_BITS_C+i)-1 downto i),0); -- First byte
         i := i + USER_BITS_C;

         axiStreamSetUserField ( SLAVE_AXI_CONFIG_G, master, din((USER_BITS_C+i)-1 downto i),-1); -- Last valid byte
         i := i + USER_BITS_C;

      elsif USER_MODE_C = TUSER_LAST_C then
         axiStreamSetUserField ( SLAVE_AXI_CONFIG_G, master, din((USER_BITS_C+i)-1 downto i),-1); -- Last valid byte
         i := i + USER_BITS_C;

      else
         master.tUser(USER_TOT_C-1 downto 0) := din((USER_TOT_C+i)-1 downto i);
         i := i + USER_TOT_C;
      end if;

      -- Strobe is optional
      if STRB_BITS_C > 0 then
         master.tStrb(STRB_BITS_C-1 downto 0) := din((STRB_BITS_C+i)-1 downto i);
         i                                    := i + STRB_BITS_C;
      end if;

      -- Dest is optional
      if DEST_BITS_C > 0 then
         master.tDest(DEST_BITS_C-1 downto 0) := din((DEST_BITS_C+i)-1 downto i);
         i                                    := i + DEST_BITS_C;
      end if;

      -- ID is optional
      if ID_BITS_C > 0 then
         master.tId(ID_BITS_C-1 downto 0) := din((ID_BITS_C+i)-1 downto i);
         i                                := i + ID_BITS_C;
      end if;

   end iSlvToAxi;

   ----------------
   -- Write Signals
   ----------------
   constant WR_LOGIC_EN_C : boolean := (WR_BYTES_C < RD_BYTES_C);
   constant WR_SIZE_C     : integer := ite(WR_LOGIC_EN_C, RD_BYTES_C / WR_BYTES_C, 1);

   type WrRegType is record
      count    : slv(bitSize(WR_SIZE_C)-1 downto 0);
      wrMaster : AxiStreamMasterType;
   end record WrRegType;

   constant WR_REG_INIT_C : WrRegType := (
      count    => (others => '0'),
      wrMaster => AXI_STREAM_MASTER_INIT_C
      );

   signal wrR, wrRin : WrRegType := WR_REG_INIT_C;

   ----------------
   -- FIFO Signals
   ----------------
   signal fifoDin       : slv(FIFO_BITS_C-1 downto 0);
   signal fifoWrite     : sl;
   signal fifoWriteLast : sl;
   signal fifoWrCount   : slv(FIFO_ADDR_WIDTH_G-1 downto 0);
   signal fifoRdCount   : slv(FIFO_ADDR_WIDTH_G-1 downto 0);
   signal fifoAFull     : sl;
   signal fifoReady     : sl;
   signal fifoPFull     : sl;
   signal fifoDout      : slv(FIFO_BITS_C-1 downto 0);
   signal fifoRead      : sl;
   signal fifoReadLast  : sl;
   signal fifoValidInt  : sl;
   signal fifoValid     : sl;
   signal fifoValidLast : sl;
   signal fifoInFrame   : sl;

   ---------------
   -- Read Signals
   ---------------
   constant RD_LOGIC_EN_C : boolean := (RD_BYTES_C < WR_BYTES_C);
   constant RD_SIZE_C     : integer := ite(RD_LOGIC_EN_C, WR_BYTES_C / RD_BYTES_C, 1);

   type RdRegType is record
      count    : slv(bitSize(RD_SIZE_C)-1 downto 0);
      bytes    : slv(bitSize(DATA_BYTES_C)-1 downto 0);
      rdMaster : AxiStreamMasterType;
      ready    : sl;
   end record RdRegType;

   constant RD_REG_INIT_C : RdRegType := (
      count    => (others => '0'),
      bytes    => conv_std_logic_vector(RD_BYTES_C, bitSize(DATA_BYTES_C)),
      rdMaster => AXI_STREAM_MASTER_INIT_C,
      ready    => '0'
      );

   signal rdR, rdRin : RdRegType := RD_REG_INIT_C;

   ---------------
   -- Sync Signals
   ---------------
   signal axisMaster : AxiStreamMasterType;
   signal axisSlave  : AxiStreamSlaveType;

begin

   assert ((SLAVE_AXI_CONFIG_G.TDATA_BYTES_C >= MASTER_AXI_CONFIG_G.TDATA_BYTES_C and
            SLAVE_AXI_CONFIG_G.TDATA_BYTES_C mod MASTER_AXI_CONFIG_G.TDATA_BYTES_C = 0) or
           (MASTER_AXI_CONFIG_G.TDATA_BYTES_C >= SLAVE_AXI_CONFIG_G.TDATA_BYTES_C and
            MASTER_AXI_CONFIG_G.TDATA_BYTES_C mod SLAVE_AXI_CONFIG_G.TDATA_BYTES_C = 0))
      report "Data widths must be even number multiples of each other" severity failure;

   assert (SLAVE_AXI_CONFIG_G.TSTRB_EN_C = MASTER_AXI_CONFIG_G.TSTRB_EN_C)
      report "TSTRB_EN_C of master and slave ports must match" severity failure;

   assert (SLAVE_AXI_CONFIG_G.TDEST_BITS_C = MASTER_AXI_CONFIG_G.TDEST_BITS_C)
      report "TDEST_BITS_C of master and slave ports must match" severity failure;

   assert (SLAVE_AXI_CONFIG_G.TID_BITS_C = MASTER_AXI_CONFIG_G.TID_BITS_C)
      report "TID_BITS_C of master and slave ports must match" severity failure;

   assert (SLAVE_AXI_CONFIG_G.TUSER_BITS_C = MASTER_AXI_CONFIG_G.TUSER_BITS_C)
      report "TUSER_BITS_C of master and slave ports must match" severity failure;

   assert (SLAVE_AXI_CONFIG_G.TUSER_MODE_C = MASTER_AXI_CONFIG_G.TUSER_MODE_C)
      report "TUSER_MODE_C of master and slave ports must match" severity failure;

   --assert (SLAVE_AXI_CONFIG_G.TDATA_BYTES_C < MASTER_AXI_CONFIG_G.TDATA_BYTES_C) and
   --       (SLAVE_AXI_CONFIG_G.TKEEP_MODE_C = MASTER_AXI_CONFIG_G.TKEEP_MODE_C) 
   --   report "TKEEP_MODE_C of ports must match or when slave is the same width or wider than master" severity failure;

   --assert (SLAVE_AXI_CONFIG_G.TDATA_BYTES_C >= MASTER_AXI_CONFIG_G.TDATA_BYTES_C) and    -- Output wider than input, output enabled
   --       (MASTER_AXI_CONFIG_G.TKEEP_MODE_C /= TKEEP_UNUSED_C) 
   --   report "TKEEP_MODE_C of master port must not be TKEEP_UNUSED_C when master is wider than slave" severity failure;

   -------------------------
   -- Write Logic
   -------------------------
   wrComb : process (wrR, sAxisMaster, fifoReady) is
      variable v   : WrRegType;
      variable idx : integer;
   begin
      v   := wrR;
      idx := conv_integer(wrR.count);

      -- Advance pipeline
      if fifoReady = '1' then

         -- init when count = 0
         if (wrR.count = 0) then
            v.wrMaster.tKeep := (others => '0');
            v.wrMaster.tData := (others => '0');
            v.wrMaster.tStrb := (others => '0');
            v.wrMaster.tUser := (others => '0');
         end if;

         v.wrMaster.tData((WR_BYTES_C*8*idx)+((WR_BYTES_C*8)-1) downto (WR_BYTES_C*8*idx)) := sAxisMaster.tData((WR_BYTES_C*8)-1 downto 0);
         v.wrMaster.tStrb((WR_BYTES_C*idx)+(WR_BYTES_C-1) downto (WR_BYTES_C*idx))         := sAxisMaster.tStrb(WR_BYTES_C-1 downto 0);
         v.wrMaster.tKeep((WR_BYTES_C*idx)+(WR_BYTES_C-1) downto (WR_BYTES_C*idx))         := sAxisMaster.tKeep(WR_BYTES_C-1 downto 0);

         v.wrMaster.tUser((WR_BYTES_C*USER_BITS_C*idx)+((WR_BYTES_C*USER_BITS_C)-1) downto (WR_BYTES_C*USER_BITS_C*idx))
            := sAxisMaster.tUser((WR_BYTES_C*USER_BITS_C)-1 downto 0);

         v.wrMaster.tDest := sAxisMaster.tDest;
         v.wrMaster.tId   := sAxisMaster.tId;
         v.wrMaster.tLast := sAxisMaster.tLast;

         -- Determine end mode, valid and ready
         if sAxisMaster.tValid = '1' then
            if (wrR.count = (WR_SIZE_C-1) or sAxisMaster.tLast = '1') then
               v.wrMaster.tValid := '1';
               v.count           := (others => '0');
            else
               v.wrMaster.tValid := '0';
               v.count           := wrR.count + 1;
            end if;
         else
            v.wrMaster.tValid := '0';
         end if;
      end if;

      wrRin <= v;

      -- Write logic enabled
      if WR_LOGIC_EN_C then
         fifoDin       <= iAxiToSlv(wrR.wrMaster);
         fifoWrite     <= wrR.wrMaster.tValid and fifoReady;
         fifoWriteLast <= wrR.wrMaster.tValid and fifoReady and wrR.wrMaster.tLast;

      -- Bypass write logic
      else
         fifoDin       <= iAxiToSlv(sAxisMaster);
         fifoWrite     <= sAxisMaster.tValid and fifoReady;
         fifoWriteLast <= sAxisMaster.tValid and fifoReady and sAxisMaster.tLast;
      end if;

      sAxisSlave.tReady <= fifoReady;

   end process wrComb;

   wrSeq : process (sAxisClk) is
   begin
      if (rising_edge(sAxisClk)) then
         if sAxisRst = '1' or WR_LOGIC_EN_C = false then
            wrR <= WR_REG_INIT_C after TPD_G;
         else
            wrR <= wrRin after TPD_G;
         end if;
      end if;
   end process wrSeq;


   -------------------------
   -- FIFO
   -------------------------

   -- Pause generation
   process (sAxisClk, fifoPFull) is
   begin
      if FIFO_FIXED_THRESH_G then
         sAxisCtrl.pause <= fifoPFull after TPD_G;
      elsif (rising_edge(sAxisClk)) then
         if sAxisRst = '1' or fifoWrCount > fifoPauseThresh then
            sAxisCtrl.pause <= '1' after TPD_G;
         else
            sAxisCtrl.pause <= '0' after TPD_G;
         end if;
      end if;
   end process;

   U_Fifo : entity work.FifoCascade
      generic map (
         TPD_G              => TPD_G,
         CASCADE_SIZE_G     => CASCADE_SIZE_G,
         LAST_STAGE_ASYNC_G => true,
         PIPE_STAGES_G      => 1,
         RST_POLARITY_G     => '1',
         RST_ASYNC_G        => false,
         GEN_SYNC_FIFO_G    => GEN_SYNC_FIFO_G,
         BRAM_EN_G          => BRAM_EN_G,
         FWFT_EN_G          => true,
         USE_DSP48_G        => "no",
         ALTERA_SYN_G       => ALTERA_SYN_G,
         ALTERA_RAM_G       => ALTERA_RAM_G,
         USE_BUILT_IN_G     => USE_BUILT_IN_G,
         XIL_DEVICE_G       => XIL_DEVICE_G,
         SYNC_STAGES_G      => 3,
         DATA_WIDTH_G       => FIFO_BITS_C,
         ADDR_WIDTH_G       => FIFO_ADDR_WIDTH_G,
         INIT_G             => "0",
         FULL_THRES_G       => FIFO_PAUSE_THRESH_G,
         EMPTY_THRES_G      => 1
         )
      port map (
         rst           => sAxisRst,
         wr_clk        => sAxisClk,
         wr_en         => fifoWrite,
         din           => fifoDin,
         wr_data_count => fifoWrCount,
         wr_ack        => open,
         overflow      => sAxisCtrl.overflow,
         prog_full     => fifoPFull,
         almost_full   => fifoAFull,
         full          => open,
         not_full      => open,
         rd_clk        => mAxisClk,
         rd_en         => fifoRead,
         dout          => fifoDout,
         rd_data_count => fifoRdCount,
         valid         => fifoValidInt,
         underflow     => open,
         prog_empty    => open,
         almost_empty  => open,
         empty         => open
         );

   -- Is ready enabled?
   fifoReady <= (not fifoAFull) when SLAVE_READY_EN_G else '1';

   U_LastFifoEnGen : if VALID_THOLD_G /= 1 generate

      U_LastFifo : entity work.FifoCascade
         generic map (
            TPD_G              => TPD_G,
            CASCADE_SIZE_G     => CASCADE_SIZE_G,
            LAST_STAGE_ASYNC_G => true,
            PIPE_STAGES_G      => 1,
            RST_POLARITY_G     => '1',
            RST_ASYNC_G        => false,
            GEN_SYNC_FIFO_G    => GEN_SYNC_FIFO_G,
            BRAM_EN_G          => false,
            FWFT_EN_G          => true,
            USE_DSP48_G        => "no",
            ALTERA_SYN_G       => ALTERA_SYN_G,
            ALTERA_RAM_G       => ALTERA_RAM_G,
            USE_BUILT_IN_G     => false,
            XIL_DEVICE_G       => XIL_DEVICE_G,
            SYNC_STAGES_G      => 3,
            DATA_WIDTH_G       => 1,
            ADDR_WIDTH_G       => FIFO_ADDR_WIDTH_G,
            INIT_G             => "0",
            FULL_THRES_G       => 1,
            EMPTY_THRES_G      => 1
            )
         port map (
            rst           => sAxisRst,
            wr_clk        => sAxisClk,
            wr_en         => fifoWriteLast,
            din           => (others=>'0'),
            wr_data_count => open,
            wr_ack        => open,
            overflow      => open,
            prog_full     => open,
            almost_full   => open,
            full          => open,
            not_full      => open,
            rd_clk        => mAxisClk,
            rd_en         => fifoReadLast,
            dout          => open,
            rd_data_count => open,
            valid         => fifoValidLast,
            underflow     => open,
            prog_empty    => open,
            almost_empty  => open,
            empty         => open
            );

      process (sAxisClk) is
      begin
         if (rising_edge(sAxisClk)) then
            if sAxisRst = '1' or fifoReadLast = '1' then
               fifoInFrame <= '0' after TPD_G;
            elsif fifoValidLast = '1' or (VALID_THOLD_G /= 0 and fifoRdCount >= VALID_THOLD_G) then
               fifoInFrame <= '1' after TPD_G;
            end if;
         end if;
      end process;

      fifoValid <= fifoValidInt and fifoInFrame;

   end generate;

   U_LastFifoDisGen : if VALID_THOLD_G = 1 generate
      fifoValidLast <= '0';
      fifoValid     <= fifoValidInt;
      fifoInFrame   <= '0';
   end generate;


   -------------------------
   -- Read Logic
   -------------------------

   rdComb : process (rdR, fifoDout, fifoValid, axisSlave) is
      variable v          : RdRegType;
      variable idx        : integer;
      variable byteCnt    : integer;
      variable fifoMaster : AxiStreamMasterType;
   begin
      v   := rdR;
      idx := conv_integer(rdR.count);

      iSlvToAxi (fifoDout, fifoValid, fifoMaster, byteCnt);

      -- Advance pipeline
      if axisSlave.tReady = '1' or rdR.rdMaster.tValid = '0' then
         v.rdMaster := AXI_STREAM_MASTER_INIT_C;

         v.rdMaster.tData((RD_BYTES_C*8)-1 downto 0) := fifoMaster.tData((RD_BYTES_C*8*idx)+((RD_BYTES_C*8)-1) downto (RD_BYTES_C*8*idx));
         v.rdMaster.tStrb(RD_BYTES_C-1 downto 0)     := fifoMaster.tStrb((RD_BYTES_C*idx)+(RD_BYTES_C-1) downto (RD_BYTES_C*idx));
         v.rdMaster.tKeep(RD_BYTES_C-1 downto 0)     := fifoMaster.tKeep((RD_BYTES_C*idx)+(RD_BYTES_C-1) downto (RD_BYTES_C*idx));

         v.rdMaster.tUser((RD_BYTES_C*USER_BITS_C)-1 downto 0)
            := fifoMaster.tUser((RD_BYTES_C*USER_BITS_C*idx)+((RD_BYTES_C*USER_BITS_C)-1) downto (RD_BYTES_C*USER_BITS_C*idx));

         v.rdMaster.tDest  := fifoMaster.tDest;
         v.rdMaster.tId    := fifoMaster.tId;

         -- Reached end of fifo data or no more valid bytes in last word
         if fifoMaster.tValid = '1' then
            if (rdR.count = (RD_SIZE_C-1)) or ((rdR.bytes = byteCnt) and (fifoMaster.tLast = '1')) then
               v.count          := (others => '0');
               v.bytes          := conv_std_logic_vector(RD_BYTES_C, bitSize(DATA_BYTES_C));
               v.ready          := '1';
               v.rdMaster.tLast := fifoMaster.tLast;
            else
               v.count          := rdR.count + 1;
               v.bytes          := rdR.bytes + RD_BYTES_C;
               v.ready          := '0';
               v.rdMaster.tLast := '0';
            end if;
         end if;

         -- Drop transfers with no tKeep bits set, except on tLast
         v.rdMaster.tValid := fifoMaster.tValid and
                              (uOr(v.rdMaster.tKeep(RD_BYTES_C-1 downto 0)) or
                              v.rdMaster.tLast);
         
      else
         v.ready := '0';
      end if;

      rdRin <= v;

      -- Read logic enabled
      if RD_LOGIC_EN_C then
         axisMaster   <= rdR.rdMaster;
         fifoRead     <= v.ready and fifoValid;
         fifoReadLast <= v.ready and fifoValid and fifoMaster.tLast;

      -- Bypass read logic
      else
         axisMaster   <= fifoMaster;
         fifoRead     <= axisSlave.tReady and fifoValid;
         fifoReadLast <= axisSlave.tReady and fifoValid and fifoMaster.tLast;
      end if;
      
   end process rdComb;

   -- If fifo is asynchronous, must use async reset on rd side.
   rdSeq : process (mAxisClk) is
   begin
      if (rising_edge(mAxisClk)) then
         if mAxisRst = '1' or RD_LOGIC_EN_C = false then
            rdR <= RD_REG_INIT_C after TPD_G;
         else
            rdR <= rdRin after TPD_G;
         end if;
      end if;
   end process rdSeq;


   -------------------------
   -- Pipeline Logic
   -------------------------

   U_Pipe : entity work.AxiStreamPipeline
      generic map (
         TPD_G          => TPD_G,
         PIPE_STAGES_G  => PIPE_STAGES_G
         )
      port map (
         -- Clock and Reset
         axisClk     => mAxisClk,
         axisRst     => mAxisRst,
         -- Slave Port
         sAxisMaster => axisMaster,
         sAxisSlave  => axisSlave,
         -- Master Port
         mAxisMaster => mAxisMaster,
         mAxisSlave  => mAxisSlave);   

end rtl;

