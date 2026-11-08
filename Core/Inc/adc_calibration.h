#ifndef ADC_CALIBRATION_H
#define ADC_CALIBRATION_H

/* 实测零点原始计数。人工测量后更新数值，不另设“已标定”标志。 */
/* V1只采PA0/PA1：这里必须填零电流时PA0完整码值，不能填V2的I-REF差值3。
   2026-11-08仅MCU+辅助供电、无功率输入，64个均值读数再平均。 */
#define ADC_CURRENT_ZERO_RAW 2076.36098063f
#define ADC_CURRENT_A_PER_PIN_V 2.000f /* 10Ω输入电阻名义修正，实物仍需标定 */
/* 2026-10-15实测电压零点：4096点，sum=554；本次数值保留。 */
#define ADC_VOLTAGE_ZERO_RAW 0.13525390625f

#endif
