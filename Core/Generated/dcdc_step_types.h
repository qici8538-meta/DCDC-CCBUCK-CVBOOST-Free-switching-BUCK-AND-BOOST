/*
 * File: dcdc_step_types.h
 *
 * MATLAB Coder version            : 23.2
 * C/C++ source code generated on  : 01-Nov-2026 00:06:18
 */

#ifndef DCDC_STEP_TYPES_H
#define DCDC_STEP_TYPES_H

/* Include Files */
#include "rtwtypes.h"

/* Type Definitions */
#ifndef typedef_DcdcState
#define typedef_DcdcState
typedef struct {
  unsigned char mode;
  unsigned char fault;
  float current_integral;
  float voltage_integral;
  float current_reference;
  float voltage_reference;
  float previous_current;
} DcdcState;
#endif /* typedef_DcdcState */

#ifndef typedef_DcdcParams
#define typedef_DcdcParams
typedef struct {
  float sample_time;
  float current_kp;
  float current_ki;
  float voltage_kp;
  float voltage_ki;
  float current_slew;
  float voltage_slew;
  float charge_limit;
  float discharge_limit;
  float overcurrent;
  float overcharge;
  float overcharge_release;
  float battery_min;
  float battery_max;
  float bus_max;
  float duty_min;
  float duty_max;
  float current_lead_time;
  float current_ff_inductance;
} DcdcParams;
#endif /* typedef_DcdcParams */

#endif
/*
 * File trailer for dcdc_step_types.h
 *
 * [EOF]
 */
