#ifndef ADC_CALIBRATION_H
#define ADC_CALIBRATION_H
/* 第二版：四路直接采样，无额外0.6分压。先实测标定，再整定PI。
 * PC0读取INA213的REF；零电流时I通道与REF通道的差值应接近0。
 * ADC参考电压是MCU的VDDA/VREF+，不是INA213约1.6667V的REF。 */
#define ADC_REFERENCE_VOLTAGE     3.3f
/* 实测零电流时 mean(raw[0]-raw[3])，可正可负；禁止带电流自动学习。 */
#define ADC_CURRENT_OFFSET_RAW    0.0f
/* 两只输入电阻实装均为10Ω；名义灵敏度0.495785821V/A。
 * K=1/(0.01*50*20000/(20000+17*10))，实板用两点标定替换。 */
#define ADC_CURRENT_A_PER_PIN_V   2.017f
#define ADC_BATTERY_ZERO_RAW      0.0f
#define ADC_BUS_ZERO_RAW          0.0f
#define ADC_BATTERY_RATIO         15.0f
#define ADC_BUS_RATIO             15.0f
/* REF合理性检查，约1.21～2.26V；接线错误/掉电按ADC故障停机。 */
#define ADC_REF_MIN_RAW           1500U
#define ADC_REF_MAX_RAW           2800U
/* 约40k帧/s，对应2kHz一阶数字低通；改PWM频率时同步计算。 */
#define ADC_CURRENT_FILTER_ALPHA  0.269543f
#endif
