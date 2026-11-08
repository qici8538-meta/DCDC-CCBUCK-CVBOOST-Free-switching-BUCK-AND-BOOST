# Horco 无线 DAP 与 MCUViewer

2026-11-07 已实测：CMSIS-DAP v2 探针序列号 132004251450，SWD 100 kHz，STM32G474 识别正常。MCUViewer 通过 GDBSERVER 127.0.0.1:3333 读取两个电压变量，实际约 60～70 Hz。该速率是上位机读取速率。

## 再次打开

1. 关闭功率来源，保留 MCU 辅助供电；确认无线 DAP 配对和 SWD 同名连接。
2. 双击本目录 `Start_MCUViewer_DAP.cmd`，启动后台 OpenOCD 服务。
3. MCUViewer 用 File → Open 打开本目录 `MCUViewer_DAP.mcuvproj`。
4. 点击 START，顶部应为 Connected，按钮变为 RUNNING，Read value 持续刷新。

工程匹配 `MDK-ARM/BUCKG474VET6/BUCKG474VET6.axf`，保留当前两个电压变量及表格。重新烧录后须使用对应构建的 AXF 并刷新地址。当前固件接口以 `人工调参指南.md` 为准，不能沿用旧版变量或旧地址。

## MCU / SLAVE 掉电后的恢复（2026-11-08 补充）

掉电会使旧 OpenOCD 的 SWD 会话失效。即使界面仍显示 Connected / RUNNING、端口 3333 仍在监听，也可能正在报读内存错误；全 0 不能作为有效测量结果。原来的 Start 脚本遇到已监听端口会保留旧服务，不负责恢复此状态。

1. 关闭功率输入，恢复 MCU 和 SLAVE DAP 辅助供电并确认无线配对。
2. MCUViewer 点击 STOP，然后点击顶部 Connected 断开旧连接。若 STOP 卡住，可先执行下一步，再断开。
3. 双击本目录 `Restart_MCUViewer_DAP.cmd`，重建后台服务。
4. 回到需要的 MCUViewer 窗口，确认已断开旧连接后点击 START；若显示 ERROR，可再点击一次启动。不要同时在两个 MCUViewer 窗口里采集。
5. 核对 REF、原始码或采样计数在更新；功率关闭时电压接近 0 本身不代表连接失败。

本次重连已实测 REF 约 1.675 V、ADC frame_count 持续增长、output_enable 和 power_output_enabled 均为 0。未复位、未烧录、未启动功率输出。重连脚本不修改固件，也不恢复掉电前写入 RAM 的参数。

## 与 Keil 切换（操作步骤）

Keil 和 OpenOCD 不要同时占用同一 DAP。

1. 先切断功率来源。
2. MCUViewer 点击 STOP，再点击顶部 Connected 断开；仅 STOP 因 Keep connection 已选仍会保留连接。
3. 双击 `Stop_MCUViewer_DAP.cmd`，释放探针，再在 Keil 中烧录/调试。
4. 退出 Keil 调试会话后，重新启动 DAP 服务，再回 MCUViewer 点击 START。

## 本次故障原因及限制

- MCUViewer 设置为 GDBSERVER，但服务没有运行，3333 无监听，因而超时。
- 恢复服务后还需处理 GDB 建连暂停 CPU。配置按 MCUViewer 官方建议在 attach 后恢复运行，并仅在目标已暂停时执行 resume；不进行复位或烧录。
- GDB 建连可能短暂停核，故首次连接、重连、复位及烧录都应在功率关闭时进行。连接稳定后再按硬件试验步骤操作。
- 本次只验证通信和实时变量更新，没有启动控制输出，也没有验证电压测量标定。读数正常刷新不等于其物理数值准确。

服务日志：`.mcuviewer-dap/server.stderr.log`。启动脚本使用本机现有 STM32CubeIDE 的 OpenOCD；若移动安装路径或更换探针，应更新 PS1 的路径或 CFG 的序列号。

参考：[MCUViewer GDB server 官方配置说明](https://docs.mcuviewer.com/acquisitionsettings/#gdb-server-probe-section)。
