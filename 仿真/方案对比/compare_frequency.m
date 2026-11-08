function compare_frequency()
% Basic (3) / advanced (1): charge/discharge efficiency, not measured eta.
folder=fileparts(mfilename('fullpath'));root=fileparts(folder);
addpath(folder,root,fullfile(root,'程序'));out=fullfile(folder,'结果');
[p,hw]=dcdc_parameters();[base,~]=comparison_setup();rows={};loss_rows={};runs=cell(2,3);
for k=1:2
    local=hw;local.pwm_arr=round(4249/k);local.pwm_frequency=170e6/(2*local.pwm_arr);
    local.Ts=1/local.pwm_frequency;local.current_filter_alpha=1-exp(-2*pi*2000*local.Ts/2);
    param=p;param.sample_time=single(local.Ts);
    for test=1:3
        c=base;c.switched=true;c.mode=1;c.duration=.40;c.name=sprintf('Frequency%d_test%d',k,test);
        if test==1,c.bus=36;c.initial_bus=36;point='CC36_ripple';
        elseif test==2,c.mode=2;c.bus=NaN;c.initial_bus=18;point='CV30_efficiency';
        else,c.bus=30;c.initial_bus=30;point='CC30_efficiency';end
        r=simulate_case(c,param,local);runs{k,test}=r;f=r.fast;t=f(:,1);span=t(end)-t(1);
        w=@(signal) trapz(t,signal)/span;
        valid=r.t>.30;
        bus_error=NaN;if c.mode==2,bus_error=max(abs(r.data(valid,1)-30));end
        rows(end+1,:)={local.pwm_frequency,c.mode,mean(r.data(valid,3)),bus_error, ...
            max(f(:,5))-min(f(:,5)),r.inductor_peak_A,max(r.data(:,8)),local.pwm_arr,point}; %#ok<AGROW>
        if test~=1
            if c.mode==2
                input=-r.tail_battery_energy_J/r.tail_interval_s;
                output=w(f(:,2).^2/c.load);direction='discharge';required=95;
            else
                input=r.tail_bus_energy_J/r.tail_interval_s;
                output=r.tail_battery_energy_J/r.tail_interval_s;direction='charge';required=90;
            end
            model_loss=input-output;
            for trtf=[80 160 320]*1e-9
                for dcr=[.05 .15 .30]
                    for other=[.2 .8]
                        % A scenario calculation. Qg is the datasheet's
                        % 146 nC test-point value, not measured at this load.
                        gate=2*146e-9*10*local.pwm_frequency;
                        overlap=.5*w(f(:,2).*abs(f(:,5)))*trtf*local.pwm_frequency;
                        % The exam eta=P2/P1 uses the two MAIN DC ports.
                        % Gate energy from the independent auxiliary supply
                        % is reported separately, not charged to battery P1.
                        total=model_loss+(dcr-hw.inductor_resistance)*w(f(:,5).^2)+overlap+other;
                        eta=output/(output+total)*100;
                        with_gate=output/(output+total+gate)*100;
                        loss_rows(end+1,:)={local.pwm_frequency,dcr,trtf*1e9,other,model_loss,gate,overlap,total,eta,with_gate, ...
                            direction,input,output,required,eta>=required}; %#ok<AGROW>
                    end
                end
            end
        end
        fprintf('Frequency %.3f kHz %s complete\n',local.pwm_frequency/1000,point);
    end
end
frequency=cell2table(rows,'VariableNames',{'frequency_Hz','mode','battery_A','bus_max_error_V', ...
    'inductor_ripple_pp_A','inductor_peak_A','fault','PWM_ARR','operating_point'});
loss=cell2table(loss_rows,'VariableNames',{'frequency_Hz','L_DCR_ohm','transition_sum_ns', ...
    'other_port_loss_W','switch_model_loss_W','gate_from_aux_estimate_W','overlap_estimate_W', ...
    'port_loss_estimate_W','port_eta_estimate_percent','port_plus_gate_eta_percent', ...
    'direction','model_input_W','model_output_W','required_efficiency_percent','estimate_pass'});
writetable(frequency,fullfile(out,'发挥1_20k与40k开关仿真.csv'),'Encoding','UTF-8');
writetable(loss,fullfile(out,'发挥1_两频率损耗敏感性_非实测.csv'),'Encoding','UTF-8');
writetable(loss(strcmp(loss.direction,'charge'),:),fullfile(out,'基本3_两频率充电效率_非实测.csv'),'Encoding','UTF-8');
save(fullfile(out,'两频率仿真.mat'),'runs','frequency','loss','p','hw','-v7.3');
set(groot,'defaultFigureVisible','off');
f=figure('Color','w','Position',[100 100 1100 750]);tiledlayout(2,1,'TileSpacing','compact');
nexttile;
for k=1:2
    fast=runs{k,1}.fast;keep=fast(:,1)>fast(end,1)-.0003;
    plot((fast(keep,1)-fast(find(keep,1),1))*1e6,fast(keep,5),'LineWidth',1);hold on;
end
grid on;ylabel('iL / A');xlabel('Time / us');title('CC at bus 36 V, battery 18 V, 2 A');legend('20 kHz','40 kHz');
nexttile;
for k=1:2
    keep=abs(loss.frequency_Hz-170e6/(2*round(4249/k)))<1 & loss.L_DCR_ohm==.15 & ...
        loss.other_port_loss_W==.8 & strcmp(loss.direction,'discharge');
    plot(loss.transition_sum_ns(keep),loss.port_eta_estimate_percent(keep),'-o','LineWidth',1);hold on;
end
yline(95,'--');grid on;ylabel('Estimated efficiency / %');xlabel('Assumed tr+tf / ns');
title('Scenario only: DCR=0.15 ohm, other=0.8 W; switching times unmeasured');legend('20 kHz','40 kHz','95%');
exportgraphics(f,fullfile(out,'发挥1_频率与估计损耗.png'),'Resolution',150);savefig(f,fullfile(out,'发挥1_频率与估计损耗.fig'));close(f);
disp(frequency);
disp(loss(loss.L_DCR_ohm==.15 & loss.transition_sum_ns==160 & loss.other_port_loss_W==.8,:));
fprintf('FREQUENCY_COMPARISON_OK; no measured efficiency is claimed.\n');
end
