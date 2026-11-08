/**
  ******************************************************************************
  * @file    app_bluetooth.h
  * @brief   蓝牙串口模块
  ******************************************************************************
  */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __APP_BLUETOOTH_H
#define __APP_BLUETOOTH_H

#ifdef __cplusplus
extern "C" {
#endif

/* HMI disabled: original Bluetooth declarations retained as line comments. */
// /* Includes ------------------------------------------------------------------*/
// #include "main.h"

// /* Exported constants --------------------------------------------------------*/
// #define APP_BLUETOOTH_RX_BUFFER_SIZE    100U   /* 接收帧缓冲，与原工程一致 */
// #define APP_BLUETOOTH_TX_TIMEOUT_MS     200U   /* 阻塞发送超时（ms） */

// /* Exported variables --------------------------------------------------------*/
// extern char AppBluetooth_RxPacket[APP_BLUETOOTH_RX_BUFFER_SIZE];
// extern volatile uint8_t AppBluetooth_RxFlag;

// /* Exported functions prototypes ---------------------------------------------*/
// void AppBluetooth_Init(void);
// void AppBluetooth_RxCplt(UART_HandleTypeDef *huart);
// void AppBluetooth_SendString(const char *string);
// void AppBluetooth_Printf(const char *format, ...);
// void AppBluetooth_Parse(void);
// void AppBluetooth_SendPlot(void);

#ifdef __cplusplus
}
#endif

#endif /* __APP_BLUETOOTH_H */
