#ifndef APP_ADC_H
#define APP_ADC_H

#include "main.h"

/* 人工看采样时，先看原始计数，再看引脚电压，最后看换算后的VOUT。 */
extern volatile uint16_t adc_current_raw;
extern volatile uint16_t adc_voltage_raw;
extern volatile float adc_current_raw_avg;
extern volatile float adc_voltage_raw_avg;
extern volatile float adc_voltage_pin; /* PA1引脚电压(V)，未扣零点、未乘15。 */
extern volatile float buck_current;
extern volatile float buck_current_avg; /* 平滑电流(A)，仅观察，不增加控制延迟。 */
extern volatile float buck_voltage;     /* 当前帧电压，PI使用。 */
extern volatile float buck_voltage_avg; /* 均值换算电压，画图使用。 */

/* 只读观测量：帧数说明是否还在采样；错误数说明HAL是否报错。无需人工置位。 */
extern volatile uint32_t adc_frame_count;
extern volatile uint32_t adc_error_count;

void BuckAdc_Start(void);
void BuckAdc_ConversionComplete(ADC_HandleTypeDef *hadc);
void BuckAdc_ConversionError(ADC_HandleTypeDef *hadc);
void BuckAdc_ReadFeedback(float *current, float *voltage, uint16_t *voltage_raw);

#endif
