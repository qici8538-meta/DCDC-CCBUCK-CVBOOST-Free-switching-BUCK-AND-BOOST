function verify_generated_code()
% Compile the DELIVERED C as a native executable and compare with MATLAB.
folder=fileparts(fileparts(mfilename('fullpath')));
addpath(folder,fullfile(folder,'程序'));
builddir=fullfile(tempdir,'DCDC_2015A_native_check');
if ~exist(builddir,'dir'), mkdir(builddir); end
copyfile(fullfile(folder,'生成代码','*.c'),builddir);
copyfile(fullfile(folder,'生成代码','*.h'),builddir);
copyfile(fullfile(folder,'程序','verify_generated_native.c'),builddir);
[p,~]=dcdc_parameters();
rng(474);
n=20000;
inputs=single(zeros(n,7));
inputs(:,1)=mod(floor((0:n-1)'/1000),4);
inputs(:,2)=single(1+rand(n,1));
inputs(:,3)=30;
inputs(:,4)=single(2*sin((1:n)'/123));
inputs(:,5)=single(18+0.3*sin((1:n)'/991));
inputs(:,6)=single(30+2*sin((1:n)'/215));
inputs(1:400:end,7)=1;
inputs(1101,5)=24.1; inputs(2301,5)=14.8;
inputs(3201,4)=2.81; inputs(4201,4)=-2.81;
inputs(5101,6)=39.2; inputs(6101,2)=NaN; inputs(7201,6)=Inf;
expected=zeros(n,9,'single'); s=dcdc_initial_state();
for k=1:n
    if inputs(k,7)~=0, s=dcdc_initial_state(); end
    [d,en,s]=dcdc_step(uint8(inputs(k,1)),inputs(k,2),inputs(k,3),inputs(k,4),inputs(k,5),inputs(k,6),s,p);
    expected(k,:)=[d single(en) single(s.fault) single(s.mode) ...
        s.current_integral s.voltage_integral s.current_reference s.voltage_reference s.previous_current];
end
f=fopen(fullfile(builddir,'inputs.bin'),'wb'); fwrite(f,inputs.','single'); fclose(f);
names=fieldnames(p); values=zeros(numel(names),1,'single');
for k=1:numel(names), values(k)=p.(names{k}); end
f=fopen(fullfile(builddir,'params.bin'),'wb'); fwrite(f,values,'single'); fclose(f);
lcc=fullfile(matlabroot,'sys','lcc64','lcc64');
names={'verify_generated_native','dcdc_step','rt_nonfinite','rtGetInf','rtGetNaN'};
old=pwd; cleanup=onCleanup(@() cd(old)); cd(builddir);
for k=1:numel(names)
    command=sprintf('"%s" -c -noregistrylookup -I"%s" -Fo"%s.obj" "%s.c"', ...
        fullfile(lcc,'bin','lcc64.exe'),fullfile(lcc,'include64'),names{k},names{k});
    [status,log]=system(command); fprintf('%s',log); assert(status==0,'Native C compilation failed');
end
objects=strjoin(strcat(names,'.obj'),' ');
command=sprintf('"%s" -L"%s" -o verify_generated_native.exe %s', ...
    fullfile(lcc,'bin','lcclnk64.exe'),fullfile(lcc,'lib64'),objects);
[status,log]=system(command); fprintf('%s',log); assert(status==0,'Native C link failed');
[status,log]=system('verify_generated_native.exe inputs.bin params.bin outputs.bin');
fprintf('%s',log); assert(status==0,'Native C execution failed');
f=fopen('outputs.bin','rb'); actual=fread(f,[9 n],'*single').'; fclose(f);
assert(isequal(size(actual),size(expected)),'Output size mismatch');
error=max(abs(double(actual)-double(expected)),[],'all');
state_equal=isequal(actual(:,2:4),expected(:,2:4));
fprintf('NATIVE_C_EQUIVALENCE: samples=%d max_abs_error=%.9g state_equal=%d\n',n,error,state_equal);
assert(error<3e-5 && state_equal,'Generated C differs from MATLAB');
result=struct('samples',n,'max_absolute_error',error,'states_equal',state_equal,'passed',true);
f=fopen(fullfile(folder,'结果','生成C一致性验证.json'),'w','n','UTF-8');
fprintf(f,'%s',jsonencode(result,PrettyPrint=true)); fclose(f);
end
