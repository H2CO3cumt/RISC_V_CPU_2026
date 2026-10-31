# Automated release metrics

Board-measured fields are intentionally not claimed here.

| Configuration | LUT | FF | DRM | setup WNS ns | hold WHS ns | estimated Fmax MHz |
|---|---:|---:|---:|---:|---:|---:|
| final | 4995 | 3908 | 6.0 | 0.577 | 0.308 | 89.3841 |

`final` 的 FF 为综合寄存器数；布局布线后 device map 的实现 FF 为 3907，两者阶段不同，不混用。

Official-CRC RTL simulation, same RV32I CoreMark image:

| Predictor | cycles | retired | CPI | BTB hit | misprediction |
|---|---:|---:|---:|---:|---:|
| Off | 1604264 | 776138 | 2.0670 | 0 | 161742 |
| On | 1251724 | 786925 | 1.5907 | 221615 | 69120 |

Predictor On reduces cycles by 21.98%. Final physical-board score remains subject to board measurement.
