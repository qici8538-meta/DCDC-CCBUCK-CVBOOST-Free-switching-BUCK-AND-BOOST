function run_all()
% One entry point: simulate, generate, compile/compare C, estimate, then copy C.
folder=fileparts(mfilename('fullpath'));
addpath(folder,fullfile(folder,'程序'),fullfile(folder,'方案对比'));
run_simulations();
verify_auto2_transient();
compare_measurement();
verify_current_display();
generate_controller();
verify_generated_code();
estimate_efficiency();
destination=fullfile(folder,'..','BUCKG474VET6_2','Core','Generated');
if ~exist(destination,'dir'), mkdir(destination); end
copyfile(fullfile(folder,'生成代码','*.c'),destination);
copyfile(fullfile(folder,'生成代码','*.h'),destination);
refresh_reading_material();
fprintf('ALL_OFFLINE_CHECKS_OK; generated C copied to Core/Generated.\n');
fprintf('Build with Keil; firmware is not flashed by this script.\n');
end
