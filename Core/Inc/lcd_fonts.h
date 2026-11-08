#ifndef LCD_FONTS_H
#define LCD_FONTS_H
#include <stdint.h>

typedef struct {
  const uint8_t *data;
  uint8_t width;
  uint8_t height;
} LCD_Font;

extern const LCD_Font LCD_Font16;
extern const LCD_Font LCD_Font32;
#endif
