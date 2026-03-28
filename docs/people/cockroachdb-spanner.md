# CockroachDB/Spanner 关键人物

CockroachDB 是一个开源的分布式 SQL 数据库，
其设计深受 Google Spanner 论文的启发。
两个项目的关键人物构成了分布式 SQL 数据库领域的重要脉络。

## CockroachDB 创始团队

### Spencer Kimball - CEO

Spencer Kimball 是 Cockroach Labs 的 CEO 和联合创始人。
在创立 Cockroach Labs 之前，他在 Google 工作了多年，
参与了 Colossus 分布式文件系统（GFS 的继任者）的开发。

在 Google 的工作经历让 Kimball 深刻理解了
大规模分布式系统的设计原则和工程挑战。
离开 Google 后，他决定构建一个受 Spanner 启发的
开源分布式数据库——让所有开发者都能使用
Google 级别的分布式数据库技术。

值得一提的是，Spencer Kimball 在更早期还是
GIMP（GNU Image Manipulation Program）的联合创始人，
这是 Linux 平台上最知名的开源图像编辑软件之一。

### Peter Mattis - CTO

Peter Mattis 是 Cockroach Labs 的 CTO 和联合创始人。
他同样曾在 Google 工作，参与了基础设施团队的工作。

Mattis 是 CockroachDB 核心引擎的主要设计者，
负责了存储引擎、分布式事务、查询执行等关键模块的架构。
他也是 GIMP 的联合创始人——他与 Kimball 的合作
从大学时代的开源项目一直延续到了 CockroachDB。

### Ben Darnell - 联合创始人

Ben Darnell 是 Cockroach Labs 的第三位联合创始人。
他同样有 Google 的工作背景，在 Google 的基础设施团队积累了
分布式系统开发的经验。

Darnell 在开源社区中也以 Tornado Web 框架的维护者身份为人所知。
Tornado 是一个 Python 异步网络框架，最初由 FriendFeed 开发。

## CockroachDB 的设计

CockroachDB 的核心设计理念直接来源于 Spanner 论文：

- **全局强一致性**：跨数据中心的序列化隔离级别
- **分布式 SQL**：完整的 SQL 支持，兼容 PostgreSQL 协议
- **自动分片**：数据自动分布在集群的各个节点上
- **多活部署**：支持跨区域的多活架构
- **在线 Schema 变更**：不停机的表结构修改

与 Spanner 不同的是，CockroachDB 没有使用原子钟（TrueTime），
而是采用了混合逻辑时钟（HLC）来实现分布式一致性。

## Google Spanner 团队

### Jeff Dean

Jeff Dean 是 Google 最知名的工程师之一，
Google Senior Fellow，参与了 Google 几乎所有重要基础设施的设计。
他是 Spanner 论文（OSDI 2012）的联合作者之一。

Jeff Dean 参与的其他里程碑式项目包括：
- **MapReduce**：大数据处理框架的开创者
- **Bigtable**：分布式宽列存储
- **TensorFlow**：机器学习框架

### Sanjay Ghemawat

Sanjay Ghemawat 是 Google Fellow，与 Jeff Dean 长期搭档，
共同设计了 Google 的多个核心基础设施系统。
他也是 Spanner 论文的联合作者。

Dean 和 Ghemawat 的合作是计算机工程史上最著名的搭档之一，
他们共同发表的论文（GFS、MapReduce、Bigtable、Spanner）
定义了现代分布式系统的基本架构范式。

### Spanner 论文

2012 年，Google 在 OSDI 会议上发表了
"Spanner: Google's Globally-Distributed Database" 论文，
描述了一个使用 TrueTime API 实现全球强一致性的分布式数据库。

Spanner 的关键创新：
- **TrueTime**：基于 GPS 和原子钟的全局时间 API
- **外部一致性**：比线性一致性更强的一致性保证
- **全球分布**：数据可以跨大洲分布并保持一致性

## 影响

从 Spanner 论文到 CockroachDB 的开源实现，
体现了学术/工业研究成果向开源社区扩散的典型路径。
CockroachDB 的三位创始人将 Google 内部的技术理念带出来，
让更广泛的开发者和企业能够使用全球分布式 SQL 数据库技术。
