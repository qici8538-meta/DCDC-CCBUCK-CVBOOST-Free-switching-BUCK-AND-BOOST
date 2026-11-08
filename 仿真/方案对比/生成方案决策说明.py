"""Build the human decision report from ACTUAL CSV/JSON outputs, no simulations."""
from __future__ import annotations
import csv
import hashlib
import json
import math
import re
from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "方案对比" / "结果"
FW = ROOT.parent / "BUCKG474VET6_2"
BASELINE_HASH = "36AE2BE2309EECD10FFC11704B263FD11C52101B7A472AFD2E483142E013D583"


def read_csv(name):
    with (EVIDENCE / name).open(encoding="utf-8-sig", newline="") as file:
        return list(csv.DictReader(file))


def number(row, key):
    value = row[key]
    return float(value) if value else math.nan


def digest(path):
    return hashlib.file_digest(path.open("rb"), "sha256").hexdigest().upper()


def main():
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib import colors
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.enums import TA_LEFT
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Image

    cc = read_csv("基本1_两方案11档恒流.csv")
    line = read_csv("基本2_两方案输入变化率.csv")
    dynamic = read_csv("基本12_动态对比.csv")
    cv = read_csv("发挥1_单环与双环.csv")
    auto = read_csv("发挥2_阈值切换与连续双向.csv")
    freq = read_csv("发挥1_20k与40k开关仿真.csv")
    losses = read_csv("发挥1_两频率损耗敏感性_非实测.csv")
    tuning = read_csv("双环动态整定.csv")
    single_tuning = read_csv("电压单环独立整定.csv")
    hysteresis_tuning = read_csv("阈值模式独立整定.csv")
    measurement = read_csv("基本4_两方案摘要.csv")
    measurement_drift = read_csv("基本4_标定后5V漂移敏感性.csv")
    summary = json.loads((ROOT / "结果" / "指标摘要.json").read_text(encoding="utf-8-sig"))
    native = json.loads((ROOT / "结果" / "生成C一致性验证.json").read_text(encoding="utf-8-sig"))
    switch_display = list(csv.DictReader((ROOT / "结果" / "基本14_开关波形采样与显示复核.csv").open(encoding="utf-8-sig",newline="")))
    delivery = json.loads((ROOT / "归档与日志" / "交付校验.json").read_text(encoding="utf-8-sig"))
    baseline = digest(ROOT.parent / "BUCKG474VET6-v1.zip")
    assert baseline == BASELINE_HASH, "Frozen original ZIP changed"
    assert native["passed"] and delivery["keil_errors"] == 0 and delivery["keil_warnings"] == 0

    cc_max = {s: max(number(r, "error_percent") for r in cc if r["scheme"] == s) for s in ("CC1", "CC2")}
    pick = lambda records, scheme, test: next(r for r in records if r["scheme"] == scheme and int(r["test"]) == test)
    ccl = {r["scheme"]: r for r in line}
    ccd = {r["scheme"]: r for r in dynamic if r["test"] == "line_step"}
    fc = sorted([r for r in freq if r["operating_point"] == "CC36_ripple"], key=lambda r: number(r, "frequency_Hz"))
    nominal_losses = [r for r in losses if abs(number(r, "L_DCR_ohm")-.15) < 1e-8
                 and abs(number(r, "transition_sum_ns")-160) < 1e-6
                 and abs(number(r, "other_port_loss_W")-.8) < 1e-8]
    fl = sorted([r for r in nominal_losses if r["direction"] == "discharge"], key=lambda r: number(r, "frequency_Hz"))
    charge_losses = sorted([r for r in nominal_losses if r["direction"] == "charge"], key=lambda r: number(r, "frequency_Hz"))
    nominal_drift = max(number(r, "worst_display_error_percent") for r in measurement_drift if abs(number(r, "postcal_5V_change_V")-.03)<1e-8)
    best_single = min(single_tuning, key=lambda r: number(r, "score"))
    best_hysteresis = min(hysteresis_tuning, key=lambda r: number(r, "score"))
    best_cascade = min(tuning, key=lambda r: number(r, "score"))
    old_step_error=number(tuning[0],"auto_step_error_V")
    current_scale = float(re.search(r"#define\s+ADC_CURRENT_A_PER_PIN_V\s+([-+0-9.eE]+)f", (FW / "Core/Inc/adc_calibration.h").read_text(encoding="utf-8-sig")).group(1))
    report_date = date.today().isoformat()
    settings_text = (FW / "Core" / "Inc" / "control_settings.h").read_text(encoding="utf-8-sig")
    settings = {k: float(v) for k, v in re.findall(r"#define\s+(DCDC_\w+)\s+([-+0-9.eE]+)f", settings_text)}
    transient=json.loads((ROOT / "结果/AUTO2_突变验收.json").read_text(encoding="utf-8-sig"))
    with (ROOT/"结果/AUTO2_突变方案比较.csv").open(encoding="utf-8-sig",newline="") as file:
        transient_proposals=list(csv.DictReader(file))
    transient_rows=[[r['case'],f"{number(r,'max_error_V'):.4f}",f"{number(r,'settled_current_std_A'):.4f}",f"{number(r,'settled_ref_std_A'):.4f}","通过" if r['pass']=='1' else "未通过"] for r in transient_proposals]
    for macro, field in (("DCDC_CURRENT_KP","current_kp"),("DCDC_CURRENT_KI","current_ki"),("DCDC_VOLTAGE_KP","voltage_kp"),("DCDC_VOLTAGE_KI","voltage_ki"),("DCDC_CURRENT_SLEW","current_slew"),("DCDC_CURRENT_LEAD_TIME","current_lead_time"),("DCDC_CURRENT_FF_INDUCTANCE","current_ff_inductance")):
        assert abs(settings[macro]-transient["gains"][field])<1e-5,"Transient test differs from firmware defaults"
    assert transient["nominal_all_pass"]
    pairs = {}
    for path in sorted((ROOT / "生成代码").glob("*")):
        if path.suffix in (".c", ".h"):
            pairs[path.name] = digest(path) == digest(FW / "Core" / "Generated" / path.name)
    assert pairs and all(pairs.values())
    project = (FW / "MDK-ARM" / "BUCKG474VET6.uvprojx").read_text(encoding="utf-8-sig")
    assert "candidate_step" not in project and "apply_candidate" not in project
    app_h = (FW / "Core" / "Inc" / "app_control.h").read_text(encoding="utf-8-sig")
    knobs = re.search(r"typedef struct\s*\{(.*?)\}\s*ControlGains", app_h, re.S).group(1)
    assert len(re.findall(r"\bfloat\s+\w+\s*;", knobs)) == 4
    decision = {
        "scope": {"basic": [1, 2, 3, 4, 5], "advanced": [1, 2]},
        "selected": {"basic_1_2": "CC2_voltage_ratio_feedforward_current_PI",
                     "basic_3": "20.0047kHz_synchronous_BUCK",
                     "basic_4": "two_point_current_calibration_IIR_LCD_0p01A",
                     "basic_5": "24V_latched_stop_manual_reset",
                     "advanced_1_voltage": "CV2_voltage_current_cascade",
                     "advanced_1_frequency": "20.0047kHz_ARR4249",
                     "advanced_2": "AUTO2_continuous_signed_current_cascade"},
        "human_PI_gains": {k: settings[k] for k in ("DCDC_CURRENT_KP", "DCDC_CURRENT_KI", "DCDC_VOLTAGE_KP", "DCDC_VOLTAGE_KI")},
        "updated_date": report_date,
        "INA213_input_resistor_each_ohm": 10,
        "nominal_current_scale_A_per_V": 2.017,
        "firmware_current_scale_A_per_V": current_scale,
        "current_slew_A_per_s": settings["DCDC_CURRENT_SLEW"],
        "code_source": str(ROOT / "程序" / "dcdc_step.m"),
        "code_source_sha256": digest(ROOT / "程序" / "dcdc_step.m"),
        "simulation_parameters_sha256": digest(ROOT / "程序" / "dcdc_parameters.m"),
        "default_header_sha256": digest(FW / "Core" / "Inc" / "control_settings.h"),
        "calibration_header_sha256": digest(FW / "Core" / "Inc" / "adc_calibration.h"),
        "generated_files_identical": pairs,
        "alternative_sources_compiled_into_firmware": False,
        "human_PI_knob_count": 4, "archive_sha256": baseline,
        "archive_unchanged": True, "hardware_flashed": False,
        "native_C_comparison": native,
        "cycle_mean_current_error_percent": summary["current_switching_mean_error_percent"],
        "switching_display_error_percent": summary["display_switching_error_percent"],
        "keil_errors": delivery["keil_errors"], "keil_warnings": delivery["keil_warnings"],
        "measured_efficiency_available": False,
        "bench_current_calibration_performed": False,
        "extra_instant_step_passes_0p5V": transient["nominal_all_pass"],
        "transient_validation": transient,
    }
    (ROOT / "方案对比" / "决策与代码对应.json").write_text(json.dumps(decision, ensure_ascii=False, indent=2), encoding="utf-8")

    first = pick(auto, "AUTO1", 1); chosen = pick(auto, "AUTO2", 1)
    first_step = pick(auto, "AUTO1", 2); chosen_step = pick(auto, "AUTO2", 2)
    cc_rows = [["电流PI，运行无前馈", f"{cc_max['CC1']:.4f}%", f"{number(ccl['CC1'],'variation_percent'):.6f}%", f"{number(ccd['CC1'],'inductor_peak_A'):.3f} A / 过流锁存"],
               ["电压比前馈＋电流PI（选）", f"{cc_max['CC2']:.4f}%", f"{number(ccl['CC2'],'variation_percent'):.6f}%", f"{number(ccd['CC2'],'inductor_peak_A'):.3f} A / 无故障"]]
    cv_rows = []
    for s, label in (("CV1", "电压单环"), ("CV2", "电压/电流双环（选）")):
        a = pick(cv, s, 1); b = pick(cv, s, 2); c = pick(cv, s, 3)
        cv_rows.append([label, f"{number(a,'late_max_error_V'):.4f} V", f"{number(b,'max_error_after_220ms_V'):.4f} V", f"{number(c,'late_max_error_V'):.4f} V"])
    auto_rows = []
    for test, label in ((1, "18 V，15 V/s往返调压"), (3, "15.5 V，L/C各-20%"), (4, "21 V，L/C各+20%"), (2, "附加：Us瞬间32/38V往返")):
        a = pick(auto, "AUTO1", test); b = pick(auto, "AUTO2", test)
        auto_rows.append([label, f"{number(a,'max_bus_error_V'):.4f} V", f"{number(b,'max_bus_error_V'):.4f} V"])
    freq_rows = []
    for k in range(2):
        freq_rows.append([f"{number(fc[k],'frequency_Hz')/1000:.4f} kHz", f"{number(fc[k],'inductor_ripple_pp_A'):.3f} A", f"{number(fl[k],'port_eta_estimate_percent'):.3f}%", f"{number(fl[k],'gate_from_aux_estimate_W'):.3f} W"])
    charge_rows = [[f"{number(r,'frequency_Hz')/1000:.4f} kHz", f"{number(r,'model_output_W'):.3f} W", f"{number(r,'port_loss_estimate_W'):.3f} W", f"{number(r,'port_eta_estimate_percent'):.3f}%"] for r in charge_losses]
    measurement_rows = [["名义系数直接换算" if int(r['scheme'])==1 else "实时REF＋两点标定（选）", f"{number(r,'max_mean_error_percent'):.3f}%", f"{number(r,'max_display_error_percent'):.3f}%"] for r in measurement]

    def md_table(headers, rows):
        return "\n".join(["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)] + ["| " + " | ".join(row) + " |" for row in rows])

    md = f"""# 2015 A 双向 DC-DC：方案比较与决策说明

更新日期：{report_date}（AUTO2突变响应与真实PWM/ADC时序更新）。按最新范围覆盖基本要求（1）～（5）和发挥部分（1）（2）。硬件沿用第二版原理图及STM32G474VET6最小系统板；旧PCB不在本次工作范围内。

## 1. 最终选择

| 项目 | 实际比较的方案 | 最终决定 |
|---|---|---|
| 基本（1）恒流、基本（2）输入变化率 | CC1：电流PI、启动工作点预置、运行无前馈；CC2：电压比前馈＋电流PI | 选CC2，两问共用一个电流控制器 |
| 基本（3）充电效率≥90% | 30V/2A同步BUCK下约20kHz与40kHz | 保留20kHz；用显式开关电路和损耗情景估算，实物待验收 |
| 基本（4）电流测量显示≤2%误差 | M1：固定名义零点；M2：实时REF＋两点标定，相同IIR与显示取整 | 选M2，标定残余零偏/增益，LCD显示0.01A |
| 基本（5）过充保护 | 直接验证越阈值停机、锁存、恢复条件 | 24V锁存停机，低于23V且人工停机后解锁；此问明确且简单，不凑第二种 |
| 发挥（1）稳压 | CV1：直接电压PI＋越限电流接管；CV2：电压外环/电流内环 | 选CV2，电流参考与限流关系明确，可复用CC内环 |
| 发挥（1）效率相关实现 | 原频率约20kHz与约40kHz，均跑显式开关模型和损耗敏感性 | 保留20kHz，ARR=4249；95%仍待实物验收 |
| 发挥（2）自动转换 | AUTO1：上下阈值切换CC/CV；AUTO2：连续带符号电流双环 | 选AUTO2，正常调压及容差下余量更大，过零不重置控制器 |

固件只保留所选算法及其四个PI增益。未选方案、试验状态和候选搜索不编入固件。

## 2. 公共条件与公平性

本机MATLAB R2023b实际运行。电路为470µH、两端各440µF、10mΩ分流器，电池端口默认18V/0.20Ω；电感DCR暂估0.15Ω、MOS等效通态电阻暂估0.015Ω。模型保留电池侧电容，因此反馈是**电池支路电流，不是瞬时电感电流**。含12位ADC、INA213名义增益偏差、电流滤波、PWM计数量化、PWM1谷值高电平、两次ADC逐路采样、谷值控制/峰值装载CCR和520ns死区。空母线接电池浪涌不在此稳压模型验收范围内。

各结构共用启停、保护和限幅。CC1启动也预置U1/U2工作点，避免把零占空比错误启动作为劣势；运行后不再更新前馈。单电压环独立搜索12组增益，原PI双环搜索8组，阈值策略搜索4个死区，均有CSV记录；这是有界工程比较，不是全局最优证明。结构比较共49组电路运行，频率比较另6组（包括新增30V/2A充电效率）；测量另有4种假设误差角、11档和2种方法。最终所选方案另执行完整回归、开关模型及C一致性检查。PWM/ADC事件依据工程配置建模，ISR计算耗时、采样保持孔径、器件传播延迟及寄生参数尚无实测辨识，不称为与实板完全等效。

自动正常调压：Us在32～38V以15V/s往返，D压降暂估0.7V、源串联5Ω、负载30Ω；稳定/动态统计从220ms后开始，启动单独看波形。本轮按用户要求把瞬间6V阶跃列为明确验收项；另保留15V/s扫描与30Ω→45Ω负载测试。

## 3. 基本（1）（2）：电流PI与电压前馈PI

{md_table(['方案','11档最大恒流误差','原题输入变化率','附加24→30→36V阶跃的iL峰值/状态'],cc_rows)}

11档为1.0～2.0A、每档0.1A。变化率严格按题目abs(I36-I24)/I30×100%计算。两种PI在稳态都通过。本次标定初值已补偿INA213两只实装10Ω输入电阻的名义增益影响，实物仍需基本（4）的两点标定。选择CC2的主要依据是输入变化时及时修正工作点；CC1在附加阶跃中触发电池支路过流后锁存，不能继续正常调节。CC2附加阶跃的最大实际电池电流误差约{number(ccd['CC2'],'max_current_error_A'):.3f}A，不能把稳态变化率理解为瞬间误差也小于1%。

CC2输入阶跃的电感峰值约{number(ccd['CC2'],'inductor_peak_A'):.3f}A。现有电感标称电流资料不能证明Isat达到此值；软件±2.8A检测的是电池支路，不能代替电感峰值保护。此附加工况须在实际电感饱和/温升校核后再上电验证。

以上11档为平均模型统计。本轮闭环开关模型已按两次ADC逐路采样与DMA完成时刻运行，另对1A/2A开关波形复核显示。周期平均实际电流的控制误差最大约{summary['current_switching_mean_error_percent']:.3f}%，仍≤5%，但大于平均模型误差；详见`结果/基本14_开关波形采样与显示复核.csv`。不将平均模型很小的误差当成实物精度。

![输入突变对比](方案对比/结果/基本2_输入突变对比.png)

## 4. 基本（3）：充电效率≥90%

在U2=30V、I1=2A、18V电池模型下，分别运行约20kHz和40kHz的显式开关BUCK。母线输入功率与电池端输出功率按各RK4积分阶段积分，避免在栅极跳变处离散取样造成输入功率偏差。效率按原题η1=P1/P2计算，独立辅助供电的栅极功耗另列。

{md_table(['频率','电池端输出功率','主端口损耗情景','充电端口效率情景'],charge_rows)}

上述情景DCR=0.15Ω、tr+tf=160ns、其他主端口损耗0.8W；36种充电损耗情景见`方案对比/结果/基本3_两频率充电效率_非实测.csv`。两频率均给定2A，但实际逐路采样下周期平均电流略不同，表中保留各自实际模型功率。保留20kHz的依据是当前电感已有可用纹波，同时降低频率相关损耗。模型估算通过不等于真实≥90%，还需实测两端功率、DCR、开关波形及温升。保持同步整流，不增加无电感过零采样支持的二极管模拟模式。

## 5. 基本（4）：电流测量与LCD显示

M1用固定名义零点和2A/V；M2在每帧扣除REF，再用真实零电流与已知2A时的I/REF平均码标定残余零偏和增益。两者使用相同2kHz IIR和LCD 0.01A四舍五入。比较中给校准电流表加入±0.1%误差，I与REF各加入3计数RMS噪声和±2计数平滑INL；4组静态角包含分流器±5%、放大器假设±1%、REF偏差和ADC参考偏差。它们是设计敏感性情景，**不是器件实测或覆盖一切误差的上界**。每档评估稳定后的所有可能LCD取样相位，较只取一个刷新时刻保守。

{md_table(['方案','最大平均换算误差','含LCD取整的最大误差'],measurement_rows)}

选择M2：实时REF扣除公共偏置漂移，两点标定处理残余零偏和增益误差。四组假设情景的显示误差不超过2%（包含边界），仍须实物标定。标定后5V变化30mV的本轮情景，1A附近最差显示误差约{nominal_drift:.1f}%，不代表已覆盖开关尖峰或异步采样误差。`calibrate_current(NI0,NR0,NI1,NR1,Ical,Vadc)`输出两行宏，不自动写文件、不带电学习零点。

当前固件使用实时REF＋`ADC_CURRENT_OFFSET_RAW`残余零偏＋`ADC_CURRENT_A_PER_PIN_V`增益；{current_scale:g}A/V为两只实装10Ω的理论名义修正，实物残余零偏和增益须台架标定。滤波后的实测电池电流用于LCD，100ms刷新，显示两位小数，不以设定电流冒充测量值。

另在1A/2A实际开关波形上回放每周期两次ADC与现有IIR，稳定后所有相位的0.01A取整显示，相对真实周期平均电流最大误差约{summary['display_switching_error_percent']:.3f}%，通过所设2%检查。此项是显示链波形回放；模拟噪声/静态误差角和开关纹波分别验证，最终仍由电流表验收。

![测量与显示精度](方案对比/结果/基本4_测量与显示精度对比.png)

## 6. 基本（5）：明确的锁存过充保护

此问不需要两套控制架构。采用题目串滑阻抬高端口U1的方式，所选方案约在{summary['overcharge_trip_V']:.4f}V触发。关断SD#及PWM输出，电压回落也不自动恢复；低于23V且人工停机才解锁。八项保护逻辑检查及生成C对照覆盖锁存、复位、双向过流、欠压、母线过压和无效输入。24V是端口试验阈值，不能据此给五串普通锂电芯充到24V。

## 7. 发挥（1）：稳压结构及频率

单环独立整定为Kp={number(best_single,'Kp_duty_per_V'):.3f}占空比/V、Ki={number(best_single,'Ki_duty_per_Vs'):.3f}占空比/(V·s)。最终双环增加电流反馈相位超前与参考变化前馈，使用当前头文件的四个增益。单环保留越限电流接管和同一硬过流保护，并非无保护的理想电压源。

{md_table(['方案','18V电池稳态偏差','附加30Ω→45Ω负载变化最大偏差','15.5V电池稳态偏差'],cv_rows)}

两者启动进入±0.5V所需时间均约116ms，主要由100V/s母线给定斜坡决定，不能宣称双环启动更快。双环在本次负载变化中偏差较小，也把充放电电流给定限制写在同一内环接口中，故选CV2。单环同样可实现稳态指标，未被认定为不可行。

{md_table(['频率','36V/18V/2A时iL纹波p-p','端口效率情景估算','独立辅助供电栅极损耗估算'],freq_rows)}

频率表的效率是假定DCR=0.15Ω、tr+tf=160ns、其他**主端口相关**损耗0.8W的情景值。完整CSV还扫描DCR=0.05/0.15/0.30Ω、tr+tf=80/160/320ns、其他端口损耗0.2/0.8W，充/放电各36种损耗情景。40kHz纹波更小，但在上述情景下增加开关及死区损耗；20kHz的稳压和纹波已有可用仿真结果，故保留20kHz。未测磁芯损耗、ESR、开关波形可能改变最优频率，**不宣称20kHz为实物全局最优或95%已经达标**。

效率口径按原题η2=P2/P1。独立辅助电源提供的栅极能量不加到电池主端口P1中；另列栅极功耗与计入该项的保守效率，便于看整体代价。Pg=2QgVgsf，Qg暂取数据手册146nC、Vgs取10V的情景值；该测试点不是本板2A实测值。开关重叠损耗近似0.5·U2·|iL|·(tr+tf)·f。30W、95%对应主端口总损耗预算约1.579W，最终须用端口实测功率验收。

![放电启动对比](方案对比/结果/发挥1_启动对比.png)
![负载变化对比](方案对比/结果/发挥1_负载变化对比.png)
![频率与估计损耗](方案对比/结果/发挥1_频率与估计损耗.png)

## 8. 发挥（2）：阈值切换与连续双向控制

AUTO1独立选择的半死区为{number(best_hysteresis,'half_band_V'):.2f}V：母线过高切1A恒流充电，过低切30V恒压放电，中间保持模式。AUTO2的电压环直接给出正负电流，正值充电、负值放电，过零无需重置积分器。

{md_table(['工况','AUTO1最大母线偏差','AUTO2最大母线偏差（选）'],auto_rows)}

正常18V往返调压，AUTO1发生{int(number(first,'mode_changes'))}次CC/CV转换，AUTO2保持统一自动模式，方向由电流参考连续过零决定。AUTO1在低电池电压/小L/C下超过±0.5V；AUTO2在比较表及完整容差复核下保留更大余量。所选方案正常往返确有充、放电，平均模型分别达到约{summary['automatic_charge_A']:.3f}A与{summary['automatic_discharge_A']:.3f}A。

**本轮突变结果：** 旧AUTO2在相同真实时序平均模型下偏差约{transient['baseline_error_V']:.3f}V；只提高PI约{transient['PI_only_error_V']:.3f}V。所选方案增加参考变化前馈与电流反馈相位超前，标称18V电池、L=470µH、两端440µF，三个扰动PWM相位的显式开关模型范围为{transient['nominal_min_V']:.4f}～{transient['nominal_max_V']:.4f}V，最大偏差{transient['nominal_max_error_V']:.4f}V，通过±0.5V。升、降两个方向及积分过程中的开关纹波都计入。

**容差边界：** 15.5/18/21V电池、L与电容组分别取0.8/1/1.2倍共27组平均模型（Cbat与Cbus使用同一倍率，并非两只电容分别独立扫描），最大偏差{transient['corner_max_error_V']:.3f}V，{('全部通过' if transient['corner_all_pass'] else '未全部通过')}。最差角的开关复核偏差{transient['worst_corner_switch_error_V']:.3f}V。不能宣称所有容差组合已通过；实板若接近这些边界，需测得实际L/C、内阻与采样延迟后再整定。

根因与补偿：旧3000A/s参考斜率使约2A方向转换至少耗时0.67ms；1.2A母线电流差在440µF上积累，形成明显偏差。由电感方程得到参考变化前馈，采用有效系数235µH（标称L的一半，不是把真实电感改成235µH）。电流反馈超前150µs，参考依据为(Rb+Rshunt)Cbat约92µs与IIR低频延迟约68µs之和。实际反馈仍是R4电池支路电流。四个PI增益仍属于工程整定结果，未完成严格频域裕度设计，不声称由完整自动控制理论推导得到。

不能只看电压峰值：Kpv=14候选虽然电压峰值较小，但周期摆动明显，未采用。最终Kpv=10；标称开关模型末100ms电池支路电流标准差不超过{transient['nominal_max_settled_current_std_A']:.4f}A，参考标准差不超过{transient['nominal_max_settled_ref_std_A']:.4f}A。验收脚本另加0.1A支路标准差和0.2A参考标准差的工程筛选线（不是赛题指标），用于拒绝靠大幅极限环摆动压住电压的参数。

下面四组使用相同标称功率级、真实配置时序的平均模型；末100ms统计摆动，显式开关复核另见上方最终验收范围。

{md_table(['突变方案','最大电压偏差/V','支路电流标准差/A','参考标准差/A','电压及摆动筛选'],transient_rows)}

详细波形见[09突变图](../../结果/AUTO2_32至38V突变.png)，复现入口`verify_auto2_transient`。
![自动往返调压](方案对比/结果/发挥2_往返调压对比.png)
![附加瞬间阶跃](方案对比/结果/发挥2_瞬间阶跃压力测试.png)

## 9. 最终代码与人工调参

唯一算法源为[dcdc_step.m](程序/dcdc_step.m)。CC使用I*=充电设定；CV/AUTO使用I*=限幅(Kpv·(U2-U2*)+积分)。CV限制在[-2.5,0]A，AUTO在[-2.5,+2]A。内环为If=I+Tlead·ΔI/Ts，dH=限幅((U1+Lff·ΔI*/Ts)/U2+Kpi·(I*-If)+积分)，占空比5%～95%；有抗积分饱和、模式初始化及CCR预装载时序。代码由本机MATLAB Coder生成，不手工改生成C。

| 人工参数 | 最终默认值 | 单位 |
|---|---:|---|
| DCDC_CURRENT_KP | {settings['DCDC_CURRENT_KP']:.3f} | 占空比/A |
| DCDC_CURRENT_KI | {settings['DCDC_CURRENT_KI']:.1f} | 占空比/(A·s) |
| DCDC_VOLTAGE_KP | {settings['DCDC_VOLTAGE_KP']:.2f} | A/V |
| DCDC_VOLTAGE_KI | {settings['DCDC_VOLTAGE_KI']:.1f} | A/(V·s) |
| DCDC_CURRENT_SLEW | {settings['DCDC_CURRENT_SLEW']:.0f} | A/s，已有参考变化率限制 |

默认值只在[control_settings.h](../BUCKG474VET6_2/Core/Inc/control_settings.h)集中维护；RAM在线调整仍只有control_gains的四个PI增益。当前Kpi=0.02意为误差1A贡献2个百分点占空比；Ki按秒定义，函数内部乘周期。电流零点、两点增益和电压比例仍在adc_calibration.h。没有新增候选编号、实验开关或调试许可变量。台架起步可把已有current_slew降回100A/s，先做标定及低功率电流环，确认稳定后逐步提高；这会改变动态结果，应重跑仿真。

| 需求/决定 | 算法、硬件接口与验证文件 |
|---|---|
| CC2、CV2、AUTO2 | 仿真/程序/dcdc_step.m → Core/Generated/dcdc_step.c |
| 四个PI默认值、变化率与保护阈值 | Core/Inc/control_settings.h；Core/Src/app_control.c初始化读入 |
| ADC及电流方向 | Core/Src/app_adc.c；Core/Inc/adc_calibration.h；PC1母线采样 |
| 基本（4）标定和显示 | 仿真/calibrate_current.m；adc_calibration.h已有两个常数；app_lcd.c实测IBAT两位小数 |
| 24V锁存与实际关断 | dcdc_step.m故障状态；app_control.c拉低PB0并关MOE |
| 20.0047kHz | Core/Src/tim.c及.ioc：170MHz、中心对齐、ARR=4249 |
| 比较证据 | 方案对比/结果/*.csv、*.mat、*.png、*.fig |
| 机器可读对应关系 | 方案对比/决策与代码对应.json，含源文件和默认参数SHA256 |

## 10. 复现、已验证事项与实际边界

在本目录运行MATLAB：

```matlab
run_scheme_comparison  % 重跑候选、结构比较、频率比较；不改固件默认值
run_all                % 按当前人工默认值回归、生成C、验证并同步到工程
```

Keil再Rebuild。当前交付已实际执行当前回归与方案比较：Keil 0错误、0警告，生成C与MATLAB {native['samples']:,}步对照最大绝对差{native['max_absolute_error']:.3g}，所有生成C/H与工程副本相同。**未烧录，默认上电停机。** 重现入口不会把未选方案放入工程。原PI候选整定是固定有限集合，当前默认以AUTO2突变验收为依据，今后人工改变增益不等于需自动改选架构。

基线BUCKG474VET6-v1.zip未改，SHA256：`{baseline}`。过期过程备份已清理，当前代码与验证证据保留。

第二版最终连接核查已完成：BOM、去耦、跟随器和采样/功率网分离已修正。正常量程采用5V供电且不加额外0.6分压，REF接PC0；异常过压与掉电时序仍是原型限制。实际标定、Isat/DCR、MOS尖峰、效率与温升待测。当前接线见[当前硬件说明](硬件核查/当前硬件说明.md)。

资料依据：芯片测试条件和损耗公式已核对[Infineon IRF3205数据手册](https://www.infineon.com/assets/row/public/documents/24/49/infineon-irf3205-datasheet-en.pdf)、[TI MOSFET损耗说明](https://www.ti.com/lit/an/slyt664/slyt664.pdf)、[TI栅极供电损耗说明](https://www.ti.com.cn/cn/lit/pdf/slua958)。各方案优劣由本机仿真数据推得，不把参考设计当成本板实测。
"""
    # Keep the detailed Markdown with the evidence; the reading entry is the PDF.
    md = md.replace("(方案对比/结果/", "(").replace("(硬件核查/", "(../../硬件核查/")
    md = md.replace("(程序/", "(../../程序/").replace("(../BUCKG474VET6_2/", "(../../../BUCKG474VET6_2/")
    (EVIDENCE / "方案决策说明.md").write_text(md, encoding="utf-8")

    pdfmetrics.registerFont(TTFont("DecisionCN", r"C:\Windows\Fonts\simsun.ttc", subfontIndex=0))
    body = ParagraphStyle("body", fontName="DecisionCN", fontSize=10.3, leading=15.7, textColor=colors.HexColor("#243345"), spaceAfter=8, wordWrap="CJK", alignment=TA_LEFT)
    title = ParagraphStyle("title", parent=body, fontSize=23, leading=32, textColor=colors.HexColor("#173b60"), spaceAfter=16)
    heading = ParagraphStyle("heading", parent=body, fontSize=15, leading=22, textColor=colors.HexColor("#173b60"), spaceBefore=4, spaceAfter=9)
    small = ParagraphStyle("small", parent=body, fontSize=8.7, leading=12.7, spaceAfter=6)
    cell = ParagraphStyle("cell", parent=small, fontSize=9, leading=13, spaceAfter=0)
    pdf_path = ROOT / "00_重点看" / "方案决策说明.pdf"
    story = []
    def para(text, style=body):
        story.append(Paragraph(escape(text).replace("\n", "<br/>"), style))
    def table(headers, rows, widths):
        data = [[Paragraph(escape(str(s)), cell) for s in row] for row in [headers] + rows]
        tab = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
        tab.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,0), colors.HexColor("#e7eff6")),
            ("LINEBELOW", (0,0), (-1,0), .8, colors.HexColor("#7695b0")),
            ("LINEBELOW", (0,1), (-1,-1), .35, colors.HexColor("#d8e0e7")),
            ("VALIGN", (0,0), (-1,-1), "TOP"), ("LEFTPADDING", (0,0), (-1,-1), 7),
            ("RIGHTPADDING", (0,0), (-1,-1), 7), ("TOPPADDING", (0,0), (-1,-1), 7),
            ("BOTTOMPADDING", (0,0), (-1,-1), 7)]))
        story.append(tab); story.append(Spacer(1,9))
    def figure(name, height=None):
        from PIL import Image as PILImage
        path=EVIDENCE/name
        w,h=PILImage.open(path).size
        target_w=490
        target_h=target_w*h/w
        if height and target_h>height:
            target_w*=height/target_h;target_h=height
        story.append(Image(str(path), width=target_w, height=target_h));story.append(Spacer(1,7))
    def newpage(): story.append(PageBreak())

    para("2015 A 双向 DC-DC\n方案比较与决策说明", title)
    para(f"{report_date}  |  第二版原理图 + STM32G474VET6最小系统板；输入电阻实装各10Ω", small)
    para("按最新范围覆盖基本（1）～（5）与发挥（1）（2）。本机MATLAB实际运行；所选算法已对应到BUCKG474VET6_2。旧PCB未处理，v1.zip未改。")
    para(f"数据版本：本轮更新AUTO2动态补偿与PWM/ADC时序，重新回归和比较。当前所选方案11档平均模型误差最大约{summary['current_max_error_percent']:.3f}%，输入变化率约{summary['line_variation_percent']:.6f}%。当前回归和结构/频率比较均采用当前采样换算；原PI候选表用于比较，最终参数依据突变验收文件核对。",small)
    table(["项目", "比较方案", "选择"], [
        ["基本（1）（2）", "运行无前馈电流PI / 电压比前馈PI", "电压比前馈＋电流PI"],
        ["基本（3）", "30V/2A下20kHz / 40kHz充电损耗", "20kHz同步BUCK；效率待实测"],
        ["基本（4）", "固定名义零点 / 实时REF加标定", "实时REF、残余零偏/增益、0.01A显示"],
        ["基本（5）", "明确简单，直接验证", "24V锁存停机＋人工复位"],
        ["发挥（1）稳压", "直接电压PI / 电压与电流双环", "电压外环＋电流内环"],
        ["发挥（1）频率", "约20kHz / 40kHz显式开关仿真", "保留20kHz、ARR=4249"],
        ["发挥（2）", "上下阈值切CC/CV / 连续带符号电流", "连续双向控制，过零不重置积分"],
    ], [85,255,171])
    para("比较条件", heading)
    para("同一470µH、两端各440µF、10mΩ分流器，默认18V电池；反馈为电池支路电流。含ADC/PWM量化、电流滤波、PWM1真实相位、ADC分路时序、CCR峰值装载、520ns死区，共用启停、限幅及保护。DCR等未测寄生参数明确按假设处理。")
    para("电压单环12组增益、原PI双环8组、阈值4个死区分别整定。结构比较49组，频率另6组；测量比较4种误差角、11档、2种方法。有限候选比较不证明全局最优。")
    para("验收边界", heading)
    para(f"标称突变三个相位通过：U2={transient['nominal_min_V']:.4f}～{transient['nominal_max_V']:.4f}V，最大偏差{transient['nominal_max_error_V']:.4f}V。27组独立L/C与电池电压角落仍有超限，最大{transient['corner_max_error_V']:.3f}V。实板参数与效率仍须实测。")

    newpage();para("基本（1）（2）（5）：电流与保护", heading)
    table(["方案", "11档最大误差", "输入变化率", "输入阶跃iL峰值/状态"], cc_rows, [146,86,90,189])
    para("两种PI稳态均通过，输入变化率严格按题目计算。无前馈方案启动也预置U1/U2工作点；其附加阶跃过流锁存不是故意从0占空比启动造成。选择前馈的依据是运行中主动修正输入电压变化。")
    para(f"表内为平均模型统计。1A/2A开关周期平均控制误差最大约{summary['current_switching_mean_error_percent']:.3f}%，也通过5%。附加输入阶跃的iL峰值约{number(ccd['CC2'],'inductor_peak_A'):.3f}A，须核实际Isat；稳态1%不代表瞬间1%。",small)
    figure("基本2_输入突变对比.png",300)
    para("过充保护不凑第二种", heading)
    para(f"按原题串滑阻抬高端口U1，约{summary['overcharge_trip_V']:.4f}V锁存关断；低于23V且人工停机才解锁。八项逻辑检查通过。24V是端口试验阈值，五串电芯本体仍按电芯/BMS规定。")

    newpage();para("基本（3）（4）：充电效率与测量", heading)
    para("基本（3）：30V、2A充电效率≥90%", heading)
    table(["频率", "输出功率", "损耗情景", "端口效率情景"],charge_rows,[125,125,125,136])
    para("功率按RK4各阶段积分，避免开关跳变处采样造成偏差。表中DCR=0.15Ω、tr+tf=160ns、其他主端口损耗0.8W；另有36种充电损耗情景。按η1=P1/P2计，独立辅助栅极供电另列。保留20kHz，90%仍需实测。",small)
    para("基本（4）：测量与显示误差≤2%", heading)
    table(["方案", "最大平均误差", "含LCD取整最大误差"],measurement_rows,[225,130,156])
    para("4种假设误差角：分流器±5%、放大器假设±1%、REF与ADC参考偏差。含3计数RMS噪声、±2计数INL、±0.1%校准表误差，按实际IIR及0.01A显示取整比较。它们不是实测器件上界。",small)
    figure("基本4_测量与显示精度对比.png",230)
    para(f"实时REF加标定情景最大显示误差约2%（包含边界）；1A/2A开关波形双相位回放最大约{summary['display_switching_error_percent']:.3f}%。实时REF下，标定后5V变化30mV的情景误差为{nominal_drift:.1f}%。两只实装10Ω使灵敏度约0.495786V/A，其倒数为名义系数2.017A/V；当前固件为{current_scale:g}A/V。PC0逐帧读取约5/3V的REF，残余零偏名义0；两个系数由calibrate_current(NI0,NR0,NI1,NR1,Ical,Vadc)计算后人工写入。",small)

    newpage();para("发挥（1）：稳压结构与频率", heading)
    table(["方案", "18V稳态", "负载30Ω→45Ω", "15.5V稳态"],cv_rows,[150,105,151,105])
    para(f"单环独立整定Kp={number(best_single,'Kp_duty_per_V'):.3f}、Ki={number(best_single,'Ki_duty_per_Vs'):.3f}（占空比制）。两者启动均约116ms，主要受给定斜坡限制。双环负载变化偏差较小，且复用CC电流内环，故选双环。",small)
    table(["频率", "CC电感纹波p-p", "端口效率情景", "辅助栅极功耗"],freq_rows,[112,137,128,134])
    para("效率情景：DCR=0.15Ω、tr+tf=160ns、其他主端口损耗0.8W。完整数据扫描36种情景。40kHz纹波小、开关代价高；现阶段保留20kHz。原题η2=P2/P1，独立辅助供电的栅极功耗另列，不混入主端口P1。",small)
    figure("发挥1_频率与估计损耗.png",260)
    para("95%仍须实测", heading)
    para("30W输出允许主端口总损耗约1.579W。开关时间、DCR、磁芯及电容损耗未测，情景估计不能证明达标，也不能证明20kHz为实物最优。",small)

    newpage();para("发挥（2）：自动转换策略", heading)
    table(["工况", "阈值切换", "连续双向（选）"],auto_rows,[245,133,133])
    para(f"阈值方案半死区{number(best_hysteresis,'half_band_V'):.2f}V，高时切1A恒流充电、低时切恒压放电。正常往返中CC/CV转换{int(number(first,'mode_changes'))}次；连续双向在统一自动模式中让电流参考过零，容差余量更大。")
    figure("../../结果/AUTO2_32至38V突变.png",300)
    para(f"同一真实时序平均模型：旧AUTO2约{transient['baseline_error_V']:.3f}V，仅提高PI约{transient['PI_only_error_V']:.3f}V。加入参考变化前馈及电流反馈超前后，三个扰动相位的标称开关模型最大偏差{transient['nominal_max_error_V']:.4f}V。",small)
    para(f"Kpv=14候选因放电摆动未采用，最终Kpv=10；标称末100ms支路电流标准差≤{transient['nominal_max_settled_current_std_A']:.4f}A。27组L/C与电池电压角落最大偏差{transient['corner_max_error_V']:.3f}V，{('全部通过' if transient['corner_all_pass'] else '未全部通过')}；最差角开关复核{transient['worst_corner_switch_error_V']:.3f}V。PI采用工程整定，尚无完整频域裕度证明。",small)

    newpage();para("代码对应、人工调参与交付验证", heading)
    table(["入口", "最终默认值/对应内容"],[
        ["control_settings.h", f"电流Kp={settings['DCDC_CURRENT_KP']:.3f}、Ki={settings['DCDC_CURRENT_KI']:.0f}；电压Kp={settings['DCDC_VOLTAGE_KP']:.0f}、Ki={settings['DCDC_VOLTAGE_KI']:.0f}；斜率40000A/s；相位超前150µs、参考前馈235µH。"],
        ["dcdc_step.m → Core/Generated", "MATLAB Coder生成所选CC2/CV2/AUTO2；dH=(U1+Lff·ΔI*/Ts)/U2+经相位超前的电流PI。"],
        ["app_control.c", "实际定时周期、参数初始化、PB0低和MOE关断；上电停机。"],
        ["adc_calibration.h / app_adc.c", "实时REF扣除、残余零偏/增益标定；calibrate_current.m辅助计算。app_lcd.c显示真实IBAT，0.01A。"],
        ["tim.c / .ioc", "170MHz、中心对齐、ARR=4249，约20.0047kHz。"],
    ],[170,341])
    para("运行时仍只有control_gains的四个PI旋钮。KpI单位为占空比/A，KiI为占空比/(A·s)；电压环单位分别为A/V、A/(V·s)。积分、候选状态与试验选择器均不作为人工调参变量。")
    para("台架先标定、低功率固定电流环，再调电压环。已有current_slew可从100A/s起步，逐渐提高；它会影响动态性能。不能把较快仿真整定视作首次上板已验证。",small)
    para("复现与验证", heading)
    para(f"MATLAB依次运行run_scheme_comparison、run_all，再Keil Rebuild。已实跑：Keil 0错误/0警告；生成C与MATLAB {native['samples']:,}步对照，最大差{native['max_absolute_error']:.3g}；C/H工程副本校验一致。未选方案未编入，未烧录。",small)
    para("当前第二版连接核查已完成，正常量程沿用5V供电且不加额外输出分压，REF接PC0。实物标定、电感Isat/DCR、开关尖峰、效率与温升仍待确认；异常过压与掉电时序是原型限制。",small)
    para("基线v1.zip SHA256保持：\n"+baseline,small)
    para("完整表、图及逐项解释见“方案对比/结果/方案决策说明.md”；机器可读关系见“方案对比/决策与代码对应.json”。",small)
    para("依据：Infineon IRF3205数据手册；TI SLYT664损耗说明、SLUA958栅极供电损耗说明。数据手册测试点不等于本板实测，方案判断来自本机模型。",small)

    def page_footer(canvas, doc):
        canvas.saveState();canvas.setStrokeColor(colors.HexColor("#d8e0e7"));canvas.line(42,35,553,35)
        canvas.setFont("DecisionCN",8);canvas.setFillColor(colors.HexColor("#67798a"))
        canvas.drawString(42,23,"2015 A | 基本1-5 / 发挥1-2 | 第二版原理图")
        canvas.drawRightString(553,23,str(doc.page));canvas.restoreState()
    doc=SimpleDocTemplate(str(pdf_path),pagesize=A4,rightMargin=42,leftMargin=42,topMargin=40,bottomMargin=46,
                          title="2015 A 双向DC-DC 方案比较与决策说明",author="DCDC Control")
    doc.build(story,onFirstPage=page_footer,onLaterPages=page_footer)
    print("DECISION_REPORT_OK",pdf_path)
    print("SELECTED_CODE_MAPPING_OK; original ZIP unchanged; four human PI gains.")


if __name__ == "__main__":
    main()
