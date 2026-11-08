function [base,choices]=comparison_setup()
% Fixed comparison definitions; controls share the same circuit and guards.
base=struct('name','','kind','steady','duration',0.40,'mode',1, ...
    'current',2,'bus',30,'battery',18,'initial_bus',30,'load',30,'switched',false);
choices=struct();
choices.current_pi=struct('kind','current_pi');
choices.voltage_pi=struct('kind','voltage_pi','voltage_kp',single(0.01),'voltage_ki',single(0.3));
choices.hysteresis=struct('kind','hysteresis','band',single(0.15));
end
