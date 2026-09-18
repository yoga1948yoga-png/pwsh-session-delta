# Stage 3 — Full release test gate

结论：READY FOR WINDOWS ARM64 REAL-SESSION VALIDATION。
含义：通过当前环境的自动化发布门槛，可以进入 Stage 4 人工真双 Session 验证；不是 v0.1.0 已发布或所有 Windows/PowerShell 版本均已验证。

## Tested environment

- Windows OS API version: Microsoft Windows 10.0.26200（Windows 11 内核版本标识）。
- OS architecture: Arm64；PowerShell process architecture: Arm64。
- PowerShell 7.6.5，Pester 5.9.0；运行 token 未提升，无管理员权限。
- 其他 PowerShell 7 / Windows 版本未验证；不扩大版本矩阵声明。
- 运行器：`tests/Invoke-Stage3Tests.ps1 -PesterManifest <local Pester manifest>`。不联网安装依赖。

## Full regression

| Suite | Total | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: | ---: |
| Export + independent Session (Stage 2A) | 35 | 35 | 0 | 0 |
| Compare (Stage 2B) | 57 | 57 | 0 | 0 |
| Release controls and E2E (Stage 3) | 10 | 10 | 0 | 0 |
| Total | 102 | 102 | 0 | 0 |

机器可读结果见 [stage3-test-results.json](stage3-test-results.json)，包含实际控制结果、E2E summary、环境、清理/隐私扫描布尔结果和固定测试名，不存原始错误或 Pester runtime。

原 Export.Tests.ps1 的一个空 A11 Skip 占位已由 Release.Tests.ps1 的真实正负控制替代；不是把 Skip 改成空的 PASS，也不是排除旧的可执行测试。运行器运行全部四个正式测试文件。没有其余 Skip。

## A11 native executable

使用当前 Windows System32 的 choice.exe，复制到 Pester TestDrive 内隔离目录，赋予 GUID 唯一 exe 名称。无下载、无提交 binary、无编译器或额外产品依赖。fixture 与最终数据均在仓库外的测试临时目录。

检测方式：由 driver 使用 .NET Process.GetProcessesByName 查询唯一进程名；实验 pwsh 的 stdin 为保持打开的重定向管道，choice.exe 无参数启动后持续等待输入，因此不依赖捕捉短暂进程。stdout/stderr 异步排空，不向可分享报告保存私人异常。

- Positive control：在独立 pwsh -NoProfile -NonInteractive 中显式启动同一 exe，不传参数。最多等待 10 秒，每 10 ms 检查；检测到后再等待 250 ms 并确认仍有一个该进程。实际成功。随后仅终止本测试唯一哨兵及受控子进程。
- Product negative：另一个新进程调用真实 Export，以同一唯一 exe 名作为 CommandName。driver 持续监测，Export 必须在期限内成功退出；snapshot externalCandidates=Confirmed observation，type=Application；没有哨兵启动。实际成功。
- finally 清理覆盖失败路径，杀掉被意外启动的哨兵/测试子进程，再删除唯一复制 exe；Pester 清理其他 TestDrive 内容。
- 额外静态 AST 测试锁定 Discovery 中允许的调用，拒绝动态目标调用和目标进程启动方法；保留原 script/batch/Function/dynamicparam 执行哨兵测试。

证据边界：这是经正控制验证的持续存活哨兵及当前查询代码验证，不是系统范围任意短命进程追踪，也不声称敌意 PowerShell engine 下的安全证明。没有使用管理员 WMI/ETW/Sysmon/Procmon，没有修改安全策略。正控制主动执行测试哨兵属于本阶段明确授权的夹具行为，不是产品执行诊断目标。

## A12 binary module autoload

每个 positive / negative 都在不同的新 pwsh -NoProfile 进程中运行。先导入本工具，之后测量目标模块。正控制只执行精确 Get-Command，绝不执行目标 Cmdlet。

| Fixture | Positive | Product negative |
| --- | --- | --- |
| CimCmdlets / Get-CimInstance | module 初始 0，精确 discovery 后 1；CommandType=Cmdlet | 实际 Export 后 module 仍 0；loaded-module 集不变；assembly 基线不变 |
| Microsoft.PowerShell.ThreadJob / Start-ThreadJob | module/assembly 初始均 0，精确 discovery 后均 1 | 实际 Export 后 module/assembly 均 0；loaded-module 集不变 |

CimCmdlets 的 assembly 在本机某些新进程准备路径中已经预加载，不能把“模块未导入”误写成“assembly 必然不存在”。最初将其初始 assembly 数固定为 0 的夹具断言失败；另一次准备路径又观察到 0，说明应记录基线而不假定。最终检查 module 未加载及 assembly 前后不变，并增加自带 ThreadJob 提供可靠的 assembly 0→1 正控制 / 0→0 负控制。没有修改产品来适应测试，没有生成自定义 binary module。

两个负控制的 internalCandidates/externalCandidates/aliases/functions 均为 No observed value，符合“当前已加载模块中可见候选”的策略。没有运行 Get-CimInstance 或 Start-ThreadJob，也没有创建 CIM 查询或 ThreadJob。

## Automated Export → files → Compare

测试只在两个真正独立 pwsh 进程中设置 fixture 并调用真实 Export；父 driver 不伪造 snapshot JSON。仅在测试模块作用域替换 secret 存储目录，真实 ACL/secret 实现照常执行。两个进程共享测试 key。

差异链：A 有 Alias、B 无；两侧 Function 定义不同；同一对 PATH 目录交换顺序；同名 cmd candidate 在 A 采集后从一个测试目录移到另一个目录，B 再采集。Compare 的 PATH、Alias、Function、external candidate 均确认差异，unknown=0；Object/JSON/Markdown 均经过断言。candidate 为安全测试文件，没有执行 marker。文件迁移属于测试夹具设置，不是产品修复功能。

相同链：两个新进程建立相同 Alias、Function、PATH、cwd、偏好和候选。真实各自 Export 后再 Compare，summary=No observed difference，18 个无差异结果、0 confirmed、0 unknown；没有忽略应比较字段。

这是 automated gate；Windows Terminal、IDE terminal 等真实用户 Session 的人工验证 pending Stage 4。

## Privacy and offline contract

端到端产物包含原始 Export 文件、Export 返回对象的序列化、Compare Object/JSON/Markdown、正负控制证明数据；异常路径使用含唯一私人 marker 的损坏输入，检查只返回 InvalidReferenceSnapshot。

扫描禁止项：实际 username、profile、machine name、测试绝对目录、随机 unique sensitive marker、Function 定义里的 marker、测试 secret 的 Base64/大小写 hex。只在内存读取测试 key 用于泄漏断言，Compare 没有读取 key。扫描所有链路可分享产物；driver 再扫描将写出的结果 JSON、validation Markdown，并对实际保存的结果 JSON 读回扫描。禁止项不写入结果文件。测试结束清除 driver 中用于扫描的变量。

Compare.Tests.ps1 的 offline mocks 和状态前后检查全量重跑：Get-Command、secret/environment helpers、Get-Alias、Get-Item、Import-Module 均不得被 Compare 调用；PATH、PSModulePath、偏好、Function/Alias 不变。代码路径只读取两份 snapshot，不创建 key，不执行目标。

## A01–A20 final automated gate audit

所有 PASS 的证据均为 automated test；历史 research evidence 为补充，不替代正式门槛。真实用户双 Session 验证仍 pending Stage 4，不属于功能未实现。

| ID | Status | Evidence |
| --- | --- | --- |
| A01 | PASS | automated：真实双进程 Alias 存在性采集、E2E Alias 差异，未执行目标 |
| A02 | PASS | automated：独立会话 Function 存在/缺失采集，Compare 存在性断言，E2E 定义差异 |
| A03 | PASS | automated：相同/不同定义摘要、端到端 Function 差异及最终泄漏扫描 |
| A04 | PASS | automated：采集保序、Compare 顺序测试、真实 E2E PATH 顺序差异 |
| A05 | PASS | automated：真实 Export 不同候选目录→文件→Compare，JSON/Markdown 断言，无 winner |
| A06 | PASS | automated：普通不存在命令的完整 absence 与 Compare 双 absence |
| A07 | PASS | automated：采集空格路径，E2E 测试目录包含空格 |
| A08 | PASS | automated：中文路径/文件名/UTF-8，真实 E2E 目录包含中文 |
| A09 | PASS | automated：Export 单元泄漏测试及完整产物/报告/返回对象/异常最终扫描 |
| A10 | PASS | automated：两个独立 Export 的相同 fixture，18 equal/0 difference/0 unknown |
| A11 | PASS | automated：native 正负控制、Discovery AST 约束、原 script/batch/Function/dynamicparam 哨兵 |
| A12 | PASS | automated：CimCmdlets 和 ThreadJob 的独立正负控制、模块/assembly 检查、已有 loaded Cmdlet/external 测试；research 补充 |
| A13 | PASS | automated：失败注入，单/双 unknown 不判相同，其余字段继续比较 |
| A14 | PASS | automated：exact 筛选、前缀排除、多目录/同名候选、多重集顺序/数量；research 补充排序边界 |
| A15 | PASS | automated：独立会话共享测试 key，scheme/version/keyId 不兼容与缺字段严格区分 |
| A16 | PASS | automated：PATH/PSModulePath/PATHEXT 顺序、重复、空项与 absence 保留 |
| A17 | PASS | automated：Export 状态/作用域及 Compare offline 状态保持；新进程模块集合不变 |
| A18 | PASS | automated：字面 wildcard 字符、external unknown、不安全输入/路径拒绝；research 补充已知边界 |
| A19 | PASS | automated：损坏 JSON、结构/类型/重复 key，Markdown 转义、混合三态、E2E 两种报告 |
| A20 | PASS | automated：secret ACL/并发/损坏/写失败，Compare 不读 key/环境且不写报告文件 |

## Scope and cleanup

无生产代码修改，snapshot schemaVersion 仍为 1。运行器核对测试前后 src 文件 hash 不变。测试新增 Release.Tests.ps1 和 Invoke-Stage3Tests.ps1，仅移除由真实测试替代的旧 Skip 占位。

所有临时 snapshot、comparison report、native exe、marker、secret、PATH 目录位于 Pester TestDrive；最终仓库只保存无敏感数据的测试代码、汇总和文档。driver 确认本轮 release fixture 根目录已不存在。没有新增 binary fixture 或真实本机 snapshot 入库。

## Known limitations

- A/B 必须使用相同 CommandName 拼写。schema 1 的 query 是原始文本 HMAC，无法恢复后 OrdinalIgnoreCase 配对；不同 token 未配对则 unknown。不改 schema。
- discovery 仅验证 Windows / PowerShell 7.6.5；其他版本不是已验证支持矩阵。
- caller 局部作用域、不安全/无法检查的 PATH、特殊字符 external 查询保持现有保守 unknown。
- 不推断 winner、可执行性或因果；快照不是原子系统状态，也不认证输入真实性。
- 未做 Stage 4 人工真实 Session 验证；未公开仓库、未选许可证、未打包、未加入 CI、未发布 v0.1.0。

当前没有阻止进入 Stage 4 的自动化 release-gate blocker；正式发布仍需后续人工验证和 Maintainer 审核。完成本阶段后停止。
