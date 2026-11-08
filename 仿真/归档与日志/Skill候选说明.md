# MATLAB 电力电子 skill 候选（未安装）

核查日期：2026-10-31。用户已选择“先不安装，完成修复后再看候选说明”。本次只查阅公开源码，不部署仓库或改变现有工具集。

| 候选 | 适合本项目之处 | 必须知道的边界 |
|---|---|---|
| **[npuzsy/simulink-power-electronics](https://github.com/npuzsy/simulink-power-electronics)，优先建议** | Apache-2.0；专为 Codex 的 Simulink/Simscape 电力电子检查设计，关注测量极性、采样、求解器、波形及验证证据，已有 Buck 布局案例 | DC-DC 子 skill 明确标为 developing，不能当成成熟的双向变换器 PI 自动设计器。依赖 Simulink Agentic Toolkit/MCP；仍需本机实跑验收 |
| [OrangeXxin/power-electronics-agent](https://github.com/OrangeXxin/power-electronics-agent) | MIT；面向电赛，包含需求→参数计算→平均模型→物理开关模型→指标验收的流程和配套脚本 | 主要案例是 R2025b 的 Boost PFC，本机为 R2023b；公式、器件端口及许可证描述均须按本机产品文档核对，不能直接套到本项目 |
| [MathWorks 官方 Simulink Agentic Toolkit](https://github.com/matlab/simulink-agentic-toolkit) | 官方公开源码；已有建模、仿真、线性化、仿真扫频和代码生成工作流。本机已经存在其中多项 skill，宜先核对现有安装 | 通用 MBD 工具集，不是电力电子专用 PI 设计专家。许可证限定结合 MathWorks 产品使用，不能当作通用 MIT/Apache 授权 |

**建议选择：第一项作为电力电子检查补充，结合已经存在的官方工具集。** 这只是选型建议，尚未在本机安装验证该社区 skill。

后续质量要求不由“装了 skill”替代：先明确功率级与真实测量位置，形成可追溯方程；把 PWM、ADC、延迟和限幅放进模型；需要严格整定时推导/线性化模型并验证频域裕度；平均模型、开关模型、容差/扰动、生成 C 和实物测量分别给出证据。

直接审阅的文件：[根 SKILL](https://github.com/npuzsy/simulink-power-electronics/blob/master/SKILL.md)、[DC-DC 子 SKILL](https://github.com/npuzsy/simulink-power-electronics/blob/master/subskills/dc-dc-converters/SKILL.md)、[电赛流程 SKILL](https://github.com/OrangeXxin/power-electronics-agent/blob/main/skill/SKILL.md)、[官方线性化 SKILL](https://github.com/matlab/simulink-agentic-toolkit/blob/main/skills-catalog/control-systems/simulink-linearize/SKILL.md)、[官方频响 SKILL](https://github.com/matlab/simulink-agentic-toolkit/blob/main/skills-catalog/control-systems/simulink-frequency-response/SKILL.md)。
