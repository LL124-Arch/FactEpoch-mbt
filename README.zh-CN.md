# FactEpoch-mbt

[English](README.md)

> **状态：仅激活阶段的双时态读取已可用。** 可移植根包已提供领域类型、原子化调用方时间戳写入、确定性回放、`valid_at × known_at` 查询、闭区间激活历史和双轴事实集合 diff。替代、撤回、闭合标记、日志、压缩、搜索、CLI、抽取器与发布版本尚未实现。

FactEpoch-mbt 是一个正在开发的、面向 Agent 记忆的纯 MoonBit 双时态事实图谱内核。它分别记录事实在现实语义中何时成立、系统何时得知它、事实来自哪个 Episode，以及哪一个显式事件替代或撤回了它。它不是完整 Agent 框架、对话缓存、向量库或图数据库。

首个版本要让应用能够同时回答两类问题：

- 9 月 18 日时，系统认为用户在 9 月 12 日偏好什么？
- 收到晚到修正后，系统现在如何理解同一个历史时点？

这正是项目存在的理由。只有一个 `updated_at` 字段无法在不抹除历史的前提下回答这两个问题。

[Quickstart](docs/quickstart.mbt.md) 中包含已由测试覆盖的事件写入与双时态查询示例。在仓库根目录运行：

```text
moon check --target all
moon test --target all
moon test docs --target all
```

## 正在实现的 v1 契约

- UTC Unix 毫秒时间戳；事实有效区间采用半开区间 `[valid_from, valid_to)`。
- 每次查询都必须给出 `valid_at` 和 `known_at`。
- 已知时间包含所有满足 `recorded_at <= known_at` 的激活；history 使用闭合激活窗口，diff 每次只改变一个时间轴。
- predicate 过滤使用已记录的 ASCII 大小写/空白键，同时保留来源中的原始 predicate。
- 可移植内核中的 ID 和事件时间由调用方提供；只有 CLI 读取时钟并分配单调序号。
- 整批预校验：`MemoryGraph::apply` 要么接收整批事件，要么保持图状态完全不变。
- 已存在事件 ID 只有在完整 `RecordedEvent`（stream、顺序、时间、变体和领域 payload）相同时才按幂等重放处理；任一部分不同都会报错。
- 替代与撤回必须显式发生，模型不能静默令事实失效。
- 保留 Episode 到事实的来源链、确定性历史、按分数/时间/ID 的稳定排序，以及 BFS、余弦评分、RRF。
- 版本化 canonical JSONL、SHA-256 事件链、语义状态摘要和产物摘要。
- 先冻结遗忘计划，再逻辑遗忘；随后可选用非原地 preserve 或 redact 压缩。
- 核心包支持 `wasm`、`wasm-gc`、`js`、`native`。
- 默认提供离线 fixture 抽取器；另有严格隔离、显式启用的 native OpenAI-compatible 适配器。

公共接口及其不变量冻结在[设计契约](docs/design.md)中。已实现部分在 `wasm`、`wasm-gc`、`js` 和 `native` 上都有测试；上面尚未落地的条目仍是路线承诺，而非当前能力声明。

## 产品边界

FactEpoch 负责时态事实语义，不负责存储基础设施或 Agent 编排。v1 明确不实现 Neo4j、FalkorDB、Kuzu、Neptune、SQLite、ANN/BM25 数据库、完整 Graphiti API、动态 ontology、community、MCP、REST、Web UI 或多厂商模型 SDK。

外部 embedding 或 BM25 系统可通过小型 DTO 提交已经排好序的候选 ID，但不会成为内核依赖。核心不读取系统时间、环境变量、文件、数据库或网络。

## 为什么还需要一个 MoonBit 记忆项目？

Mooncakes 已经存在有价值的记忆、Agent、检索和向量存储项目。FactEpoch 关注不同的不变量：沿现实有效时间与系统已知时间重建事实版本，并保留来源 Episode 与显式替代链。

| 项目 | 已发布方向 | FactEpoch 计划中的差异 |
| --- | --- | --- |
| [MoonBit-memory](https://mooncakes.io/docs/Across2005/MoonBit-memory) | 内存管理工具 | FactEpoch 建模可持久化的时态事实和来源，而不是分配或运行时内存管理。 |
| [mnemo](https://mooncakes.io/docs/mizchi/mnemo) | 记忆相关工具 | FactEpoch 的核心契约是可重建历史的双时态事件账本。 |
| [agent](https://mooncakes.io/docs/weopqrst/agent) | Agent 构建组件 | FactEpoch 是可嵌入的记忆内核，不是 Agent 运行时。 |
| [MoonRetrieve](https://mooncakes.io/docs/niuniu513-ask/MoonRetrieve) | 检索组件 | FactEpoch 能消费排序候选，但主要职责是重建时态事实状态。 |
| [vcdb](https://mooncakes.io/docs/trkbt10/vcdb) | 向量存储/检索 | FactEpoch 不提供向量数据库；它在外部候选之上提供过滤、图遍历和确定性融合。 |
| [yimai_prophecy_moonbit](https://mooncakes.io/docs/Across2005/yimai_prophecy_moonbit) | 记忆与预测工作流 | 这是本次检索中最接近的项目。FactEpoch 将主张收窄为显式 `valid_at × known_at` 查询、事实版本、来源 Episode 和可审计替代。 |

这些内容只是基于链接页面的范围比较，不是质量评价，也不声称其他项目永远不能支持类似能力。[差异化说明](docs/differentiation.md)记录了比较标准和复核日期。

## 选择性迁移 Graphiti

语义参考固定为 [Graphiti](https://github.com/getzep/graphiti) `0.30.1`、commit [`547422865cca9fb5a82915c074d899428c145ff4`](https://github.com/getzep/graphiti/tree/547422865cca9fb5a82915c074d899428c145ff4)。FactEpoch 会把其中确定性的数据模型、时间、正式 ID 分配前的候选去重与排序行为选择性迁移为惯用 MoonBit。上游精确去重仅适用于同一 group 内、按有向端点与规范化 statement 比较的实体引用候选；正式 `FactId` 绝不会被静默合并。FactEpoch 不是完整移植，也不承诺 drop-in API 兼容。

Graphiti issue [#1728](https://github.com/getzep/graphiti/issues/1728) 记录了无关事实被错误失效的风险。FactEpoch 因此要求被替代事实属于同一 group，并匹配 subject 与 predicate/端点结构。这个更严格的行为会标记为 `documented_adaptation`，不会伪装成上游精确对齐。

当前基线不包含 Graphiti 实现源码。后续翻译文件必须遵守 [THIRD_PARTY.md](THIRD_PARTY.md) 中的文件头政策；对照 fixture 必须写明上游 commit，以及属于 `exact_upstream` 还是 `documented_adaptation`。

## 目标仓库布局

```text
FactEpoch-mbt/
├── README.md / README.zh-CN.md
├── LICENSE / NOTICE / THIRD_PARTY.md
├── CHANGELOG.md / ROADMAP.md
├── CONTRIBUTING.md / SECURITY.md
├── moon.mod / moon.pkg
├── *.mbt
├── codec/jsonl/
├── integrity/
├── compact/
├── extract/{api,fixture,openai_compat}/
├── cmd/{factepoch,factepoch-openai-demo}/
├── examples/{profile_drift,repo_decisions,support_case}/
├── compat/python/
├── fixtures/graphiti/
├── bench/
├── docs/
│   ├── quickstart.mbt.md
│   ├── architecture.md
│   ├── upstream.md
│   ├── differentiation.md
│   ├── compatibility.md
│   ├── limitations.md
│   └── decisions/
└── .github/workflows/ci.yml
```

仓库只使用一个 `moon.mod`。根包拥有公共领域类型和可移植图接口，避免循环依赖与重导出歧义。

## 计划中的命令行

```text
factepoch init
factepoch episode add
factepoch entity put
factepoch fact assert|supersede|retract
factepoch query current|at|as-known-at
factepoch history|diff|neighbors|explain
factepoch forget plan|apply
factepoch compact|verify|doctor
factepoch import graphiti
factepoch export
```

`factepoch-openai-demo` 将是显式 opt-in 的 native 可执行文件，不属于默认离线流程。

## 完整性与隐私边界

SHA-256 收据能证明字节和投影与给定摘要一致，但不能认证写入者，也无法抵抗同时替换产物和期望摘要的攻击者。redact 压缩会让新产物不再包含已确认遗忘的正文，却无法擦除源日志、备份、缓存或磁盘残留。详见 [SECURITY.md](SECURITY.md) 和[限制说明](docs/limitations.md)。

## 文档

- [设计契约](docs/design.md)
- [架构](docs/architecture.md)
- [实施计划](docs/implementation-plan.md)
- [上游映射与归因](docs/upstream.md)
- [差异化说明](docs/differentiation.md)
- [兼容性政策](docs/compatibility.md)
- [已知限制](docs/limitations.md)
- [Quickstart 状态](docs/quickstart.mbt.md)
- [ADR 0001：范围与上游](docs/decisions/0001-scope-and-upstream.md)
- [ADR 0002：双时态投影](docs/decisions/0002-bitemporal-projection.md)

## 贡献与许可证

修改协议行为前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。FactEpoch-mbt 使用 [Apache License 2.0](LICENSE)，第三方来源记录在 [NOTICE](NOTICE) 与 [THIRD_PARTY.md](THIRD_PARTY.md)。
