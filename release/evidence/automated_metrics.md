# Automated release metrics

Board-measured fields are intentionally not claimed here.

| Configuration | LUT | FF | DRM | setup WNS ns | hold WHS ns | estimated Fmax MHz |
|---|---:|---:|---:|---:|---:|---:|
| final | 3550 | 3136 | 5.5 | 2.812 | 0.314 | 58.1801 |

`final` 的 FF 为综合寄存器数；布局布线后 device map 的实现 FF 为 3127，两者阶段不同，不混用。

Official-CRC RTL simulation, same RV32I CoreMark image:

| Predictor | cycles | retired | CPI | BTB hit | misprediction |
|---|---:|---:|---:|---:|---:|
| Off | 1604264 | 776138 | 2.0670 | 0 | 132127 |
| On | 1295932 | 783550 | 1.6539 | 204729 | 51947 |

Predictor On reduces cycles by 19.22%. Final physical-board score remains subject to board measurement.
