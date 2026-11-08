function compare_measurement()
% Basic (4): physical ADC -> identical firmware IIR -> LCD 0.01-A rounding.
% Compare fixed nominal zero with live REF subtraction + two-point calibration.
folder=fileparts(mfilename('fullpath'));root=fileparts(folder);
addpath(folder,root,fullfile(root,'程序'));out=fullfile(folder,'结果');
[~,hw]=dcdc_parameters();rng(201504);
% Illustrative static tolerance corners, NOT measured component bounds.
% [shunt ratio, amplifier ratio, REF voltage change, ADC Vref ratio]
corners=[1 1 0 1; .95 .99 .020 1.005;1.05 1.01 -.020 .995;1.03 .995 .010 1.007];
rows={};parameters={};drift_rows={};traces=struct();
for corner=1:size(corners,1)
    actual=hw;actual.shunt=hw.shunt*corners(corner,1);actual.current_gain=hw.current_gain*corners(corner,2);
    actual.current_zero=hw.current_zero+corners(corner,3);actual.adc_reference=hw.adc_reference*corners(corner,4);
    % Calibration uses averaged counts at true 0 A and true 2 A. 0.1%
    % reference-meter error is included rather than using perfect knowledge.
    [i0,r0]=sensor(zeros(8000,1),actual);[i2,r2]=sensor(2*ones(8000,1),actual);
    zero=mean(i0);ref_zero=mean(r0);at_two=mean(i2);ref_two=mean(r2);
    meter_current=2*(1+(-1)^corner*.001);
    [n0,gain]=calibrate_current(zero,ref_zero,at_two,ref_two,meter_current,hw.adc_reference);
    parameters(end+1,:)={corner,corners(corner,1),corners(corner,2),corners(corner,3), ...
        corners(corner,4),n0,gain}; %#ok<AGROW>
    for setting=10:20
        true_current=setting/10;
        % Same raw sequence for both methods. Three ADC-count RMS noise and
        % smooth +/-2-count INL are assumptions, not a measured noise claim.
        [raw,reference_raw]=sensor(true_current*ones(12000,1),actual);
        for scheme=1:2
            if scheme==1
                measured=(double(raw)-hw.current_zero/hw.adc_reference*hw.adc_counts)*hw.adc_reference/hw.adc_counts*2;
            else
                measured=(double(raw)-double(reference_raw)-n0)*hw.adc_reference/hw.adc_counts*gain;
            end
            filtered=filter(hw.current_filter_alpha,[1 -(1-hw.current_filter_alpha)],measured);
            valid=(4001:12000)';
            % 100-ms LCD refresh at arbitrary phase. Evaluate every settled
            % frame's rounded value, a conservative bound on display phase.
            display=round(filtered(valid)*100)/100;
            max_error=max(abs(display-true_current))/true_current*100;
            mean_error=abs(mean(filtered(valid))-true_current)/true_current*100;
            % LCD decimal values can produce 2.000000000000002 in binary arithmetic.
            rows(end+1,:)={corner,scheme,true_current,mean_error,max_error,max_error<=2+1e-9}; %#ok<AGROW>
        end
    end
    % Residual REF drift AFTER calibration is a separate sensitivity check.
    for delta=[0 .010 .030]
        drifting=actual;drifting.current_zero=actual.current_zero+delta/3;
        [raw,reference_raw]=sensor(ones(12000,1),drifting);
        measured=(double(raw)-double(reference_raw)-n0)*hw.adc_reference/hw.adc_counts*gain;
        filtered=filter(hw.current_filter_alpha,[1 -(1-hw.current_filter_alpha)],measured);
        shown=round(filtered(4001:end)*100)/100;
        drift_rows(end+1,:)={corner,delta,abs(mean(filtered(4001:end))-1)*100, ...
            max(abs(shown-1))*100}; %#ok<AGROW>
    end
end
accuracy=cell2table(rows,'VariableNames',{'corner','scheme','true_A','mean_conversion_error_percent', ...
    'worst_display_error_percent','pass_2percent'});
calibration=cell2table(parameters,'VariableNames',{'corner','shunt_ratio','INA_gain_ratio','REF_offset_V', ...
    'ADC_reference_ratio','calibrated_I_minus_REF_offset_raw','calibrated_A_per_pin_V'});
drift=cell2table(drift_rows,'VariableNames',{'corner','postcal_5V_change_V','mean_error_at1A_percent','worst_display_error_percent'});
writetable(accuracy,fullfile(out,'基本4_名义系数与两点标定.csv'),'Encoding','UTF-8');
writetable(calibration,fullfile(out,'基本4_仿真标定数据_非实测.csv'),'Encoding','UTF-8');
writetable(drift,fullfile(out,'基本4_标定后5V漂移敏感性.csv'),'Encoding','UTF-8');
summary=table((1:2)',zeros(2,1),zeros(2,1),'VariableNames',{'scheme','max_mean_error_percent','max_display_error_percent'});
for k=1:2
    keep=accuracy.scheme==k;
    summary.max_mean_error_percent(k)=max(accuracy.mean_conversion_error_percent(keep));
    summary.max_display_error_percent(k)=max(accuracy.worst_display_error_percent(keep));
end
assert(summary.max_display_error_percent(2)<=2+1e-9,'Calibrated measurement did not pass assumed corners.');
writetable(summary,fullfile(out,'基本4_两方案摘要.csv'),'Encoding','UTF-8');
save(fullfile(out,'电流测量方案对比.mat'),'accuracy','calibration','drift','summary','corners','hw','traces');
set(groot,'defaultFigureVisible','off');f=figure('Color','w','Position',[100 100 1100 700]);
tiledlayout(2,1,'TileSpacing','compact');
nexttile;hold on;
for scheme=1:2
    a=accuracy(accuracy.scheme==scheme,:);values=zeros(11,1);
    for k=10:20,values(k-9)=max(a.worst_display_error_percent(a.true_A==k/10));end
    plot(1:.1:2,values,'-o','LineWidth',1.2);
end
yline(2,'--');grid on;ylabel('Worst display error / %');xlabel('True branch current / A');
legend('Fixed nominal zero','Live REF + two-point calibration','2%');title('Assumed tolerance corners, ADC noise/INL, IIR and 0.01-A LCD rounding');
nexttile;hold on;
for corner=1:size(corners,1)
    a=drift(drift.corner==corner,:);plot(a.postcal_5V_change_V*1000,a.worst_display_error_percent,'-o');
end
yline(2,'--');grid on;ylabel('Worst display error at 1 A / %');xlabel('5-V supply change AFTER calibration / mV');
exportgraphics(f,fullfile(out,'基本4_测量与显示精度对比.png'),'Resolution',150);savefig(f,fullfile(out,'基本4_测量与显示精度对比.fig'));close(f);
disp(summary);disp(drift);fprintf('CURRENT_MEASUREMENT_COMPARISON_OK; synthetic calibration is not bench calibration.\n');
end

function [raw,reference_raw]=sensor(current,hw)
pin=hw.current_zero+hw.shunt*hw.current_gain*hw.current_gain_factor*current;
ideal=pin/hw.adc_reference*hw.adc_counts;
inl=2*sin(ideal/350);
raw=round(min(max(ideal+inl+3*randn(size(current)),0),hw.adc_counts));
reference=hw.current_zero/hw.adc_reference*hw.adc_counts;
reference_raw=round(min(max(reference+2*sin(reference/350)+3*randn(size(current)),0),hw.adc_counts));
end
