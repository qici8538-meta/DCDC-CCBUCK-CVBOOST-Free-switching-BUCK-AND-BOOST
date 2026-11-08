function run_comparison()
% Compare only basic (1)(2)(5), advanced (1)(2). This script never alters FW.
folder=fileparts(mfilename('fullpath'));root=fileparts(folder);
addpath(folder,root,fullfile(root,'程序'));
out=fullfile(folder,'结果');if ~isfolder(out),mkdir(out);end
[original,hw]=dcdc_parameters();[base,choices]=comparison_setup();
tuning=load(fullfile(out,'候选整定.mat'));p=original;
% The delivered controller uses the human-owned current header, never an old
% best_p silently loaded from a previous architecture search.
choices.voltage_pi=tuning.best;choices.hysteresis=tuning.best_h;
set(groot,'defaultFigureVisible','off');set(groot,'defaultAxesFontName','Microsoft YaHei');
traces=struct();cc_rows={};line_rows={};dynamic_rows={};
for scheme=1:2
    label=sprintf('CC%d',scheme);currents=zeros(1,3);
    for setting=10:20
        c=base;c.name=sprintf('%s_%02d',label,setting);c.current=setting/10;
        if scheme==1,c=apply_candidate(c,choices.current_pi);end
        r=simulate_case(c,p,hw);valid=r.t>0.30;
        actual=mean(r.data(valid,3));err=100*abs(actual-c.current)/c.current;
        cc_rows(end+1,:)={label,c.current,actual,err,max(r.data(:,8))}; %#ok<AGROW>
        traces.(c.name)=r;
    end
    for k=1:3
        c=base;c.bus=18+6*k;c.initial_bus=c.bus;c.name=sprintf('%s_bus%d',label,c.bus);
        if scheme==1,c=apply_candidate(c,choices.current_pi);end
        r=simulate_case(c,p,hw);currents(k)=mean(r.data(r.t>0.30,3));traces.(c.name)=r;
    end
    line_rows(end+1,:)={label,currents(1),currents(2),currents(3), ...
        100*abs(currents(3)-currents(1))/currents(2)}; %#ok<AGROW>
    for kind={'current_step','line_step'}
        c=base;c.name=[label '_' kind{1}];c.kind=kind{1};c.duration=0.65;
        if scheme==1,c=apply_candidate(c,choices.current_pi);end
        r=simulate_case(c,p,hw);traces.(c.name)=r;
        if strcmp(c.kind,'current_step')
            active=r.t>0.15;last_change=.15;target=2;limit=.1;
        else
            active=r.t>0.20;last_change=.40;target=2;limit=.1;
        end
        err=r.data(active,3)-target;
        final_interval=r.t>last_change;
        settle=settling(r.t(final_interval),r.data(final_interval,3)-target,limit)-last_change;
        dynamic_rows(end+1,:)={label,c.kind,max(abs(err)),r.inductor_peak_A, ...
            settle,max(r.data(:,8))}; %#ok<AGROW>
    end
    fprintf('CC comparison scheme %d complete\n',scheme);
end
cc=cell2table(cc_rows,'VariableNames',{'scheme','set_A','actual_A','error_percent','fault'});
line=cell2table(line_rows,'VariableNames',{'scheme','I24_A','I30_A','I36_A','variation_percent'});
cc_dynamic=cell2table(dynamic_rows,'VariableNames',{'scheme','test','max_current_error_A', ...
    'inductor_peak_A','settling_after_last_change_s','fault'});
writetable(cc,fullfile(out,'基本1_两方案11档恒流.csv'),'Encoding','UTF-8');
writetable(line,fullfile(out,'基本2_两方案输入变化率.csv'),'Encoding','UTF-8');
writetable(cc_dynamic,fullfile(out,'基本12_动态对比.csv'),'Encoding','UTF-8');

rows={};
for scheme=1:2
    label=sprintf('CV%d',scheme);
    for test=1:3
        c=base;c.mode=2;c.bus=NaN;c.initial_bus=18;c.duration=.65;
        if test==1,c.kind='steady';
        elseif test==2,c.kind='load_step';c.load_after=45;c.duration=.75;
        else,c.kind='steady';c.battery=15.5;c.initial_bus=c.battery;end
        c.name=sprintf('%s_test%d',label,test);
        if scheme==1,c=apply_candidate(c,choices.voltage_pi);end
        r=simulate_case(c,p,hw);traces.(c.name)=r;
        valid=r.t>0.35;dynamic=r.t>0.22;
        rows(end+1,:)={label,test,c.battery,max(abs(r.data(valid,1)-30)), ...
            max(abs(r.data(dynamic,1)-30)),settling(r.t,r.data(:,1)-30,.5), ...
            r.inductor_peak_A,max(r.data(:,8))}; %#ok<AGROW>
    end
    fprintf('CV comparison scheme %d complete\n',scheme);
end
cv=cell2table(rows,'VariableNames',{'scheme','test','battery_V','late_max_error_V', ...
    'max_error_after_220ms_V','settling_from_start_s','inductor_peak_A','fault'});
writetable(cv,fullfile(out,'发挥1_单环与双环.csv'),'Encoding','UTF-8');

rows={};
for scheme=1:2
    label=sprintf('AUTO%d',scheme);
    for test=1:4
        c=base;c.mode=3;c.bus=NaN;c.initial_bus=18;c.duration=1.5;c.kind='automatic';
        local=hw;
        if test==2,c.kind='auto_step';c.duration=1.0;c.source_steps=[0 32;.25 38;.65 32];
        elseif test==3,c.battery=15.5;c.initial_bus=c.battery;local.L=.8*hw.L;local.Cbat=.8*hw.Cbat;local.Cbus=.8*hw.Cbus;
        elseif test==4,c.battery=21;c.initial_bus=c.battery;local.L=1.2*hw.L;local.Cbat=1.2*hw.Cbat;local.Cbus=1.2*hw.Cbus;end
        c.name=sprintf('%s_test%d',label,test);
        if scheme==1,c=apply_candidate(c,choices.hysteresis);end
        r=simulate_case(c,p,local);traces.(c.name)=r;valid=r.t>.22;
        rows(end+1,:)={label,test,c.battery,max(abs(r.data(valid,1)-30)), ...
            max(r.data(valid,3)),min(r.data(valid,3)),r.inductor_peak_A, ...
            sum(diff(double(r.controller_mode))~=0),max(r.data(:,8))}; %#ok<AGROW>
    end
    fprintf('AUTO comparison scheme %d complete\n',scheme);
end
auto=cell2table(rows,'VariableNames',{'scheme','test','battery_V','max_bus_error_V', ...
    'charge_max_A','discharge_min_A','inductor_peak_A','mode_changes','fault'});
writetable(auto,fullfile(out,'发挥2_阈值切换与连续双向.csv'),'Encoding','UTF-8');

% Confirm unselected structural alternatives at the physical switching level.
rows={};
for test=1:3
    c=base;c.switched=true;c.name=sprintf('Alternative_switch%d',test);
    if test==1,c=apply_candidate(c,choices.current_pi);
    elseif test==2,c.mode=2;c.bus=NaN;c.initial_bus=18;c.duration=.65;c=apply_candidate(c,choices.voltage_pi);
    else,c.mode=3;c.bus=NaN;c.initial_bus=18;c.duration=1.5;c.kind='automatic';c=apply_candidate(c,choices.hysteresis);end
    r=simulate_case(c,p,hw);traces.(c.name)=r;valid=r.t>.30;
    rows(end+1,:)={test,mean(r.data(valid,3)),max(abs(r.data(valid,1)-30)), ...
        r.inductor_peak_A,max(r.data(:,8))}; %#ok<AGROW>
    fprintf('Alternative switching model %d complete\n',test);
end
switching=cell2table(rows,'VariableNames',{'alternative','mean_battery_A', ...
    'max_bus_error_V','inductor_peak_A','fault'});
writetable(switching,fullfile(out,'未选方案_开关模型复核.csv'),'Encoding','UTF-8');
save(fullfile(out,'全部方案对比.mat'),'traces','p','original','hw','choices','cc','line','cc_dynamic','cv','auto','switching','-v7.3');
for pair={ {'CC1_line_step','CC2_line_step','基本2_输入突变对比'}, ...
        {'CV1_test1','CV2_test1','发挥1_启动对比'}, ...
        {'CV1_test2','CV2_test2','发挥1_负载变化对比'}, ...
        {'AUTO1_test1','AUTO2_test1','发挥2_往返调压对比'}, ...
        {'AUTO1_test2','AUTO2_test2','发挥2_瞬间阶跃压力测试'} }
    a=pair{1};draw_pair(traces.(a{1}),traces.(a{2}),fullfile(out,a{3}));
end
disp(line);disp(cc_dynamic);disp(cv);disp(auto);disp(switching);
fprintf('SCHEME_COMPARISON_OK; candidates saved; firmware unchanged by comparison.\n');
end

function t=settling(time,error,limit)
k=find(abs(error)>limit,1,'last');
if isempty(k),t=time(1);elseif k==numel(time),t=NaN;else,t=time(k+1);end
end

function draw_pair(a,b,path)
f=figure('Color','w','Position',[100 100 1150 820]);tiledlayout(3,1,'TileSpacing','compact');
nexttile;plot(a.t,a.data(:,1),b.t,b.data(:,1),'LineWidth',1);hold on;yline(30.5,'--');yline(29.5,'--');
grid on;ylabel('U2 / V');legend(a.name,b.name,'Interpreter','none','Location','best');
title('Same schematic, ADC, PWM delay and protection; separately tuned alternatives');
nexttile;plot(a.t,a.data(:,3),b.t,b.data(:,3),'LineWidth',1);grid on;ylabel('Battery branch / A');
nexttile;plot(a.t,a.data(:,6),b.t,b.data(:,6),'LineWidth',1);grid on;ylabel('High-side duty / %');xlabel('Time / s');
exportgraphics(f,[path '.png'],'Resolution',150);savefig(f,[path '.fig']);close(f);
write_trace(a,fileparts(path));write_trace(b,fileparts(path));
end

function write_trace(r,out)
table=array2table([r.t,r.data,double(r.controller_mode)],'VariableNames',[{'time_s'},r.columns,{'active_control_mode'}]);
writetable(table,fullfile(out,[r.name '.csv']),'Encoding','UTF-8');
end
