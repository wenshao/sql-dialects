# Snowflake 创始人 - Dageville, Cruanes, Żukowski

> 信息来源：
> - [Wikipedia: Snowflake Inc.](https://en.wikipedia.org/wiki/Snowflake_Inc.)
> - [The Snowflake Elastic Data Warehouse (SIGMOD 2016)](https://dl.acm.org/doi/10.1145/2882903.2903741)
> - [Marcin Żukowski LinkedIn](https://www.linkedin.com/in/marcinzukowski/)
> - [Benoit Dageville LinkedIn](https://www.linkedin.com/in/benoit-dageville-b512823/)
> - [Sutter Hill Ventures: Snowflake origin](https://www.sutterhillventures.com/portfolio/snowflake)

---

Snowflake 是全球最成功的云数据仓库公司之一，
由三位数据库领域的资深专家于 2012 年在加利福尼亚州圣马特奥创立。
2020 年 9 月 Snowflake 在纽约证券交易所上市（NYSE: SNOW），完成了当时软件行业史上最大的 IPO。

> 来源：[Wikipedia: Snowflake Inc.](https://en.wikipedia.org/wiki/Snowflake_Inc.)

## Benoit Dageville - 联合创始人

### Oracle 时代

Benoit Dageville 是法国人，在加入 Snowflake 之前，
他在 Oracle 工作了约 15 年，是 Oracle 数据库内核团队的精英架构师。
他在 Oracle 期间深度参与了查询优化器和自动调优相关的核心模块开发，
是 Oracle 自动工作负载仓库（AWR）和自动数据库诊断监控器（ADDM）的关键设计者。

> 来源：[Benoit Dageville LinkedIn](https://www.linkedin.com/in/benoit-dageville-b512823/)

### Snowflake 架构

Dageville 是 Snowflake 架构的核心设计者之一。
他将在 Oracle 积累的深厚经验带入 Snowflake，
同时彻底抛弃了传统数据库的 shared-nothing 或 shared-disk 架构，
创造性地提出了"多集群共享数据"（multi-cluster shared data）架构——
计算与存储完全分离，计算资源可以独立弹性扩缩。

## Thierry Cruanes - 联合创始人

### Oracle 时代

Thierry Cruanes 同样来自法国，在 Oracle 工作超过十年，
是 Oracle 并行执行引擎的核心架构师。他在 Oracle 期间主导了
Real Application Clusters (RAC) 相关的关键技术工作。

### 在 Snowflake 的贡献

Cruanes 在 Snowflake 负责核心引擎的架构设计。
他与 Dageville 在 Oracle 时期就是同事，两人对传统数据库架构的
局限性有着共同的深刻理解——这促使他们决定从零开始，
为云环境重新设计数据仓库系统。

## Marcin Żukowski - 联合创始人

### 学术与 VectorWise 背景

Marcin Żukowski 来自波兰，学术背景与前两位截然不同。
他在荷兰 CWI（Centrum Wiskunde & Informatica）获得博士学位，
师从 Peter Boncz，研究向量化查询执行技术。

Żukowski 是 VectorWise 的联合创始人。VectorWise 源自 CWI 的
MonetDB/X100 研究项目，是向量化执行引擎的先驱。
VectorWise 后来被 Actian 收购。

> 来源：Żukowski 的博士论文 *Balancing Vectorized Query Execution with Bandwidth-Optimized Storage* (CWI, 2009)

### 向量化执行引擎

Żukowski 将向量化执行的核心理念带入了 Snowflake 的查询引擎设计。
这使得 Snowflake 的执行引擎在性能上显著优于传统的行式处理引擎。

## Snowflake 的发展

### 创立与早期 (2012-2014)

Dageville 和 Cruanes 于 2012 年联合创立 Snowflake，
Żukowski 随后加入成为第三位联合创始人。
公司在 2014 年发布了第一个公开版本，
运行在 Amazon Web Services 之上。

> 来源：[Wikipedia: Snowflake Inc.](https://en.wikipedia.org/wiki/Snowflake_Inc.)

### SIGMOD 2016 论文

Snowflake 的架构在 SIGMOD 2016 论文 *The Snowflake Elastic Data Warehouse* 中有详细描述。该论文由 Dageville、Cruanes、Żukowski 等人合著。

> 来源：[SIGMOD 2016](https://dl.acm.org/doi/10.1145/2882903.2903741)

### 技术架构

Snowflake 的核心架构创新包括：
- **计算存储分离**：数据存储在云对象存储（S3/GCS/Azure Blob），计算按需启停
- **虚拟数据仓库**：独立的计算集群互不干扰
- **自动优化**：无需手动调优索引或分区
- **零拷贝克隆**：通过元数据操作实现数据的即时克隆
- **Time Travel**：支持访问历史数据快照

### 史上最大软件 IPO (2020)

2020 年 9 月 16 日，Snowflake 在纽约证券交易所上市（NYSE: SNOW）。
IPO 定价 120 美元/股，首日收盘价 253.93 美元，市值一度超过 700 亿美元，
成为当时软件行业有史以来规模最大的 IPO。
沃伦·巴菲特的伯克希尔·哈撒韦公司也参与了 IPO 前的投资，
这在科技股投资中极为罕见。

> 来源：[Wikipedia: Snowflake Inc.](https://en.wikipedia.org/wiki/Snowflake_Inc.)

## 影响

三位创始人的组合体现了 Snowflake 成功的关键因素：
- Dageville 和 Cruanes 带来了深厚的商业数据库工程经验
- Żukowski 带来了前沿的学术研究成果和向量化执行技术
- 三人共同证明了"为云重新设计"而非"把旧系统搬上云"的正确性

Snowflake 的成功深刻改变了数据仓库市场的格局，
推动了整个行业向云原生架构的转型。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
