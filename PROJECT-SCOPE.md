# pwsh-session-delta — v0.1 scope

状态：Stage 3 全量自动化门槛通过；A11/A12 正式测试已补齐，并通过真实 Export→文件→Compare 双进程测试。snapshot schema 1 未改变；最新证据见 docs/stage3-validation.md。Stage 4 已由用户人工验证通过（7.6.6，4 confirmed / 14 equal / 0 unknown）；Stage 5 准备公开仓库，尚未发布。
项目名固定为 `pwsh-session-delta`，模块名暂定为 `PwshSessionDelta`。
Primary Maintainer 是项目所有者；辅助工程实现不能自行扩大范围或决定发布。

> A local-first PowerShell 7 tool that captures privacy-aware snapshots inside two Windows PowerShell sessions and reports observable differences that may affect command resolution, without claiming root cause.

这里的 “Windows PowerShell sessions” 指运行在 Windows 上的 PowerShell 7 会话，不指 Windows PowerShell 5.1 产品。

## Problem

同一条命令在两个终端中的可见 Alias、Function、搜索路径或候选文件可能不同。
需要记录两边实际会话的有限状态，比较可观察差异，避免凭印象解释原因。
差异是调查线索，不是故障根因，也不证明命令能成功运行。

## Target user

使用 Windows 与 PowerShell 7 的开发者，尤其是需要比较 Windows Terminal、VS Code terminal、coding agent shell 或两个独立会话的初学者。
工具不控制终端、不连接 agent、不要求管理员权限。

## Supported platform

- 仅 Windows + PowerShell 7（Core）；运行时拒绝其他平台和 Windows PowerShell 5.1。
- Validated on Windows ARM64 with PowerShell 7.6.5 and 7.6.6. 精确 qualified-version set 仅为这两个版本。`PowerShellVersion = '7.0'` 是语法装载下限，不是全 7.x 兼容认证。
- 正式 v0.1 发布前按实际通过的版本确定测试矩阵；未验证版本不得承诺安全解析完整性。
- 运行时纯 PowerShell / 随附 .NET；Pester 仅为开发测试依赖。

## Non-goals

不支持 Windows PowerShell 5.1、Linux、macOS、WSL、cmd.exe 或 Bash 会话。
不做 GUI、AI/LLM、OpenAI API、服务器、上传、自动修复、注册表修改、提权、完整系统诊断或网络诊断。
不加入 Docker、数据库、Web server、Node.js、Python、复杂构建系统、遥测、analytics、依赖注入框架或无必要的抽象层。
不读取全部环境变量，不扫描全部函数，不保存函数源码，不运行被查询的命令。
本阶段不创建远程仓库、不 push、不发布 PowerShell Gallery 包；Stage 5 采用 MIT 许可证。

## Snapshot model

1. 用户在真正的 Session A 内导入本模块并采集 A。
2. 用户在真正的 Session B 内导入本模块并采集 B。
3. 比较两个已经存在的 snapshot；比较操作不重新查询任何现场命令。

两个会话必须使用相同的隐私比较上下文和查询命令集合。禁止用父进程启动的“干净子进程”替代用户选择的 B。
测试夹具可以使用独立 pwsh 进程；它们只是受控实验，不是产品的会话模型。
采集发生在用户调用位置，不能搬到新的 runspace 或子进程而声称仍代表调用者的 Alias/Function。
局部作用域、模块私有作用域以及模块导入对可见性的影响必须测试；不可见的内容不能伪装成已确认不存在。
先读取调用者的偏好值，再进入查询作用域；不改变调用者的 PATH、PSModulePath、偏好变量、Alias 或 Function。

只读指不修改被诊断状态。允许写用户请求的 snapshot、报告和本地隐私密钥文件；默认拒绝覆盖已有文件。
格式为带版本号的 JSON snapshot；比较返回结构化 PowerShell 对象，支持 JSON 和 Markdown 报告。
Markdown 不是反向导入或比较的数据格式。字段名、参数细节仍可在实现审核时微调。

## Public commands

保留 `Export-PwshSessionSnapshot` 与 `Compare-PwshSessionSnapshot`。
`Export`、`Compare` 是 PowerShell approved verbs，名词单数且带项目标识；无需改名。

Export 与 Compare 参数已实现：

```powershell
# Session A：首次采集自动建立当前用户的本地 secret。
Export-PwshSessionSnapshot -CommandName 'git' -LiteralPath .\A.snapshot.json
# 在用户实际需要比较的 Session B 中运行：
Export-PwshSessionSnapshot -CommandName 'git' -LiteralPath .\B.snapshot.json
# 之后可在任一会话比较：
Compare-PwshSessionSnapshot -ReferencePath .\A.snapshot.json -DifferencePath .\B.snapshot.json
Compare-PwshSessionSnapshot -ReferencePath .\A.snapshot.json -DifferencePath .\B.snapshot.json -Format Markdown
```

Compare 默认返回对象；`-Format Json|Markdown` 渲染同一结果。两个路径参数均按字面解释；无输出文件参数，只返回对象或格式化字符串，不写文件。它只读取两份 snapshot，不读取 secret 或当前命令环境。
仅导出 Export-PwshSessionSnapshot 与 Compare-PwshSessionSnapshot 两个 public commands。

## Observable fields

| 字段 | 允许记录的内容及比较规则 |
| --- | --- |
| PowerShell version | 当前 `$PSVersionTable.PSVersion` 字符串，不执行 `pwsh --version` |
| 当前工作目录 | 当前 PowerShell location 的脱敏身份；非文件系统 provider 无法安全解释时记 unknown |
| 指定 command 的发现结果 | 查询身份、观察完整性、候选类别、脱敏候选路径/模块身份；不序列化原始 CommandInfo，不承诺 winner |
| 同名 Alias | 是否观察到、脱敏的目标字符串；不执行或递归解析目标 |
| 同名 Function | 是否观察到、函数定义的稳定 keyed hash；只在内存瞬时读取源码 |
| process PATH | 有序条目，保留重复、空条目、缺失与空值的区别 |
| process PSModulePath | 同上；不枚举或导入磁盘上所有模块 |
| process PATHEXT | 有序扩展名；保留原始大小写和空值语义，不去重 |
| PSModuleAutoLoadingPreference | 调用者原始值、是否显式设置和有效值；未设置的默认值与显式 All 分开记录 |

其余只允许解析和比较必需的元数据：schemaVersion、discoveryPolicyVersion、redactionScheme、redactionVersion、keyId、字段状态/固定 reason code。
不采集 username、机器名、系统环境清单、OS 构建号、时间戳、PID、命令历史、凭据、模块清单、程序版本或文件内容。
用户目录只允许临时读取用于脱敏分类；不作为原始字段落盘。

## Privacy model

默认且 v0.1 始终脱敏，无 raw/unredacted 输出开关，无上传和遥测。

- 默认仅保证同一 Windows 用户、同一机器、同一个本地 secret 下的稳定比较。不新增 PrivacyKeyPath 参数、密钥命令或配置界面。
- secret 固定存储在当前用户 LocalApplicationData 特殊目录下的 `pwsh-session-delta/redaction-v1.key`；Windows 通常显示为 `%LOCALAPPDATA%\pwsh-session-delta\redaction-v1.key`。使用系统特殊目录 API 获取路径，不根据当前项目目录或调用 shell 决定位置。
- secret 为密码学安全随机生成的 32 个原始字节，仅用于 HMAC；不是用户密码、机器名或路径派生值。首次 Export、且工具目录尚不存在时建立专用目录与 secret，之后所有会话只读取复用。目录本身是已有状态标志；另存一个 64 字节非敏感 `redaction-v1.id`（派生 keyId）以检测等长 secret 的意外损坏。标记缺失/不符同样失败关闭，不自动补建。Compare 不需要这两个本地文件，也不创建它们。
- 创建目录时即设置受保护 DACL：owner 为当前用户 SID，只允许当前用户和 LocalSystem 访问，并让新文件继承这份受限 ACL。写 secret 前及复用时验证目录/文件无宽泛授权、无异常 owner、无 reparse point；无法确认本地位置或 ACL 时失败，不提权、不修复现有权限、不修改父目录权限。ACL 仅保护工具自身产物，不是系统修复功能。
- 文件通过 CreateNew 独占创建，不覆盖既有 secret；并发创建者只能读取并验证胜出者的完整 32 字节文件，未完成/不可读时明确失败重试，不自行覆盖或重新生成。工具目录已经存在而 secret 缺失、文件长度错误、读写失败或 ACL 不合格时，Export 返回固定脱敏错误并停止，不输出 snapshot、不退回明文或临时 secret。只有首次全新目录允许生成。
- 不引入 DPAPI/凭据库、云端存储、同步或 rotation framework；受限 ACL 下的原始 secret 文件是本版本的最小合同。管理员、SYSTEM、同用户恶意进程和磁盘离线读取不在此保护保证内。
- 使用完整 HMAC-SHA256，而非普通 SHA256，降低对常见路径/短函数的离线字典猜测风险。
- 同一密钥、算法版本、字段域和原文产生相同标记；不同路径不得统一成一个占位符。输入固定为 UTF-8(`pwsh-session-delta:redaction:v1` + NUL + domain + NUL + 原文)，无 BOM；domain 来自固定内部枚举，不能由用户指定。显示示例：`<USERPROFILE:path:hex>`、`<PATH:hex>`、`<COMMAND:hex>`、`<FUNCTION:hex>`；hex 为完整 64 位小写十六进制摘要。
- 路径 HMAC 的域在 CWD、PATH、PSModulePath、候选文件之间一致，方便跨字段关联。分类标签只是解释标签；比较身份使用独立 digest，不比较显示标签。
- 对 UTF-8 原始路径字符串计算摘要，保留大小写、尾斜线、相对形式等文本差异。不擅自归一化、展开变量、解析链接或合并目录；这些差异仅是文本观察，不证明文件实体不同。
- PATH 与 PSModulePath 保留顺序和重复身份；同一目录在 A/B 中的位置变化可被确认。
- Function definition hash 使用读取到的定义字符串的 UTF-8 字节，不改变换行、空白和 Unicode。源码不同即 hash 不同；不宣称行为不同。源码不可写入 snapshot、报告、错误、调试输出或测试结果。
- CommandName、Alias 目标、module identity 也可能含私人名称，默认使用分域 HMAC 标记；用户可用输入顺序对应查询项。不能只脱敏文件路径而泄漏函数名中的用户名。
- profile 路径、机器名、项目名和文件名均不以原文或保留的路径尾部输出。错误只用固定 reason code，不记录原始 exception/message/stack trace。
- snapshot 必须记录 `redactionScheme='HMAC-SHA256'`、`redactionVersion=1`、`keyId`。keyId 固定为 HMAC-SHA256(secret, UTF-8(`pwsh-session-delta:key-id:v1`)) 的完整小写 hex，使用独立域，不需额外 UUID 文件。它同时作为本地完整性标记内容，是可公开的比较标识，不含 secret，但会关联同 secret 的快照；不是抵御同用户攻击者同时替换两个文件的认证机制。
- secret 及其任何可恢复编码绝对禁止进入 snapshot、报告、日志、错误；也不记录其路径或原始值映射表。只输出上述 keyId 和脱敏摘要。报告沿用标记，Compare 无需读取本地 secret。
- keyId 不同/缺失、redaction scheme/version 不兼容导致受影响的脱敏字段 `Unable to determine`；仍可比较版本等不依赖密钥的字段。keyId 不是文件签名，不证明第三方 snapshot 真实或未被修改。
- secret 不提交或分享。删除本地状态会失去旧标识的连续性；不提供恢复/同步功能。复制 snapshot 前仍应检查内容。

这是确定性假名化，不是不可逆匿名化：会泄漏相等关系、顺序、数量、命令类型与 profile 分类；密钥泄露会削弱保护。
v0.1 面向同一 Windows 用户下的两个会话；跨机器/跨用户可比性不是必需能力。
此处固定了最小存储和比较合同；Stage 2A 已实现并测试实际 ACL、损坏/不可读和输出失败，并通过两个进程竞争首次创建的测试：成功者必须共享 keyId，未完成状态允许安全失败后重试。该有界实验不是对所有并发时序或掉电行为的证明。

## Safe command discovery requirement

### Adopted semantics

采用“当前会话可见候选发现”，不预测启用自动加载后实际执行会发生什么。

1. 只接受 literal、非空 bare command name（可带 `.exe/.cmd/.bat/.ps1` 后缀）；不执行输入。路径、模块限定、参数串、控制字符或无法无歧义解释的输入返回 `Unable to determine / UnsupportedCommandForm`，不传给解释器。`* ? [ ]` 和反引号在本接口中是名称的字面字符，绝不表示用户模式；其中 `* ?` 不能出现在 Windows 普通文件名中，但可以出现在 Alias 名称中。
2. 使用受信任的 `Microsoft.PowerShell.Core\Get-Command`，查询模式必须包含真实的通配符：`WildcardPattern.Escape(name) + '*'`，并使用 `-ListImported -All`。在结果中按 `OrdinalIgnoreCase` 严格筛选指定名称，不接纳前缀相似命令。
3. 对不带扩展名的输入，只为 Application/ExternalScript 候选接受严格等于 `name + PATHEXT entry` 或 `name + '.ps1'` 的名称，按 OrdinalIgnoreCase 比较；PATHEXT 只接受普通扩展名条目，不将它作为查询模式。其他类型必须严格等于 name。保留匹配依据；这些是名称关联规则，不是对可执行性或完整 PowerShell resolution 的模拟。
4. v0.1 不修改任何 scope 的 PSModuleAutoLoadingPreference；直接记录调用者值。Stage 1.5 在 All 下验证 wildcard 路径，局部 None 既非必要也不是安全保证。
5. 仅从结果手动投影 Name、CommandType、必要模块身份和文件 Path；Alias 只读目标，Function 只读定义并立即 HMAC。禁止通用 CommandInfo JSON 序列化。
6. 禁止使用精确名称 Get-Command 作为后备；禁止 `-ArgumentList`、`-Syntax`、`-ParameterName`、参数元数据枚举、Alias.ResolvedCommand、Get-Help、dot-source、Invoke-Expression、调用运算符执行目标及 `--version`/`--help` 探测。
7. 不用 `Import-Module` 加载目标依赖，不枚举未加载模块来补全结果，不启动新的 runspace/子进程代替本会话。正常显式导入本工具本身是使用准备，不是目标命令发现。
8. wildcard 结果按类型/名称排序，不能当成执行优先级。v0.1 只比较候选集合及独立的有序 PATH/PATHEXT；不提供 winner/observed binding 推断，即使只看到一个候选也不能宣称它必将执行。询问最终 resolution winner 时固定返回 `Unable to determine / CandidateOnlyPolicy`。这一能力边界是报告说明，不是人为添加一个永远 unknown 的快照 diff 字段；A10 仍比较实际可观察字段。
9. 空集合表示 “No candidate observed under this policy”，不等于全系统不存在命令。实际调用是否会 autoload、Alias 最终会到哪里、命令能否运行均不作保证。
10. 已确认一个限制：`Escape(name) + '*'` 能匹配特殊字符 Alias，但在 7.6.5 和 7.6.6 中漏掉实际存在的 `delta[box].exe`。因此含 `* ? [ ]` 或反引号的名字，其 external candidates 完整性必须为 `Unable to determine / LiteralExternalNameNotQualified`；仍可单独报告可靠观察到的同名 Alias/Function。不得把空结果当作 external 不存在，不做精确查询、全 PATH `*` 查询或自行解释 shell 文本来补全。
11. 查询错误、权限问题、发现范围不完整、作用域不可见、搜索路径不可安全检查时，受影响字段返回 `Unable to determine`。只做已知本地搜索目录的必要读取；发现 UNC、映射网络盘、无法判定的重解析路径等时，在 external lookup 前停止该分支，不做网络探测/鉴权/远端访问。此规则是保守拒绝，不要求实现网络诊断、全系统链接扫描或证明整个 OS 没有任何网络流量。

### Evidence and release gate

Stage 1.5 在 Windows / PowerShell 7.6.5 中比较 wildcard -All 与 wildcard -All -ListImported：Alias、Function、已加载 Cmdlet、PATH 中 exe/cmd/bat/ps1 及重复 executable 的候选一致；只有未加载模块的 Cmdlet 被 ListImported 排除。这正好符合“当前会话可见候选”合同，因此保留 ListImported，而不是为搜索更多模块而删除它。
交换 PATH 目录顺序会交换同名文件位置；交换 PATHEXT 顺序不改变 wildcard 按类型/名称分组的顺序。PowerShell 7.6.5 源码也确认该排序，不能用第一项推断 winner。
测量期间 loaded-module 集合无变化，未新增导入、构造函数、函数正文、脚本正文、dynamicparam 或 batch 标记。exe 使用复制的 pwsh host；没有调用目标的代码，但未做独立原生进程启动跟踪，不能把这项证据夸大为完整 A11 已通过。
Stage 1 的普通精确查询及“精确名称 + ListImported + 局部 None”触发导入的历史结论保留；Stage 1.5 不重跑这些不安全正控制。
这是受控夹具证据，不是所有 PowerShell 7 版本、所有作用域或恶意会话的安全证明。
详见 [研究记录](docs/command-discovery-research.md)、[Stage 1.5 实验](tests/research/Compare-WildcardDiscovery.ps1) 与 [脱敏实验结果](tests/research/command-discovery-7.6.5.json)。
正式发布前必须让真正的 Export 实现通过下列 Pester 测试，包括原生 executable 不执行、查询前后 loaded-module 集合一致、失败路径不导入，以及 bare name 扩展名处理。
如果实现无法通过，只返回 unknown 或停止发布，不能偷偷放宽只读约束。

## Tri-state result semantics

每个可比较字段只有以下三个结论，JSON 与 Markdown 使用相同的英文标签：

| 结论 | 条件 |
| --- | --- |
| Confirmed difference | 两侧该观察完整、可比，值不同；仅确认观察差异 |
| No observed difference | 两侧该观察完整、可比，值相同 |
| Unable to determine | 任一侧失败、不可见、不完整、策略不兼容或证据不足 |

字段中的 absent / empty / not observed 是采集状态，不是第四种比较结论。unknown 不得编码成 null 后与另一侧 null 判相等。
两个完整空候选集合可以是候选集合的 `No observed difference`；其最终执行解析仍可能 `Unable to determine`。
汇总：至少一项 confirmed 时为 `Confirmed difference`，并单列 unknown 数量；没有 confirmed 但有 unknown 时为 `Unable to determine`；全部可比且相同才为 `No observed difference`。
schema 不支持、JSON 损坏、必需字段/隐私标识缺失或类型错误时终止失败，不返回业务 unknown。结构合法但 scheme/version/keyId 不兼容时，仅依赖这些 identity 的比较 unknown，普通字段继续比较；不重新查询、不猜测。不加入 snapshot 签名或真实性认证能力。
查询集合不同的缺项为 unknown；缺失、空值、显式设置和默认值分开比较。报告必须注明覆盖范围。
schema 1 的 query 本身是原始输入文本 HMAC；无法在离线比较中恢复 OrdinalIgnoreCase 名称语义。按已有摘要匹配，大小写拼写不同可能成为两个缺项 unknown。重复 query 一致时合并并记录次数，冲突时 unknown；候选按保留数量的无序多重集比较。详细规则见 docs/comparison-schema.md。
禁止因果断言，例如 “Root cause found”、“This caused the issue”、“The problem is definitely ...”。

## v0.1 acceptance tests

以下是完整 v0.1 发布门槛。Stage 3 已全量执行采集、比较、native/binary 正负控制与自动化双进程 E2E；102 个正式测试通过，0 失败、0 跳过。A01–A20 最新自动化 gate 证据见 docs/stage3-validation.md；Stage 4 人工验证结果见 docs/stage4-manual-validation.md。研究探针不能替代正式测试。
涉及两会话时分别在 A/B 内调用实际 Export，随后仅消费文件做 Compare。

来源编号指最初需求的章节；Stage 1.5 指本轮明确收紧的技术合同。20 项均是原要求的直接测试或细分，不增加 public command、集成或诊断产品能力。

| ID | 场景与必须满足的结果 | 冻结 requirement 来源 | 性质 | v0.1 release gate |
| --- | --- | --- | --- | --- |
| A01 | 临时同名 Alias 只在 A 存在：Alias 字段 Confirmed difference；目标不运行 | 原 §3、§4、§8：同名 Alias | 直接验收 | 是 |
| A02 | 临时 Function 只在 A 存在：存在性 Confirmed difference；不运行函数 | 原 §3、§4、§8：Function 存在性 | 直接验收 | 是 |
| A03 | 同名 Function 定义不同则 hash 不同，同定义同 secret 则 hash 相同；JSON/Markdown/错误无源码 | 原 §3、§6、§8：定义 hash 与不泄漏源码 | 直接验收及隐私细分 | 是 |
| A04 | PATH 相同条目顺序不同：Confirmed difference；不排序、不去重 | 原 §3、§8：process PATH 顺序 | 直接验收 | 是 |
| A05 | 同名命令在两侧不同本地路径可见：候选路径 Confirmed difference；winner 明确 Unable to determine，不断言因果 | 原 §3、§4、§5、§8：不同解析路径且不猜测 | 直接验收，删除未验证的 winner 推断承诺 | 是 |
| A06 | 不存在的普通命令：完整候选为空；不崩溃、不导入；不据此宣称全系统不存在/实际执行必失败 | 原 §4、§5、§8：命令不存在 | 直接验收及语义细分 | 是 |
| A07 | 路径包含空格：完整保留条目，不按空格拆分；安全发现成功 | 原 §8：空格路径 | 直接验收 | 是 |
| A08 | 路径包含中文/非 ASCII：UTF-8 往返、稳定标记和比较正确 | 原 §8：非 ASCII 路径 | 直接验收 | 是 |
| A09 | 用户名、profile、机器名、私人路径、PATH/PSModulePath 原文、函数内容和 secret 不出现在快照/报告/错误中 | 原 §6、§8：默认脱敏 | 直接验收及泄漏面细分 | 是 |
| A10 | 完整且相同的观察字段：No observed difference；采集文件名不影响；报告注明 candidate-only 边界 | 原 §5、§8：无观察差异 | 直接验收 | 是 |
| A11 | exe/cmd/bat/ps1/Function/dynamicparam 的执行哨兵保持未触发；禁止 --help/--version；检查查询代码无目标调用 | 原 §4、§8：不执行目标 | 安全测试细分；cmd/bat 只是 PowerShell 候选文件 | 是 |
| A12 | 工具已导入后的实际 lookup 中，未加载 fixture 无 import marker、loaded-module 集合不变；loaded/unloaded Cmdlet 和各 external 类型符合冻结策略 | 原 §4、§8；Stage 1.5 §1：无 autoload | 安全测试细分；夹具准备不计为 lookup，也不要求危险精确查询 | 是 |
| A13 | 权限/读取/发现失败：受影响字段 Unable to determine，不把两个失败值判相同；其余可比字段正常比较 | 原 §4、§5、§8：采集失败 | 直接验收及部分失败细分 | 是 |
| A14 | Alias/Function/应用共存、前缀近似名、bare name/扩展名、多目录候选：严格筛选、不从列表顺序推断 winner | 原 §3、§4、§5；Stage 1.5 §1：安全发现 | 边界测试细分 | 是 |
| A15 | scheme/version/keyId 缺失/类型错误：无效输入终止失败；结构合法但不兼容：受影响摘要字段 unknown；同用户同机同 secret 的独立快照标记稳定 | 原 §6；Stage 1.5 §2；Stage 2B §2、§5：验证与 identity 分层 | 隐私测试细分，无跨机器/用户功能 | 是 |
| A16 | PATH/PSModulePath 空条目、重复、missing/empty、尾斜线、大小写文本差异按规则保留；PATHEXT 顺序也保留 | 原 §3、§6：有意义的环境路径比较 | 数据边界细分 | 是 |
| A17 | lookup 前后 PATH、PSModulePath、偏好、Alias、Function 不变；模块/调用者作用域及默认偏好正确观察或 unknown | 原 §2、§3、§4：实际会话、指定字段、只读 | 状态与作用域细分，不实现 IDE/agent 集成 | 是 |
| A18 | `* ? [ ]`/反引号按字面匹配；external 特殊字符限制标 unknown；路径/参数串及不安全搜索路径安全拒绝，无精确 fallback | 原 §4、§5；Stage 1.5 §1：安全输入和未知语义 | 安全拒绝测试，不新增网络诊断或全局无网络证明 | 是 |
| A19 | JSON 损坏/schema 不兼容、Markdown 特殊字符、unknown/confirmed 混合：错误脱敏、输出有效、汇总符合三态 | 原 §5、§6、§7：三态和 JSON/Markdown | 格式/错误处理细分，不增加签名认证 | 是 |
| A20 | snapshot 写失败或已存在不静默覆盖；Compare 只返回结果、不写报告文件；secret 首次安全创建、跨会话复用，丢失/不可读/损坏/宽松 ACL/并发未完成时失败关闭；Compare 不读 secret 或当前命令环境 | 原 §2、§4、§6、§7；Stage 1.5 §2；Stage 2B §1、§17：本地只读与最小输出接口 | 持久化安全细分，不新增密钥管理功能 | 是 |

审计收紧：A05 删除“无歧义 observed binding”推断；A12 不把不安全精确正控制列为必需 gate；A18 删除可能被理解为全系统网络监控的绝对承诺；A19 不要求验证第三方 snapshot 的真实性；A20 不再把“secret 已存在”当作错误，正常复用才是预期。
未发现 IDE/Codex 专用集成、clean shell 创建、自动修复、全系统/环境扫描、GUI、AI、telemetry 或上传混入这些 gate。

## Known limitations

- 快照是顺序读取，不是原子状态锁；另一个线程/进程改变文件或路径可能影响观察，不锁定系统。
- 发现受作用域、加载状态、文件可访问性影响；不遍历所有模块，不证明完整系统状态。
- wildcard 候选不等同运行时 winner；v0.1 不推断 winner。特殊字面字符 external 查询已有可复现漏项，完整性必须 unknown；其他版本/作用域仍需发布前验收。
- 只记录路径和定义文本身份；不验证 executable 内容、签名、版本、可运行性、参数或依赖。
- HMAC 相同不证明行为相同；定义/路径文本不同也不证明故障原因。
- 不为恶意修改 PowerShell engine、command lookup hooks 或当前进程提供安全沙箱保证；不得执行任意插件来尝试补全数据。
- 已有 Export MVP；从局部函数、脚本文件或嵌套 scriptblock 调用时，internal observations 与偏好保守 unknown，顶层实际会话已验证。不实现反射访问 caller 私有状态。
- Export 通过 UTF-8 临时文件、Flush(true)、同目录不覆盖 rename 发布完整文件；临时文件只放在用户显式指定的输出目录，无默认仓库路径。失败清理仅处理该唯一临时文件，不清理旧研究目录。掉电/进程强杀可能留下脱敏 .tmp，不会把它标为最终 JSON；不提供事务恢复系统。
- Stage 3 已关闭原生哨兵启动检测和实际 binary Cmdlet autoload 的自动化 gate；Stage 4.1 在 Windows ARM64 / PowerShell 7.6.6 上重跑 152 次研究查询及完整 102 项测试通过，qualified runtimes 为 7.6.5、7.6.6。Stage 4 已由真实用户报告 PASS。
- Stage 5 采用 MIT，版权署名 laweit-lxy；当前尚未发布。

## Deferred ideas

- case-insensitive privacy-preserving query identity：未来独立评审；本阶段不改变 schema 1 的原始文本 HMAC。
- current-vs-clean-child convenience mode；不能成为 v0.1 依赖。
- 更广版本矩阵、更多输入形式、跨用户/机器比较及更丰富报告：以后另行评审。
- 完整 resolution/winner 模拟、特殊字符 external 名称的更完整发现：只有在不执行/不导入的约束下另行证明后才考虑。
- 自定义 secret 路径、跨机器/用户 pseudonym、云密钥、同步、UI 和 rotation framework 不属于 v0.1，也不作为当前计划。
- Stage 5 已准备 MIT 和最小 CI；GitHub 远程仓库、Gallery 打包与发布仍是后续阶段。
- 不把本页 Non-goals 自动转为未来路线图。

## Competitive positioning

只允许以下谨慎措辞，不声称 first、unique 或 only：

> Limited research did not identify an obvious direct substitute combining two-session PowerShell snapshot comparison, command-resolution-focused diagnostics, privacy-aware reporting, and a read-only design.

该句是允许的定位措辞，不代表本阶段完成了市场调查；本次研究仅验证安全 discovery 设计。
