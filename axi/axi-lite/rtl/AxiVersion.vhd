
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

entity MyGpioModule is
   generic (
      TPD_G              : time             := 1 ns);
   port (
      -- AXI-Lite Interface
      axiClk         : in    sl;
      axiRst         : in    sl;
      axiReadMaster  : in    AxiLiteReadMasterType;
      axiReadSlave   : out   AxiLiteReadSlaveType;
      axiWriteMaster : in    AxiLiteWriteMasterType;
      axiWriteSlave  : out   AxiLiteWriteSlaveType;
      -- Signals that I want to monitor
      clrA          : out   sl;
      clrB          : out   sl;
      statusA       : in   sl;
      statusB       : in   sl;
      statusC       : in   sl);
end MyGpioModule;

architecture rtl of MyGpioModule is
   type RegType is record
      clrA           : sl;
      clrB           : sl;
      axiReadSlave   : AxiLiteReadSlaveType;
      axiWriteSlave  : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      clrA     => '0',
      clrB     => '0',
      axiReadSlave   => AXI_LITE_READ_SLAVE_INIT_C,
      axiWriteSlave  => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal statusASync : sl;
   signal statusBSync : sl;
   signal statusCSync : sl;

begin

   U_sync : entity surf.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => 3)
      port map (
         clk         => axiClk,
         -- Data in
         dataIn(0)   => statusA,
         dataIn(1)   => statusB,
         dataIn(2)   => statusC,
         -- Data out
         dataOut(0)  => statusASync,
         dataOut(1)  => statusBSync,
         dataOut(2)  => statusCSync;

   U_adcOvThreash1 : entity surf.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => 4)
      port map (
         clk         => axiClk,
         -- Data in
         dataIn  => adcOvThreash1,
         -- Data out
         dataOut  => adcOvThreash1Sync)         

   comb : process () is
      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;
   begin
      -- Latch the current value
      v := r;

      -- Reset strobes
      v.clrA := '0';
      v.clrB := '0';
         
      ------------------------
      -- AXI-Lite Transactions
      ------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, axiWriteMaster, axiReadMaster, v.axiWriteSlave, v.axiReadSlave);

      axiSlaveRegisterR(axilEp, x"00", 0, statusASync);
      axiSlaveRegisterR(axilEp, x"00", 1, statusBSync);
      axiSlaveRegisterR(axilEp, x"00", 2, statusCSync);
         
      axiSlaveRegister(axilEp, x"04", 0, v.clrA);
      axiSlaveRegister(axilEp, x"08", 0, v.clrB);

      -- Close the transaction
      axiSlaveDefault(axilEp, v.axiWriteSlave, v.axiReadSlave, AXI_RESP_DECERR_C);

      --------
      -- Reset
      --------
      if (RST_ASYNC_G = false and axiRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Outputs
      axiReadSlave   <= r.axiReadSlave;
      axiWriteSlave  <= r.axiWriteSlave;
      clrA     <= r.clrA;
      clrB <= r.clrB;

   end process comb;

   seq : process (axiClk, axiRst) is
   begin
      if (RST_ASYNC_G and axiRst = '1') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(axiClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end architecture rtl;
