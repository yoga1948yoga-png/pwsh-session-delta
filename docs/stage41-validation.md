# Stage 4.1 — PowerShell 7.6.6 runtime qualification

结论：READY TO REPEAT STAGE 4 ON POWERSHELL 7.6.6。

Validated on Windows ARM64 with PowerShell 7.6.5 and 7.6.6.
本轮仅认证 7.6.6，不声明整个 7.6.x、未来版本或全部 Windows 系统。没有执行人工 Stage 4，没有远程仓库、push、CI、打包或发布。

## Root of RuntimeNotQualified

`src/PwshSessionDelta/Private/Discovery.ps1` 的 Get-DeltaCommandObservation 原第 11 行精确判断 `$PSVersionTable.PSVersion.ToString() -ne '7.6.5'`，其他 runtime 在任何发现查询前返回。
四个 command observation 分支 internalCandidates、externalCandidates、aliases、functions 全部为 Unable to determine / RuntimeNotQualified。
这是主动安全降级，不是 Export 写入失败。版本、cwd、PATH、PSModulePath、PATHEXT、偏好等普通观察仍按原逻辑采集；query token 仍可生成。

首先只读定位 gate 后才运行研究，研究一致后才调整候选精确版本集，再以完整产品测试完成认证。没有删除 gate 或以 >= 比较替代它。

## Actual test runtime

Windows OS API version Microsoft Windows 10.0.26200；OS/process 均 Arm64；PowerShell 7.6.6；Pester 5.9.0；非管理员 token。
Codex primary runtime 仍为 7.6.5；本轮显式调用已安装 Microsoft.PowerShell 7.6.6 ARM64 包的 pwsh.exe。测试中的独立进程使用该进程的 PSHOME，因此 A11/A12 与双进程 E2E 也实际运行在 7.6.6。

## Research

复用 Stage 1.5 探针，增加 ExpectedVersion 参数（默认仍为 7.6.5），只改变运行版本检查和一条断言标签；研究查询/夹具算法没有改变。
[独立 7.6.6 evidence](../tests/research/command-discovery-7.6.6.json)：152 次查询，447 项断言通过，唯一 marker 是准备阶段主动导入 loaded fixture 的 marker。测量期间模块集合不变、marker 数量/字节数不变。

与 [7.6.5 evidence](../tests/research/command-discovery-7.6.5.json) 的完整 Rows 数据以 depth=10 压缩 JSON 做大小写敏感比较，152 行完全相同（含候选顺序、接受集合、PATH/PATHEXT 组合和副作用检查）。旧文件未覆盖。

| Contract | 7.6.6 result |
| --- | --- |
| wildcard Get-Command -All | 不导入未加载 fixture，不执行目标或追加 marker |
| 加上 -ListImported | 普通 external candidates 不遗漏；排除未加载 binary Cmdlet |
| Alias / Function / loaded Cmdlet | 与 7.6.5 一致 |
| unloaded binary Cmdlet | wildcard 可列出但不导入；ListImported 排除 |
| exe / cmd / bat / ps1 | 两种查询方案候选一致 |
| 多 PATH 目录同名 executable | 两个候选均保留；交换 PATH 顺序可改变同名条目次序 |
| 普通不存在 command | 完整空集合 |
| * ? [ ] 和反引号 literal Alias | Escape + 人工追加 wildcard + exact filtering 保留字面名称 |
| bracket external 名称 | 已存在的 delta[box].exe 仍漏项，继续 unknown |
| candidate ordering | 改 PATHEXT 顺序不改变类型/名称分组；不可解释为 winner |

没有发现这些受测行为相对 7.6.5 改变；不把这解释为所有未测行为完全相同。

## A11 / A12

A11 PASS：复用 choice.exe 唯一副本的 native sentinel。独立正控制实际启动后被检测且持续存在；产品 Export 负控制正常产生 Application 候选，未检测到 sentinel 启动。无管理员依赖。代码静态执行边界检查与 script/batch/Function/dynamicparam 原测试也通过。

A12 PASS：每个正负控制均为全新 pwsh -NoProfile 进程。

| Fixture | Positive module / assembly | Product negative module / assembly |
| --- | --- | --- |
| CimCmdlets | 0→1 / 0→1 | 0→0 / 1→1（已有基线，无新增） |
| Microsoft.PowerShell.ThreadJob | 0→1 / 0→1 | 0→0 / 0→0 |

两侧负控制的 loaded-module 集保持不变，snapshot 符合 ListImported 当前会话候选语义。正控制仅精确 Get-Command，不执行目标 Cmdlet。CimCmdlets 基线预加载与 Stage 3 相同；ThreadJob 提供明确 assembly 未加载证据。

## Full regression

[stage41-test-results-7.6.6.json](stage41-test-results-7.6.6.json) 来自完整 Stage 3 runner；其中 stage=3 表示复用的测试套件，而非误用历史结果，environment.powerShell=7.6.6。

| Suite | Total | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: | ---: |
| Export + independent Session | 35 | 35 | 0 | 0 |
| Compare | 57 | 57 | 0 | 0 |
| Release controls / E2E | 10 | 10 | 0 | 0 |
| Total | 102 | 102 | 0 | 0 |

差异 E2E：5 confirmed、13 equal、0 unknown；相同 E2E：0 confirmed、18 equal、0 unknown。
24 份端到端产物隐私扫描通过，Compare offline 回归通过。release TestDrive 清理完成；研究夹具残留另见下文，二者不是同一个目录。

## Minimal production change

只修改 Private/Discovery.ps1：

```powershell
$qualifiedVersions = @('7.6.5', '7.6.6')
if ($PSVersionTable.PSVersion.ToString() -cnotin $qualifiedVersions) {
    # 原有 RuntimeNotQualified 返回逻辑保持不变
}
```

没有修改 wildcard escaping、exact filtering、ListImported、candidate ordering、PATH 安全检查、caller scope、Alias/Function 采集或隐私算法。
snapshot schema 1 和 comparison schema 1 不变。实际 PowerShell 版本仍直接采集当前 runtime 的版本，未改成常量。

## Cleanup and limitations

研究进程内清理遇到加载中 DLL 锁，进程退出后的递归删除请求被自动审批策略拒绝，未改用其他方式绕过。
本轮唯一剩余研究目录：`%TEMP%\pwsh-delta-stage15-<run-id>`，已检查剩余顶层为 DeltaLoaded。位于仓库外，未被 Git 跟踪；只包含合成研究夹具，无产品 secret 或用户 snapshot。

无新增 discovery 限制。保留 query HMAC 大小写不能离线归一化、特殊字符 external unknown、复杂 PATH 和 caller scope 保守 unknown、不推断 winner/根因等原限制。
下一步由用户在 7.6.6 的两个实际 Session 重新 Import-Module -Force，再重复人工 Stage 4；本次没有冒充人工验收 PASS。
