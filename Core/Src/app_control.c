/**
  ******************************************************************************
  * @file    app_control.c
  * @brief   Buck 变换器双闭环控制模块
  *
  *          采用 CubeMX 生成的 HAL 句柄驱动：
  *            htim1 / hadc1 / PWM_EN(PB0) / PWM_IN(PA8)
  ******************************************************************************
  */

/* Includes ------------------------------------------------------------------*/
#include "app_control.h"
#include "tim.h"

/* Private define ------------------------------------------------------------*/
/* 唯一模式选择：0=单电流环，1=电压外环+电流内环，2=开环，3=单电压环。
   断VIN后修改，Keil重新编译、下载并复位；不再通过RAM变量切换模式。 */
#define BUCK_CONTROL_MODE 3U
#if (BUCK_CONTROL_MODE != 0U) && (BUCK_CONTROL_MODE != 1U) && \
    (BUCK_CONTROL_MODE != 2U) && (BUCK_CONTROL_MODE != 3U)
#error "BUCK_CONTROL_MODE must be 0, 1, 2 or 3"
#endif
/* MANUAL_TARGET: 上电目标(V)，与模式无关；运行时仍可写 voltage_reference。 */
#define MANUAL_TARGET_VOLTAGE BUCK_VOLTAGE_TARGET_MIN_V /* 每次复位恢复2V。 */
/* 单电压环每个完整PWM周期控制一次；修改PWM频率时同步更新。 */
#define VOLTAGE_CONTROL_PERIOD_S 0.00005f

/* Private variables ---------------------------------------------------------*/
volatile PI_CTRL_DATA_DEF voltage_pi;
volatile PI_CTRL_DATA_DEF current_pi;
volatile PI_CTRL_DATA_DEF voltage_only_pi;
volatile float voltage_reference;////
volatile float current_reference;
volatile float current_limit;
volatile float pwm_limit;
volatile float buck_duty;
volatile float openloop_command;

volatile uint8_t power_output_enabled; /* 仅反映实际输出状态，不是人工开关。 */
static uint8_t control_fault_latched; /* 自动故障记忆，不是调试入口。 */
static int8_t voltage_step_direction; /* 端点折返，保证每次按键最多变化1V。 */

/* Private function prototypes -----------------------------------------------*/
static void BuckControl_DisableOutput(void);
static void BuckControl_Stop(void);
static uint8_t BuckControl_VoltageParametersValid(float arr);
static uint8_t BuckControl_Finite(float value);

/* Private functions ---------------------------------------------------------*/

/**
  * @brief  关闭功率级：TIM1 主输出(MOE)关闭 + IR2104 使能 PB0 拉低
  *         （等价于原工程 TIM_CtrlPWMOutputs(TIM1, DISABLE) + PB0 复位）
  */
static void BuckControl_DisableOutput(void)
{
    __HAL_TIM_MOE_DISABLE_UNCONDITIONALLY(&htim1);
    HAL_GPIO_WritePin(PWM_EN_GPIO_Port, PWM_EN_Pin, GPIO_PIN_RESET);
    power_output_enabled = 0U;
}

/* 统一停机：关驱动和主输出，比较值、占空比、各PI积分归零。 */
static void BuckControl_Stop(void)
{
    BuckControl_DisableOutput();
    __HAL_TIM_SET_COMPARE(&htim1, TIM_CHANNEL_1, 0U);
    buck_duty = 0.0f;
    voltage_pi.Out = voltage_pi.ui = voltage_pi.up = 0.0f;
    current_pi.Out = current_pi.ui = current_pi.up = 0.0f;
    voltage_only_pi.Out = voltage_only_pi.ui = voltage_only_pi.up = 0.0f;
}

/* ARMCC fast floating-point mode can assume that NaN does not occur. Check
   IEEE-754 exponent bits so debugger-written NaN/Inf cannot bypass bounds. */
static uint8_t BuckControl_Finite(float value)
{
    union { float value; uint32_t bits; } representation;
    representation.value = value;
    return (representation.bits & 0x7F800000U) != 0x7F800000U;
}

/* Ordinary bounds checks on live parameters; no test commands or result codes. */
static uint8_t BuckControl_VoltageParametersValid(float arr)
{
    return BuckControl_Finite(voltage_reference) &&
           BuckControl_Finite(voltage_only_pi.Kp) && BuckControl_Finite(voltage_only_pi.Ki) &&
           BuckControl_Finite(voltage_only_pi.Kd) && BuckControl_Finite(pwm_limit) &&
           ((voltage_reference == 0.0f) ||
            ((voltage_reference >= BUCK_VOLTAGE_TARGET_MIN_V) &&
             (voltage_reference <= BUCK_VOLTAGE_TARGET_MAX_V))) &&
           (voltage_only_pi.Kp >= 0.0f) && (voltage_only_pi.Kp <= 100.0f) &&
           (voltage_only_pi.Ki >= 0.0f) &&
           (voltage_only_pi.Ki <= 100.0f / VOLTAGE_CONTROL_PERIOD_S) &&
           (voltage_only_pi.Kd == 0.0f) &&
           (pwm_limit > 0.0f) && (pwm_limit <= arr);
}

/* Exported functions --------------------------------------------------------*/

/**
  * @brief  业务参数初始化（对应原工程 BuckControl_ParameterInit）
  * @note   必须在 MX_TIM1_Init() 之后调用：PWM 量程统一取自当前实际 ARR。
  */
void BuckControl_ParameterInit(void)
{
    float arr = (float)__HAL_TIM_GET_AUTORELOAD(&htim1);

    voltage_pi.Kp = 0.43f;
    voltage_pi.Ki = 0.001f;
    voltage_pi.Kd = 0.0f;
    voltage_pi.Umax = 6.0f;            /* 外环输出即电流给定上限 */
    voltage_pi.Umin = 0.0f;
    current_pi.Kp = 1.0f;
    current_pi.Ki = 0.001f;
    current_pi.Kd = 0.0f;
    current_pi.Umax = arr;             /* 原 4199.0f（原 ARR），改为当前实际 ARR */
    current_pi.Umin = 0.0f;
    current_limit = 6.6f;
    pwm_limit = arr;                   /* PWM 比较值上限 = 当前实际 ARR */

    /* 单电压环按占空比百分比调参，不用人工乘ARR。
       Kp=1：每差1V，比例项贡献1个百分点占空比。  0.5-2
       Ki=2：持续差1V，积分每秒增加2个百分点。    10-100 
        */
    voltage_only_pi = (PI_CTRL_DATA_DEF){0};
    voltage_only_pi.Kp = 1.0f;
    voltage_only_pi.Ki = 2.0f;
    voltage_only_pi.Kd = 0.0f;
    voltage_only_pi.Umax = arr;        /* 单电压环也使用完整PWM比较值范围。 */
    voltage_only_pi.Umin = 0.0f;

    openloop_command = 0.3f * arr;    /* MANUAL_DUTY: 5%, then 10% for polarity test. */
    voltage_reference = MANUAL_TARGET_VOLTAGE;
    voltage_step_direction = 1;
    current_reference = 0.0f; /* Mode 0: 0A停PWM，正给定开始。 */

    voltage_pi.Out = 0.0f;
    voltage_pi.ui = 0.0f;
    voltage_pi.up = 0.0f;
    current_pi.Out = 0.0f;
    current_pi.ui = 0.0f;
    current_pi.up = 0.0f;

    /* 输出状态。采样变量由app_adc.c的启动函数负责初始化。 */
    buck_duty = 0.0f;
    power_output_enabled = 0U;
    control_fault_latched = 0U;
}

/* 主循环中每个已消抖的按下事件调用一次。其他模式不响应电压按键。
   2->3->...->9->10->9->...->3->2；端点不跳回，积分也不因换档清零。 */
void BuckControl_KeyPressed(void)
{
    float target;

    if (BUCK_CONTROL_MODE != 3U)
        return;

    target = voltage_reference;
    /* 人工写0停机后，按一次从2V重新开始；异常给定也恢复到下限。 */
    if (!BuckControl_Finite(target) || (target < BUCK_VOLTAGE_TARGET_MIN_V) ||
        (target > BUCK_VOLTAGE_TARGET_MAX_V))
    {
        voltage_step_direction = 1;
        voltage_reference = BUCK_VOLTAGE_TARGET_MIN_V;
        return;
    }
    if (target >= BUCK_VOLTAGE_TARGET_MAX_V)
        voltage_step_direction = -1;
    else if (target <= BUCK_VOLTAGE_TARGET_MIN_V)
        voltage_step_direction = 1;

    voltage_reference = limit_value(target + (float)voltage_step_direction *
                                   BUCK_VOLTAGE_TARGET_STEP_V,
                                   BUCK_VOLTAGE_TARGET_MIN_V, BUCK_VOLTAGE_TARGET_MAX_V);
}

/**
  * @brief  启动 ADC DMA / TIM1；模式仅由 BUCK_CONTROL_MODE 选择。
  * @note   只调用一次。开环控制计算不依赖 ADC，PB0 与主输出由控制中断使能。
  */
void BuckControl_Start(void)
{
    BuckControl_Stop();
    /* 先启动ADC DMA，等待TIM1产生触发；采样细节全部在app_adc.c。 */
    BuckAdc_Start();
    __HAL_TIM_SET_COMPARE(&htim1, TIM_CHANNEL_1, 0U);
    if (HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_1) != HAL_OK)
        Error_Handler();
    BuckControl_DisableOutput();
    //允许更新事件产生CPU中断
    __HAL_TIM_ENABLE_IT(&htim1, TIM_IT_UPDATE);
}



void BuckControl_AdcError(ADC_HandleTypeDef *hadc)
{
    BuckAdc_ConversionError(hadc);
    if ((hadc->Instance == ADC1) && (BUCK_CONTROL_MODE != 2U))
        BuckControl_Stop();
}


/**
  * @brief  TIM1 更新中断控制（由 HAL_TIM_PeriodElapsedCallback 调用）
  * @param  htim 定时器句柄
  * @note   TIM1 采用中心对齐模式，一个开关周期内会产生两次更新事件
  *         （CNT=ARR 的峰值处与 CNT=0 的零点处）。这里只在计数方向为
  *         向上（即 CNT=0 的零点事件）时执行控制，保证 PI 与比较值
  *         更新每个完整开关周期只执行一次。
  */
void BuckControl_TimerElapsed(TIM_HandleTypeDef *htim)
{
    float current;
    float voltage;
    float target;
    float command;
    float maximum;
    uint16_t voltage_raw;

    //顶部更新后开始向下计数，这次不算控制；底部更新后开始向上计数，才继续计算。
    if ((htim->Instance != TIM1) || __HAL_TIM_IS_TIM_COUNTING_DOWN(htim))
        return;

    maximum = limit_value(pwm_limit, 0.0f, (float)__HAL_TIM_GET_AUTORELOAD(htim));
    
    // 开环控制模式
    if (BUCK_CONTROL_MODE == 2U)
    {
        /* 原开环比较值逻辑：不读反馈控制PWM。零指令明确关闭驱动。 */
        if (!BuckControl_Finite(openloop_command) || !BuckControl_Finite(pwm_limit) ||
            (openloop_command <= 0.0f) || (maximum <= 0.0f))
        {
            BuckControl_Stop();
            return;
        }
        command = limit_value(openloop_command, 0.0f, maximum);
        voltage_pi.Out = voltage_pi.ui = voltage_pi.up = 0.0f;
        current_pi.Out = current_pi.ui = current_pi.up = 0.0f;
        voltage_only_pi.Out = voltage_only_pi.ui = voltage_only_pi.up = 0.0f;
    }
    else
    {
        /* 1. 还没采到第一帧，或HAL已报ADC错误：不使用空值/故障值闭环。
           帧数和错误数是观测量，不是需要人工置位的通行证。 */
        if ((adc_frame_count == 0U) || (adc_error_count != 0U) ||
            !BuckControl_Finite(pwm_limit) || (maximum <= 0.0f))
        {
            BuckControl_Stop();
            return;
        }

        /* 2. 取同一帧的反馈。ADC换算已完成，这里只复制，不重新算ADC。 */
        BuckAdc_ReadFeedback(&current, &voltage, &voltage_raw);

        /* 3. 控制命令，不属于ADC：给定0就是停机；无需额外启停变量。ADC未饱和时解除故障记忆。
           ADC错误计数不会在这里清除，ADC故障须排查后复位。 */
        if (((BUCK_CONTROL_MODE == 0U) && BuckControl_Finite(current_reference) &&
             (current_reference <= 0.0f)) ||
            ((BUCK_CONTROL_MODE != 0U) && BuckControl_Finite(voltage_reference) &&
             (voltage_reference <= 0.0f)))
        {
            if (voltage_raw < 4090U)
                control_fault_latched = 0U;
            BuckControl_Stop();
            return;
        }

        /* 4. PI参数检查，不属于ADC：防止误写NaN/负增益等异常参数。 */
        if (((BUCK_CONTROL_MODE == 3U) &&
             !BuckControl_VoltageParametersValid((float)__HAL_TIM_GET_AUTORELOAD(htim))) ||
            ((BUCK_CONTROL_MODE == 1U) && !BuckControl_Finite(voltage_reference)) ||
            ((BUCK_CONTROL_MODE == 0U) && !BuckControl_Finite(current_reference)))
        {
            BuckControl_Stop();
            return;
        }

        /* 只保留ADC饱和关断；已取消按输出电压阈值关断的OVP。 */
        if ((voltage_raw >= 4090U) ||
            ((BUCK_CONTROL_MODE != 3U) && (current >= current_limit)))
            control_fault_latched = 1U;
        if (control_fault_latched != 0U)
        {
            BuckControl_Stop();
            return;
        }

        // 单电压环模式
        if (BUCK_CONTROL_MODE == 3U)
        {
            /* 单电压环只使用电压反馈，坏的电流通道不参与控制/保护。 */
            voltage_pi.Out = voltage_pi.ui = voltage_pi.up = 0.0f;
            current_pi.Out = current_pi.ui = current_pi.up = 0.0f;
            voltage_only_pi.Umax = maximum;
            target = voltage_reference;
            command = limit_value(pi_func_percent(&voltage_only_pi, target, voltage,
                                  (float)__HAL_TIM_GET_AUTORELOAD(htim),
                                  VOLTAGE_CONTROL_PERIOD_S), 0.0f, maximum);
        }
        else
        // 电压外环+电流内环模式或单电流环模式
        {
            voltage_only_pi.Out = voltage_only_pi.ui = voltage_only_pi.up = 0.0f;
            // 电压外环模式
            if (BUCK_CONTROL_MODE == 1U)
            {
                target = pi_func(&voltage_pi,
                                 voltage_reference,
                                 voltage);
            }
            else
            // （单）电流环模式
            {
                target = current_reference;
                voltage_pi.Out = voltage_pi.ui = voltage_pi.up = 0.0f;
            }
            //BUCK_CONTROL_MODE 为0/1时，共用的电流内环部分
            target = limit_value(target, 0.0f, current_limit);
            command = limit_value(pi_func(&current_pi, target, current), 0.0f, maximum);
        }
        if ((adc_error_count != 0U) || (adc_frame_count == 0U))
        {
            BuckControl_Stop();
            return;
        }
    }

    buck_duty = command; /* PWM比较计数，不是电压或百分比。 */
    __HAL_TIM_SET_COMPARE(htim, TIM_CHANNEL_1, (uint32_t)command);
    if (power_output_enabled == 0U)
    {
        /* 首拍先把预装载比较值装入，再开启MOE与IR2104。 */
        __HAL_TIM_DISABLE_IT(htim, TIM_IT_UPDATE);
        (void)HAL_TIM_GenerateEvent(htim, TIM_EVENTSOURCE_UPDATE);
        __HAL_TIM_CLEAR_FLAG(htim, TIM_FLAG_UPDATE);
        __HAL_TIM_ENABLE_IT(htim, TIM_IT_UPDATE);
        power_output_enabled = 1U;
    }
    HAL_GPIO_WritePin(PWM_EN_GPIO_Port, PWM_EN_Pin, GPIO_PIN_SET);
    __HAL_TIM_MOE_ENABLE(htim);
}
