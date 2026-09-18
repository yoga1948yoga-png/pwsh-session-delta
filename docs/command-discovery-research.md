# Command discovery research

## Stage 1.5 — final candidate discovery contract

环境：Windows / PowerShell 7.6.5 Core。日期：2026-09-17。
本节替代 Stage 1 的暂定算法解释；后面的历史记录保留，不能把旧实验的精确查询当作新算法。

### Reproduce

从项目根目录，在 PowerShell 7.6.5 中运行（仅创建研究进程）：

```powershell
pwsh -NoProfile -File .\tests\research\Compare-WildcardDiscovery.ps1 -ResultPath .\tests\research\command-discovery-7.6.5.json
```

- [脚本](../tests/research/Compare-WildcardDiscovery.ps1) 用随 PowerShell 的 Add-Type 编译两个合成 binary modules，确实导出 Cmdlet，而不是把 Function 冒充 Cmdlet。
- 准备阶段显式导入 DeltaLoaded，预期产生一个 import.marker；DeltaUnloaded 从不导入。编译和准备模块发生在测量前，不是补全查询。查询阶段保持 autoload 偏好 All，不用 None 掩盖风险。
- PATH 仅包含自己的两个临时本地目录，含空格/中文；PSModulePath 仅指向夹具目录。环境改动只在这个可丢弃实验进程中发生。
- 19 个查询名 × 2 种查询方式 × 2 种 PATH 顺序 × 2 种 PATHEXT 顺序，共 152 次查询。最终 447 条研究断言通过；含故意确认“已知漏项存在”的断言，不表示漏项已修复。
- [保存结果](../tests/research/command-discovery-7.6.5.json) 记录模式、原始候选投影、严格筛选结果、模块变化及标记变化；临时绝对路径统一替换为 `<FIXTURE>`，不保存真实用户名或机器路径。
- 每次测量前后比较 Get-Module -All 的 name/version 集合及夹具 marker 数和总字节数。导入初始化器向标记追加内容，因此重复导入同一模块也会被检测，不会被相同的模块集合掩盖。查询代码从不调用结果对象，只读取 name/type/module/path，不访问参数元数据。
- 已加载 DLL 在 Windows 下可能锁住临时目录，脚本会警告，需等研究进程退出后清理；不得 dot-source 到工作会话。结果不依赖保留临时夹具。本次直接清理被执行审批策略拒绝，已保留残留，不影响查询结果。

### Matrix

表中计数是在 PATH=A;B、PATHEXT=.EXE;.CMD;.BAT 时严格筛选后的计数。

| 场景 | wildcard -All | wildcard -All -ListImported | 解释 |
| --- | --- | --- | --- |
| Alias | 1 | 1 | 同名 Alias 可见 |
| Function | 1 | 1 | 同名 Function 可见 |
| 已加载 module 的 Cmdlet | 1 | 1 | 已加载二进制 Cmdlet 可见 |
| 未加载 module 的 Cmdlet | 1 | 0 | 无 ListImported 会返回静态可发现的未加载候选；两者均未导入它 |
| PATH 中 .exe | 2 | 2 | 两个目录的同名文件均保留 |
| PATH 中 .cmd | 2 | 2 | 分类为 Application，不执行 cmd.exe |
| PATH 中 .bat | 2 | 2 | 分类为 Application，不执行批处理 |
| PATH 中 .ps1 | 2 | 2 | 分类为 ExternalScript，不运行正文/dynamicparam |
| 不带扩展名 delta-native | 2 | 2 | name+.exe 严格名称关联，非 winner 判断 |
| 不存在命令 | 0 | 0 | 普通名字的观察候选为空，不证明调用时不会 autoload |
| 特殊字符 Alias：*、?、[、]、[]、反引号 | 各 1 | 各 1 | escape 加 exact filter 后只接受字面同名项 |
| 实际存在的 delta[box].exe | 0 | 0 | 两种方案都漏项，必须返回 external 完整性 unknown |

其余 PATH/PATHEXT 组合的配对结果也一致；两种参数方式的唯一候选差异是未加载 Cmdlet。
ListImported 没有遗漏此次实验所需的普通 external candidates；不把这一结论推广到所有名字和所有 PowerShell 版本。

### Ordering evidence

查询 delta-mixed 时，两种方案都按以下顺序输出：

```text
ps1(A), ps1(B), bat(A), bat(B), cmd(A), cmd(B), exe(A), exe(B)
```

交换 PATH 为 B;A：每对同名文件变成 B,A。
交换 PATHEXT 为 .BAT;.CMD;.EXE：上面的按类型/名称分组顺序不变。
因此结果存在可观察顺序，但不能称为最终 command resolution 优先级。

[PowerShell v7.6.5 GetCommandCommand.cs](https://github.com/PowerShell/PowerShell/blob/v7.6.5/src/System.Management.Automation/engine/GetCommandCommand.cs#L462-L467) 对含 wildcard 的结果执行稳定排序；同文件的 [CommandInfoComparer](https://github.com/PowerShell/PowerShell/blob/v7.6.5/src/System.Management.Automation/engine/GetCommandCommand.cs#L626-L649) 按 CommandType、Name 比较。
这也说明不能把官方 Get-Command 文档中精确查询 -All 的优先级说明直接套用到 wildcard 结果。
未执行目标或用精确查询进行 winner 对照；没有足够证据模拟完整执行语义，v0.1 不提供 winner 推断。

### Final algorithm

1. 输入作为字符串值接收，不插入脚本源，不调用 Invoke-Expression；拒绝路径、模块限定和参数串。
2. `pattern = [WildcardPattern]::Escape(name) + '*'`，必须先 escape 再添加工具控制的一个 wildcard；不要将整个 pattern 再 escape。
3. `Microsoft.PowerShell.Core\Get-Command -Name $pattern -All -ListImported`；不更改 autoload preference。保留 ListImported，以排除未加载模块而不是拿它当通用安全开关；禁用 autoload 的关键是保持 wildcard 查询路径。
4. 内部类型只接受 Name 与用户 name 的 OrdinalIgnoreCase 字面相等；external 类型还允许无扩展名输入与 name+PATHEXT 项/name+.ps1 的严格字符串相等，不使用 -like/-match 过滤用户名称。
5. 只保留白名单属性并脱敏；不保存原始 CommandInfo，不访问 Alias.ResolvedCommand、Parameters/ParameterSets、Syntax、Definition 之外的函数元数据。Function 定义只在内存计算 HMAC，不调用。
6. 候选集合按身份比较，与 PATH/PATHEXT 的有序条目分开；不把候选数组次序报告成优先级。无精确 fallback、不导入未加载模块、不遍历系统补全。

例如 `delta*literal` 形成的实际模式包含被转义的字面 `*`，末尾另有一个工具添加的 wildcard。
`delta[literal` 的 raw 结果还包含 `delta[literal]` 前缀项，最终 exact filter 将它剔除；这证明 filtering 是必要步骤。

这个简单 escape 方案适合作为安全的候选发现方法，但不是所有 external 名称的完整查找器。
发现 bracket executable 漏项后，冻结规则为：含 `* ? [ ]` 或反引号时，external candidates 完整性为 `Unable to determine / LiteralExternalNameNotQualified`，即使列表为空也不写“不存在”；可靠的同名 Alias/Function 可以单独记录。
不引入另一套文件系统解析器或全 PATH `*` 补扫来“修复”该限制。

### Unable to determine boundaries

- 所有最终 winner/实际调用行为问题：CandidateOnlyPolicy，即使只有一个观察候选。
- 多候选、扩展名优先级、Alias 目标递归、自动加载后的结果：不推断。
- 特殊字面字符的 external 完整性：已知未资格化，不能用空结果断言不存在。
- 读取错误、权限不足、作用域不可见、不安全/不明确搜索路径、未经验证的版本行为：受影响字段 unknown。
- 普通名字的安全完整空集合可以比较为 No observed difference；不等于全系统不存在命令。
- winner 不作为一个永远 unknown 的必比字段强行加入汇总；报告说明候选观察范围，汇总仅针对冻结的观察字段。

### Import / execution evidence and unknowns

152 次查询期间模块集合没有变化，marker 数一直为 1（仅准备阶段的 loaded-module import.marker）。没有 Cmdlet 构造/执行、Function、脚本正文、dynamicparam 或 batch 新标记。
没有执行目标、--help、--version 或查询后 Import-Module 的代码；新实验没有精确查询。
exe 夹具是复制的 pwsh.exe，没有 native 启动哨兵或进程跟踪，所以不能声称已独立实验证明原生进程绝无启动；实际 MVP 的 A11 仍须补齐这种执行检测。脚本/batch 哨兵也未通过主动执行做正控制，因为本轮禁止执行目标。
本结果不证明敌意 PowerShell engine/lookup hook 的沙箱安全，也不认证所有 7.x 版本或所有局部/模块作用域。

### Stage 1.5 readiness

READY FOR MVP IMPLEMENTATION：候选观察合同、特殊字符 unknown 边界、ListImported 选择和“不推断 winner”已经可执行地定义；HMAC 最小合同及 A01–A20 映射见 PROJECT-SCOPE。
这是允许进入后续实现审核的设计结论，不是授权本阶段开始实现，也不表示 release gate 已通过。

## Stage 1 — historical record

日期：2026-09-17。环境：Windows，PowerShell 7.6.5 Core。
仅为范围冻结提供证据；未实现产品采集器或比较器。

## 官方资料

- [Get-Command](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-command?view=powershell-7.6)：精确查询可能导入模块；ListImported 限定当前会话命令；参数元数据查询需要谨慎。
- [about_Modules](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules?view=powershell-7.5)：含通配符的 Get-Command 不触发模块导入。
- [about_Command_Precedence](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_command_precedence?view=powershell-7.6)：加载状态与命令优先级影响实际调用，候选发现不能替代执行语义。

## 方法

[Probe-CommandDiscovery.ps1](../tests/research/Probe-CommandDiscovery.ps1) 创建自己的模块 manifest 和模块正文。
模块导入时写 import.marker；导出函数如果执行则抛错。脚本目标的正文和 dynamicparam 各写独立标记。
通过标记检查区分“发现”“导入”“执行”，而不是只看 Get-Command 有没有返回对象。
探针只投影名字/类型，避免格式化原始 CommandInfo 间接获取更多元数据。

## 观察结果

| 实验 | 观察 |
| --- | --- |
| wildcard 查询 | 没有导入 fixture |
| wildcard + ListImported + All | 未加载 fixture 不在可见结果中，没有导入 |
| 普通精确名称正控制 | 写入 import.marker，证明 autoload 夹具有效 |
| 模块函数中的 wildcard + ListImported + All + 局部 None | 没有导入 fixture；调用者偏好仍为 All |
| 模块函数中的精确名称 + ListImported + 局部 None | 仍写入 import.marker；拒绝作为产品策略 |
| 调用者临时 Alias / Function | 从探针模块内可见；不执行目标 |
| Core cmdlet | 可见 |
| 空格和中文 PATH 中的 .ps1 | 可发现；正文与 dynamicparam 标记均未出现 |
| 不存在的命令 | wildcard 得到空候选 |
| 额外精确查询脚本 | 本夹具无正文/dynamicparam 执行；不能抵消前述 autoload 风险 |
| 额外精确查询不带扩展名 executable | 找到复制的 pwsh.exe；该精确查询方法仍被拒绝 |

开发探针时曾误以为局部 None + ListImported 足以安全精确查询，断言失败并确认产生了导入标记。
最终脚本把该项作为被拒绝方案的观察值保留，而不是伪装成成功的安全断言。
本次不进一步推断引擎内部的原因；scope 与 discovery 实现细节需独立研究，产品不用此路径。

## 决定和证据边界

选择 wildcard + ListImported + 严格名称过滤；禁止精确查询后备。局部 None 不能充当安全保证。
扩展名补全、多个候选顺序、局部/私有作用域、远程 PATH 排除、不同 7.x 版本仍需产品 Pester 测试。
本探针复制一个 executable 用于发现，不等于完成了带原生执行副作用检测的验收。
没有运行用户的程序；仅合成模块的正控制允许自身导入产生临时标记。
研究进程修改环境仅为夹具，产品必须保持被诊断会话状态。
发现不了或无法判定优先级时返回 Unable to determine，不通过执行目标补全信息。

## Stage 4.1 — 7.6.6 qualification

Windows ARM64 / PowerShell 7.6.6 已重跑同一探针：152 queries、447 assertions，全部 Rows 与 7.6.5 一致。保留 ListImported、literal escaping/exact filtering、特殊字符 external unknown 和 candidate-only semantics。
结果单独保存于 [command-discovery-7.6.6.json](../tests/research/command-discovery-7.6.6.json)，没有覆盖 7.6.5 evidence。A11/A12 与完整 102 项产品回归均通过。详见 [stage41-validation.md](stage41-validation.md)，含 runtime 选择、精确版本集合和研究临时目录清理限制。
