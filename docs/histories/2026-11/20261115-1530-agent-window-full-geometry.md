# Agent window full geometry

用户要求 Agent 新 Chrome 大窗口默认进入持久虚拟屏，并保全真实原位置与尺寸，不能要求人工先缩小，也不能搬动人工窗口。原 provider 仅保存位置；超大窗口移入小屏后，OS 自动调整的尺寸无法归还。

`AgentDisplay` 现在在建屏和 AX 写入前保存完整原 frame；停放时仅拟合越界尺寸，尺寸和位置写入均核对精确窗口身份并读取实际结果。AX 抛错但已生效时继续观察，不重复不明动作。归还按位置、尺寸、必要的位置校正执行，完整 frame 验收后才丢弃恢复记录及 pin；未知身份或部分写入保留恢复入口。既有 persistent retention、release 和单 owner 不变。

`ensure_agent_display` 回执升级 protocol 2，并声明 `geometry:"fit_restore_v1"`；消费者必须确认实际 owner 回执后才启用依赖完整几何的窗口认领。protocol 1 不构成此能力证明。

独立 fresh-context 方案审视完成，无 Blocker/Major/Nit；要求实际落地完整 frame/Space 确认、unknown 不按 gone 清除、部分成功恢复测试，均纳入实现与针对性测试。定向代码审视发现屏幕同尺寸窗口可能受到菜单栏约束；已统一按既有 inset 可用区拟合并补边界测试。测试与运行采用状态由本轮交接补记；此处不声明已安装、签名、GUI 验收或系统重启验证。

非 GUI 验证：以已签 provider 的冻结源码为基线叠加本次准确 delta，30 项定向测试通过，包含 13 项几何测试、启动回执、精确生命周期、persistent pin/session 和完整 frame 容差。canonical 全测试目标的编译被未修改的 LockedUseIncidentReplayTests 原有错误阻断；没有为此覆盖无关源码。G1 修复已独立定向复核关闭；`git diff --check` 通过。真实安装与窗口交互仍待原负责人同批 provider/consumer 验收。

交互修订：已证2048×1122自动fit和原屏完整归还；小主屏fallback实际夹小，保持未确认。追加可容实体屏选择和fallback40pt定位，原屏未变exact不变；34项非GUI定向测试通过，真实fallback及新签名版采用另证。
