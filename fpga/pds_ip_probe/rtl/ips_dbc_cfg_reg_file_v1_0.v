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
//the cfg_reg_file module, which is register file of configuration 
//

  module ips_dbc_cfg_reg_file_v1_0 
  #(
   parameter NEW_JTAG_IF     = 1,
   parameter c_CFG_CHAIN_BIT = 256
   )
  (
   input   rstn,     
   input   cfg_clk,
   input   cfg_cs,
   input [4:0]  conf_id,
   input   [c_CFG_CHAIN_BIT-1:0] cfg_reg_data,
   input   cfg_rden,
   output  reg cfg_rdlast,
   output  reg cfg_rdata    //read latency is one clock cycle
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
dZA7YJ+MECJyROf+/NNX/DGclLF4PJex6VyZTP2FltwTixAgGOIsClJyIT/O/3fby53ejOmUwXoS
OSU2rBkim9NhxbJ5Kh38sp2F6tDEYjYf50P5B9NkPNyC930H4N0QxEgHE2zQlb2ov/o1jJMxQVEK
I9pl8nr5wQ1CoGVx1ARPNDW/R8UbOzYfGxP7w3w/mB8i2kUzQvYmuXFuv7jPwQaRPBhyTHiGmqyF
Zhip4XODyuLI+wJEaz8QcwxkLqAZq5jMswl8Sbu8+xpXpuUrjUu2lCkrxZBk0KgrPB0zuEnuAv0w
3GERT2nfA2YHyEtR9IAkU3NtySIUe36IZazexQ==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_24", key_method="rsa"
`pragma protect key_block
R8+zSpCBT35hvPya9puqk0tTkVMORks29dl4qgsCYC4Oi6fsiL7FdTNHILFa7hgDLL1Dz2+kYJcw
wdDm75wABjkCusqm8psry23bp7V0AnhMadxylYjT1EdKx7faSRYmNhXANyOpxVNbXUFP9m9DMioQ
m4/hQqLmTJAZ3ydOjKXWCLP3UiC+JUlLBMUpEVUBdjQkS7mpXDTFE9JgWEeAqVmpxk8KYrfiq1gs
aUDRhf7TxyIJRIhMVNDeFcaC7jjqkao8LV2N2++25uYxP+9MFiF+n3RJjk5LGPow3yo7bqr8lSKU
gGbBVeWZvjp96h3XGoYr2yWqNxJG4IPhzRU4sA==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=1728)
`pragma protect data_block
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
B/VxQB4ysPrIBY3raOMnFupi

`pragma protect end_protected
  endmodule