#ifndef CONTROL_SETTINGS_H
#define CONTROL_SETTINGS_H

/* 人工调参入口。先固定电流环，再调母线电压外环；Ki 均按秒定义。
 * MATLAB dcdc_parameters.m 也读取本文件，仿真和固件共用默认参数。
 * 来源：仿真/00_重点看/方案决策说明.pdf 的所选方案；未选方案不编入固件。
 * 这里只是仿真整定初值；实物标定与限流台架整定仍需完成。 */
#define DCDC_CURRENT_KP          0.020f  /* 高侧占空比(0..1)/A */
#define DCDC_CURRENT_KI          8.0f    /* 高侧占空比/(A*s) */
#define DCDC_VOLTAGE_KP          10.0f   /* A/V，误差=母线电压-目标 */
#define DCDC_VOLTAGE_KI          120.0f  /* A/(V*s) */
#define DCDC_CURRENT_SLEW        40000.0f /* A/s，突变验收用；台架可从100起步 */
#define DCDC_VOLTAGE_SLEW        100.0f  /* V/s，母线给定软启动 */
#define DCDC_CHARGE_LIMIT        2.0f    /* A */
#define DCDC_DISCHARGE_LIMIT     2.5f    /* A，放电取负号 */
#define DCDC_OVERCURRENT         2.8f    /* 电池支路电流软件关断阈值，不是iL峰值 */
#define DCDC_OVERCHARGE          24.0f   /* 题目端口U1阈值，串滑阻试验 */
#define DCDC_OVERCHARGE_RELEASE  23.0f   /* 低于此值且人工停机才解锁 */
#define DCDC_BATTERY_MIN         15.0f
#define DCDC_BATTERY_MAX         25.0f
#define DCDC_BUS_MAX             39.0f
#define DCDC_DUTY_MIN            0.05f   /* 保留自举刷新，禁止0%/100%常开 */
#define DCDC_DUTY_MAX            0.95f
/* 动态补偿，仅编译时配置，不新增在线旋钮。
 * lead约为电池支路R*C与电流滤波延迟之和；不是把实测iBAT冒充iL。
 * 前馈取标称470uH的一半，避免全逆模型对误差/延迟过敏；不代表电感是235uH。 */
#define DCDC_CURRENT_LEAD_TIME       0.000150f /* s */
#define DCDC_CURRENT_FF_INDUCTANCE   0.000235f /* H，参考变化前馈的有效系数 */

#endif
