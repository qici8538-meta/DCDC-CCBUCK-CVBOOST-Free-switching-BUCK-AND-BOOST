/* SPI1 LCD interface, ported from the board's 6.LCD reference example. */
#include "spi.h"

SPI_HandleTypeDef hspi1;

void MX_SPI1_Init(void)
{
  hspi1.Instance = SPI1;
  hspi1.Init.Mode = SPI_MODE_MASTER;
  hspi1.Init.Direction = SPI_DIRECTION_2LINES;
  hspi1.Init.DataSize = SPI_DATASIZE_8BIT;
  hspi1.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi1.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi1.Init.NSS = SPI_NSS_SOFT;
  hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_8;
  hspi1.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi1.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi1.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi1.Init.CRCPolynomial = 7;
  hspi1.Init.CRCLength = SPI_CRC_LENGTH_DATASIZE;
  hspi1.Init.NSSPMode = SPI_NSS_PULSE_ENABLE;
  if (HAL_SPI_Init(&hspi1) != HAL_OK)
    Error_Handler();
}

void HAL_SPI_MspInit(SPI_HandleTypeDef *hspi)
{
  GPIO_InitTypeDef config = {0};
  if (hspi->Instance != SPI1)
    return;
  __HAL_RCC_SPI1_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  config.Pin = GPIO_PIN_3 | GPIO_PIN_5;
  config.Mode = GPIO_MODE_AF_PP;
  config.Pull = GPIO_NOPULL;
  config.Speed = GPIO_SPEED_FREQ_HIGH;
  config.Alternate = GPIO_AF5_SPI1;
  HAL_GPIO_Init(GPIOB, &config);
}

void HAL_SPI_MspDeInit(SPI_HandleTypeDef *hspi)
{
  if (hspi->Instance != SPI1)
    return;
  __HAL_RCC_SPI1_CLK_DISABLE();
  HAL_GPIO_DeInit(GPIOB, GPIO_PIN_3 | GPIO_PIN_5);
}
