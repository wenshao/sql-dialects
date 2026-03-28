# Alexey Milovidov - ClickHouse 创始人

> 信息来源：
> - [GitHub: alexey-milovidov](https://github.com/alexey-milovidov)
> - [Wikipedia: ClickHouse](https://en.wikipedia.org/wiki/ClickHouse)
> - [ClickHouse Inc.](https://clickhouse.com/)
> - [Yandex Metrica](https://metrica.yandex.com/)

---

Alexey Milovidov 是 ClickHouse 的创始人和核心开发者，
也是 ClickHouse Inc. 的联合创始人和 CTO。
ClickHouse 是当前最快的开源列式分析数据库之一。

## 早期背景

Milovidov 在俄罗斯的 Yandex 公司工作时开始了 ClickHouse 的开发。
Yandex 是俄罗斯最大的互联网公司，运营着搜索引擎、地图、
出租车服务等多种互联网产品。

## Yandex Metrica 与 ClickHouse 的起源

### 问题背景

Yandex Metrica 是仅次于 Google Analytics 的全球第二大网站分析系统。
它需要处理海量的点击流数据，并支持实时的交互式分析查询。

2008 年左右，Milovidov 开始为 Yandex Metrica 开发一个专用的
列式存储分析引擎。当时市场上没有能满足 Yandex 需求的现成解决方案——
既要支持实时数据写入，又要支持毫秒级的分析查询。

### 设计目标

ClickHouse 的设计从一开始就聚焦于：
- 极致的查询速度（利用向量化执行和列式存储）
- 支持实时数据写入
- 线性可扩展的分布式架构
- SQL 兼容的查询接口

## 开源 (2016)

2016 年 6 月，ClickHouse 在 Apache 2.0 许可证下开源。
这是一个关键决策——将一个 Yandex 内部使用了 8 年的系统
完全开放给社区。

开源后，ClickHouse 迅速获得了全球开发者的关注。
其极端的查询性能在各种基准测试中表现突出，
吸引了大量用户和贡献者。

## ClickHouse Inc. (2021)

2019 年，ClickHouse 团队从 Yandex 分拆独立运营。
2021 年，Milovidov 与 Yury Izrailevsky 共同创立了 ClickHouse Inc.，
正式将 ClickHouse 的开发完全从 Yandex 独立出来。
公司获得了大量风险投资，估值达到数十亿美元。

Milovidov 担任公司的 CTO 和联合创始人，
继续领导 ClickHouse 的技术方向。

## 技术贡献

### 代码贡献

Milovidov 是 ClickHouse 代码库中贡献最多的开发者。
在 GitHub 上，他的提交量占整个项目的很大比例（历史上超过 75%）。
这在如此规模的开源项目中是非常罕见的。

### 关键技术决策

Milovidov 主导了 ClickHouse 的多项关键技术设计：
- **MergeTree 引擎家族**：ClickHouse 的核心存储引擎
- **向量化查询执行**：利用 SIMD 指令加速计算
- **列式压缩**：针对不同数据类型的专用压缩算法
- **近似查询处理**：HyperLogLog、分位数等近似算法
- **物化视图**：实时聚合和预计算

### SQL 方言

ClickHouse 的 SQL 方言在标准 SQL 基础上做了大量扩展：
- 数组和嵌套数据类型的一等支持
- Lambda 表达式和高阶函数
- 丰富的聚合函数（包括 -If、-Array 等组合器）
- 近百种内置函数

## GitHub 与社区

- **GitHub**: [github.com/alexey-milovidov](https://github.com/alexey-milovidov)
- 在 GitHub 上拥有大量关注者
- 积极参与 Issue 讨论和代码审查
- 在社区中以快速响应和技术深度著称

## 公开演讲

Milovidov 经常在数据库和大数据相关的会议上演讲，包括：
- ClickHouse Meetup（全球各地）
- 各类数据工程会议

他的演讲通常深入技术细节，涵盖性能优化、系统架构、
以及 ClickHouse 内部实现的各个方面。

## 影响

ClickHouse 在实时分析领域产生了重大影响：
- 被 Uber、Cloudflare、eBay 等大型公司采用
- 推动了列式分析数据库的普及
- 证明了开源分析数据库可以达到极端的查询性能
- 影响了后续分析数据库的设计（如 Apache Doris 等）

Milovidov 对 ClickHouse 的持续投入——从 Yandex 的内部工具
到全球广泛使用的开源项目——是一个技术人员长期专注于
一个系统并取得巨大成功的典范。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
