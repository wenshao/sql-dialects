# SQL Server 关键人物

> 信息来源：
> - [Wikipedia: Jim Gray (computer scientist)](https://en.wikipedia.org/wiki/Jim_Gray_(computer_scientist))
> - [ACM Turing Award 1998: Jim Gray](https://amturing.acm.org/award_winners/gray_3649936.cfm)
> - [Wikipedia: David DeWitt](https://en.wikipedia.org/wiki/David_DeWitt)
> - [Access Path Selection in a Relational Database Management System (1979)](https://dl.acm.org/doi/10.1145/582095.582099)

---

SQL Server 的发展历程与多位数据库领域的先驱密切相关。
本文介绍几位对 SQL Server 及关系型数据库理论产生深远影响的关键人物。

## Jim Gray (1944-2007) - 事务处理先驱

### 学术成就

Jim Gray 是计算机科学史上最重要的数据库研究者之一。
他因在数据库和事务处理领域的开创性贡献，
于 1998 年获得图灵奖（ACM Turing Award）。

Gray 的关键学术贡献包括：
- **事务处理**：形式化定义了事务的 ACID 属性
- **两阶段锁协议**：数据库并发控制的基础
- **粒度锁**：多粒度锁定的层次模型
- **WAL（Write-Ahead Logging）**：预写日志机制
- **五分钟法则**：描述数据在内存和磁盘之间迁移的经济模型

### 职业生涯

Gray 曾在 IBM、Tandem Computers 等公司工作。
1995 年，他加入微软研究院（Microsoft Research），
在位于旧金山的 Bay Area Research Center 工作。

在微软期间，Gray 将学术研究与工程实践结合，
对 SQL Server 的事务处理和可靠性设计产生了影响。
他还推动了 TerraServer 等大规模数据项目。

### 失踪

2007 年 1 月，Gray 在旧金山湾区独自驾驶帆船出海后失踪。
尽管进行了大规模搜救，包括利用卫星图像和众包搜索，
最终未能找到他。他于 2012 年被正式宣告死亡。
数据库社区为纪念他，设立了以他命名的多个奖项和荣誉。

## David DeWitt - 并行数据库先驱

### 学术贡献

David DeWitt 是威斯康星大学麦迪逊分校的教授，
是并行数据库和数据库系统性能评测领域的先驱。

他的主要贡献包括：
- **Gamma 数据库项目**：早期并行数据库系统的重要原型
- **数据库基准测试**：推动了 TPC 基准测试的发展
- **Shared-Nothing 架构**：并行数据库的基础架构范式
- 在数据库查询优化和并行执行方面发表了大量有影响力的论文

### 微软 Jim Gray Systems Lab

2008 年，DeWitt 加入微软，领导位于麦迪逊的
Jim Gray Systems Lab（以 Jim Gray 命名的研究实验室）。
他在微软的工作聚焦于大规模数据管理和云数据库技术，
对 SQL Server 和 Azure SQL 的技术方向产生了影响。

## Pat Selinger - 查询优化器先驱

### System R 与查询优化

Pat Selinger（Patricia Selinger）是 IBM System R 项目的核心成员。
1979 年，她发表了开创性论文 "Access Path Selection in a Relational
Database Management System"，首次系统性地描述了基于成本的查询优化方法。

这篇论文定义了现代关系型数据库查询优化器的基本框架：
- **基于成本的优化**：通过统计信息估算不同执行计划的代价
- **等价变换**：通过关系代数变换生成候选执行计划
- **连接顺序选择**：动态规划算法选择最优连接顺序
- **索引选择**：评估不同索引路径的访问代价

### 深远影响

Selinger 的查询优化器设计直接影响了几乎所有后续的关系型数据库：
- SQL Server 的查询优化器继承了 System R 的基于成本的优化框架
- Oracle、PostgreSQL、MySQL 等数据库的优化器也受到了直接影响
- 40 多年后，基于成本的优化仍然是主流数据库查询优化的核心方法

### 职业生涯

Selinger 在 IBM 工作了数十年，晋升至 IBM Fellow——
IBM 技术人员的最高荣誉。她还获得了多项行业和学术荣誉，
包括入选计算机历史博物馆 Fellow。

## 影响

这三位人物从不同角度塑造了关系型数据库的发展：
- Gray 定义了事务处理的理论基础
- DeWitt 推动了并行数据库的研究和实践
- Selinger 发明了基于成本的查询优化方法

他们的工作不仅影响了 SQL Server，
更是整个关系型数据库行业的理论和工程基石。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
