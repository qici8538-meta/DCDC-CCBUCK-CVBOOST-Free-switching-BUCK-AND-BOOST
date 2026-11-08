function run_scheme_comparison()
% Reproduce decision evidence ONLY. Human-owned firmware defaults are not
% changed by candidate scores; run_all generates the currently chosen kernel.
folder=fileparts(mfilename('fullpath'));
addpath(folder,fullfile(folder,'程序'),fullfile(folder,'方案对比'));
fprintf('Scope: basic (1) through (5), advanced (1)(2).\n');
tune_candidates();
run_comparison();
compare_frequency();
compare_measurement();
refresh_reading_material();
fprintf('SCHEME_DECISION_EVIDENCE_OK. See 00_重点看/方案决策说明.pdf.\n');
fprintf('No alternative-controller selector or candidate state is copied to firmware.\n');
end
