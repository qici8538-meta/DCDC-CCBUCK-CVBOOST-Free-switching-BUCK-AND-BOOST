/**
  ******************************************************************************
  * @file    pid.h
  * @brief   PI 控制器模块
  ******************************************************************************
  */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __PID_H
#define __PID_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Exported types ------------------------------------------------------------*/
typedef struct PI_CTRL_DATA_TAG
{
    float Out;
    float Kp;
    float Ki;                 /* pi_func为每拍增益；pi_func_percent为百分点/(V*s) */
    float Kd;                 /* 默认 0，运行 PI；非零时启用差分项 */
    float Umax;
    float Umin;
    float up;                 /* 上一次误差 */
    float ui;                 /* 积分输出，与 Out 单位一致 */
    float temp_p;
    float temp_imax;
    float temp_imin;
} PI_CTRL_DATA_DEF;

/* Exported functions prototypes ---------------------------------------------*/
float limit_value(float value, float low, float high);
float pi_func(volatile PI_CTRL_DATA_DEF *pi, float ref, float fbk);
/* 百分比PI：电压环输入V，电流环输入A；内部乘ARR/100及控制周期，Out仍为计数。 */
float pi_func_percent(volatile PI_CTRL_DATA_DEF *pi, float ref, float fbk,
                      float arr, float sample_period_s);

#ifdef __cplusplus
}
#endif

#endif /* __PID_H */
