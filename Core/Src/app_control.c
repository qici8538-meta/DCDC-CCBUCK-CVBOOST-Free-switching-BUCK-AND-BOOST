#include "app_control.h"
#include "control_settings.h"
#include "adc_calibration.h"
#include "dcdc_step.h"
#include "tim.h"

volatile ControlGains control_gains;
volatile uint8_t control_mode, output_enable, power_output_enabled, control_fault;
volatile float charge_current_set, bus_voltage_set, duty_percent, current_reference;
static DcdcState state;
static DcdcParams params;
static uint8_t arm_pending, stale_samples;
static uint32_t previous_frame;
static int8_t current_step_direction;

/* RAM在线调参写入NaN/Inf时仍能可靠停机，不依赖编译器浮点假设。 */
static uint8_t Finite32(float value)
{
    union { float value; uint32_t bits; } number;
    number.value = value;
    return (number.bits & 0x7F800000U) != 0x7F800000U;
}

/* SD#=0才是双管关断；IN=0且使能有效会持续开低侧。 */
static void DisableOutput(void)
{
    PWM_EN_GPIO_Port->BRR = PWM_EN_Pin;
    TIM1->BDTR &= ~TIM_BDTR_MOE;
    TIM1->CCR1 = 0U;
    arm_pending = 0U;
    power_output_enabled = 0U;
    duty_percent = 0.0f;
}
void BuckControl_EmergencyStop(uint8_t fault)
{
    DisableOutput();
    if (fault != 0U) control_fault = fault;
}
void BuckControl_ParameterInit(void)
{
    RCC_ClkInitTypeDef clocks;
    uint32_t latency, timer_clock = HAL_RCC_GetPCLK2Freq();
    HAL_RCC_GetClockConfig(&clocks, &latency);
    if (clocks.APB2CLKDivider != RCC_HCLK_DIV1) timer_clock *= 2U;
    control_gains = (ControlGains){DCDC_CURRENT_KP,DCDC_CURRENT_KI,DCDC_VOLTAGE_KP,DCDC_VOLTAGE_KI};
    params.sample_time = 2.0f * (float)TIM1->ARR / (float)timer_clock;
    params.current_kp = DCDC_CURRENT_KP;
    params.current_ki = DCDC_CURRENT_KI;
    params.voltage_kp = DCDC_VOLTAGE_KP;
    params.voltage_ki = DCDC_VOLTAGE_KI;
    params.current_slew = DCDC_CURRENT_SLEW;
    params.voltage_slew = DCDC_VOLTAGE_SLEW;
    params.charge_limit = DCDC_CHARGE_LIMIT;
    params.discharge_limit = DCDC_DISCHARGE_LIMIT;
    params.overcurrent = DCDC_OVERCURRENT;
    params.overcharge = DCDC_OVERCHARGE;
    params.overcharge_release = DCDC_OVERCHARGE_RELEASE;
    params.battery_min = DCDC_BATTERY_MIN;
    params.battery_max = DCDC_BATTERY_MAX;
    params.bus_max = DCDC_BUS_MAX;
    params.duty_min = DCDC_DUTY_MIN;
    params.duty_max = DCDC_DUTY_MAX;
    params.current_lead_time = DCDC_CURRENT_LEAD_TIME;
    params.current_ff_inductance = DCDC_CURRENT_FF_INDUCTANCE;
    dcdc_step_initialize();
    state = (DcdcState){0};
    control_mode = 1U;
    output_enable = 0U; /* 上电只采样显示，人工长按/写1启动。 */
    charge_current_set = 1.0f;
    bus_voltage_set = 30.0f;
    control_fault = 0U;
    current_reference = 0.0f;
    stale_samples = 0U;
    previous_frame = 0U;
    current_step_direction = 1;
    DisableOutput();
}
void BuckControl_KeyEvent(uint8_t event)
{
    if (event == 2U)
    {
        output_enable = (output_enable == 0U) ? 1U : 0U;
        if (output_enable == 0U) DisableOutput();
    }
    else if (event == 1U)
    {
        if (output_enable == 0U)
            control_mode = (control_mode >= 3U) ? 1U : (uint8_t)(control_mode + 1U);
        else if ((control_mode == 1U) && (control_fault == 0U))
        {
            if (!Finite32(charge_current_set) || (charge_current_set < 1.0f) ||
                (charge_current_set > 2.0f)) return;
            uint32_t tenths = (uint32_t)(charge_current_set * 10.0f + 0.5f);
            if (tenths >= 20U) current_step_direction = -1;
            else if (tenths <= 10U) current_step_direction = 1;
            charge_current_set = (float)((int32_t)tenths + current_step_direction) * 0.1f;
        }
    }
}
void BuckControl_Start(void)
{
    DisableOutput();
    BuckAdc_Start();
    if (HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_1) != HAL_OK) Error_Handler();
    DisableOutput();
    __HAL_TIM_CLEAR_FLAG(&htim1, TIM_FLAG_UPDATE);
    __HAL_TIM_ENABLE_IT(&htim1, TIM_IT_UPDATE);
}
void BuckControl_AdcError(ADC_HandleTypeDef *hadc)
{
    BuckAdc_ConversionError(hadc);
    if (hadc->Instance == ADC1) BuckControl_EmergencyStop(5U);
}
void BuckControl_TimerElapsed(TIM_HandleTypeDef *htim)
{
    BuckFeedback feedback;
    float duty;
    boolean_T enabled;
    uint8_t mode;
    uint32_t mask;
    if (htim->Instance != TIM1) return;
    if (__HAL_TIM_IS_TIM_COUNTING_DOWN(htim))
    {
        /* CCR在峰值更新装载后开门，IN此时为低，先给自举刷新窗口。
         * 不强制UG，避免额外ADC触发；禁止长时间0%开低侧充自举。 */
        mask = __get_PRIMASK();
        __disable_irq();
        if (arm_pending && output_enable && (control_fault == 0U) && (adc_error_count == 0U))
        {
            PWM_EN_GPIO_Port->BSRR = PWM_EN_Pin;
            __HAL_TIM_MOE_ENABLE(htim);
            power_output_enabled = 1U;
            arm_pending = 0U;
        }
        __set_PRIMASK(mask);
        return;
    }
    BuckAdc_ReadFeedback(&feedback);
    if (feedback.frame_count == 0U) { DisableOutput(); return; }
    if (feedback.frame_count == previous_frame)
    {
        if (stale_samples < 3U) stale_samples++;
    }
    else { stale_samples = 0U; previous_frame = feedback.frame_count; }
    if ((adc_error_count != 0U) || (stale_samples >= 2U))
    {
        state.fault = 5U; control_fault = 5U; DisableOutput(); return;
    }
    if ((output_enable > 1U) || (control_mode < 1U) || (control_mode > 3U))
    {
        state.fault = 6U; control_fault = 6U; DisableOutput(); return;
    }
    mode = output_enable ? control_mode : 0U;
    if (mode != 0U)
    {
        if (!Finite32(charge_current_set) || !Finite32(bus_voltage_set) ||
            !Finite32(control_gains.current_kp) || !Finite32(control_gains.current_ki) ||
            !Finite32(control_gains.voltage_kp) || !Finite32(control_gains.voltage_ki))
        {
            state.fault = 6U; control_fault = 6U; DisableOutput(); return;
        }
        if ((feedback.raw[0] <= 5U) || (feedback.raw[0] >= 4090U) ||
            (feedback.raw[1] >= 4090U) || (feedback.raw[2] >= 4090U) ||
            (feedback.raw[3] < ADC_REF_MIN_RAW) || (feedback.raw[3] > ADC_REF_MAX_RAW))
            state.fault = 5U;
        else if ((feedback.current_unfiltered >= params.overcurrent) ||
                 (feedback.current_unfiltered <= -params.overcurrent))
            state.fault = 3U;
    }
    params.current_kp = control_gains.current_kp;
    params.current_ki = control_gains.current_ki;
    params.voltage_kp = control_gains.voltage_kp;
    params.voltage_ki = control_gains.voltage_ki;
    /* 同一MATLAB函数生成的C。内部积分/斜坡不作为人工操作变量。 */
    dcdc_step(mode,charge_current_set,bus_voltage_set,feedback.battery_current,
              feedback.battery_voltage,feedback.bus_voltage,&state,&params,&duty,&enabled);
    control_fault = state.fault;
    current_reference = state.current_reference;
    if (!enabled || (adc_error_count != 0U)) { DisableOutput(); return; }
    TIM1->CCR1 = (uint32_t)(duty * (float)TIM1->ARR + 0.5f);
    duty_percent = duty * 100.0f;
    mask = __get_PRIMASK();
    __disable_irq();
    if ((adc_error_count == 0U) && (control_fault == 0U) && output_enable)
    {
        if (power_output_enabled == 0U) arm_pending = 1U;
    }
    else DisableOutput();
    __set_PRIMASK(mask);
}
