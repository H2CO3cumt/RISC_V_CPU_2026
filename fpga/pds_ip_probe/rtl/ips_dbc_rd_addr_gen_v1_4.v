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
//the rd_addr_gen module, it contains tdo_mux_s function 
//
//

module ips_dbc_rd_addr_gen_v1_4
 #(
   parameter  NEW_JTAG_IF = 1,
   parameter  INFO_CHAIN_BIT = 81,                       //the total bit number of information  
   parameter  INFO_CHAIN  = 0,      //the information data
   parameter  DATA_DEPTH     = 9,	                       //the range is 9~17
   parameter  DATA_BIT       = 1,	                       //1~4096   
   parameter  DATA_CHAIN_BIT       = 2,	                 //DATA_BIT+1
   parameter  STATUS_CHAIN_BIT     = 10                  //	DATA_DEPTH +1    
 )
 (
   input                       h_rstn,          //hw resetn from user logic              
   input                       clk_conf,        //jtag clk            
   input                       rst_conf,        //sw rst from jtag_hub            
   input                       clk_trig,   
   input                       info_en,         //sw select to read the info data to tdo ,control[4]            
   input                       status_en,       //sw select to read the status data to tdo, control[5]          
   input                       ramdata_en,      //sw select to read the ram data to tdo,control[6]          
   output reg [DATA_DEPTH-1:0] ram_radr,            
   input  [DATA_DEPTH:0]       status,              
   input  [DATA_BIT:0]         ram_rdata,           
  //add others tdo             
   input  [19:0]               conf_rdlast,
   input  [19:0]               conf_rdata,
   input                       conf_sel,   
   input  [4:0]                conf_id,
   input  [4:0]                conf_reg_rb,
   input                       operation_ind,      
   output reg                  tdo_mux             
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
x/0gfn0M6fkRSlxHIm/6N85xf+M5a0KGuyPBsXPEqIrwT5gmDcyZuoK6Pwe2ZjR6C79hizFq7m/O
8iR15iTSbd6foKZgPVJajocoRYuI6TbdVBObzt6F3+NXDzHOWb61Y2Q5UTJvJRAJTcpluuCEaVib
8cr5mjjJBX8keurAUjOQpHxMGW/A3ALEbTcsF4J2IDw/uXca0n7dZmU9zIbRsZ02pGnTs3+GN9HW
gQWlFuEq1rek/hBiOdfibKA85JoLkVUTkNzV1ViKSX8wL3AtRyCuc+pv0zwu/t/8ujO3+6HNnWQf
x2PA1qFbu1IeK3QEXoJoADJfsTNLDz9pMfAHvw==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_24", key_method="rsa"
`pragma protect key_block
bjrkQUe5kkccsT5VMggzuA7Qlj/0QnVjiqtXm3UPIJcLrI+w042THEsrRyTzKJAJ464U2L/w1DIY
yeRZN9sjFXcPBeqpg0RnVdvEL3RYA+LWByFmfd9TqW28n3tQQLtvsPDFZTu3vtv5Xhb8un7JTmD3
CP7WfMOpf5D9XNICJW6B8P+iCzUHhml7247pQg1Js7IZh/Do2d9iNEYHJqMefeGDdmc4bcL+8lB4
bpy9G373DL8R34YiXEPx8Fzl9AP8jQWuASoQYHqVnvg+lLLRASyy4XuVh1jjDtE/7skQEXbgfW3n
Qi2lJlX32vKque70kXj/8QMDOkUE7IpATsMFlA==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=9616)
`pragma protect data_block
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

`pragma protect end_protected
endmodule