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
// storage_qualification module, set the storage qualification, include parameter stor_neg_whole
// Called by     :  debug_core
// Modification history
//
//----------------------------------------------------------------------

module ips_dbc_storage_qualification_v1_2
#(
  parameter NEW_JTAG_IF     = 1,
  parameter  STOR_PIPELINE       = 0,    	//0~1, EXPERIMENTAL
  parameter  TRIG0_TO_15_MU      = 1,    	//1~16
  parameter  STOR_QUAL_CHAIN_BIT = 2,    	//{stor_m0_en,stor_m0_neg...stor_m15_en,stor_m15_neg,stor_neg_whole}
  parameter INIT_STOR_QUAL = 0 
 )
(
  input                         h_rstn ,
  input [1:0]                   clk_conf_trig ,
  input [1:0]                   rst_conf_trig ,
  input                         conf_sel      ,
  input                         conf_tdi      ,
  input                         shift_i      ,  
  input [TRIG0_TO_15_MU-1:0]    match         ,
  output                        stor_en       ,
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
xIECdWejdjjpORNcMPUd1hlQn9T28+m6V9+fTIU6phKcKO8fOBSbOjIpvBXpbjACYT/3q64hpDm6
KjfJHRHCL+ATEgFyxjhByNpov6fpH5Oe2cmD9lH82Cy1KXbn02kSMwVDs5gNDY1gM178cKO9k0EI
zkbaHrRWS8uU8zFFuMDaFR+KHrt9SQyNHACoUbGLzzMgeIqXRIjCSvlcTmDB3R3lqHqtnSf6tqfa
ZX6qvZ008W9aXTQH0q6rJsCI9Cz2EeZ1WRla4VmprI0inkM+vhiBX5FxLxQKlI3I/zWcjt/01dzL
j4d061OPIB6rcTcQtqoEKZbO2zoyS9OmUYgBFA==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_24", key_method="rsa"
`pragma protect key_block
nBnFt1gywM6RTVAASQLQ/zlAbdxYqRvXNR+pffNHA40vlSw/NS+a32wPBkh/YfNWYcITUbMdFHfE
0THekFlOaDm8gwfBk8W5J8QhQlCV4II1z5uISXfupmvf5sM/Nc6jVnGFkonylecTZllp5K+gezhq
vsNlfS9Py8R6o/b0vYotCsfCE2QthcGi2sOjQS8rYSvcfqB6nrFKs3Pt6XypzRvFBc9X/bqDoBeQ
uTV4wDWlUAUKLuTHo91St9clEJA1ClruyziCmj2hDIMfFmqW3ZpNGFSBMVPBKhEmOVtsmDebyz78
vH0vp/Wk7H65PErud2nRnd4zgpCPnhbaQSAx3w==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=5792)
`pragma protect data_block
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

`pragma protect end_protected
endmodule