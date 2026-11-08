#ifndef APP_ADC_H
#define APP_ADC_H
#include "main.h"
typedef struct {
    float battery_current; /* A，电池支路，正充电，控制用滤波反馈 */          ///*debug中添加形如：adc_feedback.battery_current*/
    float battery_voltage; /* V，U1电池端口 */                             ///
    float bus_voltage; /* V，U2母线 */                                   ///
    float current_unfiltered; /* A，快速过流判定 */                      /// 
    float reference_voltage; /* V，PC0实测INA213的REF，仅观察 */         ///
    uint16_t raw[4]; /* [0]PA0电流，[1]PA1电池电压，[2]PC1母线，[3]PC0 REF */     ///
    uint32_t frame_count;
} BuckFeedback;
extern volatile BuckFeedback adc_feedback;///
extern volatile uint32_t adc_error_count;
void BuckAdc_Start(void);
void BuckAdc_ConversionComplete(ADC_HandleTypeDef *hadc);
void BuckAdc_ConversionError(ADC_HandleTypeDef *hadc);
void BuckAdc_ReadFeedback(BuckFeedback *out);
#endif
