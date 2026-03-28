# Michael Stonebraker - PostgreSQL 的学术根源

> 信息来源：
> - [Wikipedia: Michael Stonebraker](https://en.wikipedia.org/wiki/Michael_Stonebraker)
> - [ACM Turing Award 2014](https://amturing.acm.org/award_winners/stonebraker_1172121.cfm)
> - [Wikipedia: PostgreSQL](https://en.wikipedia.org/wiki/PostgreSQL)
> - [Wikipedia: Ingres (database)](https://en.wikipedia.org/wiki/Ingres_(database))
> - [Stonebraker et al., "The Design of POSTGRES" (1986)](https://dl.acm.org/doi/10.1145/16856.16888)

---

Michael Stonebraker 是数据库领域最具影响力的学者和创业者之一。
他在 UC Berkeley 的研究工作直接催生了 PostgreSQL，
同时他还创办了多家数据库公司，持续推动数据库技术的边界。

> 来源：[Wikipedia: Michael Stonebraker](https://en.wikipedia.org/wiki/Michael_Stonebraker)

## 学术背景

Stonebraker 在密歇根大学获得计算机科学博士学位（1971 年），
随后加入 UC Berkeley 计算机科学系，此后在此任教超过 30 年。
2001 年他转到 MIT 担任兼职教授（Adjunct Professor），同时继续从事数据库研究和创业。

> 来源：[Wikipedia: Michael Stonebraker](https://en.wikipedia.org/wiki/Michael_Stonebraker)

## Ingres (1973-1985)

Stonebraker 在 Berkeley 的第一个重大项目是 Ingres（Interactive Graphics and
Retrieval System）。Ingres 是最早的关系数据库实现之一，
与 IBM 的 System R 几乎同时期开发，但采用了不同的技术路线。

Ingres 使用 QUEL 而非 SQL 作为查询语言，并且在查询处理方面有独特的创新。
项目的商业化版本后来被 Computer Associates（现 Broadcom）收购。

> 来源：[Wikipedia: Ingres (database)](https://en.wikipedia.org/wiki/Ingres_(database))

## POSTGRES 项目 (1986-1994)

1986 年，Stonebraker 启动了 POSTGRES 项目（Post-Ingres），
目标是解决当时关系数据库的已知局限：

- **可扩展类型系统**：用户可以定义自己的数据类型和操作符
- **规则系统**：支持主动数据库功能
- **对象关系模型**：将面向对象的概念引入关系数据库

POSTGRES 项目发表了多篇影响深远的论文，
其中 1986 年的 *The Design of POSTGRES*（SIGMOD 1986）是数据库领域的经典文献。

> 来源：[ACM: The Design of POSTGRES](https://dl.acm.org/doi/10.1145/16856.16888)

### 从 POSTGRES 到 PostgreSQL

1994 年，Stonebraker 离开 POSTGRES 项目后，
两位研究生 Andrew Yu 和 Jolly Chen 为 POSTGRES 添加了 SQL 支持，
将其更名为 Postgres95，后来又更名为 PostgreSQL。

PostgreSQL 今天是世界上最先进的开源关系数据库之一，
其可扩展架构直接源自 Stonebraker 的 POSTGRES 设计。

## 图灵奖 (2014)

2014 年，Stonebraker 获得 ACM 图灵奖（A.M. Turing Award），
颁奖词称他"对现代数据库系统概念和实践做出了根本性贡献"。

> 来源：[ACM Turing Award 2014](https://amturing.acm.org/award_winners/stonebraker_1172121.cfm)

ACM 的评价特别提到了他在以下方面的贡献：
- 关系数据库的早期实现（Ingres）
- 对象关系数据库（POSTGRES）
- 新型数据库架构的持续探索

## 创业经历

Stonebraker 是数据库领域最活跃的创业者之一，创办或联合创办了多家公司：

| 公司 | 年份 | 技术方向 |
|------|------|----------|
| Ingres Corp | 1980 | 关系数据库 |
| Illustra | 1992 | 对象关系数据库（基于 POSTGRES） |
| StreamBase | 2003 | 流处理 |
| Vertica | 2005 | 列式分析数据库 |
| VoltDB | 2009 | 内存 OLTP 数据库 |
| Tamr | 2013 | 数据整合与清洗 |

Vertica 于 2011 年被 HP 收购，StreamBase 被 TIBCO 收购，
Illustra 被 Informix 收购（Informix 于 2001 年被 IBM 收购）。

> 来源：[Wikipedia: Michael Stonebraker](https://en.wikipedia.org/wiki/Michael_Stonebraker)

## 学术观点与论文

Stonebraker 以直言不讳著称，曾多次公开批评"一刀切"的数据库架构。
他主张不同的工作负载需要不同架构的数据库系统：

- OLTP 不需要传统的磁盘架构（VoltDB 的出发点）
- 分析查询适合列式存储（Vertica 的出发点）
- MapReduce 不是数据库的替代品

他与人合著的 "MapReduce: A major step backwards"（2008）
引发了数据库社区和大数据社区之间的广泛讨论。

## 对数据库领域的影响

Stonebraker 的影响远超 PostgreSQL 本身：

- 培养了大量数据库领域的学者和工程师
- 推动了对象关系、列式存储、流处理、内存数据库等多个方向
- 通过创业将学术成果转化为实际产品
- 他的学生和同事遍布学术界和工业界的数据库团队

可以说，现代数据库的许多核心思想都可以追溯到 Stonebraker 在 Berkeley 的工作。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
