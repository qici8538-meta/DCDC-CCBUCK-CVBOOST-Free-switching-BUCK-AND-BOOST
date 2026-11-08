function tune_candidates()
folder=fileparts(mfilename('fullpath'));root=fileparts(folder);
addpath(folder,root,fullfile(root,'程序'));
out=fullfile(folder,'结果'); if ~isfolder(out),mkdir(out);end
[p,hw]=dcdc_parameters(); [base,choices]=comparison_setup();
selected=p;
% Historical PI-only search remains a comparator, not the delivered default.
p.current_lead_time=single(0);p.current_ff_inductance=single(0);
% Give the structurally different single-loop controller its OWN tuning.
rows={}; best_score=Inf; best=choices.voltage_pi;
for kp=[0.004 0.008 0.012 0.020]
    for ki=[0.06 0.20 0.60]
        choice=choices.voltage_pi; choice.voltage_kp=single(kp); choice.voltage_ki=single(ki);
        c=base; c.mode=2; c.bus=NaN; c.initial_bus=18; c.duration=0.65;
        c.name='single_voltage_tune'; c=apply_candidate(c,choice);
        r=simulate_case(c,p,hw); valid=r.t>0.35;
        error=max(abs(r.data(valid,1)-30)); fault=max(r.data(:,8));
        settling=settling_time(r.t,r.data(:,1)-30,0.5);
        score=error+10*settling+1000*(fault~=0);
        rows(end+1,:)={kp,ki,error,settling,r.inductor_peak_A,fault,score}; %#ok<AGROW>
        if score<best_score, best_score=score;best=choice;end
    end
end
voltage_tuning=cell2table(rows,'VariableNames',{'Kp_duty_per_V','Ki_duty_per_Vs', ...
    'steady_max_error_V','settling_s','inductor_peak_A','fault','score'});
writetable(voltage_tuning,fullfile(out,'电压单环独立整定.csv'),'Encoding','UTF-8');
% Search a bounded set for cascade transient response. All gains retain SI
% units. The later comparison and tolerance checks decide whether to adopt.
grid=[.030 12 .35 35 100; .030 12 .50 50 300; .040 16 .50 50 500; ...
    .040 16 .70 70 1000; .050 20 .70 70 1000; .050 25 1.0 100 2000; ...
    .060 30 1.0 100 3000; .040 16 1.2 120 3000];
rows={}; best_score=Inf; best_p=p;
for k=1:size(grid,1)
    local=p; local.current_kp=single(grid(k,1));local.current_ki=single(grid(k,2));
    local.voltage_kp=single(grid(k,3));local.voltage_ki=single(grid(k,4));local.current_slew=single(grid(k,5));
    c=base; c.mode=3;c.bus=NaN;c.initial_bus=18;c.duration=1.0;c.kind='auto_step';c.name='cascade_tune';
    r=simulate_case(c,local,hw);valid=r.t>0.22;
    error=max(abs(r.data(valid,1)-30));fault=max(r.data(:,8));
    score=error+1000*(fault~=0)+0.05*max(0,r.inductor_peak_A-2.8);
    rows(end+1,:)={grid(k,1),grid(k,2),grid(k,3),grid(k,4),grid(k,5), ...
        error,r.inductor_peak_A,fault,score}; %#ok<AGROW>
    if score<best_score,best_score=score;best_p=local;end
end
cascade_tuning=cell2table(rows,'VariableNames',{'I_Kp','I_Ki','V_Kp','V_Ki', ...
    'current_slew_Aps','auto_step_error_V','inductor_peak_A','fault','score'});
writetable(cascade_tuning,fullfile(out,'双环动态整定.csv'),'Encoding','UTF-8');
% Hysteresis is also tuned separately, rather than assuming one dead band.
rows={};best_score=Inf;best_h=choices.hysteresis;
for band=[.05 .10 .15 .20]
    h=choices.hysteresis;h.band=single(band);
    c=base;c.mode=3;c.bus=NaN;c.initial_bus=18;c.duration=1.5;c.kind='automatic';c.name='hysteresis_tune';
    c=apply_candidate(c,h);r=simulate_case(c,selected,hw);valid=r.t>0.22;
    error=max(abs(r.data(valid,1)-30));fault=max(r.data(:,8));
    transitions=sum(diff(double(r.controller_mode))~=0);
    score=error+1000*(fault~=0)+0.00001*transitions;
    rows(end+1,:)={band,error,r.inductor_peak_A,fault,transitions,score}; %#ok<AGROW>
    if score<best_score,best_score=score;best_h=h;end
end
hysteresis_tuning=cell2table(rows,'VariableNames',{'half_band_V','auto_ramp_error_V', ...
    'inductor_peak_A','fault','mode_changes','score'});
writetable(hysteresis_tuning,fullfile(out,'阈值模式独立整定.csv'),'Encoding','UTF-8');
save(fullfile(out,'候选整定.mat'),'best','best_p','best_h','voltage_tuning','cascade_tuning','hysteresis_tuning');
disp(voltage_tuning);disp(cascade_tuning);disp(hysteresis_tuning);
fprintf('CANDIDATE_TUNING_OK\n');
end

function t=settling_time(time,error,limit)
k=find(abs(error)>limit,1,'last');
if isempty(k),t=0;elseif k==numel(time),t=2;else,t=time(k+1);end
end
