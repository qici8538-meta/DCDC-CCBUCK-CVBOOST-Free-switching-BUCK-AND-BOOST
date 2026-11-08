/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    gpio.c
  * @brief   This file provides code for the configuration
  *          of all used GPIO pins.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "gpio.h"

/* USER CODE BEGIN 0 */

#define KEY_DEBOUNCE_MS 20U
static GPIO_PinState key_last_sample;
static GPIO_PinState key_stable_state;
static uint32_t key_changed_at;
static uint32_t key_pressed_at;
static uint8_t key_ready;
static uint8_t key_long_sent;

/* USER CODE END 0 */

/*----------------------------------------------------------------------------*/
/* Configure GPIO                                                             */
/*----------------------------------------------------------------------------*/
/* USER CODE BEGIN 1 */

/* USER CODE END 1 */

/** Configure pins as
        * Analog
        * Input
        * Output
        * EVENT_OUT
        * EXTI
*/
void MX_GPIO_Init(void)
{

  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOF_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOD_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(PWM_EN_GPIO_Port, PWM_EN_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOD, LCD_CS_Pin|LCD_DC_Pin, GPIO_PIN_SET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(LCD_BL_GPIO_Port, LCD_BL_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin : PWM_EN_Pin */
  GPIO_InitStruct.Pin = PWM_EN_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(PWM_EN_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : LCD_CS_Pin LCD_DC_Pin LCD_BL_Pin */
  GPIO_InitStruct.Pin = LCD_CS_Pin|LCD_DC_Pin|LCD_BL_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
  HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);

  /*Configure GPIO pin : Key_Pin */
  GPIO_InitStruct.Pin = Key_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(Key_GPIO_Port, &GPIO_InitStruct);

}

/* USER CODE BEGIN 2 */

/* GPIO初始化后调用。复位时按住按键不换档，先稳定松开才接受下一次按下。 */
void AppKey_Init(void)
{
  key_last_sample = HAL_GPIO_ReadPin(Key_GPIO_Port, Key_Pin);
  key_stable_state = GPIO_PIN_RESET;
  key_changed_at = HAL_GetTick();
  key_pressed_at = key_changed_at;
  key_ready = 0U;
  key_long_sent = 1U;
}

/* 主循环持续轮询：按下/松开均需稳定20ms；长按不连发，不使用HAL_Delay。 */
uint8_t AppKey_PollEvent(void)
{
  GPIO_PinState sample = HAL_GPIO_ReadPin(Key_GPIO_Port, Key_Pin);
  uint32_t now = HAL_GetTick();

  if (sample != key_last_sample)
  {
    key_last_sample = sample;
    key_changed_at = now;
  }
  else if ((sample != key_stable_state) &&
           ((uint32_t)(now - key_changed_at) >= KEY_DEBOUNCE_MS))
  {
    key_stable_state = sample;
    if (sample == GPIO_PIN_RESET)
    {
      key_pressed_at = now;
      key_long_sent = 0U;
    }
    else
    {
      uint8_t short_press = (key_ready && !key_long_sent) ? 1U : 0U;
      key_ready = 1U;
      return short_press;
    }
  }
  if (key_ready && (key_stable_state == GPIO_PIN_RESET) && !key_long_sent &&
      ((uint32_t)(now - key_pressed_at) >= 800U))
  {
    key_long_sent = 1U;
    return 2U;
  }
  return 0U;
}

/* USER CODE END 2 */
