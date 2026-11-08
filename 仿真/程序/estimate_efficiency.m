function estimate_efficiency()
% Model calculation only. DCR, switching times and auxiliary losses UNMEASURED.
folder=fileparts(fileparts(mfilename('fullpath')));
data=load(fullfile(folder,'结果','全部仿真数据.mat'),'results','hw');
r=data.results.Switching_mode2;
fast=r.fast; t=fast(:,1); duration=t(end)-t(1);
weighted=@(signal) trapz(t,signal)/duration;
input_power=-r.tail_battery_energy_J/r.tail_interval_s;
output_power=weighted(fast(:,2).^2/r.settings.load);
inductor_ms=weighted(fast(:,5).^2);
model_loss=input_power-output_power;
rows={};
for dcr=[0.05 0.15 0.30 0.50]
    for unmodelled=[0.2 0.8]
        total=model_loss+(dcr-data.hw.inductor_resistance)*inductor_ms+unmodelled;
        efficiency=output_power/(output_power+total)*100;
        rows(end+1,:)={dcr,unmodelled,input_power,output_power,total,efficiency,efficiency>=95}; %#ok<AGROW>
    end
end
result=cell2table(rows,'VariableNames',{'assumed_L_DCR_ohm','assumed_other_loss_W', ...
    'switch_model_input_W','switch_model_output_W','estimated_total_loss_W','estimated_efficiency_percent','estimate_ge_95percent'});
writetable(result,fullfile(folder,'结果','效率估算_非实测.csv'),'Encoding','UTF-8');
disp(result);
fprintf('95%% loss budget at 30 W: %.6f W. No measured-efficiency claim.\n',30*(1/0.95-1));
end
