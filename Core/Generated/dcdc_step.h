/*
 * File: dcdc_step.h
 *
 * MATLAB Coder version            : 23.2
 * C/C++ source code generated on  : 01-Nov-2026 00:06:18
 */

#ifndef DCDC_STEP_H
#define DCDC_STEP_H

/* Include Files */
#include "dcdc_step_types.h"
#include "rtwtypes.h"
#include <stddef.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Function Declarations */
extern void dcdc_step(unsigned char mode, float charge_current,
                      float bus_target, float battery_current,
                      float battery_voltage, float bus_voltage, DcdcState *s,
                      const DcdcParams *p, float *duty, boolean_T *enabled);

extern void dcdc_step_initialize(void);

extern void dcdc_step_terminate(void);

#ifdef __cplusplus
}
#endif

#endif
/*
 * File trailer for dcdc_step.h
 *
 * [EOF]
 */
