function verify_current_display()
% Basic (1)(4): cycle-mean current versus two ADC phases and LCD rounding.
% Independently replay BOTH 40-kHz ADC phases on the actual switch waveform.
% The closed-loop model also schedules real ADC ranks and DMA/IIR timing.
folder=fileparts(fileparts(mfilename('fullpath')));
addpath(folder,fullfile(folder,'程序'),fullfile(folder,'方案对比'));
[p,hw]=dcdc_parameters();[c,~]=comparison_setup();
saved=load(fullfile(folder,'结果','全部仿真数据.mat'),'results');rows={};waves=cell(1,2);
for setting=1:2
    if setting==1
        c.current=1;c.switched=true;c.name='Current_display_1A';r=simulate_case(c,p,hw);
    else
        r=saved.results.Switching_mode1;
    end
    waves{setting}=r;fast=r.fast;t=fast(:,1);
    mean_true=trapz(t,fast(:,4))/(t(end)-t(1));
    interval=hw.Ts/2;
    times=(ceil(t(1)/interval):floor(t(end)/interval))'*interval;
    current=interp1(t,fast(:,4),times,'linear');
    pin=hw.current_zero+hw.shunt*hw.current_gain*hw.current_gain_factor*current;
    raw=round(pin/hw.adc_reference*hw.adc_counts);
    reference_raw=round(hw.current_zero/hw.adc_reference*hw.adc_counts);
    measured=single(raw-reference_raw-hw.cal_current_offset)*single(hw.adc_reference/hw.adc_counts)*single(hw.cal_current_scale);
    filtered=zeros(size(measured),'single');filtered(1)=measured(1);
    for k=2:numel(measured)
        filtered(k)=filtered(k-1)+single(hw.current_filter_alpha)*(measured(k)-filtered(k-1));
    end
    keep=times>times(1)+.001;
    shown=round(double(filtered(keep))*100)/100;
    display_error=max(abs(shown-mean_true))/mean_true*100;
    regulation_error=abs(mean_true-setting)/setting*100;
    rows(end+1,:)={setting,mean_true,min(shown),max(shown),regulation_error,display_error, ...
        regulation_error<=5,display_error<=2}; %#ok<AGROW>
end
check=cell2table(rows,'VariableNames',{'set_A','cycle_mean_true_A','display_min_A','display_max_A', ...
    'cycle_mean_control_error_percent','worst_display_error_percent','pass_control_5percent','pass_display_2percent'});
writetable(check,fullfile(folder,'结果','基本14_开关波形采样与显示复核.csv'),'Encoding','UTF-8');
save(fullfile(folder,'结果','开关电流测量复核.mat'),'check','waves','p','hw','-v7.3');
assert(all(check.pass_control_5percent) && all(check.pass_display_2percent),'Switch-wave current/display check failed');
path=fullfile(folder,'结果','指标摘要.json');summary=jsondecode(fileread(path));
summary.current_switching_mean_error_percent=max(check.cycle_mean_control_error_percent);
summary.display_switching_error_percent=max(check.worst_display_error_percent);
f=fopen(path,'w','n','UTF-8');fprintf(f,'%s',jsonencode(summary,PrettyPrint=true));fclose(f);
disp(check);fprintf('SWITCH_WAVE_CURRENT_DISPLAY_OK\n');
end
