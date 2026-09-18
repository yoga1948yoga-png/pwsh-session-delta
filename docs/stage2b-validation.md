# Stage 2B validation

结论：READY FOR FULL RELEASE TESTING。Compare MVP 已实现且本阶段自动测试通过；这表示可以进入完整发布测试，不表示 READY TO RELEASE。没有创建远程仓库、push、发布包或加入 CI。

## Changes

新增实现：

- `src/PwshSessionDelta/Compare-PwshSessionSnapshot.ps1`：小型 public command，读取两个字面路径、比较、选择渲染方式。
- `Private/SnapshotValidation.ps1`：schema 1 结构/类型/重复 JSON key 检查，固定输入错误。
- `Private/Comparison.ps1`：通用三态 helper、有序字段比较、候选多重集、query 配对、摘要和 Markdown 渲染。

修改 module manifest/loader，仅增加 Compare 导出及其三个实现文件。Export-PwshSessionSnapshot.ps1、Observation.ps1、Discovery.ps1、Privacy.ps1、Storage.ps1 均未修改；snapshot-schema.md 和 Stage 2A 示例也未改动。schemaVersion 仍是 1，无迁移、无既有快照重写。

新增 `tests/Compare.Tests.ps1`、`tests/Invoke-Stage2BTests.ps1`，没有修改原有 Export/Session 测试。新增本阶段测试结果、Export 回归结果、comparison-schema.md、此验证说明、合成 difference snapshot 及 JSON/Markdown 示例。README、tests/README 和 PROJECT-SCOPE 同步当前状态。

PROJECT-SCOPE 必要更正：损坏/缺字段输入终止失败，与合法隐私不兼容的字段级 unknown 分开；去掉草案中 Compare 的文件写入参数，维持用户要求的最小接口；记录已有 schema 中 query HMAC 的大小写限制。A15/A20 按本轮明确要求收紧，无新增产品能力。

## Tests

Windows / PowerShell 7.6.5 / Pester 5.9.0：

| Suite | Total | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: | ---: |
| Stage 2B Compare | 57 | 57 | 0 | 0 |
| Stage 2A regression | 36 | 35 | 0 | 1 |
| Total | 93 | 92 | 0 | 1 |

可复现命令见 tests/README.md。机器可读结果：[Compare](stage2b-test-results.json)、[Export regression](stage2a-regression-2b-results.json)。只保存测试名和结果，没有完整 Pester runtime/error 或用户数据。

Compare 测试使用 docs/example-snapshot.json 的公开合成内容及 TestDrive 中的变体，未使用用户真实快照。覆盖：字段顺序/重复/空项，候选多重集及 only/both，query 顺序/缺项/重复冲突，Function/Alias 摘要，双 unknown，隐私 scheme/version/keyId 不兼容，明确 absence，各种错误输入和重复 key，中文/方括号文件名，JSON 往返和 Markdown 转义，以及环境保持/禁止调用 mocks。

离线性证据：Compare 及其 helpers 的源代码只有 Read-DeltaSnapshot 对输入文件的 ReadAllText；没有 secret、Get-Command、环境变量或目标调用路径。Pester 将 Get-Command/Get-DeltaSecret/Get-DeltaEnvironment/Get-Alias/Get-Item/Import-Module 设为调用即抛错，并断言 0 次；比较前后 PATH、PSModulePath、偏好、Function/Alias 保持一致。这是所测实现路径的证据，不声称对敌意 engine 或系统级行为作绝对证明。

本轮 Export 回归按原测试设计读取/创建 TestDrive 下的测试 key；这不属于 Compare 操作，也没有让 Compare 读取 secret。测试框架启动独立 pwsh 是夹具控制，不是执行被诊断目标。未调用诊断目标或其 --help/--version。

## A01–A20 current evidence

PASS（分层）表示现有采集测试和合成比较测试各自通过；尚未把所有场景串成完整 A/B Export → Compare 的正式发布测试，不把这张表冒充完整 release certification。

| ID | 最新状态 | 证据 / 剩余事项 |
| --- | --- | --- |
| A01 | PASS（分层） | 真实独立 A/B Alias 采集；合成存在/缺失比较、目标摘要不递归 |
| A02 | PASS（分层） | 真实独立 A/B Function 采集；合成存在/缺失比较 |
| A03 | PASS（分层） | 采集同定义/异定义摘要及源码不泄漏；比较相同/不同 digest 与 Markdown 安全结构 |
| A04 | PASS（分层） | PATH 采集保序；比较仅交换顺序即确认差异 |
| A05 | PASS（比较） | 合成 external path identity 改变，referenceOnly/differenceOnly；正式双会话不同 executable 路径链待完整 release suite |
| A06 | PASS（分层） | 不存在普通命令的采集 absence；两个 absence 比较无差异 |
| A07 | PASS（分层） | 空格路径发现；Compare 字面文件名空格不拆分 |
| A08 | PASS（分层） | 中文路径采集摘要/UTF-8；Compare 中文文件名及 Markdown 非 ASCII 转义保留 |
| A09 | PASS（分层） | Export 无原始敏感值；Compare 只投影已验证字段，不复制路径文件名、源码或 secret |
| A10 | PASS（比较） | 两份等价完整合成快照：10 个叶结果无差异，unknown=0；无 winner 字段 |
| A11 | PARTIAL | 既有 Function/script/batch/dynamicparam 哨兵通过；原生进程独立检测仍 SKIP；Compare 本身没有目标调用 |
| A12 | PARTIAL | 实际 Export 的未加载脚本模块/loaded Cmdlet 已通过；未加载 binary Cmdlet 尚需迁入实际 Export 正式测试 |
| A13 | PASS（分层） | 采集失败字段 unknown；Compare 单 unknown/双 unknown 不判相等，其他字段继续 |
| A14 | PASS（分层） | 采集筛选测试；候选重排不变、重复计数不同即差异，无 winner |
| A15 | PASS（分层） | 独立 Export keyId 稳定；Compare 不兼容身份字段级 unknown，缺失标识输入报错 |
| A16 | PASS（分层） | 采集保留空项/重复/文本；Compare PATH/PSModulePath/PATHEXT 按序，未归一化 |
| A17 | PASS（分层） | Export 会话/作用域测试；Compare 禁止 live lookup 的 mocks 和前后状态保持 |
| A18 | PASS（采集） | 原特殊字符/不安全路径测试回归通过；Compare 不重新执行发现 |
| A19 | PASS（比较） | 严格输入失败、重复/冲突 key、错误类型、JSON/Markdown 和混合三态摘要 |
| A20 | PASS（分层） | 原 secret/ACL/并发/写失败回归通过；Compare 不读 key、不写文件、不查当前环境 |

## Examples and output

输入：[reference](example-snapshot.json) 与 [synthetic difference](example-snapshot-difference.json)。difference 仅将版本改为 7.6.4、PATH 设为 EnvironmentReadFailed、候选 path digest 改为公开测试值。

输出：[example-comparison.json](example-comparison.json) 与 [example-comparison.md](example-comparison.md)。summary 为 Confirmed difference，2 confirmed、7 no observed difference、1 unknown。JSON 保留深层候选和三态；Markdown 解释相同对象，无完整 JSON dump。

```powershell
Compare-PwshSessionSnapshot -ReferencePath .\docs\example-snapshot.json -DifferencePath .\docs\example-snapshot-difference.json -Format Json
Compare-PwshSessionSnapshot -ReferencePath .\docs\example-snapshot.json -DifferencePath .\docs\example-snapshot-difference.json -Format Markdown
```

## Remaining limitations

- schema 1 query/name 是对原始大小写文本的 HMAC；不能离线恢复 OrdinalIgnoreCase 原名语义。相同拼写才能稳定关联。没有为 Compare 方便修改 Export。
- 不兼容 key 时 command query 无法可靠关联，因此连其独立 type 也不能跨查询错配。全局非 HMAC 字段仍比较。
- 未支持未知 snapshot/capture policy 结构；结构合法但未知隐私方案只作保守 unknown，不调用其他实现。
- 不认证输入真实性，也不能恢复原始路径/Function 内容。HMAC 相等不证明命令行为相同。
- 所有候选是观察，不提供执行优先级、winner 或因果判断。
- Compare 在内存中读取两份 JSON，未提供大文件流式处理；无输出文件管理功能。
- A11/A12 正式发布 gate 仍未完成，全部验收链仍需完整 release testing；未扩展至新的 PowerShell 版本矩阵。
- 未创建 GitHub repository、CI、package 或远程发布。当前版本仍 0.0.0，许可证仍待 Maintainer 决定。

这些限制不要求扩大 v0.1 产品范围。完成 Stage 2B 后停止，等待下一轮审核。
