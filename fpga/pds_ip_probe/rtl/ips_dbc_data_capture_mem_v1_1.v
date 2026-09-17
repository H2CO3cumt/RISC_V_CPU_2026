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
//the data_capture_memory module
// Called by     :  debug_core
// Modification history
//
//----------------------------------------------------------------------

module ips_dbc_data_capture_mem_v1_1
#(
 parameter  MEM_STYLE  = 0,
 parameter  DATA_DEPTH = 9,
 parameter  DATA_WIDTH = 8
 )
(
 input                   rdclock  ,
 input                   wrclock  ,
 input  [DATA_DEPTH-1:0] rdaddress,
 output reg [DATA_WIDTH-1:0] q        ,
 input                   wren     ,
 input  [DATA_DEPTH-1:0] wraddress,
 input  [DATA_WIDTH-1:0] data     
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
qD8nt0S5sadC1elem2dt8M2c4OnTwUZYbqNi3CU9gjS9AlCbEc191oHnvSb55Q4OZlKyKO88ln4l
BWrCjfTp0amN/403kGSqzeRqkoxSoD1/hadt2AdONsWbfjvwwPJppmUtElUZ8eDYAFPTgbyglw4H
fN95+ep8/8TkCQSA9Dx+ttMBbYWmE4TaCCdia2pq6I8pVX4TNpJRnSYXowWA5NOHj6w1u0Pe1qFf
IstMOXAKirUmu5I7RaNxvbkRNwZNclNySDttXZ5nmyUb5cJ/yIUj/wN8ZRipZGs/LBD6IyHATx4l
ndYXegeF5Vpm+HMuDU2+UT7ZT740tFQh87BExg==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_24", key_method="rsa"
`pragma protect key_block
MXmtPkvAFSGAeO4U9HWFuDttZA+PpAHcH5sBlpjdLaSKUCxk/SkG427WcFnPn/AOmBQlzl0goYwW
9eEB+NigOhXerh7GtDUpjYV2VSwEzJ1dXrBuDmTVp9y2zApBDUCdDDjIKjoOev9I0rsTMqK2Q2WQ
78gIwNhwCJI3Sr0oz8qhv9iSbFQatvbSjsI/bjoRfmwZkxPvtyDYgeryYjsjOZ1mrINLwxpbEqZr
0nNsGXZ/0rxbGM4M9wD8iV+zHUZve9fBqhqHMwJjnoBmWxVuw48WepCOobfOTfiOdyRRMiaJ8XC2
xi7u3tBsoK1IVNzGJQkvHzPBWXZBG4Z3MV3DCw==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=1360)
`pragma protect data_block
m09dwMecu0oRD6sKcctoc0mL8ViGhZxtP60BHSQqenNA+gdveG7/3BsqmCUzTWBNRBs9tQ8W8CCX
DEX8iz2kLqhPsmHk/hcuMMd4iOUv3mLyglBidsBNuCZigR2inbWq8jOzgdxz1PvOJgPvV34Xs3R6
3M3Y/3phMBgqCalKbwJzRF39VU1HJXW5na4ECku12iqmS+Zer7c2tLc62X/22DH3YtSlHQmAQOt6
rbtUCu0j4hyMO1VTU6F2/HR+iWuDpZmkYmJ93/u4oU+1XrU+f9Pz7V1k3OnW2GFgLilhZwCy+IFs
jaJi2WBEO0Nz0+ZAy4kiyT/9v16sMk8uc+zQ3Ryk238IxD1C098YxGoSoR2X1Nr+4pifICRIzjzq
JY6hpTCJWFxsHfUIAfEhmGPiie4Tgkt+5AGJREfFFrrzFhOHYzLPQGpZqDLzlrN5eLiksWukgrhS
9cnA5uOBYFNOk/23JtL+Y6/F4rPGCnxO0s1Ud2kiYzTDjHIO9sw+TsYp89x0TtGFSLKMVBx2MQAP
sRgmu56pf4MLJez+ZvvV+kCIuVnsxcHPKCv/z9UOCrlINFCogimi6Kp7WhDVtZNyREgYfTv+t4jM
ckAvZ8Gp4c3WSV6Xm48Bc360if65JePL+yxplecnzC9RGT6SVkCLqHEC8T3/KUA/Ml+bippMFOXn
69a33iakbkVxI9hXmPeNOutdmejuZH+DcG2t0xSOf993kUgAN2VcQW8yu97cO43CqeuxyjXrjZud
CWGSY5iCBV3KVA7dlxTca93wszQUMfPU4m7IArrd0VYVAENmNFSdWYMGjqgF/n4XEvDyNtWFzz0o
X2T1huiIjGcppybkcJDrqxSGT7mdvmiuc5QmG7weL5thFj7/9oT2iUnyonr2AD1nizSSDTaSRSVy
nO24A4kt9w+ar87mA7oiqqoLrcvMNIsPjXW3/Tm2A3lLDAwX931Bm4zb37Q07O0ZC286KjGKDJsF
gdUgSt3RJoI6jHcx5owLYt5t36A/9nXb8no8zosEME/GjPQQ8OZu1NrgSYayP93cAcN5sSEHsG/R
zmMLE4DWKDb0Wolb/RPArX9DEPWvYyMDafnVVuyFqxv0BodirHQ7z58b+Ae+fCUb0VUVB+sD2y9K
WnEwxRdPk+UABABUiMVfqxqpwo0p5TpVTZjmTrJLW9SRkK2m5tqN8c1DBvS/2qjwJdpOA3lnG6kB
ruhlFKBvlhOK4EteOqmUbBWSuv/hVpp9tywGz/3jCkx6Gvevh3sUqTTmUin/kM99+v34k7yPkEmi
NVLlptJ97AWES+ftLTEGqHPvlMm17tAe3Mzm/iFlHl12vxIF/ZLG9Y1J0B8loTQKIpdNoCefPBob
G2LG6EcEQKA8cymUO10Z5fZ2dUN0Z21PBSg6wewE8tW2VJ7IDbspSOliHIz9Q/yeD0Vyoy4rJntL
3WoO+aGW5lLXNMRYkN7NK8kJLUb4ojdWCQZ0FItYKJKiyDdntCR8ZUkPVPQzSug9LHhPsx5qRLzj
Hx77McxxrBQvtX4Mh2LBEqPvn2zbJ5pX0FeY1CKn/e/h381u/8BgjQmVDFsZnX0V7K4a92/iCSnZ
Arkpv1/8En8qLDDxEs0bjR13OKjD8DgGa7+6OGpeDp+GG/PD27okwgx4WE8kD7VVJIIReavpQVZK
3E2IZdpj/acIYcu2NtM8eQOW0t2DhzlsArAngjYshrC+9y5tgm1CYLzhouA7yXsY5DhGe3XsklJ0
PI1m+3WSUSE/JlhtcDEDjdwGtHsSCX7KuggVtzkVjg10RNzyL5qw/pvwc/a7E4imKw==

`pragma protect end_protected
endmodule