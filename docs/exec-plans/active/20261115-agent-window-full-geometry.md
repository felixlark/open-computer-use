# Agent window full geometry

## 目标与范围

原生 `get_app_state` 的精确 PID/window_id 停放链必须容纳大于 1920×1080 虚拟屏的 Agent Chrome 窗口，并在显式归还时恢复真实原位置与尺寸。只改 provider 停放/归还、启动能力回执及针对性非 GUI 测试；沿 #578 原负责人集成、签名、安装和真实 GUI 验收，不建立第二个运行 owner。

## 当前事实与方案

`AgentDisplay.ParkedWindow` 只保存位置；park 只移动、仅检查左上角；restore 只检查位置。因此消费者拒绝超大窗口，而 WindowServer 停放时自动缩短窗口也无法恢复原尺寸。现有 pin、PID/launchDate/AX identity、persistent retention 与 release 语义保留。

1. 在创建屏幕或任何 AX 写入前读取有效的完整原 frame，保存进唯一恢复记录；读取失败不捏造尺寸。重复 park 不覆盖原 frame。
2. provider 自己计算屏内目标 frame；只有超过既有 inset 可用区域的维度才缩小。包括恰好屏幕尺寸的窗口，否则目标 y=0 可能被 WindowServer 菜单栏约束夹到 y=30。先记录恢复状态，再按尺寸、位置顺序用公开 AX 属性停放。完整 frame 与 Space membership 均须读回确认。
3. 所有 AX 写入前核实同一 PID、launchDate、window ID 与 AX element。单次写入成功或抛错都读取实际结果；如果目标属性已生效即可继续，未知/未生效则报错并保留恢复记录，不重复不明动作。
4. 归还先回原物理屏的原位置，再恢复原尺寸，最后按实际读回需要校正位置。恢复后完整 frame 匹配才移除记录及 pin；部分生效的错误仍保留恢复入口。同一物理屏、同一 bounds 恢复原 frame；显示拓扑变化沿既有相对位置回退，原尺寸保留，不能把回退当成原屏原样验收。原屏无来源的窗口沿既有 fallback，Plus 仅在退出时保留 born-hidden Chrome 并 release；明确归还调用 provider 的物理屏 fallback，原尺寸保留，并与原屏原 frame 恢复分别记证。
5. `ensure_agent_display` 回执升级 `protocol:2`、`geometry:"fit_restore_v1"`。消费者确认这一实际 owner 回执及真实显示器后才启动 Chrome watcher/claim；protocol1 不构成新几何支持。旧 exact lifecycle 工具参数不新增假参数。

## 不变量与风险

- 人工窗口不认领，不通过 focused-window/title 回退；身份丢失不向替代窗口写入。
- 不在 Plus 预缩小，否则会污染 OCU 保存的原始 frame。
- AX 可超时但已投递；失败后先观察，不能盲重发。应用最小尺寸、OS 自动约束导致无法完整容纳或归还时明确报错，不以局部成功清除记录。
- persistent display 与 pin 跨 session 存续；只在已确认完整归还或显式 release 时释放本窗口恢复所有权。
- 不调用 provider、GUI 或进程控制；源码/单测证据不代表安装采用。

## 验证与进度

- [x] 保存准确 before 文件/hash/diff，保全 canonical 既有 dirty。
- [x] 独立 fresh-context 只读审视方案与关键失败恢复边界，方案级无 Blocker/Major/Nit；代码定向审视 G1 指出屏幕同尺寸窗口未拟合 inset，已修正并补边界测试。
- [x] 非 GUI 测试覆盖超大目标 frame、完整归还、AX 错误但已生效、未生效不重发、身份变化、窗口自动尺寸变化及持久回执；已签 provider 冻结源码叠加准确 delta 的测试投影通过 30 项定向测试。canonical 原有 LockedUseIncidentReplayTests 编译错误已另报，未修改其文件。
- [ ] 按 before 快照交付本任务 delta；主负责人完成 signed provider/consumer 同批切换及真实 Chrome 大窗/人工窗口/焦点/跨 session 验收。

## 回滚与验收责任

保留已安装 provider 及其冻结源码；Root 使用既有正常 owner 退出和安装回退流程，不能用旧 proxy 探测新 owner。真实安装验收必须观察停放后完整 frame 在屏内、归还 frame 四字段一致、人工窗口几何和前台焦点不变、断连后 persistent pin 不丢失。此文只记录当前 source 方案，不声明上述运行验收已完成。

代码定向审视 G1 修订已由同一独立 reviewer 对最终哈希定向复核关闭，无新增 Blocker/Major。交付状态为 source delta 与非 GUI 验证已备，真实采用仍归 Root。

## 安装交互发现的实体屏回退修订

B14D配对的原屏exact恢复已通过；born-hidden窗口归还默认主屏时，实际被较小主屏夹小并保留restore-unconfirmed，未记为通过。修订仅影响fallback：原屏bounds未变继续exact；拓扑变化后原屏能容原尺寸则保留原屏，否则选择能容原尺寸与既有40pt边缘余量的实体屏，main可容优先，再largest fitting；皆不能容时选择largest并继续要求完整frame真实读回。fallback定位也夹至40pt可用区域，原尺寸不变；无实体屏抛错保留记录。34项非GUI定向测试通过，修订安装验收待Root完成。
