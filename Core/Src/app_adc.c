#include "app_adc.h"
#include "adc.h"
#include "adc_calibration.h"
static volatile uint16_t adc_dma_buffer[4] __ALIGNED(4);
volatile BuckFeedback adc_feedback;
volatile uint32_t adc_error_count;
void BuckAdc_Start(void)
{
    adc_feedback = (BuckFeedback){0};
    adc_error_count = 0U;
    MX_ADC1_Init();
    HAL_Delay(1U);
    if (HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED) != HAL_OK) Error_Handler();
    if (HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc_dma_buffer, 4U) != HAL_OK) Error_Handler();
    __HAL_DMA_DISABLE_IT(&hdma_adc1, DMA_IT_HT);
}
void BuckAdc_ConversionComplete(ADC_HandleTypeDef *hadc)
{
    BuckFeedback next;
    const float scale = ADC_REFERENCE_VOLTAGE / 4095.0f;
    if (hadc->Instance != ADC1) return;
    next.raw[0] = adc_dma_buffer[0];
    /* DMA顺序I/REF/VBAT/VBUS：让I和REF相邻采样；观察数组沿用I/VBAT/VBUS/REF。 */
    next.raw[1] = adc_dma_buffer[2];
    next.raw[2] = adc_dma_buffer[3];
    next.raw[3] = adc_dma_buffer[1];
    next.reference_voltage = (float)next.raw[3] * scale;
    next.current_unfiltered = ((float)next.raw[0] - (float)next.raw[3] - ADC_CURRENT_OFFSET_RAW) * scale * ADC_CURRENT_A_PER_PIN_V;
    next.battery_voltage = ((float)next.raw[1] - ADC_BATTERY_ZERO_RAW) * scale * ADC_BATTERY_RATIO;
    next.bus_voltage = ((float)next.raw[2] - ADC_BUS_ZERO_RAW) * scale * ADC_BUS_RATIO;
    if (adc_feedback.frame_count == 0U)
        next.battery_current = next.current_unfiltered;
    else
        next.battery_current = adc_feedback.battery_current + ADC_CURRENT_FILTER_ALPHA *
            (next.current_unfiltered - adc_feedback.battery_current);
    next.frame_count = adc_feedback.frame_count + 1U;
    adc_feedback = next;
}
void BuckAdc_ConversionError(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC1) adc_error_count++;
}
void BuckAdc_ReadFeedback(BuckFeedback *out)
{
    uint32_t mask = __get_PRIMASK();
    __disable_irq();
    *out = adc_feedback;
    __set_PRIMASK(mask);
}
