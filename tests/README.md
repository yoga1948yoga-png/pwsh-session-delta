# Tests

Validated on Windows ARM64 with PowerShell 7.6.5 and 7.6.6. Codex 内置 runtime 与用户安装 runtime 可能不同；必须检查执行文件实际版本，不能仅凭 PATH 中的 `pwsh` 名称判断。

Stage 4.1 复用完整 Stage 3 suite；在实际 7.6.6 进程中运行以下命令并为结果指定独立文件，避免覆盖 7.6.5 历史证据：

```powershell
$PSVersionTable.PSVersion # 必须为 7.6.6
.\tests\research\Compare-WildcardDiscovery.ps1 -ExpectedVersion 7.6.6 -ResultPath .\tests\research\command-discovery-7.6.6.json
.\tests\Invoke-Stage3Tests.ps1 -PesterManifest $PesterManifest -ResultPath .\docs\stage41-test-results-7.6.6.json
```

研究脚本须在 disposable `pwsh -NoProfile` 进程运行；上述为该进程内的命令示例。PesterManifest 指向已有 Pester 5.9 manifest。研究脚本的 ExpectedVersion 是防止跑错 runtime 的测试参数，不是产品 gate。
详情：[7.6.6 认证](../docs/stage41-validation.md)。旧 7.6.5 evidence 保持原样；本轮不执行人工 Stage 4。

正式 v0.1 验收清单在 [PROJECT-SCOPE.md](../PROJECT-SCOPE.md#v01-acceptance-tests)。Stage 2A Export 与 Stage 2B Compare 均有 Pester 5.9 测试。

```powershell
# 使用已安装的 Pester >= 5.9：
.\tests\Invoke-Stage2ATests.ps1
# 或显式指定本地保存的 Pester manifest（无需改系统安装）：
.\tests\Invoke-Stage2ATests.ps1 -PesterManifest C:\path\Pester\5.9.0\Pester.psd1
.\tests\Invoke-Stage2BTests.ps1 -PesterManifest C:\path\Pester\5.9.0\Pester.psd1
.\tests\Invoke-Stage3Tests.ps1 -PesterManifest C:\path\Pester\5.9.0\Pester.psd1
```

本次从官方 PowerShell Gallery 下载 Pester 5.9.0 到系统临时开发依赖目录；没有替换系统 Pester 3.4.0，没有修改 PSModulePath 持久配置。运行器本身不联网安装。

- `Export.Tests.ps1`：观察/脱敏/安全发现/ACL/文件失败路径；Pester 函数包装下的测试用 global fixtures，并仅在这些用例中模拟顶层 caller 可见性。
- `Session.Tests.ps1`：不模拟 caller 可见性，启动独立实验 pwsh 进程，调用真实 Export；验证 A/B 差异、共同 keyId、局部作用域 unknown、默认偏好和首次创建竞争。进程启动只是测试夹具，不属于产品。
- secret 存储位置只在测试模块作用域中替换到 Pester TestDrive，没有公开测试参数，不修改用户正式 secret。
- 原 A11 native Skip 已由 Stage 3 的真实正负控制替代；没有空的绿色测试。失败注入使用 Pester Mock。
- `Compare.Tests.ps1`：只使用公开合成 snapshot，验证三态、严格输入验证、顺序/多重集/query 规则、隐私不兼容、JSON/Markdown 和离线约束；不读用户快照或正式 secret。
- Stage 2B 结果见 [stage2b-test-results.json](../docs/stage2b-test-results.json)；本轮 Export 回归见 [stage2a-regression-2b-results.json](../docs/stage2a-regression-2b-results.json)。分层通过不等于完整发布资格。
- `Release.Tests.ps1`：Windows 自带 choice.exe 唯一副本的启动正控制/Export 负控制、CimCmdlets 和 ThreadJob 的独立 autoload 正负控制、真实双进程差异/相同 Export→Compare、最终隐私扫描。
- `Invoke-Stage3Tests.ps1`：全量四个测试文件，要求无失败/跳过、无提权、fixture 清理完成；扫描最终结果 JSON 和 validation Markdown，核对 src hash 未变。运行器不输出或保存扫描用的敏感字符串。
- Stage 3：[102 项结果](../docs/stage3-test-results.json)、[完整审计](../docs/stage3-validation.md)。native 正控制会故意启动测试副本，binary 正控制会在 disposable 进程故意 autoload；与产品负控制是不同进程。无需管理员、SDK 或互联网 executable。
- 结果见 [stage2a-test-results.json](../docs/stage2a-test-results.json) 和 [验收说明](../docs/stage2a-validation.md)。结果只保存固定测试名称与状态，不序列化 Pester runtime/errors。

下述研究脚本是历史实验，不属于本阶段正式测试运行器：

`research/Probe-CommandDiscovery.ps1` 是无 Pester 依赖的设计实验，不是产品逻辑。
在 Windows PowerShell 7 中，从项目根目录使用新的实验进程运行：

```powershell
pwsh -NoProfile -File .\tests\research\Probe-CommandDiscovery.ps1
```

它会创建唯一临时目录和合成模块、脚本，临时改动该实验进程的 PATH/PSModulePath。
普通精确查询和被否决的精确查询方案会有意导入自己创建的模块，以检测 autoload；不查询真实业务命令。
最后恢复该进程的环境、卸载测试模块，并在路径边界检查后清理自己创建的临时目录。
脚本只能在可丢弃的实验进程运行，不应 dot-source 到工作会话。
新进程只是安全实验容器，不是产品中的 Session B。

发布前须把核心安全断言移植到针对真实 Export 的 Pester 测试。探针成功不能替代完整模块测试，也不能证明原生程序绝无执行副作用。

## Stage 5 CI and local gates

Run all formal tests locally without elevation; use -ResultPath .\artifacts\test-results.json to keep personal outputs ignored. Stage 4 manual acceptance is now user-reported PASS; historical stage reports retain their original status.

The workflow pins Windows ARM64, PowerShell 7.6.6 and Pester 5.9.0. It runs the same 102 tests, including A11/A12, with no Skip filter. Its explicit -AllowElevatedTestHost only permits GitHub's elevated host; the report records that this does not certify the non-admin gate. Default local behavior still rejects elevated runs. No hosted CI run has happened yet. Stage 3 local non-admin and real-user Stage 4 evidence remain required.

No production discovery/Export/Compare algorithm was changed for CI. See docs/stage5-prepublication-audit.md.
