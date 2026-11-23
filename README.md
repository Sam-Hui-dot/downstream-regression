# MoonBit 下游依赖回归检查器

给库维护者一份升级前的下游报告。项目同时提供**全目标纯 MoonBit 核心库**（`Sam-Hui-dot/downstream-regression`）与**命令行工具**（`cmd/main`）。CLI 用同一个 `moon` 可执行文件，在两个独立目录分别解析指定依赖和运行 `moon test`，输出结构化 JSON 报告、人类可读 Markdown 报告（可直接用于 GitHub Actions Step Summary）、离线交互式 HTML 报告（`report.html` / `batch.html`）与完整原始日志，并内置原生 `.mbti` 公共 API 破坏性变更静态比对器（`mbti-diff`）。

## 安装与快速验证

### 1. 从 Mooncakes 安装 CLI

```powershell
moon update
moon install Sam-Hui-dot/downstream-regression/cmd/main@0.3.0
main --help
```

### 2. 作为 MoonBit 库使用（支持 Wasm / WasmGC / JS / Native）

根包 `Sam-Hui-dot/downstream-regression` 不依赖进程 IO，可在任意目标上导入使用（用于日志解析、`moon tree` 依赖漂移核对、`moon.mod` / `moon.mod.json` 依赖改写、`.mbti` 公共 API 破坏性变更静态分析、回归分类以及 Markdown / HTML 报告渲染）：

```powershell
moon add Sam-Hui-dot/downstream-regression@0.3.0
```

```moonbit
let counts = @downstream-regression.parse_test_counts("Total tests: 89, passed: 83, failed: 6.")
let updated = @downstream-regression.rewrite_manifest_dependency(
  MoonModJson,
  manifest_text,
  "moonbitlang/async",
  "0.21.0",
  "0.22.0",
)
let api_diff = @downstream-regression.diff_mbti(old_mbti_text, new_mbti_text)
let md = @downstream-regression.render_markdown_report(comparison)
let html = @downstream-regression.render_html_report(comparison)
```

### 3. 零外部依赖运行自带单元测试

在仓库根目录直接运行全目标单元测试（不依赖外部下游仓库）：

```powershell
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
```

## CLI 运行

历史案例复验使用 Moon `0.1.20261104`（`moonc 0.10.20+65efd5b93`）或支持相同命令与输出格式的版本。Windows 下建议给工具指定 `moon.exe` 和 `git.exe` 的绝对路径。

```powershell
moon run cmd/main --target wasm -- --help
moon run cmd/main --target wasm -- snapshot moon git D:/src/moonback ccb19d7 moonback moonbitlang/async 0.21.0 0.22.0 wasm
moon run cmd/main --target wasm -- --out ./evidence snapshot moon git D:/src/moonback ccb19d7 moonback moonbitlang/async 0.21.0 0.22.0 wasm
```

- `snapshot` 接受本地 Git 仓库、提交和其中的模块路径（根模块用 `.`）。工具在隔离目录检出两份相同的已提交源码，自动识别 `moon.mod` 或 `moon.mod.json`，仅替换候选目录中唯一匹配的直接依赖版本，并通过 `moon tree` 核实精确解析结果。
- 可选参数 `--out <DIR>` 将证据目录输出到指定路径（未指定时默认写入系统临时目录）。
- 也可直接传入两个已准备好的模块目录进行对照：

```powershell
moon run cmd/main --target wasm -- moon moonbitlang/async D:/cases/moonback-old/moonback 0.21.0 D:/cases/moonback-candidate/moonback 0.22.0 wasm
```

参数末尾指定下游测试目标，默认 `wasm`，可选 `wasm`、`native`、`wasm-gc`、`js`。CLI 自身支持 `wasm` 与 `native` 构建。由于正常的 Moon 构建和测试会执行下游项目代码，应在可信源码上运行。

## `.mbti` 公共 API 破坏性变更分析

`mbti-diff` 子命令直接解析两份 MoonBit 接口快照文件（`pkg.generated.mbti`），在运行下游测试之前即可静态识别删除/签名前后不一致的公开函数与方法、类型定义/可见性收窄、结构体字段/枚举构造器变更、trait 实现移除与新增公开符号：

```powershell
moon run cmd/main --target wasm -- mbti-diff old.mbti new.mbti --format markdown --fail-on-breaking
moon run cmd/main --target wasm -- mbti-diff old.mbti new.mbti --format json --out api-diff.json
```

- `--format text|markdown|json`：默认 `text`。
- `--fail-on-breaking`：检测到破坏性变更（`breaking_count > 0`）时以退出码 `1` 退出，适合直接接入 CI 门禁。

## 批量核对

以多个下游项目组成一份 JSON 清单。`repo` 以当前工作目录为基准，`target` 缺省为 `wasm`。批量模式依次执行每个案例，一个案例出错时记录原因并继续其余案例，最终在证据目录生成 `batch.json`（含各案例状态、基线/候选测试计数、新增失败数与编译错误数）、可直接写入 `$GITHUB_STEP_SUMMARY` 的 `batch.md` 汇总表，以及带即时过滤与状态筛选的离线单页 `batch.html`。

```powershell
moon run cmd/main --target wasm -- --out ./batch-evidence batch moon git examples/historical-plan.json
```

示例使用 `../downstream-upgrade-study` 中的历史项目。从本仓库根目录运行以下命令可准备源码并核对结果：

```powershell
git clone https://github.com/moonbitlang/moonback.git ../downstream-upgrade-study/moonback
git clone https://github.com/moonbitlang/moonyacc.git ../downstream-upgrade-study/moonyacc
pwsh -NoProfile -File examples/verify-historical.ps1
```

## 报告与退出码

- 退出码 `0`：两轮测试均通过且测试统计可比较（`pass`）。
- 退出码 `1`：新增测试失败（`new_test_failure`）、既有失败消息变化（`failure_changed`），或基线通过后候选版出现 MoonBit 编译诊断（`candidate_compile_failure`）。
- 退出码 `2`：既有失败（`candidate_failing` / `baseline_failing`）、测试总数或跳过数变化（`test_summary_changed`）、诊断无法完整解析（`baseline_inconclusive` / `candidate_inconclusive`）或工具执行出错。

单案例证据目录保存 `report.json`、`report.md`、`report.html`、`toolchain.txt`、`baseline-tree.txt`、`candidate-tree.txt`、`baseline-test.txt` 与 `candidate-test.txt`。`report.json` 包含 `other_dependency_changes`，列出目标依赖之外的解析变化。版本检查、依赖解析和单轮测试的时限分别为 30 秒、60 秒和 10 分钟；单份日志解析上限为 16 MiB，超出时保留完整原始日志并报错。当前以 `moon test` 的英文输出为输入。

## 历史案例与验证

在 Windows 上使用 Moon `0.1.20261104` 和 Wasm 测试目标，批量 CLI 实测如下（详见 [docs/VALIDATION.md](docs/VALIDATION.md)）：

| 下游 | 依赖升级 | 旧版 → 新版 | CLI 状态 |
| --- | --- | --- | --- |
| MoonBack `ccb19d7` | `async` 0.21.0 → 0.22.0 | 89/89 → 83/89 | `new_test_failure`，列出 6 项失败 |
| moonyacc `0adc773` | `async` 0.20.3 → 0.22.4 | 74/74 → 74/74 | `pass` |

MoonBack 的新增失败中，4 项报 `TaskCancelled`，2 项超时，涉及连接复用、空闲连接取消和连接断开。维护者在 `c4b5564` 适配了取消语义，同一工具链手工复验修复提交通过 97/97 项测试。

GitHub Actions 使用带 SHA-256 校验的官方 Windows 历史工具链和标准库，执行格式检查、四目标（Wasm / WasmGC / JS / Native）严格检查与单元测试、独立消费者库导入验证、Wasm 构建、上述两个历史下游用例以及 `examples/compile-regression` 编译回归检测，并将生成的 `batch.md` 与 `report.md` 渲染至 Actions Job Summary。

- [验证范围与源码统计说明](docs/VALIDATION.md)
- [MoonBack 上游适配提交](https://github.com/moonbitlang/moonback/commit/c4b5564d947e5c713d12761e67966828c53478a8)
- [moonyacc 升级记录](https://github.com/moonbitlang/moonyacc/pull/83)
