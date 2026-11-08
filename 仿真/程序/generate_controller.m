function generate_controller()
% Run after run_simulations. Actual MATLAB Coder output, never handwritten C.
folder = fileparts(fileparts(mfilename('fullpath')));
addpath(folder,fullfile(folder,'程序'));
[p, ~] = dcdc_parameters();
s = dcdc_initial_state();
cfg = coder.config('lib');
cfg.GenCodeOnly = true;
cfg.TargetLang = 'C';
cfg.GenerateReport = false;
cfg.HardwareImplementation.ProdHWDeviceType = 'ARM Compatible->ARM Cortex-M';
cfg.EnableDynamicMemoryAllocation = false;
cfg.PreserveVariableNames = 'All';
cfg.FilePartitionMethod = 'SingleFile';
cfg.GenerateExampleMain = 'DoNotGenerate';
out = fullfile(folder, '生成代码');
% LCC does not accept a build directory containing spaces without 8dot3.
% Keep its build workspace in the OS temp area, deliver every result here.
builddir=fullfile(tempdir,'DCDC_2015A_codegen');
codegen('-config', cfg, 'dcdc_step', '-args', ...
    {uint8(0), single(2), single(30), single(0), single(18), single(30), s, p}, '-d', builddir);
if ~exist(out,'dir'), mkdir(out); end
copyfile(fullfile(builddir,'*.c'),out);
copyfile(fullfile(builddir,'*.h'),out);
save(fullfile(out, 'generation_parameters.mat'), 'p');
fprintf('C_GENERATION_OK: %s\n', out);
end
