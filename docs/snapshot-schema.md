# Snapshot schema 1 — Stage 2A

此合同在采集实现之前固定。只使用普通对象、数组、字符串、数字、布尔值和 null，不序列化 CommandInfo 或其他 runtime object。

顶层固定字段：

| 字段 | 值 |
| --- | --- |
| schemaVersion | 1 |
| capture | `{ model: 'current-session', discoveryPolicyVersion: 1 }`；无时间戳、PID、机器名 |
| privacy | `{ redactionScheme: 'HMAC-SHA256', redactionVersion: 1, keyId: 64位小写hex }` |
| observations | 六项观察：powerShellVersion、workingDirectory、path、psModulePath、pathExt、moduleAutoLoadingPreference |
| commands | 按输入顺序排列的 command observation 数组 |

所有 observation 固定为 `{ status, reasonCode, value }`：

- `Confirmed observation`：读取成功且存在；reasonCode=null。
- `No observed value`：读取成功且不存在；reasonCode=null，value=null。空字符串和空条目不是缺失。
- `Unable to determine`：失败/未资格化；固定非敏感 reasonCode，value=null。不把失败与缺失混为一谈。

powerShellVersion.value 为版本字符串。workingDirectory.value 为路径 token。
path/psModulePath.value 为有序 token 数组，保留重复和空项；空项 token 对空字符串进行相同 HMAC。
pathExt.value 为有序字符串数组，仅允许普通扩展名或空项；异常文本整项 unknown，避免泄漏任意私人内容。
moduleAutoLoadingPreference.value 为 `{ explicitlySet: boolean, effectiveValue: 'All'|'None'|'ModuleQualified' }`；未设置时仍为 Confirmed observation、explicitlySet=false、effectiveValue=All。不能安全解释的值 unknown。

token 固定为 `{ kind, digest }`；kind 为 `path`、`command`、`alias-target`、`module` 或 `function`；digest 为 HMAC 完整小写 hex。无原文，无尾部路径提示。函数对 Definition 原始 UTF-8（无 BOM）计算 HMAC，不更改换行、空白、大小写或 Unicode。

每个 command 固定为：

```text
{ query: command-token,
  internalCandidates: observation,
  externalCandidates: observation,
  aliases: observation,
  functions: observation }
```

候选存在时 value 为数组。internal candidate：`{ name: command-token, type: 'Alias'|'Function'|'Filter'|'Cmdlet', module: module-token|null }`。
external candidate：`{ name: command-token, type: 'Application'|'ExternalScript', path: path-token }`。
alias：`{ name: command-token, target: alias-target-token }`，不解析目标。
function/filter：`{ name: command-token, definitionDigest: 64位hex }`。
完整空集合记 No observed value。部分扫描不完整时整个相应分支 unknown，不保存可能被误当成完整集合的部分候选。internal 和 external 状态独立。

无 winner 字段，无比较结论字段；这是观察三态，不是 Stage 2B 的差异三态。查询顺序只对应用户输入；候选顺序没有优先级语义。

固定 reason codes：UnsupportedCommandForm、LookupFailed、UnsafeSearchPath、LiteralExternalNameNotQualified、RuntimeNotQualified、LocationUnavailable、EnvironmentReadFailed、InvalidPathExt、PreferenceUnavailable、CallerScopeNotVisible。
致命 Export 错误不产生 snapshot：InvalidOutputPath、OutputExists、SecretUnavailable、SnapshotWriteFailed。错误文本只含固定 code，无底层异常消息/目标对象。

输出为 UTF-8 无 BOM JSON。必须包含所有顶层字段；版本/策略变更不得悄悄改变 schema 1 的字段含义。
示例见 [example-snapshot.json](example-snapshot.json)；它使用虚构内容和公开虚构 key，不是用户的真实快照。

Stage 2A 实现边界：caller 函数/脚本/嵌套 scriptblock 的局部可见性不可靠时，internalCandidates/aliases/functions 为 CallerScopeNotVisible，偏好为 PreferenceUnavailable；external 仍可根据 process PATH 单独观察。此 code 在 schema 冻结后的实现验证中明确补齐，不新增采集字段。
