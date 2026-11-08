function [duty, enabled, s] = dcdc_step(mode, charge_current, bus_target, ...
    battery_current, battery_voltage, bus_voltage, s, p)
%#codegen
% Positive current charges the battery. duty is the HIGH-SIDE on fraction.
% mode: 0 OFF, 1 constant-current charge, 2 bus CV discharge, 3 automatic.
% This exact function is converted to C; the firmware does not reimplement PI.
% AUTO2 transient revision: branch-current phase lead and partial L*dIref/dt
% feedforward. Four online PI gains remain shared by CC/CV/AUTO.
% Selected after CC PI/feedforward, CV single/cascade and AUTO hysteresis/
% continuous-current comparisons. Alternatives stay in the simulation folder.
coder.cstructname(s, 'DcdcState');
coder.cstructname(p, 'DcdcParams');
duty = single(0);
enabled = false;

% Manual OFF resets controllers. A high battery cannot clear an overcharge.
if mode == uint8(0)
    s.mode = uint8(0);
    s.current_integral = single(0);
    s.voltage_integral = single(0);
    s.current_reference = single(0);
    s.voltage_reference = bus_voltage;
    s.previous_current = battery_current;
    if isfinite(battery_voltage) && battery_voltage < p.overcharge_release
        s.fault = uint8(0);
    end
    return
end

if ~isfinite(charge_current) || ~isfinite(bus_target) || ...
        ~isfinite(battery_current) || ~isfinite(battery_voltage) || ...
        ~isfinite(bus_voltage) || mode > uint8(3) || ...
        ~(charge_current >= single(1) && charge_current <= p.charge_limit) || ...
        ~(bus_target >= single(20) && bus_target <= single(32)) || ...
        ~(isfinite(p.current_kp) && p.current_kp >= single(0) && p.current_kp <= single(0.2)) || ...
        ~(isfinite(p.current_ki) && p.current_ki >= single(0) && p.current_ki <= single(200)) || ...
        ~(isfinite(p.voltage_kp) && p.voltage_kp >= single(0) && p.voltage_kp <= single(25)) || ...
        ~(isfinite(p.voltage_ki) && p.voltage_ki >= single(0) && p.voltage_ki <= single(200)) || ...
        ~(isfinite(p.current_lead_time) && p.current_lead_time >= single(0) && p.current_lead_time <= single(.001)) || ...
        ~(isfinite(p.current_ff_inductance) && p.current_ff_inductance >= single(0) && p.current_ff_inductance <= single(.001))
    s.fault = uint8(6); % invalid command / gain
elseif abs(battery_current) >= p.overcurrent
    s.fault = uint8(3);
elseif bus_voltage >= p.bus_max
    s.fault = uint8(4);
elseif battery_voltage >= p.battery_max
    s.fault = uint8(1);
elseif battery_voltage < p.battery_min
    s.fault = uint8(2);
elseif mode ~= uint8(2) && battery_voltage >= p.overcharge
    s.fault = uint8(1); % latch: no automatic restart after terminal voltage falls
end
if s.fault ~= uint8(0)
    s.current_reference = single(0);
    s.current_integral = single(0);
    s.voltage_integral = single(0);
    return
end

% Wait for a precharged bus. MOS body diodes remain physical paths when OFF.
if bus_voltage < battery_voltage - single(1) || ...
        (mode == uint8(1) && bus_voltage < battery_voltage + single(0.5))
    s.mode = uint8(0);
    s.current_reference = single(0);
    s.current_integral = single(0);
    s.voltage_integral = single(0);
    return
end
if s.mode ~= mode
    s.mode = mode;
    s.current_integral = single(0);
    s.voltage_integral = single(0);
    s.current_reference = single(0);
    s.voltage_reference = min(bus_voltage, bus_target);
    s.previous_current = battery_current;
end

if mode == uint8(1)
    requested_current = charge_current;
else
    s.voltage_reference = ramp(s.voltage_reference, bus_target, p.voltage_slew * p.sample_time);
    % Bus high -> positive battery current; bus low -> negative current.
    voltage_error = bus_voltage - s.voltage_reference;
    maximum_charge = p.charge_limit;
    if mode == uint8(2)
        maximum_charge = single(0); % discharge mode never commands charging
    end
    trial_integral = s.voltage_integral + p.voltage_ki * p.sample_time * voltage_error;
    requested_current = p.voltage_kp * voltage_error + trial_integral;
    if (requested_current <= maximum_charge || voltage_error < single(0)) && ...
            (requested_current >= -p.discharge_limit || voltage_error > single(0))
        s.voltage_integral = trial_integral;
    end
    requested_current = clamp(p.voltage_kp * voltage_error + s.voltage_integral, ...
        -p.discharge_limit, maximum_charge);
end
previous_reference = s.current_reference;
s.current_reference = ramp(s.current_reference, requested_current, p.current_slew * p.sample_time);
% R4 senses branch current, with Cbat and the ADC IIR adding phase lag.
% Limited-order phase lead provides damping; it is NOT a measured iL channel.
current_feedback = battery_current + p.current_lead_time / p.sample_time * ...
    (battery_current - s.previous_current);
s.previous_current = battery_current;
current_error = s.current_reference - current_feedback;
% From vL=L*di/dt: act on a changing reference before waiting for current error.
% The effective inductance is deliberately partial, not an exact plant inverse.
feedforward = (battery_voltage + p.current_ff_inductance * ...
    (s.current_reference-previous_reference) / p.sample_time) / bus_voltage;
trial_integral = s.current_integral + p.current_ki * p.sample_time * current_error;
unlimited_duty = feedforward + p.current_kp * current_error + trial_integral;
if (unlimited_duty <= p.duty_max || current_error < single(0)) && ...
        (unlimited_duty >= p.duty_min || current_error > single(0))
    s.current_integral = trial_integral;
end
duty = clamp(feedforward + p.current_kp * current_error + s.current_integral, p.duty_min, p.duty_max);
enabled = true;
end

function y = clamp(x, low, high)
y = min(max(x, low), high);
end

function y = ramp(previous, target, increment)
y = previous + clamp(target - previous, -increment, increment);
end
