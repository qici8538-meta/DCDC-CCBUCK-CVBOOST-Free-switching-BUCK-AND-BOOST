"""Verify this delivery against real build logs, IOC, generated code and frozen baseline."""
from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as ET
here=Path(__file__).resolve().parent
sim=here.parent; root=sim.parent; fw=root/"BUCKG474VET6_2"
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
baseline=digest(root/"BUCKG474VET6-v1.zip")
assert baseline=="36AE2BE2309EECD10FFC11704B263FD11C52101B7A472AFD2E483142E013D583"
matches={p.name:digest(p)==digest(fw/"Core/Generated"/p.name) for p in (sim/"生成代码").iterdir() if p.suffix in (".c",".h")}
assert matches and all(matches.values())
project=fw/"MDK-ARM/BUCKG474VET6.uvprojx"
sources=[(project.parent/n.text).resolve() for n in ET.parse(project).findall(".//FilePath")]
assert sources and all(p.is_file() for p in sources)
assert not any(p.name in ("pid.c","app_bluetooth.c") for p in sources)
build=(here/"Keil构建日志.txt").read_bytes().decode("utf-8",errors="replace")
assert re.search(r"0 Error\(s\),\s*0 Warning\(s\)",build)
axf=fw/"MDK-ARM/BUCKG474VET6/BUCKG474VET6.axf"; hexfile=axf.with_suffix(".hex")
latest=max(p.stat().st_mtime_ns for p in sources+list((fw/"Core").rglob("*.h")))
assert min(axf.stat().st_mtime_ns,hexfile.stat().st_mtime_ns)>=latest
ioc=dict(line.split("=",1) for line in (fw/"BUCKG474VET6.ioc").read_text().splitlines() if "=" in line)
assert ioc["ADC1.NbrOfConversion"]=="4"
assert ioc["PC0.Signal"]=="ADC1_IN6" and ioc["PC0.GPIO_Label"]=="SAMPLE_REF"
assert ioc["SPI1.DataSize"]=="SPI_DATASIZE_8BIT"
for index,channel in enumerate((1,6,2,7),2):
    suffix=str(index)+chr(92)+"#ChannelRegularConversion"
    assert ioc["ADC1.Channel-"+suffix]=="ADC_CHANNEL_"+str(channel)
    assert ioc["ADC1.Rank-"+suffix]==str(index-1)
adc=(fw/"Core/Src/adc.c").read_text(encoding="utf-8-sig")
assert "NbrOfConversion = 4" in adc and "ADC_REGULAR_RANK_4" in adc
assert "SAMPLE_REF_Pin|SAMPLE_VBUS_Pin" in adc
wrapper=(fw/"Core/Src/app_adc.c").read_text(encoding="utf-8-sig")
assert "next.raw[3] = adc_dma_buffer[1]" in wrapper and "next.raw[1] = adc_dma_buffer[2]" in wrapper
assert "(float)next.raw[0] - (float)next.raw[3] - ADC_CURRENT_OFFSET_RAW" in wrapper
assert "ADC_CURRENT_ZERO_RAW" not in (fw/"Core/Inc/adc_calibration.h").read_text(encoding="utf-8-sig")
native=json.loads((sim/"结果/生成C一致性验证.json").read_text(encoding="utf-8-sig"))
assert native["passed"] and native["samples"]==20000
matlab=(here/"AUTO2突变MATLAB验证日志.txt").read_text(encoding="utf-8-sig",errors="replace")
for marker in ("MATLAB_SIMULATION_OK","SWITCH_WAVE_CURRENT_DISPLAY_OK","C_GENERATION_OK","NATIVE_C_EQUIVALENCE","ALL_OFFLINE_CHECKS_OK"):
    assert marker in matlab,marker
assert "LIVE_REF_ADC_NATIVE_OK" in (here/"ADC换算验证日志.txt").read_text(encoding="utf-8-sig")
cube=(here/"CubeMX四路生成日志.txt").read_text(encoding="utf-8-sig",errors="replace")
assert "Generated code:" in cube and "Bye bye" in cube
transient=json.loads((sim/"结果/AUTO2_突变验收.json").read_text(encoding="utf-8-sig"))
assert transient["nominal_all_pass"]
settings=(fw/"Core/Inc/control_settings.h").read_text(encoding="utf-8-sig")
for field,value in transient["gains"].items():
    if field=="sample_time": continue
    macro="DCDC_"+field.upper()
    actual=float(re.search(r"#define\s+"+macro+r"\s+([-+0-9.eE]+)f",settings).group(1))
    assert abs(actual-value)<1e-5,macro
assert "AUTO2_FINAL_REGRESSION_OK" in matlab
result=dict(auto2_transient=transient,archive_sha256=baseline,archive_unchanged=True,generated_C_and_headers_match=matches,
    project_source_paths_exist=True,matlab_final_log_success=True,hardware_flashed=False,
    axf_sha256=digest(axf),hex_sha256=digest(hexfile),keil_errors=0,keil_warnings=0,
    binary_newer_than_sources=True,scope=dict(basic=[1,2,3,4,5],advanced=[1,2]),
    physical_efficiency_measured=False,bench_ADC_calibration_performed=False,
    adc_channels=4,adc_scan_order=["PA0 I","PC0 REF","PA1 VBAT","PC1 VBUS"],
    feedback_raw_order=["I","VBAT","VBUS","REF"],live_REF_subtraction=True,
    nominal_current_scale_A_per_V=2.017,nominal_voltage_ratio=15,
    INA213_input_resistor_each_ohm=10,cubemx_generation_verified=True,
    matlab_log="AUTO2突变MATLAB验证日志.txt",
    firmware_sources={name:digest(fw/name) for name in ("BUCKG474VET6.ioc","Core/Src/adc.c","Core/Src/app_adc.c","Core/Src/app_control.c","Core/Inc/adc_calibration.h","Core/Inc/control_settings.h")})
(here/"交付校验.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
print("FINAL_DELIVERY_CHECK_OK: 4-channel CubeMX + live REF + current AXF/HEX, 0 errors/0 warnings; frozen ZIP unchanged.")

