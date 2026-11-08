function verify_auto2_transient()
% Acceptance of the DELIVERED defaults; no hidden gain changes in this test.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'程序'));
out=fullfile(root,'结果');[p,hw]=dcdc_parameters();[base,~]=comparison_setup();
base.mode=3;base.bus=NaN;base.initial_bus=18;base.duration=1;base.kind='auto_step';
base.measure_start_s=.22;base.source_steps=[0 32;.25 38;.65 32];base.hardware_timing=true;
rows={};traces=struct();
for test=1:4
 q=p;c=base;
 if test==1
  name='旧AUTO2';q.current_kp=single(.04);q.current_ki=single(16);
  q.voltage_kp=single(1.2);q.voltage_ki=single(120);q.current_slew=single(3000);
  q.current_lead_time=single(0);q.current_ff_inductance=single(0);
 elseif test==2
  name='仅提高PI';q.current_lead_time=single(0);q.current_ff_inductance=single(0);
 elseif test==3
  name='偏激外环候选';q.voltage_kp=single(14);
 else,name='所选AUTO2';end
 c.name=name;r=simulate_case(c,q,hw);traces.(sprintf('scheme%d',test))=r;
 rows(end+1,:)=metric(name,r,q,hw,false); %#ok<AGROW>
 fprintf('AUTO2_PROPOSAL %d %s min %.6f max %.6f fault %d\n',test,name,r.bus_min_V,r.bus_max_V,max(r.data(:,8)));
end
proposals=cell2table(rows,'VariableNames',columns());
writetable(proposals,fullfile(out,'AUTO2_突变方案比较.csv'),'Encoding','UTF-8');

% Independent L/C corners, battery range, and exact input-event PWM phases.
rows={};worst_error=-Inf;worst_case=base;
for eb=[15.5 18 21]
 for lm=[.8 1 1.2]
  for cm=[.8 1 1.2]
   c=base;c.battery=eb;c.initial_bus=eb;c.name=sprintf('Eb%g_L%g_C%g',eb,lm,cm);
   h=hw;h.L=hw.L*lm;h.Cbat=hw.Cbat*cm;h.Cbus=hw.Cbus*cm;
   r=simulate_case(c,p,h);rows(end+1,:)=metric(c.name,r,p,h,false); %#ok<AGROW>
   err=max(abs([r.bus_min_V,r.bus_max_V]-30));
   if err>worst_error,worst_error=err;worst_case=c;worst_hw=h;end
   fprintf('AUTO2_CORNER %s error %.6f fault %d\n',c.name,err,max(r.data(:,8)));
  end
 end
end
corners=cell2table(rows,'VariableNames',columns());
writetable(corners,fullfile(out,'AUTO2_突变容差检查.csv'),'Encoding','UTF-8');

% Full switch waveform, including all numerical integration points and ADC
% ranks/IRQ/CCR preload timing. Check both source-step directions and phases.
rows={};selected=[];
for test=1:4
 c=base;h=hw;c.switched=true;
 if test==1,c.name='标称_相位0';phase=0;
 elseif test==2,c.name='标称_相位半周期';phase=hw.Ts/2;
 elseif test==3,c.name='标称_相位四分之一周期';phase=hw.Ts/4;
 else,c=worst_case;h=worst_hw;c.switched=true;c.name='平均模型最差角_开关复核';phase=0;end
 c.source_steps=[0 32;.25+phase 38;.65+phase 32];
 c.capture_windows_s=[.247 .258;.647 .658];
 r=simulate_case(c,p,h);rows(end+1,:)=metric(c.name,r,p,h,true); %#ok<AGROW>
 if test==1,selected=r;end
 fprintf('AUTO2_SWITCH %s min %.6f max %.6f error %.6f fault %d\n',c.name,r.bus_min_V,r.bus_max_V,max(abs([r.bus_min_V,r.bus_max_V]-30)),max(r.data(:,8)));
end
switches=cell2table(rows,'VariableNames',columns());
writetable(switches,fullfile(out,'AUTO2_突变开关与相位检查.csv'),'Encoding','UTF-8');
summary=struct('gains',p,'hardware_timing',true,'source_step_V',[32 38 32], ...
 'nominal_min_V',min(switches.min_bus_V(1:3)),'nominal_max_V',max(switches.max_bus_V(1:3)), ...
 'nominal_max_error_V',max(switches.max_error_V(1:3)), ...
 'nominal_all_pass',all(switches.pass(1:3)), ...
 'nominal_max_settled_current_std_A',max(switches.settled_current_std_A(1:3)), ...
 'nominal_max_settled_ref_std_A',max(switches.settled_ref_std_A(1:3)), ...
 'corner_all_pass',all(corners.pass),'corner_max_error_V',max(corners.max_error_V), ...
 'worst_corner_switch_pass',switches.pass(4),'worst_corner_switch_error_V',switches.max_error_V(4), ...
 'baseline_error_V',proposals.max_error_V(1),'PI_only_error_V',proposals.max_error_V(2), ...
 'rejected_Kpv14_current_std_A',proposals.settled_current_std_A(3), ...
 'rejected_Kpv14_ref_std_A',proposals.settled_ref_std_A(3), ...
 'all_ADC_inputs_quantized',true,'hardware_flashed',false);
f=fopen(fullfile(out,'AUTO2_突变验收.json'),'w','n','UTF-8');fprintf(f,'%s',jsonencode(summary,PrettyPrint=true));fclose(f);
save(fullfile(out,'AUTO2_突变验证.mat'),'traces','selected','p','hw','proposals','corners','switches','summary','-v7.3');
draw_result(traces.scheme1,selected,out);
assert(summary.nominal_all_pass,'Delivered AUTO2 fails nominal hardware-timing switch/phase tests');
fprintf('AUTO2_TRANSIENT_VERIFIED: nominal_max_error=%.6f V, corners_all_pass=%d\n',summary.nominal_max_error_V,summary.corner_all_pass);
end

function v=metric(name,r,p,hw,sw)
err=max(abs([r.bus_min_V,r.bus_max_V]-30));valid=r.t>=.22;fault=max(r.data(:,8));
settled=r.t>=r.settings.duration-.1;
current_std=std(r.data(settled,3));reference_std=std(r.data(settled,5));
v={name,r.settings.battery,hw.L,hw.Cbat,hw.Cbus,sw,r.bus_min_V,r.bus_max_V,err, ...
 min(r.data(valid,3)),max(r.data(valid,3)),r.inductor_peak_A,fault,err<=.5 && fault==0 && current_std<.1 && reference_std<.2, ...
 double(p.current_kp),double(p.current_ki),double(p.voltage_kp),double(p.voltage_ki), ...
 double(p.current_slew),double(p.current_lead_time),double(p.current_ff_inductance),current_std,reference_std};
end

function names=columns()
names={'case','battery_V','L_H','Cbat_F','Cbus_F','switched','min_bus_V','max_bus_V', ...
 'max_error_V','min_battery_A','max_battery_A','inductor_peak_A','fault','pass', ...
 'I_Kp','I_Ki','V_Kp','V_Ki','current_slew_Aps','current_lead_time_s','current_ff_inductance_H', ...
 'settled_current_std_A','settled_ref_std_A'};
end

function draw_result(old,r,out)
set(groot,'defaultFigureVisible','off');
f=figure('Color','w','Position',[100 100 1400 1050]);tiledlayout(3,2,'TileSpacing','compact');
nexttile;stairs(r.t,r.data(:,9),'LineWidth',1.2);grid on;xlim([.22 .85]);ylabel('Us / V');title('32 -> 38 -> 32 V, ideal steps');
nexttile;plot(old.t,old.data(:,1),r.t,r.data(:,1),'LineWidth',1);hold on;yline(29.5,'--');yline(30.5,'--');grid on;xlim([.22 .85]);ylabel('U2 / V');legend('Old AUTO2 (averaged)','Selected AUTO2 (switching)','Location','best');
for edge=[.25 .65]
 nexttile;a=r.fast(:,1)>=edge-.001 & r.fast(:,1)<=edge+.006;
 plot((r.fast(a,1)-edge)*1000,r.fast(a,2),'LineWidth',1);hold on;yline(29.5,'--');yline(30.5,'--');ylim([29.35 30.65]);grid on;
 xlabel('Time from source step / ms');ylabel('Actual U2 / V');title(sprintf('Switching waveform, t=%.2f s',edge));
end
nexttile;plot(r.t,r.data(:,3:5));grid on;xlim([.22 .85]);ylabel('Current / A');xlabel('Time / s');legend('Battery branch','Inductor','Reference','Location','best');
nexttile;plot(r.t,r.data(:,6));grid on;xlim([.22 .85]);ylabel('High-side duty / %');xlabel('Time / s');title(sprintf('U2 range %.4f .. %.4f V',r.bus_min_V,r.bus_max_V));
exportgraphics(f,fullfile(out,'AUTO2_32至38V突变.png'),'Resolution',150);savefig(f,fullfile(out,'AUTO2_32至38V突变.fig'));close(f);
end
