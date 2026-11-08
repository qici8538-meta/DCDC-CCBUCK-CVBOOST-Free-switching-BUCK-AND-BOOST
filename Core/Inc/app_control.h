#ifndef APP_CONTROL_H
#define APP_CONTROL_H
#include "main.h"
#include "app_adc.h"
/* 人工调参变量。模式1恒流充电，2恒压放电，3自动；启停独立。 */
typedef struct {
    float current_kp; /* 高侧占空比(0..1)/A */
    float current_ki; /* 高侧占空比/(A*s) */
    float voltage_kp; /* A/V */
    float voltage_ki; /* A/(V*s) */
} ControlGains;
extern volatile ControlGains control_gains;
extern volatile uint8_t control_mode;
extern volatile uint8_t output_enable; /* 0停机，1运行请求；复位0 */
extern volatile float charge_current_set; /* 1.0..2.0 A，步进0.1 */
extern volatile float bus_voltage_set; /* 默认30 V */
/* 只读观察量，内部积分和斜坡状态不作为调参入口。 */
extern volatile float duty_percent;
extern volatile float current_reference; /* A，正充电、负放电 */
extern volatile uint8_t power_output_enabled;
/* 0正常，1过充，2欠压，3过流，4母线过压，5采样，6参数，7CPU故障 */
extern volatile uint8_t control_fault;
void BuckControl_ParameterInit(void);
void BuckControl_Start(void);
void BuckControl_KeyEvent(uint8_t event); /* 1短按，2长按 */
void BuckControl_TimerElapsed(TIM_HandleTypeDef *htim);
void BuckControl_AdcError(ADC_HandleTypeDef *hadc);
void BuckControl_EmergencyStop(uint8_t fault);
#endif
