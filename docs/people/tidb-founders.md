# TiDB 创始人 - 刘奇、黄东旭、崔秋

> 信息来源：
> - [PingCAP 官网: About](https://www.pingcap.com/about/)
> - [TiDB GitHub](https://github.com/pingcap/tidb)
> - [TiKV GitHub](https://github.com/tikv/tikv)
> - [TiKV CNCF Graduation (2020-09)](https://www.cncf.io/announcements/2020/09/02/cloud-native-computing-foundation-announces-tikv-graduation/)
> - [Wikipedia: TiDB](https://en.wikipedia.org/wiki/TiDB)
> - [Chaos Mesh CNCF](https://www.cncf.io/projects/chaos-mesh/)

---

TiDB 是一个开源的分布式 NewSQL 数据库，兼容 MySQL 协议，
由 PingCAP 公司开发。PingCAP 由三位联合创始人于 2015 年在中国创立。

> 来源：[PingCAP: About](https://www.pingcap.com/about/)

## 刘奇 (Max Liu) - CEO

### 背景

刘奇是 PingCAP 的 CEO 和联合创始人。
在创立 PingCAP 之前，他曾在豌豆荚（Wandoujia）担任基础设施负责人，
负责后端系统的架构和开发。

在豌豆荚期间，刘奇积累了大规模分布式系统的实践经验。
他深刻体会到传统单机数据库在互联网公司面对海量数据时的局限性——
手动分库分表带来了巨大的运维复杂度和开发负担。

### 开源贡献

刘奇是 Go 语言社区的活跃贡献者。在创建 TiDB 之前，
他开发了多个开源项目，包括：
- **Codis**：一个流行的 Redis 集群代理方案
- **go-mysql**：Go 语言的 MySQL 协议库
- 其他 Go 语言基础设施工具

这些项目在中国的 Go 语言开源社区中获得了广泛使用。

## 黄东旭 (Ed Huang) - CTO

### 背景

黄东旭是 PingCAP 的 CTO 和联合创始人，
也是 TiDB 和 TiKV 的核心架构师。

他对分布式系统和数据库有深厚的技术功底。
在创立 PingCAP 之前，他在网易等公司从事基础设施开发工作。

### 技术架构

黄东旭主导设计了 TiDB 的整体架构：
- **计算与存储分离**：TiDB（计算层）和 TiKV（存储层）独立扩展
- **Raft 共识协议**：保证数据的强一致性
- **MVCC**：多版本并发控制
- **MySQL 协议兼容**：降低迁移成本

他经常在技术博客和会议上分享 TiDB 的架构设计和演进。

### 公开分享

黄东旭活跃于技术社区，经常在以下场合分享：
- PingCAP 技术博客
- 国内外数据库和分布式系统会议
- 开源社区活动

他的技术分享以深入浅出著称，涵盖分布式系统理论、
数据库内核实现和工程实践等话题。

## 崔秋 (Cui Qiu) - 联合创始人

崔秋是 PingCAP 的联合创始人。
在 PingCAP 的早期发展中发挥了重要作用。

## TiDB 项目

### 架构概述

TiDB 的架构由多个组件构成：

| 组件 | 语言 | 作用 |
|------|------|------|
| TiDB | Go | SQL 计算层，兼容 MySQL 协议 |
| TiKV | Rust | 分布式 KV 存储层，使用 Raft |
| PD | Go | 集群调度和元数据管理 |
| TiFlash | C++ | 列式存储，用于分析查询 |

### 开源策略

TiDB 从第一天起就是开源项目：
- TiDB 使用 Apache 2.0 许可证
- TiKV 同样使用 Apache 2.0 许可证
- 所有核心组件在 GitHub 上公开开发

### TiKV 进入 CNCF

TiKV 作为独立的分布式 KV 存储，于 2018 年 8 月被 CNCF 接受为沙箱项目，
2020 年 9 月成为 CNCF 毕业项目（Graduated）。这是对 TiKV 技术成熟度和社区健康度的认可。

> 来源：[CNCF: TiKV Graduation Announcement](https://www.cncf.io/announcements/2020/09/02/cloud-native-computing-foundation-announces-tikv-graduation/)

## 技术创新

TiDB 的主要技术创新包括：

### HTAP（混合事务分析处理）
通过 TiKV（行存储）和 TiFlash（列存储）的组合，
TiDB 支持在同一系统中同时处理 OLTP 和 OLAP 工作负载。
Raft Learner 机制实现了行存到列存的实时数据同步。

### 弹性扩展
TiDB 的计算层和存储层可以独立扩缩容，
无需手动分库分表。数据通过 Region 自动分片。

### MySQL 兼容性
TiDB 高度兼容 MySQL 协议和 SQL 语法，
用户可以使用现有的 MySQL 客户端和 ORM 框架直接连接 TiDB。

## 社区与生态

TiDB 拥有活跃的开源社区：
- GitHub 上数万颗星标
- 数百名社区贡献者
- TiDB User Group（TUG）在多个城市有活跃的本地社区

PingCAP 还开发了多个相关的开源工具：
- **TiUP**：一键部署工具
- **BR**：备份恢复工具
- **DM**：数据迁移工具（从 MySQL 迁移到 TiDB）
- **Chaos Mesh**：混沌工程平台（CNCF 孵化项目，2022 年进入 Incubating）

> 来源：[TiDB GitHub](https://github.com/pingcap/tidb)、[Chaos Mesh CNCF](https://www.cncf.io/projects/chaos-mesh/)

## 影响

PingCAP 的三位创始人推动了中国在数据库基础软件领域的重要突破：
- TiDB 是全球范围内被广泛采用的分布式 NewSQL 数据库
- TiKV 成为 CNCF 毕业项目，获得全球社区认可
- 证明了用开源模式开发世界级数据库系统的可行性
- 推动了国内数据库行业的技术进步和人才培养

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
