function [p, hw] = dcdc_parameters()
% All controller gains use SI units and seconds, never PWM timer counts.
% These initial values are simulation starting points for manual bench tuning.
p = struct('sample_time', single(2 * 4249 / 170e6), ...
    'current_kp', single(0.020), 'current_ki', single(8.0), ...
    'voltage_kp', single(10.0), 'voltage_ki', single(120.0), ...
    'current_slew', single(40000.0), 'voltage_slew', single(100.0), ...
    'charge_limit', single(2.0), 'discharge_limit', single(2.5), ...
    'overcurrent', single(2.8), 'overcharge', single(24.0), ...
    'overcharge_release', single(23.0), 'battery_min', single(15.0), ...
    'battery_max', single(25.0), 'bus_max', single(39.0), ...
    'duty_min', single(0.05), 'duty_max', single(0.95), ...
    'current_lead_time', single(0.000150), 'current_ff_inductance', single(0.000235));
% The C header is the human-owned source of default gains and thresholds.
folder=fileparts(fileparts(mfilename('fullpath')));
settings=fullfile(folder,'..','BUCKG474VET6_2','Core','Inc','control_settings.h');
if isfile(settings)
    content=fileread(settings);
    names=fieldnames(p);
    for k=2:numel(names)
        token=regexp(content,['#define\s+DCDC_' upper(names{k}) '\s+([-+0-9.eE]+)f?'],'tokens','once');
        assert(~isempty(token),'Missing setting: %s',names{k});
        p.(names{k})=single(str2double(token{1}));
    end
end
% VERIFIED from schematic: 470 uH; each port 2 x 220 uF; 10 mOhm shunt;
% INA213 gain 50; REF=5*10/(20+10); voltage channels divide by 15.
hw.L = 470e-6;
hw.Cbat = 440e-6;
hw.Cbus = 440e-6;
hw.shunt = 0.010;
hw.current_gain = 50;
% R23/R24 each fitted with 10 ohm (user confirmed 2026-10-31).
hw.current_gain_factor = 20000 / (20000 + 17 * 10);
hw.current_zero = 5/3;
hw.voltage_ratio = 15;
hw.adc_reference = 3.3;
hw.adc_counts = 4095;
calibration=fileread(fullfile(fileparts(settings),'adc_calibration.h'));
hw.adc_reference=setting(calibration,'ADC_REFERENCE_VOLTAGE');
hw.cal_current_offset=setting(calibration,'ADC_CURRENT_OFFSET_RAW');
hw.cal_current_scale=setting(calibration,'ADC_CURRENT_A_PER_PIN_V');
hw.cal_battery_zero=setting(calibration,'ADC_BATTERY_ZERO_RAW');
hw.cal_bus_zero=setting(calibration,'ADC_BUS_ZERO_RAW');
hw.cal_battery_ratio=setting(calibration,'ADC_BATTERY_RATIO');
hw.cal_bus_ratio=setting(calibration,'ADC_BUS_RATIO');
hw.current_filter_alpha=setting(calibration,'ADC_CURRENT_FILTER_ALPHA');
hw.pwm_arr = 4249;
hw.pwm_frequency = 170e6 / (2 * 4249);
% ESTIMATES, not measured hardware. Sensitivity cases vary these explicitly.
hw.inductor_resistance = 0.15;
hw.mos_resistance = 0.015;
hw.battery_resistance = 0.20;
hw.diode_drop = 0.70;
hw.deadtime = 520e-9;
hw.sensor_bandwidth = 2000;
hw.Ts = double(p.sample_time);
hw.hardware_timing = true; % actual PWM1 phase, ADC ranks, IRQ and CCR preload
end

function value=setting(text,name)
token=regexp(text,['#define\s+' name '\s+([-+0-9.eE]+)f?'],'tokens','once');
assert(~isempty(token),'Missing numeric calibration: %s',name);
value=str2double(token{1});
end
