# Graphiti 参考边界

固定参考：Graphiti `0.30.1`，commit `547422865cca9fb5a82915c074d899428c145ff4`，Apache-2.0。

这轮借鉴的是三个语义，不是 Python 文件的逐行翻译：

| Graphiti 中的概念 | FactEpoch-mbt 的落点 |
| --- | --- |
| edge/fact 的有效时间 | `Fact.valid_from`、`valid_to` 与半开区间 |
| ingestion time | `RecordedEvent.recorded_at` 与 `known_at` 前缀 replay |
| fact invalidation | `SupersedeFact` / `RetractFact` 显式终止旧事实 |

MoonBit 版本额外要求同一 group、subject、predicate 和对象种类才能替代，避免不相关事实被一起失效。来源链缩成单个 `source_episode`，这是初赛范围选择，不是 Graphiti API 兼容层。

未移植：Neo4j/FalkorDB、LLM 抽取、搜索 recipe、community、ontology、reranker、服务端和 Graphiti Python API。仓库运行时不需要 Python。

如果后续直接翻译具体算法，会在对应源码头标明上游路径、commit、版权和 “translated and modified”；当前三个 MoonBit 文件是围绕上述公开语义重新设计的实现。
