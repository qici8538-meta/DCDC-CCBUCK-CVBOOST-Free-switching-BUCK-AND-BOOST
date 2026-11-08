/**
  ******************************************************************************
  * @file    app_control.h
  * @brief   Buck 变换器双闭环控制模块
  ******************************************************************************
  */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __APP_CONTROL_H
#define __APP_CONTROL_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "pid.h"
#include "app_adc.h"

/* Exported variables --------------------------------------------------------*/
/* 编译选择：0单电流环，1双环，2开环，3单电压环。 */
#define BUCK_CONTROL_MODE 0U

/* 单电压环按键目标范围；0V另作人工停机命令。 */
/* v1.1.0 单电流环：0A停机；首次按键0.2A，端点折返。 */
#define BUCK_CURRENT_TARGET_MIN_A  0.2f
#define BUCK_CURRENT_TARGET_MAX_A  3.0f
#define BUCK_CURRENT_TARGET_STEP_A 0.1f
#define BUCK_CURRENT_VOLTAGE_MAX_V 20.0f /* 30V输入、0~5Ω电阻验证用 */

#define BUCK_VOLTAGE_TARGET_MIN_V  2.0f
#define BUCK_VOLTAGE_TARGET_MAX_V  10.0f
#define BUCK_VOLTAGE_TARGET_STEP_V 1.0f

/* PI 控制器 */
extern volatile PI_CTRL_DATA_DEF voltage_pi;
extern volatile PI_CTRL_DATA_DEF current_pi;
/* 独立单电压环：Kp单位为占空比百分点/V，Ki为百分点/(V*s)。
   Out/ui仍为PWM比较计数；不复用双闭环外环参数。 */
extern volatile PI_CTRL_DATA_DEF voltage_only_pi;

/* 给定值与保护阈值 */
extern volatile float voltage_reference;
extern volatile float current_reference;
extern volatile float current_limit;
extern volatile float pwm_limit;

/* 采样值与控制量 */
extern volatile float buck_duty;          /* 控制量计数值，非百分比 */
extern volatile float openloop_command;

/* Read-only indication of actual software PWM/driver enable. */
extern volatile uint8_t power_output_enabled;

/* Exported functions prototypes ---------------------------------------------*/
void BuckControl_ParameterInit(void);
void BuckControl_KeyPressed(void);
void BuckControl_Start(void);
void BuckControl_AdcError(ADC_HandleTypeDef *hadc);
void BuckControl_TimerElapsed(TIM_HandleTypeDef *htim);

#ifdef __cplusplus
}
#endif

#endif /* __APP_CONTROL_H */
