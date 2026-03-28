# MaxCompute/Hologres 关键人物

MaxCompute（原 ODPS）和 Hologres 是阿里云数据平台的两大核心产品，
分别面向离线大数据计算和实时数仓场景。

## MaxCompute (原 ODPS)

### 项目背景

MaxCompute 最初名为 ODPS（Open Data Processing Service），
是阿里巴巴内部最大的数据计算平台，
支撑着每年双十一的海量数据分析需求。
MaxCompute 于 2010 年前后在阿里云内部启动研发，
是中国最早的大规模云原生数据计算平台之一。

### 关涛 (Guan Tao) - MaxCompute 技术负责人

关涛是阿里云 MaxCompute 的技术负责人（Tech Lead），
长期负责 MaxCompute 的核心引擎研发和技术演进。

他的主要技术贡献包括：
- 主导 MaxCompute SQL 引擎的架构升级
- 推动 MaxCompute 从 MapReduce 模型向 DAG 执行模型的演进
- 优化 MaxCompute 的查询优化器和执行引擎性能
- 在多个技术会议上分享 MaxCompute 的技术架构与实践

关涛在阿里云的技术博客和公开演讲中，
多次介绍 MaxCompute 如何处理 EB 级别的数据，
以及如何在超大规模集群上实现高效的资源调度。

### MaxCompute SQL

MaxCompute 的 SQL 方言基于标准 SQL 进行了扩展：
- 支持用户自定义函数（UDF/UDAF/UDTF）
- 内置对半结构化数据的处理能力
- 支持参数化视图和脚本模式
- 与阿里云生态（DataWorks、PAI 等）深度集成

## Hologres

### 项目背景

Hologres 是阿里云自主研发的实时数仓引擎，
定位为一站式实时数仓解决方案。
它能够同时支持实时写入和复杂分析查询，
填补了 MaxCompute 在实时场景下的空白。

### 阿里云实时数仓团队

Hologres 由阿里云计算平台事业部的实时数仓团队研发。
团队在实时计算和存储引擎方面积累了深厚的技术经验。

Hologres 的核心技术特性：
- **行列混合存储**：同一张表同时支持行存和列存
- **高并发点查与分析**：兼顾 serving 和 analytics
- **与 MaxCompute 无缝集成**：支持直接查询 MaxCompute 外表
- **实时写入**：支持高吞吐的实时数据摄入
- **PostgreSQL 兼容**：兼容 PostgreSQL 协议和大部分语法

### 技术论文

Hologres 团队在 VLDB 2020 发表了论文
"Alibaba Hologres: A Cloud-Native Service for Hybrid Serving/Analytical Processing"，
介绍了 Hologres 的系统架构和关键技术。

## 漆远与达摩院

漆远曾任阿里巴巴达摩院副院长，
负责人工智能与数据智能相关的研究方向。
达摩院在数据库与数据系统领域的研究
为阿里云的数据库产品提供了技术输入，
包括智能调优、自动索引推荐等 AI for DB 方向的探索。

## 阿里云数据库生态

MaxCompute 和 Hologres 是阿里云数据平台的核心组件，
与其他产品共同构成完整的数据生态：

| 产品 | 定位 | 关键场景 |
|------|------|----------|
| MaxCompute | 离线数仓 | EB 级批处理分析 |
| Hologres | 实时数仓 | 实时分析与在线服务 |
| Flink (实时计算) | 流计算 | 实时 ETL 和流式处理 |
| AnalyticDB | 分析数据库 | 高并发交互式分析 |

## 影响

阿里云数据平台团队的工作在以下方面具有重要意义：
- MaxCompute 是中国最大的公共云数据计算平台之一
- Hologres 推动了实时数仓从概念到产品的落地
- 积累了超大规模数据处理的工程实践经验
- 为中国云计算行业的数据基础设施建设做出了重要贡献
