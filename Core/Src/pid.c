/**
  ******************************************************************************
  * @file    pid.c
  * @brief   PI 控制器模块
  ******************************************************************************
  */

/* Includes ------------------------------------------------------------------*/
#include "pid.h"

/**
  * @brief  限幅函数
  * @param  value 待限幅的值
  * @param  low   下限
  * @param  high  上限
  * @retval 限幅后的值
  */
float limit_value(float value, float low, float high)
{
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

/**
  * @brief  PI 控制器（含积分饱和抑制）
  * @param  pi  控制器参数
  * @param  ref 给定值
  * @param  fbk 反馈值
  * @retval 控制器输出
  */
static float pi_calculate(volatile PI_CTRL_DATA_DEF *pi, float ref, float fbk,
                          float kp, float ki, float kd)
{
    float error = ref - fbk;
    float derivative = kd * (error - pi->up);

    pi->temp_p = kp * error + derivative;

    /* 
    积分限幅／积分抗饱和：可以避免积分项在输出受限时还不断累积，导致退出饱和后恢复迟缓
    */
    if (ki == 0.0f)
    {
        pi->ui = 0.0f;
    }
    /*
    输出已经达到上限，且误差为正（还想继续增大输出）：暂停积分。
    输出已经达到下限，且误差为负（还想继续减小输出）：暂停积分。
    其他情况：执行 ui += ki * error
    */
    else if (!((pi->temp_p + pi->ui >= pi->Umax && error > 0.0f) ||
               (pi->temp_p + pi->ui <= pi->Umin && error < 0.0f)))
    {
        pi->ui = limit_value(pi->ui + ki * error, pi->Umin, pi->Umax);
    }

    pi->Out = limit_value(pi->temp_p + pi->ui, pi->Umin, pi->Umax);////
    pi->up = error;
    return pi->Out;
}

/* 原电流环、双闭环保持原单位：Ki已经包含控制周期。 */
float pi_func(volatile PI_CTRL_DATA_DEF *pi, float ref, float fbk)
{
    return pi_calculate(pi, ref, fbk, pi->Kp, pi->Ki, pi->Kd);
}

/* 单电压环、v1.1.0单电流环共用。Kp/Ki保留人工输入单位。 */
float pi_func_percent(volatile PI_CTRL_DATA_DEF *pi, float ref, float fbk,
                      float arr, float sample_period_s)
{
    float counts_per_percent = arr / 100.0f;
    return pi_calculate(pi, ref, fbk,
                        pi->Kp * counts_per_percent,
                        pi->Ki * counts_per_percent * sample_period_s,
                        pi->Kd * counts_per_percent);
}
