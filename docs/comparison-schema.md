# Comparison schema 1 — Stage 2B

`Compare-PwshSessionSnapshot -ReferencePath <string> -DifferencePath <string> [-Format Object|Json|Markdown]`

Object 为默认输出。路径是 LiteralPath 语义，包括空格、中文和方括号；只解析用户提供的文件名并读取这两份文件，不展开 wildcard。无输出文件参数；工具本身不写报告文件，不覆盖文件。需要持久化时由调用者自行选择 PowerShell 输出重定向策略。

## Input validation

仅接受 snapshot schemaVersion=1、capture.model=current-session、discoveryPolicyVersion=1 的既有结构。手写 validator 检查所有层级必需/允许字段、确切字段名、类型、状态与 value 的对应关系、token kind/digest 和固定 reasonCode。JsonDocument 首先检测任意层级重复键及大小写冲突键；损坏 JSON、注释、尾随逗号、缺字段、额外字段、错误类型、空的成功候选数组均拒绝。之后 ConvertFrom-Json -AsHashtable 读取普通数据。

失败为终止错误 `InvalidReferenceSnapshot` 或 `InvalidDifferenceSnapshot`，不返回正常比较结果，不携带输入内容、文件路径或底层异常消息。PowerShell host 自己可能显示调用位置；这不是工具生成的报告内容。合法 observation 的 unknown 才进入比较逻辑。输入验证不验证快照真实性；知道 schema 的人仍能伪造数据。

隐私元数据的读取合同：scheme 是 1–32 位 ASCII 字母/数字/连字符标识，version 是正整数，keyId 是 64 位小写 hex。允许结构正确但不认识的 scheme/version 进入字段级 unknown；只有双方均为 HMAC-SHA256 / 1 且 keyId 相同才比较 HMAC 值。缺失或类型错误仍是无效输入。此读取兼容规则不更改 Export 的 schema 1 输出合同。

## Result shape

```text
{
 comparisonSchemaVersion: 1,
 reference: { snapshotSchemaVersion, discoveryPolicyVersion, privacy },
 difference: { snapshotSchemaVersion, discoveryPolicyVersion, privacy },
 summary: { status, confirmedDifferences, noObservedDifferences, unableToDetermine },
 fieldResults: [ result ],
 commandResults: [ { queryDigest, referenceOccurrences, differenceOccurrences, results: [result] } ],
 notes: [ fixed explanation strings ]
}
result = {
 category, status,
 reference: { status, reasonCode } | null,
 difference: { status, reasonCode } | null,
 reasonCode, explanation,
 details: { referenceValue, differenceValue } | { referenceOnly, differenceOnly, both } | null
}
bag entry = { identity: safe schema-v1 identity object, count: positive integer }
```

不记录输入文件名、时间、PID、机器名、secret 或完整输入快照。普通字段 details 仅包含对应已验证值；候选值放进 bag 明细，不再次复制到 observation 摘要。query 无法配对时 observation 为 null，捕获次数在 command 容器中说明，只有一条 query-level unknown，不能伪造四项候选差异。

字段结果固定顺序：powerShellVersion、workingDirectory、path、psModulePath、pathExt、moduleAutoLoadingPreference。命令按 query digest 的 Ordinal 顺序排列；命令结果固定 internalCandidates、externalCandidates、aliases、functions。bag identity 的属性和条目按 Ordinal 排序。排序只用于报告/集合，不用于路径序列或 winner 推断。

## Tri-state helper

依次处理：

1. 任一侧 unknown：`Unable to determine / ObservationUnknown`，包括两个 unknown。
2. 双方 absence：`No observed difference / BothAbsent`。
3. 一方 absence、另一方成功 presence：`Confirmed difference / PresenceChanged`。这个存在性判断不比较 HMAC 值，因而不依赖共享 key。
4. 双方成功 presence 但所需隐私 identity 不兼容：`Unable to determine / PrivacyIdentityIncompatible`。
5. 否则按字段规则比较：`No observed difference / ValuesEqual` 或 `Confirmed difference / ValuesDifferent`。

| 字段 | 值比较规则 | 是否依赖共享 HMAC identity |
| --- | --- | --- |
| powerShellVersion | 版本文本精确相等；不推断兼容性 | 否 |
| workingDirectory | kind + digest 精确相等 | 是 |
| path / psModulePath | token 的有序序列，重复/空项 token 保留 | 是 |
| pathExt | 字符串有序序列，保留大小写/重复/空字符串 | 否 |
| moduleAutoLoadingPreference | effectiveValue 与 explicitlySet 均相等 | 否 |
| query/name | 已存储 command token digest | 是；v1 没有原始名字 |
| internalCandidates | 无序多重集：type + name token + module token/null | 名称/模块是；type 自身不是 |
| externalCandidates | 无序多重集：type + name token + path token | 名称/路径是；type 自身不是 |
| aliases | 无序多重集：name token + target token；不递归 | 是 |
| functions | 无序多重集：name token + definitionDigest | 是 |
| observation status / reasonCode | 状态传播，不把两个失败判相等 | 否；但先要可靠配对 query |

候选 identity 使用上述实际字段的 canonical JSON 作为内部相等性键；没有扩展名、priority、winner 等新字段。所有字段都参与 identity，null module 与有 module 不同。多重集的 both 数量=min(A,B)，referenceOnly=max(A−B,0)，differenceOnly=max(B−A,0)。不按数组位置配对，也不丢弃重复。

## Queries and duplicates

Stage 1.5 lookup 使用 OrdinalIgnoreCase 筛选真实名称，但 schema 1 的 query/name HMAC 使用原始 UTF-8 文本。Compare 无法把 HMAC 还原后 case-fold。用户应在 A/B 输入相同拼写；大小写不同的 query 摘要会形成两条未配对 query，而不是已确认候选差异。本阶段不为方便 Compare 修改 Export。

只存在一侧：`QueryNotCapturedBothSides`，继续共同 query。重复 query 在 schema 1 中允许：全部 observation 状态/reason 一致且成功值的多重集一致时合并比较，保留两侧次数；次数本身不构成产品差异。任一侧重复记录互相矛盾时，该 query 为 `ConflictingDuplicateQuery`，不任意选第一条。重复 unknown 即便一致，比较仍传播 unknown。

隐私 identity 不兼容时，即使摘要字符偶然相等，也不能可靠确认同一 query。按摘要列出被采集条目及次数，但整条 query 的结果是 PrivacyIdentityIncompatible，不跨 key 配对 Function 或 command type。版本/PATHEXT/偏好等全局独立字段照常比较。

## Summary and rendering

统计 fieldResults 和每个 command.results 的叶结果，各计一次，不重复计算 command 容器。至少一项 confirmed 则 overall=Confirmed difference；否则有 unknown 则 overall=Unable to determine；否则 No observed difference。confirmed 与 unknown 可以并存。数目描述观察项，不描述问题数、严重性或根因。

JSON 从同一个对象以显式 depth=32 序列化。Markdown 从该对象生成：metadata、summary、三态字段列表、command observations、privacy/limitations。不同的普通字段显示 reference/difference 值或有序 token，候选显示 only/both 和数量。所有显示均保持脱敏，动态文本进行 Markdown/HTML 转义；没有整段 JSON dump。

固定说明：`Differences are observations, not proof of causation.`

Compare 的文件读取只在 Read-DeltaSnapshot 中对两个输入调用 ReadAllText；不读取/创建 secret，不采集环境，不查询命令，不访问当前 Alias/Function，不导入目标模块，不执行目标。导入本工具及内置 Utility 是准备步骤。未实现敌意 session 沙箱、输入签名认证、大文件流式解析或 HMAC 碰撞证明。

示例：[JSON](example-comparison.json)、[Markdown](example-comparison.md)。示例使用公开合成快照，不含用户真实数据。
