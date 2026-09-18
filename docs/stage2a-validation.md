# Stage 2A validation

结果：READY FOR STAGE 2B。Export MVP 和版本化观察合同已具备，允许后续独立评审比较实现；本阶段没有开始 Compare。
这不是 v0.1 发布资格，不是 production ready 或完整诊断认证。

## Implementation

公开参数仅 `Export-PwshSessionSnapshot -CommandName <string[]> -LiteralPath <string>`，附带 PowerShell 标准 common parameters。
没有 Force、raw、密钥路径、上传或创建 session 参数。LiteralPath 必填，父目录必须已存在且可确认为本地固定盘；目标存在拒绝覆盖。
函数返回与写入 JSON 相同的已脱敏普通对象；不返回 secret 路径或 runtime object。

- `src/PwshSessionDelta/Export-PwshSessionSnapshot.ps1`：编排当前会话观察和最终写入。
- `Private/Observation.ps1`：观察三态、HMAC token、顺序环境条目、本地路径检查、caller scope 边界。
- `Private/Discovery.ps1`：两次受限 wildcard 查询，分别选择 internal / external 类型；都使用 escape + '*'、All、ListImported，之后 OrdinalIgnoreCase 过滤。没有精确 fallback、调用目标或 winner 推断。
- `Private/Privacy.ps1`：默认本地状态、ACL、安全创建/读取/完整性检查。
- `Private/Storage.ps1`：独占暂存、Flush(true)、不覆盖 rename；小的提交函数用于故障注入测试，不是 transaction framework。

schema 在实现前记录于 [snapshot-schema.md](snapshot-schema.md)，本轮补充 CallerScopeNotVisible reason code，没有扩增观察字段。
[example-snapshot.json](example-snapshot.json) 使用公开虚构字节 1..32 和虚构路径生成，不含真实用户快照或本地 secret。

## Secret and output

当前用户 LocalApplicationData / pwsh-session-delta 下仅两个文件：

1. `redaction-v1.key`：随机 32 bytes。
2. `redaction-v1.id`：64 bytes ASCII 派生 keyId，不含 secret。用于识别等长意外损坏，不是防篡改签名。

目录是已有状态标志；首次合法 Export 才创建。当前 SID 为 owner，受保护 DACL 仅允许当前 SID 和 SYSTEM，子文件继承；读取前校验 owner、ACL、位置及重解析点。仅触碰工具自己的目录，不提权或修改父目录权限。
独占 CreateNew 创建 secret，不覆盖；写完整后创建 id。任一文件丢失/损坏/不可读/权限异常、创建尚未完成均安全失败；不换 key、不自动修复。Compare 未来只需快照元数据。
目录被整体删除后无法凭空知道旧状态曾存在；新状态会产生不同 keyId，旧快照不可因此直接比较。

本轮真实默认目录已完成首次创建并通过 ACL/长度检查；不会把 key 或其可恢复编码写到验证报告。
最初 smoke 使用本轮刚写出的单 key 版本；增加完整性标记后，仅为本轮已知新建状态一次性补齐对应 id，未替换 key。正式实现不提供自动迁移或补建标记功能。

JSON 先完整序列化于内存，只含脱敏值；以 CreateNew 写入显式输出目录中的随机 `.pwsh-session-delta-*.tmp`，Flush(true) 后关闭，再以同卷不覆盖 Move 发布。没有默认仓库输出位置。
失败清理唯一的暂存文件，其他进程创建的目标保留。强杀/掉电可能残留脱敏 tmp；不把半写文件命名成最终 snapshot，不承诺掉电后目录项持久性。

## Executed tests

Windows / PowerShell 7.6.5；Pester 5.9.0；最终 36 tests：35 PASS、0 FAIL、1 SKIP。
完整用例名称与状态在 [stage2a-test-results.json](stage2a-test-results.json)。可运行 `tests/Invoke-Stage2ATests.ps1` 重现；历史研究脚本不在正式测试范围内。

通过的场景：

- Alias 存在/缺失；Function 存在/缺失、同定义稳定摘要、定义改变、源码不泄漏。
- 有序 PATH/PSModulePath、重复、空项、空格、中文；PATHEXT 缺失与空串；非法扩展文本 unknown 且不泄漏。
- 普通不存在命令；脚本/cmd/bat 候选；同名 Alias+Function；重复 exe 及前缀伪匹配排除。
- JSON 不含原始路径、用户名、机器名、查询名称、源码或 secret 编码；跨导出稳定 keyId。
- 未加载合成脚本模块没有导入标记，已加载模块集合不变；已加载 Utility Cmdlet 可观察。
- lookup 异常、非文件系统 cwd、未知 caller scope 均与 absence 区分；其他字段仍输出。
- 特殊字符 literal Alias；对应 external unknown；路径/参数文本拒绝；UNC 搜索路径不查询 external。
- 真实 ACL 创建与校验；损坏长度、等长损坏、id 丢失、实际独占锁、实际 Everyone 读权限均失败关闭，不修复。
- 目标已存在、secret 覆盖尝试、序列化失败、暂存后提交失败、竞争写者创建目标：不静默覆盖，不留伪完整输出。
- 两个独立 pwsh 测试进程分别 Export；不同 Alias/Function 观察、相同 keyId、显式 None/All 与隐式 All、真实局部 scope unknown。
- 两个进程竞争第一次创建：成功者 keyId 一致，未完成者可 SecretUnavailable 后重试，最终只有 key/id 两个状态文件。

Skipped：原生 executable 启动的独立哨兵/跟踪验证。发现复制的 pwsh.exe 不等于证明未启动；没有把“没看到进程”当成证据。
测试不调用合成目标做执行正控制；脚本/函数/batch 哨兵保持未触发，只能证明所覆盖查询的观察结果。

## Acceptance status

以下状态严格指 Stage 2A 授权的采集部分，不能读成整条 v0.1 比较/Markdown release gate 已通过。涉及 Stage 2B 的部分仍未实现。

| ID | Stage 2A 状态 | 依据及剩余边界 |
| --- | --- | --- |
| A01 | PASS | 同名 Alias 采集和真实 A/B 存在/缺失；差异分类未实现 |
| A02 | PASS | Function 采集和真实 A/B 存在/缺失；差异分类未实现 |
| A03 | PASS | 稳定/不同定义摘要、JSON 无源码；Markdown 尚不存在 |
| A04 | PASS | PATH 顺序完整保留；比较判断未实现 |
| A05 | NOT IMPLEMENTED | 两侧不同解析路径的业务比较属于 2B；已有单侧多候选采集测试 |
| A06 | PASS | 普通名字完整空候选与 unknown 区分 |
| A07 | PASS | 空格路径实际发现与记录 |
| A08 | PASS | 中文路径实际发现、JSON UTF-8 与摘要 |
| A09 | PASS | snapshot/返回对象/固定错误脱敏；Markdown 尚不存在 |
| A10 | NOT IMPLEMENTED | 无差异比较属于 2B |
| A11 | PARTIAL | Function/脚本/dynamicparam/batch 哨兵通过；原生进程独立检测 Skip |
| A12 | PARTIAL | 实际 Export 的脚本模块不 autoload 和加载集合检查通过；未加载 binary Cmdlet 的证据仍是 Stage 1.5 研究，未迁入实际 Export 正式测试（本轮不引入 C#） |
| A13 | PASS | lookup 注入失败、非法 PATHEXT、非文件系统 cwd 均局部 unknown |
| A14 | PASS | 精确筛选、扩展名关联、同名 Alias/Function 和重复 exe；不推断 winner |
| A15 | PASS | 独立会话稳定 secret/keyId；不兼容快照比较属于 2B |
| A16 | PASS | 顺序、重复、空项、missing/empty 已测试；原始文本无归一化 |
| A17 | PASS | 已测会话状态不变；顶层采集、默认/显式偏好、局部 scope unknown |
| A18 | PASS | 特殊字面字符和保守拒绝符合合同；不宣称所有网络/重解析拓扑资格化 |
| A19 | NOT IMPLEMENTED | Compare 输入验证、Markdown 与差异汇总属于 2B |
| A20 | PASS | 本阶段 secret 与 JSON 文件安全部分通过，包括有界竞争测试；报告/Compare 部分未实现 |

## Limitations and scope changes

- 只在 7.6.5 上验证 discovery；其他版本 command 字段 RuntimeNotQualified，不冒充完整支持。
- 调用者函数、脚本文件、嵌套 scriptblock 的局部状态不能可靠读取，internal/pref unknown。请在实际顶层会话提示符采集；不通过反射或创建新 runspace 替代它。
- PATH 中不存在、相对、空条目、UNC、映射网络盘、重解析点或不可检查目录使 external unknown，原始 PATH 仍被顺序脱敏记录。该保守行为可能让日常复杂 PATH 得到较多 unknown。
- 当前会话可被其他代码并发修改；观察不是原子系统快照，也不是敌意 session 的安全沙箱。
- 目录/文件验证与使用之间仍有 OS 层竞争窗口；不能抵御同用户攻击者替换文件或同时替换 key/id。未实现强杀恢复或事务框架。
- 未调用任何诊断目标、--help/--version。测试框架启动 pwsh 是夹具控制，不是将被观察目标作为命令执行。
- 实际测量期间未观察到模块新增；Import-Module 本工具时 manifest 会按声明加载内置 Microsoft.PowerShell.Utility，属于准备阶段，不是 lookup autoload。Pester 及测试支持模块也只在测量前准备。
- Stage 1.5 的四个已知临时目录仍在仓库之外；未重试清理、未改权限。采集不扫描这些目录内容，测试结果不含目录路径；即使 TEMP 出现在 PATH 中也只输出 token。无打包流程，因此不会纳入 package。
- PROJECT-SCOPE 仅同步实现状态、caller 可见性/原子发布限制，以及为了检测等长损坏增加的非敏感 id 标记。没有新产品能力、网络服务、UI、AI、比较逻辑或远程发布。

准备进入 Stage 2B 的依据：schema 可稳定消费，观察失败不伪装成 absence，真实独立 A/B 已验证，剩余资格化门槛清楚标记。A11/A12 必须在最终 v0.1 发布前继续完成，不阻止对已有 snapshot 实现离线比较。
