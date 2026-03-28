# BigQuery/Dremel 关键人物

> 信息来源：
> - [Dremel: Interactive Analysis of Web-Scale Datasets (VLDB 2010)](https://dl.acm.org/doi/10.14778/1920841.1920886)
> - [Spanner: Google's Globally-Distributed Database (OSDI 2012)](https://research.google/pubs/pub39966/)
> - [Wikipedia: BigQuery](https://en.wikipedia.org/wiki/BigQuery)

---

BigQuery 是 Google Cloud 的全托管分析数据仓库，
其底层技术源自 Google 内部的 Dremel 系统。
2010 年发表的 Dremel 论文对整个分析引擎领域产生了深远影响。

## Dremel 论文 (VLDB 2010)

### 论文概述

2010 年，Google 在 VLDB（Very Large Data Bases）会议上发表了
"Dremel: Interactive Analysis of Web-Scale Datasets" 论文。
这篇论文描述了 Google 内部用于交互式分析万亿行数据集的系统，
核心创新包括列式存储的嵌套数据模型和多级执行树架构。

Dremel 论文直接催生了 Apache Parquet 文件格式和 Apache Drill 项目，
深刻改变了大数据分析引擎的架构范式。

### Sergey Melnik - 第一作者

Sergey Melnik 是 Dremel 论文的第一作者，
在 Google 工作了约 15 年（2004-2019），
是 Google 数据基础设施团队的核心成员。

他在 Google 期间的主要贡献包括：
- **Dremel**：交互式大规模数据分析系统
- **列式嵌套数据模型**：高效存储和查询 Protocol Buffer 格式的嵌套数据
- BigQuery 早期架构的关键技术基础

Melnik 在离开 Google 后加入了 Databricks，
继续从事数据分析系统相关的工作。

### Andrey Gubarev - 联合作者

Andrey Gubarev 是 Dremel 论文的联合作者之一，
在 Google 参与了 Dremel 系统的设计与实现。
他在 Google 的数据分析基础设施团队工作多年，
为 Dremel 从内部工具演进为 BigQuery 云服务做出了贡献。

## Spanner 团队

Google Spanner 是全球首个全球分布式强一致性数据库，
于 2012 年在 OSDI 会议上发表论文。

### Andrew Fikes

Andrew Fikes 是 Google 的资深工程师（Principal Engineer），
参与了 Spanner 的设计与开发。他在 Google 的存储和数据库基础设施
领域有着长期的技术贡献，也参与了 Google 文件系统等核心项目。

### Wilson Hsieh

Wilson Hsieh 是 Spanner 论文的联合作者之一，
在 Google 的分布式系统团队工作。他对 Spanner 的
事务模型和 TrueTime API 的设计做出了贡献。

## BigQuery 的演进

### 从 Dremel 到 BigQuery

BigQuery 于 2010 年作为 Google Cloud 服务发布，
将 Google 内部的 Dremel 技术以云服务形式提供给外部用户。

BigQuery 的关键技术特性：
- **Serverless 架构**：无需管理基础设施
- **列式存储**：基于 Dremel 论文的嵌套列式模型
- **分布式执行**：多级执行树并行处理查询
- **标准 SQL 支持**：2016 年引入标准 SQL 方言

### 学术影响

Dremel 论文的影响远超 Google 自身：
- **Apache Parquet**：列式存储格式，直接受 Dremel 嵌套列模型启发
- **Apache Drill**：开源的 Dremel 实现尝试
- **Apache Impala**：Cloudera 的交互式查询引擎
- 推动了整个行业从 MapReduce 批处理向交互式分析的转变

## 影响

Dremel 论文和 BigQuery 的出现标志着大数据分析从"跑批"走向"交互式"的转折点。
Melnik、Gubarev 等人在 Google 的工作，
与 Spanner 团队的全球一致性数据库研究一起，
构成了 Google 在数据库和分析领域最重要的技术贡献。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
