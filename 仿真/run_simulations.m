function run_simulations()
folder=fileparts(mfilename('fullpath'));
addpath(folder,fullfile(folder,'程序'));
out=fullfile(folder,'结果');
if ~exist(out,'dir'), mkdir(out); end
[p,hw]=dcdc_parameters();
rng(2015);
set(groot,'defaultFigureVisible','off');
set(groot,'defaultAxesFontName','Microsoft YaHei');
base=struct('name','','kind','steady','duration',0.40,'mode',1, ...
    'current',2,'bus',30,'battery',18,'initial_bus',30,'load',30,'switched',false, ...
    'measure_start_s',.22);
results=struct();
rows={};
% Basic (1): every 0.1-A setting, actual battery-branch current.
for a=10:20
    c=base; c.current=a/10; c.name=sprintf('CC_%02d',a);
    r=simulate_case(c,p,hw);
    measured=mean(r.data(r.t>0.30,3));
    err=abs(measured-c.current)/c.current*100;
    rows(end+1,:)={c.name,c.current,measured,err,err<=5}; %#ok<AGROW>
    results.(c.name)=r;
end
cc=cell2table(rows,'VariableNames',{'case','set_A','actual_A','error_percent','pass_5percent'});
writetable(cc,fullfile(out,'基本1_恒流步进.csv'),'Encoding','UTF-8');
% Basic (2): use the original |I36-I24|/I30 definition.
currents=zeros(1,3);
for k=1:3
    c=base; c.bus=18+6*k; c.initial_bus=c.bus; c.name=sprintf('BUS_%02d',c.bus);
    r=simulate_case(c,p,hw); currents(k)=mean(r.data(r.t>0.30,3));
    results.(c.name)=r;
end
line_regulation=abs(currents(3)-currents(1))/currents(2)*100;
line=table(currents(1),currents(2),currents(3),line_regulation,line_regulation<=1, ...
    'VariableNames',{'I24_A','I30_A','I36_A','variation_percent','pass_1percent'});
writetable(line,fullfile(out,'基本2_输入变化率.csv'),'Encoding','UTF-8');

tests={'CC_step','current_step',1,0.45,30; ...
       'CC_line_step','line_step',1,0.65,30; ...
       'Overcharge','overcharge',1,0.50,30; ...
       'Boost','steady',2,0.65,NaN; ...
       'Auto_ramp','automatic',3,1.50,NaN; ...
       'Auto_step','auto_step',3,1.00,NaN};
for k=1:size(tests,1)
    c=base; c.name=tests{k,1}; c.kind=tests{k,2}; c.mode=tests{k,3};
    c.duration=tests{k,4}; c.bus=tests{k,5};
    if isnan(c.bus), c.initial_bus=c.battery; end
    if strcmp(c.kind,'auto_step'),c.source_steps=[0 32;.25 38;.65 32];end
    r=simulate_case(c,p,hw); results.(c.name)=r;
    write_trace(r,out); draw_trace(r,out);
end
% Battery range and passive tolerance sensitivity. These are assumptions,
% not a claim that the unmeasured inductor remains linear to these currents.
sensitivity={};
for eb=[15.5 18 21]
    for mult=[0.8 1.2]
        local=hw; local.L=hw.L*mult; local.Cbat=hw.Cbat*mult; local.Cbus=hw.Cbus*mult;
        c=base; c.name=sprintf('Tolerance_%g_%g',eb,mult); c.mode=3;
        c.kind='automatic'; c.battery=eb; c.initial_bus=eb; c.bus=NaN; c.duration=1.5;
        r=simulate_case(c,p,local);
        settled=r.t>0.22;
        sensitivity(end+1,:)={eb,mult,max(abs(r.data(settled,1)-30)), ...
            max(abs(r.data(:,4))),max(r.data(:,8))}; %#ok<AGROW>
    end
end
tol=cell2table(sensitivity,'VariableNames',{'battery_V','LC_multiplier', ...
    'bus_max_error_V_after_start','inductor_peak_A','fault'});
writetable(tol,fullfile(out,'容差与电池电压.csv'),'Encoding','UTF-8');
% Switch-level confirmation includes deadtime, PWM/ADC quantization and delay.
for mode=[1 2 3]
    c=base; c.mode=mode; c.switched=true; c.duration=0.40;
    c.name=sprintf('Switching_mode%d',mode);
    if mode~=1, c.bus=NaN; c.initial_bus=c.battery; end
    if mode==3, c.kind='automatic'; end
    if mode==3, c.duration=1.50; end
    r=simulate_case(c,p,hw); results.(c.name)=r;
    write_trace(r,out); draw_trace(r,out);
end
switch_rows={};
for mode=[1 2 3]
    r=results.(sprintf('Switching_mode%d',mode));
    valid=r.t>0.30;
    switch_rows(end+1,:)={mode,mean(r.data(valid,3)),max(abs(r.data(valid,1)-30)), ...
        max(r.data(:,8)),r.inductor_peak_A}; %#ok<AGROW>
end
switch_summary=cell2table(switch_rows,'VariableNames',{'mode','battery_A', ...
    'bus_max_error_V','fault','inductor_peak_A'});
writetable(switch_summary,fullfile(out,'开关模型复核.csv'),'Encoding','UTF-8');
% Explicit protection tests, independent of steady-state plots.
protection=verify_protection(p);
writetable(protection,fullfile(out,'保护逻辑测试.csv'),'Encoding','UTF-8');
boost=results.Boost; auto=results.Auto_ramp; astep=results.Auto_step;
over=results.Overcharge;
valid=boost.t>0.35;
boost_error=max(abs(boost.data(valid,1)-30));
valid=auto.t>0.22;
auto_error=max(abs(auto.data(valid,1)-30));
valid=astep.t>0.22;
auto_step_error=max(abs([astep.bus_min_V astep.bus_max_V]-30));
trip=find(over.data(:,8)==1,1);
assert(~isempty(trip),'Overcharge did not trip.');
summary=struct('current_max_error_percent',max(cc.error_percent), ...
    'line_variation_percent',line_regulation,'boost_max_error_V',boost_error, ...
    'auto_ramp_max_error_V',auto_error,'auto_step_max_error_V',auto_step_error, ...
    'overcharge_trip_V',over.data(trip,2),'overcharge_trip_s',over.t(trip), ...
    'automatic_charge_A',max(auto.data(auto.t>0.25,3)), ...
    'automatic_discharge_A',min(auto.data(auto.t>0.22,3)));
save(fullfile(out,'全部仿真数据.mat'),'results','p','hw','cc','line','tol','summary','protection','switch_summary','-v7.3');
f=fopen(fullfile(out,'指标摘要.json'),'w','n','UTF-8');
fprintf(f,'%s',jsonencode(summary,PrettyPrint=true)); fclose(f);
disp(cc); disp(line); disp(tol); disp(summary); disp(protection); disp(switch_summary);
assert(all(cc.pass_5percent),'Basic1 failed');
assert(line_regulation<=1,'Basic2 failed');
assert(boost_error<=0.5,'Boost CV failed');
assert(auto_error<=0.5,'Automatic slow sweep failed');
assert(auto_step_error<=0.5,'Automatic instantaneous source step failed');
assert(all(protection.pass),'Protection test failed');
assert(all(tol.fault==0),'Tolerance case tripped');
assert(all(tol.bus_max_error_V_after_start<=0.5),'Tolerance CV failed');
assert(all(switch_summary.fault==0),'Switching case tripped');
assert(all(switch_summary.bus_max_error_V<=0.5),'Switching CV failed');
refresh_reading_material();
fprintf('MATLAB_SIMULATION_OK\n');
end

function write_trace(r,out)
t=array2table([r.t,r.data],'VariableNames',[{'time_s'},r.columns]);
writetable(t,fullfile(out,[r.name '.csv']),'Encoding','UTF-8');
if ~isempty(r.fast)
    t=array2table(r.fast,'VariableNames',{'time_s','bus_V','battery_V','battery_A','inductor_A','switch_state'});
    writetable(t,fullfile(out,[r.name '_ripple.csv']),'Encoding','UTF-8');
end
end

function draw_trace(r,out)
f=figure('Position',[100 100 1100 850],'Color','w');
layout=tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
nexttile; plot(r.t,r.data(:,1),'LineWidth',1.2); hold on;
plot(r.t,r.data(:,2),'LineWidth',1.0); yline(30,'--'); grid on;
ylabel('Voltage / V'); legend('Bus U2','Terminal U1','30 V','Location','best');
title(strrep(r.name,'_',' '));
nexttile; plot(r.t,r.data(:,3:5),'LineWidth',1.0); grid on;
ylabel('Current / A'); legend('Battery branch','Inductor','Reference','Location','best');
nexttile; plot(r.t,r.data(:,6),'LineWidth',1.0); grid on;
ylabel('High-side duty / %');
nexttile; stairs(r.t,r.data(:,7:8),'LineWidth',1.0); grid on;
ylabel('State'); xlabel('Time / s'); legend('PWM enabled','Fault','Location','best');
title(layout,'2015A - sampled controller, schematic V2','FontWeight','bold');
exportgraphics(f,fullfile(out,[r.name '.png']),'Resolution',140);
savefig(f,fullfile(out,[r.name '.fig'])); close(f);
if ~isempty(r.fast)
    f=figure('Position',[100 100 1100 700],'Color','w');
    t=r.fast(:,1); keep=t>t(end)-0.0005;
    tiledlayout(3,1,'TileSpacing','compact');
    nexttile; plot(t(keep)*1000,r.fast(keep,2)); grid on; ylabel('Bus / V');
    title([strrep(r.name,'_',' ') ' - exact gate edges, final 0.5 ms']);
    nexttile; plot(t(keep)*1000,r.fast(keep,4:5)); grid on; ylabel('Current / A');
    legend('Battery branch','Inductor','Location','best');
    nexttile; stairs(t(keep)*1000,r.fast(keep,6)); grid on; ylabel('Gate state'); xlabel('Time / ms');
    exportgraphics(f,fullfile(out,[r.name '_ripple.png']),'Resolution',140);
    savefig(f,fullfile(out,[r.name '_ripple.fig'])); close(f);
end
end

function t=verify_protection(p)
rows={};
s=dcdc_initial_state();
[~,en,s]=dcdc_step(uint8(1),single(2),single(30),single(2),single(24.05),single(30),s,p);
rows(end+1,:)={'24V overcharge latch',~en && s.fault==1};
[~,en,s]=dcdc_step(uint8(1),single(2),single(30),single(0),single(18),single(30),s,p);
rows(end+1,:)={'no automatic restart',~en && s.fault==1};
[~,~,s]=dcdc_step(uint8(0),single(2),single(30),single(0),single(18),single(30),s,p);
rows(end+1,:)={'manual OFF clears after recovery',s.fault==0};
for current=[-2.81 2.81]
    s=dcdc_initial_state();
    [~,en,s]=dcdc_step(uint8(3),single(2),single(30),single(current),single(18),single(30),s,p);
    rows(end+1,:)={sprintf('overcurrent %g A',current),~en && s.fault==3}; %#ok<AGROW>
end
s=dcdc_initial_state();
[~,en,s]=dcdc_step(uint8(2),single(2),single(30),single(0),single(14.9),single(30),s,p);
rows(end+1,:)={'battery undervoltage',~en && s.fault==2};
s=dcdc_initial_state();
[~,en,s]=dcdc_step(uint8(3),single(2),single(30),single(0),single(18),single(39.1),s,p);
rows(end+1,:)={'bus overvoltage',~en && s.fault==4};
s=dcdc_initial_state();
[~,en,s]=dcdc_step(uint8(1),single(NaN),single(30),single(0),single(18),single(30),s,p);
rows(end+1,:)={'invalid command',~en && s.fault==6};
t=cell2table(rows,'VariableNames',{'check','pass'});
end
