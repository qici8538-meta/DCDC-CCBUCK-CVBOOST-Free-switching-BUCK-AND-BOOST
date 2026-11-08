function [duty,enabled,s]=candidate_step(mode,charge,bus_target,ibat,vbat,vbus,s,p,choice)
% Simulation-only alternatives. No experiment selector is put in firmware.
% dcdc_step supplies the SAME OFF/startup/fault/voltage-ramp rules to all.
old=s;
if strcmp(choice.kind,'hysteresis') && mode==uint8(3)
    if s.hysteresis_mode==uint8(0)
        s.hysteresis_mode=uint8(2);
    end
    if vbus>bus_target+choice.band
        s.hysteresis_mode=uint8(1);
    elseif vbus<bus_target-choice.band
        s.hysteresis_mode=uint8(2);
    end
    mode=s.hysteresis_mode;
    charge=single(1); % minimum specified CC setting, limits burst amplitude
end
[duty,enabled,s]=dcdc_step(mode,charge,bus_target,ibat,vbat,vbus,s,p);
if ~enabled, return; end
entered=old.mode~=mode;
if strcmp(choice.kind,'current_pi')
    if entered, s.fixed_working_point=vbat/vbus; end
    current_feedback=ibat+p.current_lead_time/p.sample_time*(ibat-old.previous_current);
    if entered,current_feedback=ibat;end
    error=s.current_reference-current_feedback;
    integral=old.current_integral;
    if entered, integral=single(0); end
    trial=integral+p.current_ki*p.sample_time*error;
    unlimited=s.fixed_working_point+p.current_kp*error+trial;
    if (unlimited<=p.duty_max || error<0) && (unlimited>=p.duty_min || error>0)
        integral=trial;
    end
    s.current_integral=integral;
    duty=clamp(s.fixed_working_point+p.current_kp*error+integral,p.duty_min,p.duty_max);
elseif strcmp(choice.kind,'voltage_pi') && mode~=uint8(1)
    % Direct voltage PI drives duty. Proportional current takeover only when
    % outside the current envelope; the identical hard trip remains active.
    error=vbus-s.voltage_reference;
    integral=old.voltage_integral;
    if entered, integral=single(0); end
    feedforward=vbat/vbus;
    trial=integral+choice.voltage_ki*p.sample_time*error;
    proposed=feedforward+choice.voltage_kp*error+trial;
    limited=clamp(proposed,p.duty_min,p.duty_max);
    maximum_charge=p.charge_limit;
    if mode==uint8(2), maximum_charge=single(0); end
    if ibat < -p.discharge_limit
        limited=max(limited,feedforward+p.current_kp*(-p.discharge_limit-ibat));
    elseif ibat > maximum_charge
        limited=min(limited,feedforward+p.current_kp*(maximum_charge-ibat));
    end
    limited=clamp(limited,p.duty_min,p.duty_max);
    if abs(limited-proposed)<single(1e-6) || ...
            (proposed>limited && error<0) || (proposed<limited && error>0)
        integral=trial;
    end
    s.voltage_integral=integral;
    s.current_integral=single(0);
    s.current_reference=single(0); % direct loop has no current reference
    duty=limited;
end
end

function y=clamp(x,low,high)
y=min(max(x,low),high);
end
