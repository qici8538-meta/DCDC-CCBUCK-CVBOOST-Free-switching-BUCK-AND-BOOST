function r = simulate_case(c, p, hw)
% Sampled controller + RLC power circuit. Average and explicit switch models.
% R4 measures the battery BRANCH current, not instantaneous inductor current.
hardware_timing=isfield(hw,'hardware_timing') && hw.hardware_timing;
if isfield(c,'hardware_timing'),hardware_timing=c.hardware_timing;end
if hardware_timing
    r=simulate_hardware_case(c,p,hw);return
end
n = ceil(c.duration / hw.Ts);
r.t = (0:n-1)' * hw.Ts;
r.data = zeros(n, 11);
s = dcdc_initial_state();
controller = @dcdc_step;
if isfield(c,'controller'), controller=c.controller; end
if isfield(c,'controller_state'), s=c.controller_state; end
r.controller_mode=zeros(n,1,'uint8');
x = [0; c.battery; c.initial_bus]; % iL, battery-side capacitor, bus capacitor
duty = 0;
enabled = false;
filtered_current = 0;
alpha = 1-(1-hw.current_filter_alpha)^2; % two ADC frames per control update
r.inductor_peak_A=0;
r.bus_min_V=Inf; r.bus_max_V=-Inf;
measure_start=0;
if isfield(c,'measure_start_s'), measure_start=c.measure_start_s; end
r.tail_bus_energy_J=0; r.tail_battery_energy_J=0; r.tail_interval_s=0;
if c.switched
    substeps = 100;
else
    substeps = 10;
end

dt = hw.Ts / substeps;
r.fast = zeros(0,6);
tail_start=max(1,n-ceil(0.005/hw.Ts));
if c.switched, fast=zeros((n-tail_start+1)*(substeps+10),6); else, fast=zeros(0,6); end
fast_index=0;
for k = 1:n
    t = r.t(k);
    [mode, charge_command, ideal_bus, source, rb, load_value] = commands(t,c,hw);
    if isfield(c,'source_steps')
        index=find(c.source_steps(:,1)<=t+1e-12,1,'last');
        source=c.source_steps(index,2);
    end
    ibat = (x(2) - c.battery) / (rb + hw.shunt);
    vbat = x(2) - hw.shunt * ibat;
    % Sensor bandwidth is represented by the firmware feedback IIR. Quantize
    % true terminal signals using the schematic gain and a 12-bit ADC.
    current_pin = hw.current_zero + hw.shunt*hw.current_gain*hw.current_gain_factor*ibat;
    current_raw = round(min(max(current_pin/hw.adc_reference,0),1)*hw.adc_counts);
    reference_raw = round(hw.current_zero/hw.adc_reference*hw.adc_counts);
    measured_current = (current_raw-reference_raw-hw.cal_current_offset)*hw.adc_reference/hw.adc_counts*hw.cal_current_scale;
    filtered_current = filtered_current + alpha*(measured_current-filtered_current);
    measured_vbat = quantize(vbat,hw,hw.cal_battery_ratio,hw.cal_battery_zero);
    measured_bus = quantize(x(3),hw,hw.cal_bus_ratio,hw.cal_bus_zero);
    [new_duty, new_enable, s] = controller(uint8(mode),single(charge_command),single(30), ...
        single(filtered_current),single(measured_vbat),single(measured_bus),s,p);
    % Fast raw-channel overcurrent has the same latch as the MCU wrapper.
    if mode ~= 0 && abs(measured_current) >= double(p.overcurrent)
        s.fault = uint8(3);
        new_enable = false;
    end
    r.data(k,:) = [x(3),vbat,ibat,x(1),double(s.current_reference), ...
        duty*100,double(enabled),double(s.fault),source,mode,charge_command];
    r.controller_mode(k)=s.mode;
    if ~enabled
        edges=[0 1]; states=-1;
    elseif ~c.switched
        edges=[0 1]; states=2;
    else
        % Integrate EXACTLY to gate edges. A coarse fixed grid would impose
        % a fictitious 1% duty quantizer and manufacture a limit cycle.
        dead=hw.deadtime/hw.Ts;
        edge1=(1-duty)/2; edge2=(1+duty)/2;
        edges=[0 edge1-dead/2 edge1+dead/2 edge2-dead/2 edge2+dead/2 1];
        states=[0 -1 1 -1 0];
    end
    % Optional source edges are physical events, including arbitrary PWM phase.
    % Split RK4 at these edges rather than rounding the disturbance to a sample.
    if isfield(c,'source_steps')
        extra=(c.source_steps(:,1)-t)/hw.Ts;
        extra=extra(extra>1e-9 & extra<1-1e-9);
        old_edges=edges; old_states=states;
        edges=unique([edges,extra.']);
        states=zeros(1,numel(edges)-1);
        for segment=1:numel(states)
            middle=(edges(segment)+edges(segment+1))/2;
            states(segment)=old_states(find(old_edges<=middle,1,'last'));
        end
    end
    elapsed=0;
    for segment=1:numel(states)
        duration=(edges(segment+1)-edges(segment))*hw.Ts;
        count=max(1,ceil(duration/dt)); h=duration/count;
        switch_state=states(segment);
        if isfield(c,'source_steps')
            middle=t+(edges(segment)+edges(segment+1))/2*hw.Ts;
            index=find(c.source_steps(:,1)<=middle+1e-12,1,'last');
            source=c.source_steps(index,2);
        end
        for j=1:count
            % One-sample controller delay; RK4 within each physical interval.
            f = @(z) circuit(z,switch_state,duty,ideal_bus,source,rb,load_value,c,hw);
            a=f(x); b=f(x+0.5*h*a); d=f(x+0.5*h*b); e=f(x+h*d);
            if c.switched && k>=tail_start
                % Integrate port power with the same RK4 stages. Sampling
                % bus power only at switching edges biases BUCK efficiency.
                z=[x,x+0.5*h*a,x+0.5*h*b,x+h*d];
                [pbus,pbat]=port_power(z,switch_state,duty,rb,c,hw);
                weights=[1;2;2;1];
                r.tail_bus_energy_J=r.tail_bus_energy_J+h/6*(pbus*weights);
                r.tail_battery_energy_J=r.tail_battery_energy_J+h/6*(pbat*weights);
                r.tail_interval_s=r.tail_interval_s+h;
            end
            next = x + h/6*(a+2*b+2*d+e);
            if ~enabled && x(1)*next(1)<0 && next(3)>=next(2)-hw.diode_drop
                next(1)=0;
            end
            x=next; elapsed=elapsed+h;
            r.inductor_peak_A=max(r.inductor_peak_A,abs(x(1)));
            if t+elapsed>=measure_start
                r.bus_min_V=min(r.bus_min_V,x(3));
                r.bus_max_V=max(r.bus_max_V,x(3));
            end
            if isfinite(ideal_bus), x(3)=ideal_bus; end
            if c.switched && k>=tail_start
                fast_index=fast_index+1;
                fi=(x(2)-c.battery)/(rb+hw.shunt);
                fast(fast_index,:)=[t+elapsed,x(3),x(2)-hw.shunt*fi,fi,x(1),switch_state];
            end
        end
    end
    if s.fault ~= 0
        enabled = false; % fault shutdown acts immediately, no PWM delay
        duty = 0;
    else
        duty = round(double(new_duty)*hw.pwm_arr)/hw.pwm_arr;
        enabled = logical(new_enable);
    end
    if any(~isfinite(x)) || max(abs(x))>500
        error('Electrical simulation diverged: %s at %.6f s', c.name,t);
    end
end
r.columns = {'bus_V','battery_terminal_V','battery_A','inductor_A', ...
    'current_reference_A','high_side_duty_percent','enabled','fault', ...
    'source_V','mode','charge_command_A'};
r.name = c.name;
r.settings = c;
if isfield(r.settings,'controller')
    r.settings=rmfield(r.settings,{'controller','controller_state'});
end
if c.switched, r.fast=fast(1:fast_index,:); end
end

function y=quantize(voltage,hw,ratio,zero)
y = (round(min(max(voltage/hw.voltage_ratio/hw.adc_reference,0),1)*hw.adc_counts)-zero) * ...
    hw.adc_reference/hw.adc_counts*ratio;
end

function [bus_power,battery_power]=port_power(z,q,d,rb,c,hw)
i=z(1,:); vb=z(2,:); bus=z(3,:);
ibat=(vb-c.battery)/(rb+hw.shunt);
battery_power=(vb-hw.shunt*ibat).*ibat;
if q==2
    bus_power=bus.*(d*i);
elseif q==1
    bus_power=bus.*i;
elseif q==0
    bus_power=zeros(1,4);
else
    conducting=(i < -1e-7) | (vb > bus+hw.diode_drop);
    bus_power=bus.*i.*conducting;
end
end

function dz=circuit(x,q,d,ideal_bus,source,rb,load_value,c,hw)
i=x(1); vb=x(2); bus=x(3);
ibat=(vb-c.battery)/(rb+hw.shunt);
r=hw.inductor_resistance+hw.mos_resistance;
if q==2
    node=d*bus-sign(i)*bus*hw.deadtime/hw.Ts;
    bus_current=d*i;
elseif q==1
    node=bus;
    bus_current=i;
elseif q==0
    node=0;
    bus_current=0;
elseif i>1e-7
    node=-hw.diode_drop;
    bus_current=0;
elseif i< -1e-7 || vb>bus+hw.diode_drop
    node=bus+hw.diode_drop;
    bus_current=i;
else
    node=vb;
    bus_current=0;
end
if isfinite(ideal_bus)
    dbus=0;
else
    input_current=max((source-hw.diode_drop-bus)/5,0);
    if ~isfinite(source), input_current=0; end
    dbus=(input_current-bus/load_value-bus_current)/hw.Cbus;
end
dz=[(node-vb-r*i)/hw.L;(i-ibat)/hw.Cbat;dbus];
end

function [mode,command,bus,source,rb,load_value]=commands(t,c,hw)
mode=c.mode; command=c.current; bus=c.bus; source=NaN;
rb=hw.battery_resistance; load_value=c.load;
if strcmp(c.kind,'current_step')
    if t<0.15, command=1; else, command=2; end
elseif strcmp(c.kind,'line_step')
    if t<0.20, bus=24; elseif t<0.40, bus=30; else, bus=36; end
elseif strcmp(c.kind,'overcharge')
    % As specified in the question: add a series rheostat at A-B. The cell
    % stack remains at 18 V; only converter terminal U1 reaches 24 V.
    if t>0.15, rb=hw.battery_resistance+min((t-0.15)*20,3.3); end
elseif strcmp(c.kind,'automatic')
    if t<0.25, source=32;
    elseif t<0.65, source=32+6*(t-0.25)/0.40;
    elseif t<0.85, source=38;
    elseif t<1.25, source=38-6*(t-0.85)/0.40;
    else, source=32; end
elseif strcmp(c.kind,'auto_step')
    if t<0.25 || t>=0.65, source=32; else, source=38; end
elseif strcmp(c.kind,'overcurrent')
    if t>0.20, command=NaN; end
elseif strcmp(c.kind,'load_step')
    if t>=0.25, load_value=c.load_after; end
end
end


function r=simulate_hardware_case(c,p,hw)
% TIM1 center-aligned PWM1: HIGH about the counter BOTTOM, LOW about PEAK.
% At bottom the ISR sees the previous peak's completed ADC frame. CCR preload
% takes effect at peak; the falling edge uses old CCR, rising edge the new CCR.
% ADC ranks I/REF/VBAT/VBUS are sampled separately; DMA completes ~5.65 us later.
n=ceil(c.duration/hw.Ts);r.t=(0:n-1)'*hw.Ts;r.data=zeros(n,11);
r.controller_mode=zeros(n,1,'uint8');s=dcdc_initial_state();controller=@dcdc_step;
if isfield(c,'controller'),controller=c.controller;s=c.controller_state;end
x=[0;c.battery;c.initial_bus];duty=0;enabled=false;filtered=single(0);
% Feedback fields: raw current, filtered current, terminal voltage, bus voltage.
feedback=[0 0 c.battery c.initial_bus];pending=feedback;frame_count=0;
r.inductor_peak_A=0;r.bus_min_V=Inf;r.bus_max_V=-Inf;
r.tail_bus_energy_J=0;r.tail_battery_energy_J=0;r.tail_interval_s=0;
measure_start=0;if isfield(c,'measure_start_s'),measure_start=c.measure_start_s;end
substeps=10;if c.switched,substeps=100;end
dt=hw.Ts/substeps;tail_start=max(1,n-ceil(.005/hw.Ts));
fast=zeros(0,6);fi=0;
rank_interval=60/42.5e6; % 47.5 sample + 12.5 conversion cycles
% current sample, VBAT sample, VBUS sample, DMA completion, twice per period.
adc_edges=[0,2*rank_interval,3*rank_interval,4*rank_interval]/hw.Ts;
for k=1:n
 t=r.t(k);[mode,charge,ideal_bus,source,rb,load_value]=commands(t,c,hw);
 if isfield(c,'source_steps')
  source=c.source_steps(find(c.source_steps(:,1)<=t+1e-12,1,'last'),2);
 end
 ibat=(x(2)-c.battery)/(rb+hw.shunt);vbat=x(2)-hw.shunt*ibat;
 [new_duty,new_enable,s]=controller(uint8(mode),single(charge),single(30), ...
    single(feedback(2)),single(feedback(3)),single(feedback(4)),s,p);
 if mode~=0 && abs(feedback(1))>=double(p.overcurrent),s.fault=uint8(3);new_enable=false;end
 next_duty=round(double(new_duty)*hw.pwm_arr)/hw.pwm_arr;
 r.data(k,:)=[x(3),vbat,ibat,x(1),double(s.current_reference),duty*100,enabled,double(s.fault),source,mode,charge];
 r.controller_mode(k)=s.mode;
 if s.fault~=0,enabled=false;new_enable=false;end
 dead=hw.deadtime/hw.Ts;
 if c.switched
  if enabled
   first_edges=[0,duty/2-dead/2,duty/2+dead/2,.5];first_states=[1,-1,0];
  else,first_edges=[0,.5];first_states=-1;end
  if new_enable
   second_edges=[.5,1-next_duty/2-dead/2,1-next_duty/2+dead/2,1];second_states=[0,-1,1];
  else,second_edges=[.5,1];second_states=-1;end
 else
  first_edges=[0,.5];first_states=2;if ~enabled,first_states=-1;end
  second_edges=[.5,1];second_states=2;if ~new_enable,second_states=-1;end
 end
 gate_edges=[first_edges,second_edges(2:end)];gate_states=[first_states,second_states];
 edges=unique([gate_edges,adc_edges,.5+adc_edges]);
 if isfield(c,'source_steps')
  extra=(c.source_steps(:,1)-t)/hw.Ts;edges=unique([edges,extra(extra>1e-9 & extra<1-1e-9).']);
 end
 for segment=1:numel(edges)-1
  phase=edges(segment);middle=(phase+edges(segment+1))/2;
  % Sample/complete ADC at the explicitly inserted event boundaries.
  local_phase=phase;if phase>=.5-1e-10,local_phase=phase-.5;end
  if abs(local_phase-adc_edges(1))<1e-10
   ibat=(x(2)-c.battery)/(rb+hw.shunt);
   iraw=round(min(max((hw.current_zero+hw.shunt*hw.current_gain*hw.current_gain_factor*ibat)/hw.adc_reference,0),1)*hw.adc_counts);
   rraw=round(hw.current_zero/hw.adc_reference*hw.adc_counts);
   pending(1)=(iraw-rraw-hw.cal_current_offset)*hw.adc_reference/hw.adc_counts*hw.cal_current_scale;
  elseif abs(local_phase-adc_edges(2))<1e-10
   ibat=(x(2)-c.battery)/(rb+hw.shunt);pending(3)=quantize(x(2)-hw.shunt*ibat,hw,hw.cal_battery_ratio,hw.cal_battery_zero);
  elseif abs(local_phase-adc_edges(3))<1e-10
   pending(4)=quantize(x(3),hw,hw.cal_bus_ratio,hw.cal_bus_zero);
  elseif abs(local_phase-adc_edges(4))<1e-10
   if frame_count==0,filtered=single(pending(1));
   else,filtered=filtered+single(hw.current_filter_alpha)*(single(pending(1))-filtered);end
   pending(2)=double(filtered);feedback=pending;frame_count=frame_count+1;
  end
  q=gate_states(find(gate_edges<=middle,1,'last'));d=duty;if middle>=.5,d=next_duty;end
  if isfield(c,'source_steps'),source=c.source_steps(find(c.source_steps(:,1)<=t+middle*hw.Ts+1e-12,1,'last'),2);end
  duration=(edges(segment+1)-phase)*hw.Ts;count=max(1,ceil(duration/dt));h=duration/count;
  for j=1:count
   f=@(z)circuit(z,q,d,ideal_bus,source,rb,load_value,c,hw);
   a=f(x);b=f(x+.5*h*a);dd=f(x+.5*h*b);e=f(x+h*dd);
   if c.switched && k>=tail_start
    z=[x,x+.5*h*a,x+.5*h*b,x+h*dd];[pbus,pbat]=port_power(z,q,d,rb,c,hw);weights=[1;2;2;1];
    r.tail_bus_energy_J=r.tail_bus_energy_J+h/6*(pbus*weights);r.tail_battery_energy_J=r.tail_battery_energy_J+h/6*(pbat*weights);r.tail_interval_s=r.tail_interval_s+h;
   end
   next=x+h/6*(a+2*b+2*dd+e);
   if q==-1 && x(1)*next(1)<0 && next(3)>=next(2)-hw.diode_drop,next(1)=0;end
   x=next;if isfinite(ideal_bus),x(3)=ideal_bus;end
   time=t+phase*hw.Ts+j*h;
   r.inductor_peak_A=max(r.inductor_peak_A,abs(x(1)));
   if time>=measure_start,r.bus_min_V=min(r.bus_min_V,x(3));r.bus_max_V=max(r.bus_max_V,x(3));end
   capture=c.switched && k>=tail_start;
   if isfield(c,'capture_windows_s'),capture=capture || any(time>=c.capture_windows_s(:,1) & time<=c.capture_windows_s(:,2));end
   if capture
    fi=fi+1;fast(fi,:)=[time,x(3),x(2)-hw.shunt*(x(2)-c.battery)/(rb+hw.shunt),(x(2)-c.battery)/(rb+hw.shunt),x(1),q]; %#ok<AGROW>
   end
  end
 end
 duty=next_duty;enabled=logical(new_enable);
 if any(~isfinite(x)) || max(abs(x))>500,error('Hardware-timing simulation diverged: %s',c.name);end
end
r.fast=fast;r.columns={'bus_V','battery_terminal_V','battery_A','inductor_A','current_reference_A','high_side_duty_percent','enabled','fault','source_V','mode','charge_command_A'};
r.name=c.name;r.settings=c;if isfield(r.settings,'controller'),r.settings=rmfield(r.settings,{'controller','controller_state'});end
end
