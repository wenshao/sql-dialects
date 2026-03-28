# Trino/Presto 创始人

Trino（原名 PrestoSQL）是一个分布式 SQL 查询引擎，
能够对多种数据源进行交互式分析查询。
它由 Facebook 的四位工程师创建，后来独立发展为 Trino。

## 创始团队

### Martin Traverso

Martin Traverso 是 Presto 的核心创建者之一。
他在 Facebook 工作期间主导了 Presto 的设计和开发。
离开 Facebook 后，他联合创立了 Starburst 公司，
继续领导 Trino 的技术方向。

Traverso 在分布式系统和查询引擎方面有深厚的工程经验，
是 Trino 项目的主要技术决策者之一。

### Dain Sundstrom

Dain Sundstrom 是 Presto 的另一位核心创建者。
他在 Facebook 的数据基础设施团队工作时，
参与了 Presto 从概念到生产系统的完整过程。

Sundstrom 同样是 Starburst 的联合创始人，
在 Trino 社区中持续活跃。

### David Phillips

David Phillips 是 Presto 的第三位核心创建者，
与 Traverso 和 Sundstrom 一起在 Facebook 构建了 Presto。
离开 Facebook 后加入 Starburst，继续参与 Trino 的开发。

### Eric Hwang

Eric Hwang 也是 Facebook Presto 团队的早期成员，
参与了 Presto 的初期开发工作。

## Presto 的 Facebook 起源

### 背景

2012 年左右，Facebook 的数据仓库主要依赖 Apache Hive 进行数据分析。
Hive 虽然能够处理海量数据，但本质上是一个批处理系统——
查询延迟通常在分钟到小时级别，无法满足交互式分析的需求。

Facebook 的数据科学家和工程师需要一个能够在秒级返回结果的查询引擎，
以便进行探索性数据分析。

### 设计目标

Presto 的设计目标包括：
- **交互式查询延迟**：秒级到分钟级的响应时间
- **联邦查询**：能够查询多种数据源（HDFS、MySQL、Cassandra 等）
- **ANSI SQL 支持**：使用标准 SQL 而非 HiveQL
- **可扩展性**：支持数千并发用户和 PB 级数据

### 在 Facebook 内部的使用

Presto 在 Facebook 内部迅速获得了广泛采用：
- 每天处理数 PB 的数据
- 被数据科学家、产品分析师和工程师使用
- 查询性能比 Hive 快 5-10 倍

2013 年，Facebook 将 Presto 开源。

## 从 Presto 到 Trino

### 分叉的背景

2018 年，Traverso、Sundstrom 和 Phillips 相继离开 Facebook。
他们创立了 Starburst Data 公司，提供基于 Presto 的商业产品和服务。

在此之后，出现了两个 Presto 分支：
- **Presto**（由 Facebook/Meta 继续维护，后捐赠给 Linux Foundation，称为 PrestoDB）
- **PrestoSQL**（由原始创建者维护，社区驱动）

### 更名为 Trino (2020)

2020 年 12 月，PrestoSQL 正式更名为 Trino。
更名的原因是避免与 Facebook 的 Presto 项目产生商标和品牌上的混淆。

Trino 这个名字是社区投票选出的。

## Starburst (2018)

Traverso、Sundstrom 和 Phillips 创立的 Starburst 公司
提供基于 Trino 的企业级产品：
- Starburst Enterprise（本地部署）
- Starburst Galaxy（云服务）

Starburst 获得了大量风险投资，成为数据分析领域的重要公司。

## 技术特点

### SQL 方言

Trino 的 SQL 方言强调标准兼容性：
- 高度符合 ANSI SQL 标准
- 完善的窗口函数支持
- 丰富的数据类型系统
- Lambda 表达式和高阶函数
- 复杂类型（ARRAY、MAP、ROW）的一等支持

### 连接器架构

Trino 最独特的设计是其连接器（Connector）架构：
- 每个数据源通过一个连接器接入
- 支持 Hive、Iceberg、Delta Lake、MySQL、PostgreSQL、
  MongoDB、Elasticsearch、Kafka 等数十种数据源
- 支持跨数据源的 JOIN 查询

## 影响

Presto/Trino 对数据分析领域产生了深远影响：
- 开创了"SQL-on-Anything"的查询引擎范式
- 推动了数据湖分析从批处理向交互式查询的转变
- 连接器架构被后续的查询引擎广泛借鉴
- 在 Uber、Netflix、LinkedIn、Airbnb 等公司被大规模采用

Traverso、Sundstrom 和 Phillips 通过 Presto/Trino 的工作，
证明了一个通用的 SQL 查询引擎可以覆盖多种数据源，
极大地简化了企业数据分析的技术栈。
