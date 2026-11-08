/* Board LCD port: 6.LCD/Core/Src/spi.c, ST7789 240x280, portrait Y offset 20.
 * Keep the vendor panel parameters and ASCII glyph format; omit demo graphics.
 * All drawing runs in main, with control/ADC interrupts enabled.
 */
#include "app_lcd.h"
#include "app_control.h"
#include "spi.h"
#include "lcd_fonts.h"

#define LCD_WIDTH        240U
#define LCD_HEIGHT       280U
#define LCD_Y_OFFSET      20U
#define LCD_REFRESH_MS    50U
#define LCD_TIMEOUT_MS    20U
#define LCD_WHITE     0xFFFFU
#define LCD_CYAN      0x07FFU

static uint8_t lcd_ready;
static int32_t lcd_last_centivolts;
static uint32_t lcd_last_poll;

/* A display bus error disables display updates, without stopping the Buck ISR. */
static void LCD_Send(const uint8_t *data, uint16_t size)
{
  if (lcd_ready && (HAL_SPI_Transmit(&hspi1, (uint8_t *)data, size,
                                    LCD_TIMEOUT_MS) != HAL_OK))
  {
    lcd_ready = 0U;
    HAL_GPIO_WritePin(LCD_BL_GPIO_Port, LCD_BL_Pin, GPIO_PIN_RESET);
  }
}

static void LCD_Command(uint8_t command, const uint8_t *data, uint16_t size)
{
  HAL_GPIO_WritePin(LCD_CS_GPIO_Port, LCD_CS_Pin, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(LCD_DC_GPIO_Port, LCD_DC_Pin, GPIO_PIN_RESET);
  LCD_Send(&command, 1U);
  HAL_GPIO_WritePin(LCD_DC_GPIO_Port, LCD_DC_Pin, GPIO_PIN_SET);
  if (size != 0U)
    LCD_Send(data, size);
  HAL_GPIO_WritePin(LCD_CS_GPIO_Port, LCD_CS_Pin, GPIO_PIN_SET);
}

static void LCD_Window(uint16_t x, uint16_t y, uint16_t width, uint16_t height)
{
  uint16_t end = x + width - 1U;
  uint8_t address[4];
  address[0] = (uint8_t)(x >> 8);
  address[1] = (uint8_t)x;
  address[2] = (uint8_t)(end >> 8);
  address[3] = (uint8_t)end;
  LCD_Command(0x2AU, address, 4U);
  y += LCD_Y_OFFSET;
  end = y + height - 1U;
  address[0] = (uint8_t)(y >> 8);
  address[1] = (uint8_t)y;
  address[2] = (uint8_t)(end >> 8);
  address[3] = (uint8_t)end;
  LCD_Command(0x2BU, address, 4U);
  LCD_Command(0x2CU, 0, 0U);
}

static void LCD_Clear(void)
{
  uint8_t row[LCD_WIDTH * 2U] = {0};
  uint16_t y;
  LCD_Window(0U, 0U, LCD_WIDTH, LCD_HEIGHT);
  HAL_GPIO_WritePin(LCD_CS_GPIO_Port, LCD_CS_Pin, GPIO_PIN_RESET);
  for (y = 0U; (y < LCD_HEIGHT) && lcd_ready; y++)
    LCD_Send(row, sizeof(row));
  HAL_GPIO_WritePin(LCD_CS_GPIO_Port, LCD_CS_Pin, GPIO_PIN_SET);
}

/* Vendor font bytes are row-major, least significant bit first. */
static void LCD_Text(uint16_t x, uint16_t y, const char *text,
                     const LCD_Font *font, uint8_t scale, uint16_t color)
{
  uint8_t row[64]; /* Largest glyph: 16 pixels * scale 2 * RGB565. */
  uint8_t bytes_per_row = (font->width + 7U) / 8U;
  uint8_t cx, cy, repeat, copy;
  uint16_t length, pixel, used;
  const uint8_t *glyph;
  while ((*text != '\0') && lcd_ready)
  {
    uint8_t ch = (uint8_t)*text++;
    if ((ch < 32U) || (ch > 126U)) ch = '?';
    glyph = font->data + (ch - 32U) * bytes_per_row * font->height;
    LCD_Window(x, y, font->width * scale, font->height * scale);
    HAL_GPIO_WritePin(LCD_CS_GPIO_Port, LCD_CS_Pin, GPIO_PIN_RESET);
    length = font->width * scale * 2U;
    for (cy = 0U; (cy < font->height) && lcd_ready; cy++)
    {
      used = 0U;
      for (cx = 0U; cx < font->width; cx++)
      {
        pixel = (glyph[cy * bytes_per_row + cx / 8U] & (1U << (cx % 8U))) ? color : 0U;
        for (copy = 0U; copy < scale; copy++)
        {
          row[used++] = (uint8_t)(pixel >> 8);
          row[used++] = (uint8_t)pixel;
        }
      }
      for (repeat = 0U; (repeat < scale) && lcd_ready; repeat++)
        LCD_Send(row, length);
    }
    HAL_GPIO_WritePin(LCD_CS_GPIO_Port, LCD_CS_Pin, GPIO_PIN_SET);
    x += font->width * scale;
  }
}

void AppLcd_Init(void)
{
  /* Command, byte count, data: unchanged panel voltage/gamma settings. */
  static const uint8_t setup[] = {
    0x36,1,0x00, 0x3A,1,0x05,
    0xB2,5,0x0C,0x0C,0x00,0x33,0x33, 0xB7,1,0x35,
    0xBB,1,0x19, 0xC0,1,0x2C, 0xC2,1,0x01, 0xC3,1,0x12,
    0xC4,1,0x20, 0xC6,1,0x0F, 0xD0,2,0xA4,0xA1,
    0xE0,14,0xD0,0x04,0x0D,0x11,0x13,0x2B,0x3F,0x54,0x4C,0x18,0x0D,0x0B,0x1F,0x23,
    0xE1,14,0xD0,0x04,0x0C,0x11,0x13,0x2C,0x3F,0x44,0x51,0x2F,0x1F,0x1F,0x20,0x23,
    0x21,0
  };
  uint16_t pos = 0U;
  MX_SPI1_Init();
  lcd_ready = 1U;
  lcd_last_centivolts = -2;
  lcd_last_poll = HAL_GetTick() - LCD_REFRESH_MS;
  HAL_Delay(10U);
  /* Unlike the demo, reset the panel also on MCU-only Reset. No LCD reset pin. */
  LCD_Command(0x01U, 0, 0U);
  HAL_Delay(150U);
  while ((pos < sizeof(setup)) && lcd_ready)
  {
    uint8_t command = setup[pos++];
    uint8_t size = setup[pos++];
    LCD_Command(command, &setup[pos], size);
    pos += size;
  }
  LCD_Command(0x11U, 0, 0U);
  HAL_Delay(120U);
  LCD_Clear();
  LCD_Text(64U, 52U, "TARGET VOLTAGE", &LCD_Font16, 1U, LCD_WHITE);
  LCD_Text(40U, 228U, "KEY: 2-10V / 1V STEP", &LCD_Font16, 1U, LCD_WHITE);
  AppLcd_Update();
  LCD_Command(0x29U, 0, 0U);
  if (lcd_ready)
    HAL_GPIO_WritePin(LCD_BL_GPIO_Port, LCD_BL_Pin, GPIO_PIN_SET);
}

void AppLcd_Update(void)
{
  uint32_t now = HAL_GetTick();
  union { float value; uint32_t bits; } target;
  int32_t centivolts = -1;
  char value[8] = "--.-- V";
  if (!lcd_ready || ((uint32_t)(now - lcd_last_poll) < LCD_REFRESH_MS))
    return;
  lcd_last_poll = now;
  target.value = voltage_reference; /* Same target used by the voltage PI. */
  if (((target.bits & 0x7F800000U) != 0x7F800000U) &&
      (target.value >= 0.0f) && (target.value <= BUCK_VOLTAGE_TARGET_MAX_V))
  {
    centivolts = (int32_t)(target.value * 100.0f + 0.5f);
    value[0] = (centivolts >= 1000) ? (char)('0' + centivolts / 1000) : ' ';
    value[1] = (char)('0' + centivolts / 100 % 10);
    value[2] = '.';
    value[3] = (char)('0' + centivolts / 10 % 10);
    value[4] = (char)('0' + centivolts % 10);
  }
  if (centivolts == lcd_last_centivolts)
    return;
  /* Fixed opaque field erases old digits, without clearing/flickering the screen. */
  LCD_Text(8U, 108U, value, &LCD_Font32, 2U, LCD_CYAN);
  if (lcd_ready)
    lcd_last_centivolts = centivolts;
}
