/*
 * File: dcdc_step.c
 *
 * MATLAB Coder version            : 23.2
 * C/C++ source code generated on  : 01-Nov-2026 00:06:18
 */

/* Include Files */
#include "dcdc_step.h"
#include "dcdc_step_types.h"
#include "rt_nonfinite.h"
#include "rt_nonfinite.h"
#include <math.h>

/* Variable Definitions */
static boolean_T isInitialized_dcdc_step = false;

/* Function Definitions */
/*
 * Positive current charges the battery. duty is the HIGH-SIDE on fraction.
 *  mode: 0 OFF, 1 constant-current charge, 2 bus CV discharge, 3 automatic.
 *  This exact function is converted to C; the firmware does not reimplement PI.
 *  AUTO2 transient revision: branch-current phase lead and partial L*dIref/dt
 *  feedforward. Four online PI gains remain shared by CC/CV/AUTO.
 *  Selected after CC PI/feedforward, CV single/cascade and AUTO hysteresis/
 *  continuous-current comparisons. Alternatives stay in the simulation folder.
 *
 * Arguments    : unsigned char mode
 *                float charge_current
 *                float bus_target
 *                float battery_current
 *                float battery_voltage
 *                float bus_voltage
 *                DcdcState *s
 *                const DcdcParams *p
 *                float *duty
 *                boolean_T *enabled
 * Return Type  : void
 */
void dcdc_step(unsigned char mode, float charge_current, float bus_target,
               float battery_current, float battery_voltage, float bus_voltage,
               DcdcState *s, const DcdcParams *p, float *duty,
               boolean_T *enabled)
{
  float b_increment;
  float b_u0;
  float c_u0;
  float current_error;
  float current_feedback;
  float d_u0;
  float e_u0;
  float f;
  float f1;
  float f_u0;
  float g_u0;
  float h_u0;
  float increment;
  float maximum_charge;
  float previous_reference;
  float requested_current;
  float requested_current_tmp;
  float target;
  float trial_integral;
  float u0;
  float unlimited_duty;
  float unlimited_duty_tmp;
  float voltage_error;
  if (!isInitialized_dcdc_step) {
    dcdc_step_initialize();
  }
  *duty = 0.0F;
  *enabled = false;
  /*  Manual OFF resets controllers. A high battery cannot clear an overcharge.
   */
  if (mode == 0) {
    s->mode = 0U;
    s->current_integral = 0.0F;
    s->voltage_integral = 0.0F;
    s->current_reference = 0.0F;
    s->voltage_reference = bus_voltage;
    s->previous_current = battery_current;
    if ((!rtIsInfF(battery_voltage)) && (!rtIsNaNF(battery_voltage)) &&
        (battery_voltage < p->overcharge_release)) {
      s->fault = 0U;
    }
  } else {
    if (rtIsInfF(charge_current) || rtIsNaNF(charge_current) ||
        (rtIsInfF(bus_target) || rtIsNaNF(bus_target)) ||
        (rtIsInfF(battery_current) || rtIsNaNF(battery_current)) ||
        (rtIsInfF(battery_voltage) || rtIsNaNF(battery_voltage)) ||
        (rtIsInfF(bus_voltage) || rtIsNaNF(bus_voltage)) || (mode > 3) ||
        (!(charge_current >= 1.0F)) || (!(charge_current <= p->charge_limit)) ||
        (!(bus_target >= 20.0F)) || (!(bus_target <= 32.0F)) ||
        (rtIsInfF(p->current_kp) || rtIsNaNF(p->current_kp)) ||
        (!(p->current_kp >= 0.0F)) || (!(p->current_kp <= 0.2F)) ||
        (rtIsInfF(p->current_ki) || rtIsNaNF(p->current_ki)) ||
        (!(p->current_ki >= 0.0F)) || (!(p->current_ki <= 200.0F)) ||
        (rtIsInfF(p->voltage_kp) || rtIsNaNF(p->voltage_kp)) ||
        (!(p->voltage_kp >= 0.0F)) || (!(p->voltage_kp <= 25.0F)) ||
        (rtIsInfF(p->voltage_ki) || rtIsNaNF(p->voltage_ki)) ||
        (!(p->voltage_ki >= 0.0F)) || (!(p->voltage_ki <= 200.0F)) ||
        (rtIsInfF(p->current_lead_time) || rtIsNaNF(p->current_lead_time)) ||
        (!(p->current_lead_time >= 0.0F)) ||
        (!(p->current_lead_time <= 0.001F)) ||
        (rtIsInfF(p->current_ff_inductance) ||
         rtIsNaNF(p->current_ff_inductance)) ||
        (!(p->current_ff_inductance >= 0.0F)) ||
        (!(p->current_ff_inductance <= 0.001F))) {
      s->fault = 6U;
      /*  invalid command / gain */
    } else if ((float)fabs(battery_current) >= p->overcurrent) {
      s->fault = 3U;
    } else if (bus_voltage >= p->bus_max) {
      s->fault = 4U;
    } else if (battery_voltage >= p->battery_max) {
      s->fault = 1U;
    } else if (battery_voltage < p->battery_min) {
      s->fault = 2U;
    } else if ((mode != 2) && (battery_voltage >= p->overcharge)) {
      s->fault = 1U;
      /*  latch: no automatic restart after terminal voltage falls */
    }
    if (s->fault != 0) {
      s->current_reference = 0.0F;
      s->current_integral = 0.0F;
      s->voltage_integral = 0.0F;

      /*  Wait for a precharged bus. MOS body diodes remain physical paths when
       * OFF. */
    } else if ((bus_voltage < battery_voltage - 1.0F) ||
               ((mode == 1) && (bus_voltage < battery_voltage + 0.5F))) {
      s->mode = 0U;
      s->current_reference = 0.0F;
      s->current_integral = 0.0F;
      s->voltage_integral = 0.0F;
    } else {
      if (s->mode != mode) {
        s->mode = mode;
        s->current_integral = 0.0F;
        s->voltage_integral = 0.0F;
        s->current_reference = 0.0F;
        if ((bus_voltage <= bus_target) || rtIsNaNF(bus_target)) {
          s->voltage_reference = bus_voltage;
        } else {
          s->voltage_reference = bus_target;
        }
        s->previous_current = battery_current;
      }
      if (mode == 1) {
        target = charge_current;
      } else {
        increment = p->voltage_slew * p->sample_time;
        u0 = bus_target - s->voltage_reference;
        if ((u0 >= -increment) || rtIsNaNF(-increment)) {
          b_u0 = u0;
        } else {
          b_u0 = -increment;
        }
        if ((b_u0 <= increment) || rtIsNaNF(increment)) {
          f = b_u0;
        } else {
          f = increment;
        }
        s->voltage_reference += f;
        /*  Bus high -> positive battery current; bus low -> negative current.
         */
        voltage_error = bus_voltage - s->voltage_reference;
        maximum_charge = p->charge_limit;
        if (mode == 2) {
          maximum_charge = 0.0F;
          /*  discharge mode never commands charging */
        }
        trial_integral = s->voltage_integral +
                         p->voltage_ki * p->sample_time * voltage_error;
        requested_current_tmp = p->voltage_kp * voltage_error;
        requested_current = requested_current_tmp + trial_integral;
        if (((requested_current <= maximum_charge) || (voltage_error < 0.0F)) &&
            ((requested_current >= -p->discharge_limit) ||
             (voltage_error > 0.0F))) {
          s->voltage_integral = trial_integral;
        }
        e_u0 = requested_current_tmp + s->voltage_integral;
        if ((e_u0 >= -p->discharge_limit) || rtIsNaNF(-p->discharge_limit)) {
          f_u0 = e_u0;
        } else {
          f_u0 = -p->discharge_limit;
        }
        if ((f_u0 <= maximum_charge) || rtIsNaNF(maximum_charge)) {
          target = f_u0;
        } else {
          target = maximum_charge;
        }
      }
      previous_reference = s->current_reference;
      b_increment = p->current_slew * p->sample_time;
      c_u0 = target - s->current_reference;
      if ((c_u0 >= -b_increment) || rtIsNaNF(-b_increment)) {
        d_u0 = c_u0;
      } else {
        d_u0 = -b_increment;
      }
      if ((d_u0 <= b_increment) || rtIsNaNF(b_increment)) {
        f1 = d_u0;
      } else {
        f1 = b_increment;
      }
      s->current_reference += f1;
      /*  R4 senses branch current, with Cbat and the ADC IIR adding phase lag.
       */
      /*  Limited-order phase lead provides damping; it is NOT a measured iL
       * channel. */
      current_feedback =
          battery_current + p->current_lead_time / p->sample_time *
                                (battery_current - s->previous_current);
      s->previous_current = battery_current;
      current_error = s->current_reference - current_feedback;
      /*  From vL=L*di/dt: act on a changing reference before waiting for
       * current error. */
      /*  The effective inductance is deliberately partial, not an exact plant
       * inverse. */
      trial_integral =
          s->current_integral + p->current_ki * p->sample_time * current_error;
      unlimited_duty_tmp =
          (battery_voltage + p->current_ff_inductance *
                                 (s->current_reference - previous_reference) /
                                 p->sample_time) /
              bus_voltage +
          p->current_kp * current_error;
      unlimited_duty = unlimited_duty_tmp + trial_integral;
      if (((unlimited_duty <= p->duty_max) || (current_error < 0.0F)) &&
          ((unlimited_duty >= p->duty_min) || (current_error > 0.0F))) {
        s->current_integral = trial_integral;
      }
      g_u0 = unlimited_duty_tmp + s->current_integral;
      if ((g_u0 >= p->duty_min) || rtIsNaNF(p->duty_min)) {
        h_u0 = g_u0;
      } else {
        h_u0 = p->duty_min;
      }
      if ((h_u0 <= p->duty_max) || rtIsNaNF(p->duty_max)) {
        *duty = h_u0;
      } else {
        *duty = p->duty_max;
      }
      *enabled = true;
    }
  }
}

/*
 * Arguments    : void
 * Return Type  : void
 */
void dcdc_step_initialize(void)
{
  rt_InitInfAndNaN();
  isInitialized_dcdc_step = true;
}

/*
 * Arguments    : void
 * Return Type  : void
 */
void dcdc_step_terminate(void)
{
  isInitialized_dcdc_step = false;
}

/*
 * File trailer for dcdc_step.c
 *
 * [EOF]
 */
