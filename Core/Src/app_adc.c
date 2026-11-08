/**
  * 人工读代码的顺序：
  * 1. adc.c 配通道、触发和DMA；这里的 Start 负责启动。
  * 2. TIM1触发 -> 两个通道转换 -> DMA按顺序写 adc_dma_buffer[0/1]。
  * 3. ConversionComplete 取数 -> 求均值 -> 换算，供人观察和PI读取。
  */
#include "app_adc.h"
#include "adc.h"
#include "adc_calibration.h"

/* 数值参数，不是要人工置位的标志。零点仍直接使用原校准头文件。 */
#define ADC_REFERENCE_VOLTAGE 3.3f
#define ADC_FULL_SCALE        4095.0f
#define VOLTAGE_SENSOR_RATIO  15.0f
#define CURRENT_SENSOR_RATIO  2.0f
#define ADC_AVERAGE_ALPHA     0.05f

/* 扫描顺序决定位置：Rank1/PA0 -> [0]；Rank2/PA1 -> [1]。 */
static volatile uint16_t adc_dma_buffer[2] __ALIGNED(4);

volatile uint16_t adc_current_raw;
volatile uint16_t adc_voltage_raw;//
volatile float adc_current_raw_avg;
volatile float adc_voltage_raw_avg;//
volatile float adc_voltage_pin;//
volatile float buck_current;
volatile float buck_voltage;
volatile float buck_voltage_avg;////
volatile uint32_t adc_frame_count;//
volatile uint32_t adc_error_count;//

void BuckAdc_Start(void)
{
    adc_frame_count = 0U;
    adc_error_count = 0U;
    adc_current_raw = adc_voltage_raw = 0U;
    adc_current_raw_avg = adc_voltage_raw_avg = 0.0f;
    adc_voltage_pin = buck_current = buck_voltage = buck_voltage_avg = 0.0f;

    /* 通道、采样时间、TIM1触发、DMA循环模式都在adc.c里看。 */
    MX_ADC1_Init();
    HAL_Delay(1U); /* 给模拟通路稳定时间，也覆盖临时VREFINT通道试验。 */
    /* ADC芯片自身校准：不是改传感器零点，不写ADC_VOLTAGE_ZERO_RAW。 */
    if (HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED) != HAL_OK)
        Error_Handler();

    /* 2是两个16位采样值的数量，不是2字节；DMA按halfword搬运。
       HAL形参要求uint32_t*，不改变adc.c配置的实际搬运宽度。
    
       ADC准备接收触发，DMA准备接收两个结果。
    */
    if (HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc_dma_buffer, 2U) != HAL_OK)
        Error_Handler();
    /* 等两个位置都写完再处理，不处理中间只写完一半的回调。 */
    __HAL_DMA_DISABLE_IT(&hdma_adc1, DMA_IT_HT);
}

//取出数字、平滑、换算电压
void BuckAdc_ConversionComplete(ADC_HandleTypeDef *hadc)
{
    uint16_t current_raw;
    uint16_t voltage_raw;
    if (hadc->Instance != ADC1) return;

    /* A. 取本帧原始数：这里没有HAL_ADC_GetValue，也不猜通道先后。 */
    current_raw = adc_dma_buffer[0];
    voltage_raw = adc_dma_buffer[1];
    adc_current_raw = current_raw;
    adc_voltage_raw = voltage_raw;

    /* B. 首帧直接作初值；以后用EMA减小画图抖动，算法和系数保持原值。 */
    if (adc_frame_count == 0U)
    {
        adc_current_raw_avg = (float)current_raw;
        adc_voltage_raw_avg = (float)voltage_raw;
    }
    else
    {
        adc_current_raw_avg += ADC_AVERAGE_ALPHA * ((float)current_raw - adc_current_raw_avg);
        adc_voltage_raw_avg += ADC_AVERAGE_ALPHA * ((float)voltage_raw - adc_voltage_raw_avg);
    }

    /* C. 引脚电压：用它与万用表测到的SAMPLE_V直流值对照。
       例如平均原始值100 -> 100/4095*3.3 = 0.08059V。 */
    adc_voltage_pin = adc_voltage_raw_avg * ADC_REFERENCE_VOLTAGE / ADC_FULL_SCALE;

    /* D. 保留原来的零点扣除、3.3V参考、15倍电压及2倍电流换算。 */
    buck_current = ((float)current_raw - ADC_CURRENT_ZERO_RAW) *
                   (ADC_REFERENCE_VOLTAGE / ADC_FULL_SCALE) * CURRENT_SENSOR_RATIO;
    buck_voltage = ((float)voltage_raw - ADC_VOLTAGE_ZERO_RAW) *
                   (ADC_REFERENCE_VOLTAGE / ADC_FULL_SCALE) * VOLTAGE_SENSOR_RATIO;
    buck_voltage_avg = (adc_voltage_raw_avg - ADC_VOLTAGE_ZERO_RAW) *
                       (ADC_REFERENCE_VOLTAGE / ADC_FULL_SCALE) * VOLTAGE_SENSOR_RATIO;

    /* 最后计数：计数增加说明一整帧的取数和换算已完成。 */
    adc_frame_count++;
}

void BuckAdc_ConversionError(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC1) adc_error_count++;
}

void BuckAdc_ReadFeedback(float *current, float *voltage, uint16_t *voltage_raw)
{
    /* 只在复制这三个值时短暂屏蔽中断，避免读一半时被ADC回调更新。
       这里不做HAL等待、计算或串口操作，复制后立刻恢复原中断状态。 */
    uint32_t saved_interrupt_state = __get_PRIMASK();
    __disable_irq();
    *current = buck_current;
    *voltage = buck_voltage;
    *voltage_raw = adc_voltage_raw;
    __set_PRIMASK(saved_interrupt_state);
}
