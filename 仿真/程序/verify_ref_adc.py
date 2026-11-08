"""Compile the real app_adc.c with host HAL stubs; no board connection."""
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
FW=ROOT/"BUCKG474VET6_2"
LCC=Path(r"D:\MATLAB\R2023b\sys\lcc64\lcc64")
C=r'''
#include <stdint.h>
#include <assert.h>
#include <stdio.h>
#define __MAIN_H
#define __ADC_H__
#define __ALIGNED(n)
#define ADC1 ((void*)1)
#define ADC_SINGLE_ENDED 0
#define HAL_OK 0
#define DMA_IT_HT 1
#define __HAL_DMA_DISABLE_IT(h,i) ((void)0)
typedef struct { void *Instance; } ADC_HandleTypeDef;
ADC_HandleTypeDef hadc1={ADC1};
int hdma_adc1;
static unsigned dma_length;
static void Error_Handler(void) { assert(0); }
static void MX_ADC1_Init(void) {}
static void HAL_Delay(unsigned n) { (void)n; }
static int HAL_ADCEx_Calibration_Start(ADC_HandleTypeDef *h,int mode) { (void)h;(void)mode;return 0; }
static int HAL_ADC_Start_DMA(ADC_HandleTypeDef *h,uint32_t *p,unsigned n) { (void)h;(void)p;dma_length=n;return 0; }
static unsigned __get_PRIMASK(void) { return 0; }
static void __disable_irq(void) {}
static void __set_PRIMASK(unsigned n) { (void)n; }
#include "app_adc.c"
static void frame(unsigned i,unsigned ref,unsigned bat,unsigned bus) {
    adc_dma_buffer[0]=(uint16_t)i; adc_dma_buffer[1]=(uint16_t)ref;
    adc_dma_buffer[2]=(uint16_t)bat; adc_dma_buffer[3]=(uint16_t)bus;
    BuckAdc_ConversionComplete(&hadc1);
}
static float absolute(float x) { return x<0?-x:x; }
int main(void) {
    BuckFeedback value;
    float first,expected;
    BuckAdc_Start(); assert(dma_length==4 && adc_feedback.frame_count==0);
    frame(2068,2068,1655,2482);
    assert(adc_feedback.raw[0]==2068 && adc_feedback.raw[1]==1655);
    assert(adc_feedback.raw[2]==2482 && adc_feedback.raw[3]==2068);
    assert(absolute(adc_feedback.current_unfiltered)<1e-6f);
    assert(absolute(adc_feedback.reference_voltage-2068*3.3f/4095)<1e-6f);
    frame(2684,2068,1655,2482);
    first=adc_feedback.current_unfiltered;
    expected=616*3.3f/4095*2.017f;
    assert(absolute(first-expected)<1e-6f);
    frame(2734,2118,1655,2482);
    assert(absolute(adc_feedback.current_unfiltered-first)<1e-6f);
    frame(1452,2068,1655,2482);
    assert(absolute(adc_feedback.current_unfiltered+expected)<1e-6f);
    BuckAdc_ReadFeedback(&value); assert(value.frame_count==4 && value.raw[3]==2068);
    BuckAdc_ConversionError(&hadc1); assert(adc_error_count==1);
    puts("LIVE_REF_ADC_NATIVE_OK: 4-rank mapping, zero, gain, charge/discharge, REF drift, snapshot.");
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix="dcdc_adc_test_") as temporary:
    work=Path(temporary)
    (work/"test.c").write_text(C,encoding="ascii")
    commands=[
        [str(LCC/"bin/lcc64.exe"),"-c","-noregistrylookup",f"-I{LCC/'include64'}",
         f"-I{FW/'Core/Inc'}",f"-I{FW/'Core/Src'}","-Fotest.obj","test.c"],
        [str(LCC/"bin/lcclnk64.exe"),f"-L{LCC/'lib64'}","-o","test.exe","test.obj"],
        [str(work/"test.exe")]]
    for command in commands:
        subprocess.run(command,cwd=work,check=True)

