# MoonBit 下游依赖回归检查器

给库维护者一份升级前的下游报告。用同一个 `moon` 可执行文件，在两个独立目录分别解析指定依赖和运行 `moon test`。报告列出新增失败、恢复通过和失败消息变化，留存实际依赖树、测试日志和 JSON。

## 运行

使用 Moon `0.1.20261104` 或支持相同命令和输出格式的版本。Windows 下建议给工具指定 `moon.exe` 和 Git 可执行文件的绝对路径。

```powershell
moon run cmd/main --target wasm -- --help
moon run cmd/main --target wasm -- snapshot moon git D:/src/moonback ccb19d7 moonback moonbitlang/async 0.21.0 0.22.0 wasm
```

`snapshot` 接受本地 Git 仓库、提交和其中的模块路径。根模块用 `.`。工具在临时目录检出两份相同的已提交源码，候选目录只替换 `moon.mod` 中匹配的引号内依赖版本。作用域为直接来源于注册表的依赖，必须能从 `moon tree` 核实精确版本。快照目录和报告保留在打印出的临时路径中。

也可使用已经配好的两个模块目录。使用相同源码和工具链，除显式选择的依赖外保持环境一致。

```powershell
moon run cmd/main --target wasm -- moon moonbitlang/async D:/cases/moonback-old/moonback 0.21.0 D:/cases/moonback-candidate/moonback 0.22.0 wasm
```

参数末尾指定的是下游测试目标，默认是 `wasm`。CLI 自己用 Wasm 或 Native 构建。应在可信的下游源码上运行，因为正常的 Moon 构建和测试会执行项目代码。目录隔离用于避免两次构建互相影响。

## 批量核对

以多个下游项目组成一份 JSON 清单。`repo` 以当前工作目录为基准，`target` 缺省为 `wasm`。批量模式依次执行每个案例，每个案例有自己的证据目录。一个案例出错时会记录原因并继续运行其余案例。

```powershell
moon run cmd/main --target wasm -- batch moon git examples/historical-plan.json
```

示例使用同目录下 `../downstream-upgrade-study` 中已克隆的历史项目。也可以按清单中的提交在其他本地仓库复现，再更新 `repo`。

## 报告

退出码 `0` 表示两轮测试通过且测试统计可比较，`1` 表示出现新的失败或已知失败的消息变化，`2` 表示既有失败、诊断无法完整解析或工具执行出错。编译中止和缺少测试统计会保留原始日志，并标记为无法判定。当前以 `moon test` 的英文输出为输入。

报告包含 `other_dependency_changes`，列出目标依赖之外的解析变化。两个 `*-tree.txt` 文件保留原始层级。`toolchain.txt` 记录工具链版本。版本检查、依赖解析和单轮测试的时限分别为 30 秒、60 秒和 10 分钟。超时和超过 16 MiB 的日志会作为工具错误报告，原始日志留在证据目录。

统计相同仅代表所选测试目标上的对照结果。从测试结果只能推断这次升级对该下游提交和所选目标的影响。

## 历史案例

首批用例来自已独立运行的历史实验。MoonBack 在仅升 `async` 0.21.0 到 0.22.0 后从 89/89 变为 83/89，维护者适配提交 `c4b5564` 恢复通过。moonyacc 只把 `async` 0.20.3 升到 0.22.4，两轮都是 74/74。记录属于预先完成的手工对照。CLI 的端到端复验单独进行。

- [MoonBack 上游适配提交](https://github.com/moonbitlang/moonback/commit/c4b5564d947e5c713d12761e67966828c53478a8)
- [moonyacc 升级记录](https://github.com/moonbitlang/moonyacc/pull/83)
