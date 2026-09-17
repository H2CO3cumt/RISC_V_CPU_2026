//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2014 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
// trigger_output module, set the trigger out
// Called by     :  debug_core
// Modification history
//----------------------------------------------------------------------

module ips_dbc_trigger_output_v1_2
#(
 parameter NEW_JTAG_IF     = 1,
 parameter  AREA_SPEED = 0,                      //0~5, EXPERIMENTAL
 parameter  TRIG_OUT_CHAIN_BIT = 3,	             //{trig_out_mode}
 parameter INIT_TRIG_OUT = 0 
 )
(
  input                         h_rstn ,
  input                         clk_conf,
  input                         rst_conf,
  input                         conf_sel,
  input                         conf_tdi,
  input                         clk_trig,
  input                         rst_trig,
  input                         trigger ,
  input                         shift_i,  
  output  reg                   trig_out,
  input                         conf_rden,
	input [4:0]                   conf_id,
	input                         conf_sel_rd,
  output                        conf_rdlast,
  output                        conf_rdata   
);

`pragma protect begin_protected
`pragma protect version=1
`pragma protect author="default"
`pragma protect author_info="default"
`pragma protect encrypt_agent="Synplify encryptP1735.pl"
`pragma protect encrypt_agent_info="Synplify encryptP1735.pl Version 1.1"

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Synplicity", key_keyname="SYNP22_1", key_method="rsa"
`pragma protect key_block
ufF5Lwr4Xpk/tyQPcMX86iI+DJUv7y+C8G6tsARwCO+knqptg7ETFEVYF31UPL5vjJuy7nb4yInR
DZYnPK2m9JMAp3CHzQKvLZccDfjT+Nd+cYB8+/hcos4+24pGDsrJ32lUwgDdgjQCGc4cjWMeODdz
2ZTLirWVWOlFKDoKCG2cSLATb7AsBRpo7TNahycucjc64kyeVZ256JrMhf9gsKx3MZJeKoeNtNVJ
/8E4Cc6+rW64ZR1eJwI51nWljqONGOd+AbMdWffu3uyXe29oxmwuPQq3GLzYBJEzbcSlfJRsrhr8
wqS8kiOGYCNRrEY3vKsvgGY1+YT81Gj5nfVE+A==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_24", key_method="rsa"
`pragma protect key_block
MiIyuQMr8WfqjmRbRr7TrNcaX2ibkn5RFOXjhIqcGO13VewyObRVofOYlvTvaU0Iz7oBwaqB01Q2
HmQgMDhAGSHhcOOlxMgmHT2oFw5By3nO8FmNwOsavJfQ85uKgcZLqBMXrtQehy8E8rTCHtr4/8a+
/OvdNoSueAvMjoTlyfnY75eTw+AG5+WI3Tk+5+c0jB7iZxDHygiesqukQpYSHcpAhdFX5fHAeijV
ZWrR/mYZofRvWq3BcztvmxPhP+sBxGrqes14VnEs4Ze8zIhy3axCP7J5xpnVMUaWdkmPmro4gaRI
2krx+0dTem5rYaPF2BB81uI8845jzIT0eRz46w==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=3968)
`pragma protect data_block
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

`pragma protect end_protected
endmodule