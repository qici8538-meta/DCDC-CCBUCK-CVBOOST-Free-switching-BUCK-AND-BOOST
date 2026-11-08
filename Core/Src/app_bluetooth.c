/**
  ******************************************************************************
  * @file    app_bluetooth.c
  * @brief   蓝牙串口模块
  *
  *          协议保持不变：
  *            接收：[slider,VoltageKp,0.43]
  *            发送：[plot,电压,电流,电压给定,电流给定,控制量]
  *
  *          底层收发全部使用 CubeMX 生成的 huart2：
  *            - 接收：HAL_UART_Receive_IT() 单字节中断接收，在
  *                    HAL_UART_RxCpltCallback() 中组帧后重新武装接收；
  *            - 发送：主循环中调用 HAL_UART_Transmit() 阻塞发送。
  *          发送与解析都不在 TIM1 控制中断中执行。
  ******************************************************************************
  */

/* HMI disabled: original Bluetooth implementation retained as line comments. */
// /* Includes ------------------------------------------------------------------*/
// #include "app_bluetooth.h"
// #include "app_control.h"
// #include "usart.h"
// #include <string.h>
// #include <stdlib.h>
// #include <stdio.h>
// #include <stdarg.h>

// /* Private variables ---------------------------------------------------------*/
// char AppBluetooth_RxPacket[APP_BLUETOOTH_RX_BUFFER_SIZE];
// volatile uint8_t AppBluetooth_RxFlag;

// /* HAL_UART_Receive_IT 的单字节接收缓存 */
// static uint8_t AppBluetooth_RxByte;

// /* Exported functions --------------------------------------------------------*/

// /**
//   * @brief  初始化蓝牙串口接收（启动单字节中断接收）
//   */
// void AppBluetooth_Init(void)
// {
//     AppBluetooth_RxFlag = 0U;
//     (void)HAL_UART_Receive_IT(&huart2, &AppBluetooth_RxByte, 1U);
// }

// /**
//   * @brief  接收完成回调（由 HAL_UART_RxCpltCallback 调用）
//   * @param  huart 串口句柄
//   * @note   与原工程 USART2_IRQHandler 中的组帧状态机一致：
//   *         收到 '[' 开始记录，收到 ']' 结束并置标志，超长则丢弃本帧。
//   */
// void AppBluetooth_RxCplt(UART_HandleTypeDef *huart)
// {
//     static uint8_t state;
//     static uint8_t position;
//     uint8_t data;

//     if (huart->Instance != USART2)
//     {
//         return;
//     }

//     data = AppBluetooth_RxByte;

//     if (state == 0U)
//     {
//         if ((data == (uint8_t)'[') && (AppBluetooth_RxFlag == 0U))
//         {
//             state = 1U;
//             position = 0U;
//         }
//     }
//     else if (data == (uint8_t)']')
//     {
//         state = 0U;
//         AppBluetooth_RxPacket[position] = '\0';
//         AppBluetooth_RxFlag = 1U;
//     }
//     else if (position < (uint8_t)(APP_BLUETOOTH_RX_BUFFER_SIZE - 1U))
//     {
//         AppBluetooth_RxPacket[position] = (char)data;
//         position++;
//     }
//     else
//     {
//         state = 0U;
//         position = 0U;
//     }

//     /* 重新武装接收，等待下一个字节 */
//     (void)HAL_UART_Receive_IT(huart, &AppBluetooth_RxByte, 1U);
// }

// /**
//   * @brief  发送字符串（阻塞式，禁止在中断中调用）
//   * @param  string 待发送的以 '\0' 结尾的字符串
//   */
// void AppBluetooth_SendString(const char *string)
// {
//     uint16_t length = (uint16_t)strlen(string);

//     if (length > 0U)
//     {
//         (void)HAL_UART_Transmit(&huart2, (uint8_t *)string, length, APP_BLUETOOTH_TX_TIMEOUT_MS);
//     }
// }

// /**
//   * @brief  格式化发送（阻塞式，禁止在中断中调用）
//   * @param  format 格式化字符串
//   */
// void AppBluetooth_Printf(const char *format, ...)
// {
//     char string[APP_BLUETOOTH_RX_BUFFER_SIZE];
//     va_list arguments;
//     int length;

//     va_start(arguments, format);
//     length = vsnprintf(string, sizeof(string), format, arguments);
//     va_end(arguments);

//     if (length > 0)
//     {
//         uint16_t tx_length = (uint16_t)length;

//         if (tx_length > (uint16_t)(sizeof(string) - 1U))
//         {
//             tx_length = (uint16_t)(sizeof(string) - 1U);
//         }
//         (void)HAL_UART_Transmit(&huart2, (uint8_t *)string, tx_length, APP_BLUETOOTH_TX_TIMEOUT_MS);
//     }
// }

// /**
//   * @brief  解析蓝牙滑杆命令并修改控制参数（对应原工程 BuckControl_ParseBluetooth）
//   * @note   在主循环中调用，不在中断中执行。
//   */
// void AppBluetooth_Parse(void)
// {
//     char *tag;
//     char *name;
//     char *value;

//     if (AppBluetooth_RxFlag == 0U)
//     {
//         return;
//     }

//     tag = strtok(AppBluetooth_RxPacket, ",");
//     if ((tag != NULL) && (strcmp(tag, "slider") == 0))
//     {
//         name = strtok(NULL, ",");
//         value = strtok(NULL, ",");
//         if ((name != NULL) && (value != NULL))
//         {
//             if (strcmp(name, "VoltageKp") == 0)      voltage_pi.Kp = (float)atof(value);
//             else if (strcmp(name, "VoltageKi") == 0) voltage_pi.Ki = (float)atof(value);
//             else if (strcmp(name, "VoltageKd") == 0) voltage_pi.Kd = (float)atof(value);
//             else if (strcmp(name, "CurrentKp") == 0) current_pi.Kp = (float)atof(value);
//             else if (strcmp(name, "CurrentKi") == 0) current_pi.Ki = (float)atof(value);
//             else if (strcmp(name, "CurrentKd") == 0) current_pi.Kd = (float)atof(value);
//             else if (strcmp(name, "VoltageOnlyKp") == 0) voltage_only_pi.Kp = (float)atof(value);
//             else if (strcmp(name, "VoltageOnlyKi") == 0) voltage_only_pi.Ki = (float)atof(value);
//             else if (strcmp(name, "VoltageOnlyKd") == 0) voltage_only_pi.Kd = (float)atof(value);
//             else if (strcmp(name, "VoltageRef") == 0) voltage_reference = (float)atof(value);
//             else if (strcmp(name, "CurrentRef") == 0) current_reference = (float)atof(value);
//             else if (strcmp(name, "Duty") == 0)       openloop_command = (float)atof(value);
//         }
//     }

//     AppBluetooth_RxFlag = 0U;
// }

// /**
//   * @brief  周期性发送遥测绘图数据（对应原工程 BuckControl_SendPlot）
//   * @note   每 20 次主循环发送一帧，在主循环中调用。
//   */
// void AppBluetooth_SendPlot(void)
// {
//     static uint16_t count;

//     count++;
//     if (count >= 20U)
//     {
//         count = 0U;
//         AppBluetooth_Printf("[plot,%f,%f,%f,%f,%f]", buck_voltage, buck_current,
//                             voltage_reference, current_reference, buck_duty);
//     }
// }
