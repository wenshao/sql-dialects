# Apache Flink 创始人

Apache Flink 是一个分布式流处理框架，支持有状态的流计算和批处理。
它起源于 TU Berlin（柏林工业大学）的 Stratosphere 研究项目，
由多位研究人员共同创建。

## 核心创始人

### Stephan Ewen

Stephan Ewen 是 Flink 最核心的创始人和架构师。
他在 TU Berlin 攻读博士期间参与了 Stratosphere 项目，
此后一直主导 Flink 的技术方向。

Ewen 是 DataArtisans（后更名为 Ververica）的联合创始人和 CTO。
2019 年阿里巴巴收购 Ververica 后，他继续在阿里巴巴领导 Flink 的开发工作。

他在流处理系统的架构设计方面有极深的造诣，
主导了 Flink 的状态管理、检查点机制和时间语义等核心功能的设计。

### Kostas Tzoumas

Kostas Tzoumas 是 DataArtisans/Ververica 的联合创始人和 CEO。
他同样来自 TU Berlin 的 Stratosphere 项目。

Tzoumas 在 Flink 的早期发展中同时扮演了技术和商业角色，
推动了 Flink 从学术项目到 Apache 顶级项目的转变。

### Robert Metzger

Robert Metzger 是 Stratosphere 项目和 Flink 的早期核心开发者。
他在 TU Berlin 参与了项目的早期研发，
后加入 DataArtisans/Ververica 继续 Flink 的开发工作。

Metzger 是 Flink 社区的活跃贡献者和 PMC 成员，
在社区建设和项目管理方面做出了重要贡献。

### Fabian Hueske

Fabian Hueske 是 Flink 的另一位核心创始人，
同样来自 TU Berlin 的 Stratosphere 研究组。

Hueske 与 Vasiliki Kalavri 合著了 "Stream Processing with Apache Flink"
（O'Reilly, 2019），这是 Flink 领域的重要参考书。

他在 Flink 的查询优化和 Table API/SQL 层面做出了重要贡献。

## 从 Stratosphere 到 Flink

### Stratosphere 项目 (2010)

Stratosphere 项目始于 2010 年，由 TU Berlin 的研究人员发起。
项目最初的目标是构建一个新一代的大规模数据处理系统，
能够统一批处理和流处理。

项目得到了德国科学基金会（DFG）的资助，
由 Volker Markl 教授领导的数据库和信息管理研究组支持。

### 进入 Apache (2014)

2014 年 4 月，Stratosphere 项目被捐赠给 Apache 软件基金会，
更名为 Apache Flink。"Flink" 在德语中意为"敏捷"。

同年 12 月，Flink 成为 Apache 顶级项目，
标志着它获得了 Apache 社区的认可和独立地位。

### DataArtisans / Ververica (2014)

2014 年，几位核心创始人成立了 DataArtisans 公司
（2019 年更名为 Ververica），
提供基于 Flink 的商业产品和技术支持。

## 阿里巴巴与 Blink

### 阿里巴巴的采用

阿里巴巴是 Flink 最大的企业用户之一。
阿里巴巴在内部大规模使用 Flink 进行实时数据处理，
场景包括双十一的实时数据大屏、搜索推荐、风控等。

### Blink 分支

阿里巴巴在内部开发了 Flink 的分支版本 Blink，
加入了大量针对大规模生产环境的优化和改进：
- 增强的 SQL 支持
- 优化的资源调度
- 改进的状态管理

### 合并回社区 (Flink 1.9)

2019 年，阿里巴巴收购了 Ververica，
并将 Blink 的大量改进合并回 Flink 主分支（1.9 版本）。

这次合并是 Flink 历史上最重要的技术升级之一：
- 全新的 Blink SQL Planner
- 改进的 Table API
- 优化的任务调度
- 更好的大规模集群支持

## Flink SQL

Flink SQL 是 Flink 生态中越来越重要的一部分：
- 支持标准 SQL 语法进行流处理
- 动态表（Dynamic Tables）概念
- 时间属性和水印
- 连续查询（Continuous Queries）
- 丰富的连接器生态（Kafka、Hive、JDBC 等）

Flink SQL 使得不熟悉 Java/Scala API 的用户
也能使用 SQL 来表达复杂的流处理逻辑。

## 影响

Flink 的创始人们对流处理领域产生了深远影响：
- 统一了批处理和流处理的编程模型
- 引入了精确一次（exactly-once）语义的工程实现
- 推动了事件时间（event time）处理在工业界的普及
- Flink SQL 降低了流处理的使用门槛
- 影响了后续流处理系统的设计

从 TU Berlin 的学术项目到全球广泛使用的流处理引擎，
Flink 的发展历程体现了欧洲数据库学术界向工业界
成功转化的传统。
