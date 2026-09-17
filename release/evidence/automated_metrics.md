# Automated release metrics

Board-measured fields are intentionally not claimed here.

| Configuration | LUT | FF | DRM | setup WNS ns | hold WHS ns | estimated Fmax MHz |
|---|---:|---:|---:|---:|---:|---:|
| final | 3458 | 3137 | 5.5 | 2.257 | 0.319 | 56.3603 |

`final` 的 FF 为综合寄存器数；布局布线后 device map 的实现 FF 为 3128，两者阶段不同，不混用。

Official-CRC RTL simulation, same RV32I CoreMark image:

| Predictor | cycles | retired | CPI | BTB hit | misprediction |
|---|---:|---:|---:|---:|---:|
| Off | 2106042 | 775901 | 2.7143 | 0 | 131903 |
| On | 1852156 | 779952 | 2.3747 | 203492 | 51908 |

Predictor On reduces cycles by 12.06%. Final physical-board score remains subject to board measurement.
