# MaxCompute / Hologres 关键人物

> 信息来源：
> - [Alibaba Hologres: A Cloud-Native Service for Hybrid Serving/Analytical Processing (VLDB 2020)](https://dl.acm.org/doi/10.14778/3415478.3415550)
> - [Hologres 论文 PDF](https://kai-zeng.github.io/papers/hologres.pdf)
> - [阿里云 MaxCompute 发展历程](https://help.aliyun.com/zh/maxcompute/product-overview/maxcompute-development-history)
> - [2017 云栖大会 MaxCompute 分享](https://zhuanlan.zhihu.com/p/28018611)
> - [阿里云计算平台 MaxCompute/ODPS 团队 2025 春招](https://zhuanlan.zhihu.com/p/686568747)

---

## MaxCompute (原 ODPS)

### 项目起源

MaxCompute 最初名为 ODPS（Open Data Processing Service），是阿里巴巴"飞天"（Apsara）计划的核心组件之一。2009 年 9 月，飞天项目正式启动，ODPS 作为其统一大数据计算平台在阿里内部研发。2014 年作为阿里云公共云服务对外开放，2016 年更名为 MaxCompute。

目前 MaxCompute 承载了阿里巴巴集团约 99% 的数据存储和 95% 的计算量，是阿里最核心的数据基础设施。

### 关涛（花名：观滔）— MaxCompute 技术负责人

**已知公开信息**：
- 阿里巴巴通用计算平台负责人/高级技术专家
- 在 2017 年杭州云栖大会 MaxCompute 专场做主题分享，介绍了阿里大数据计算服务的演进历程和 MaxCompute 2.0 的发展方向
- 长期负责 MaxCompute SQL 引擎的架构升级和技术演进

**技术贡献**（基于公开演讲和文档）：
- 主导 MaxCompute 从 MapReduce 执行模型向 DAG 执行模型的演进
- 推动 MaxCompute SQL 2.0 语法增强（从 Hive 兼容到接近标准 SQL）
- 负责 HBO（History-Based Optimization）查询优化器的技术方向

> 来源：[2017 云栖大会 MaxCompute 分享](https://zhuanlan.zhihu.com/p/28018611)

### MaxCompute 核心技术栈

| 组件 | 说明 | 对标 |
|------|------|------|
| 伏羲 (Fuxi) | 分布式资源调度 | YARN |
| 盘古 (Pangu) | 分布式文件系统 | HDFS |
| AliORC | 优化的列式存储格式 | Apache ORC |
| MaxCompute SQL | 查询语言 (Hive 兼容 + 标准 SQL 扩展) | HiveQL / Spark SQL |

---

## Hologres

### 项目起源

Hologres 是阿里云自主研发的实时数仓引擎，2018 年在阿里内部启动研发，2020 年在阿里云上 GA（正式发布）。定位为 HSAP（Hybrid Serving and Analytical Processing），填补了 MaxCompute 在实时场景下的空白。

### VLDB 2020 论文作者团队

Hologres 的核心技术论文发表于 VLDB 2020，论文作者列表（按顺序）：

| 作者 | 角色（推测自论文排序） |
|------|---------------------|
| **蒋晓伟 (Xiaowei Jiang)** | 第一作者，阿里云研究员，Hologres 核心架构师 |
| Yuejun Hu | 联合作者 |
| Yu Xiang | 联合作者 |
| Guangran Jiang | 联合作者 |
| Xiaojun Jin (金晓军，花名：仙隐) | 阿里云高级技术专家 |
| Chen Xia | 联合作者 |
| Weihua Jiang | 联合作者 |
| Jun Yu | 联合作者 |
| Haitao Wang | 联合作者 |
| Yuan Jiang | 联合作者 |
| Jihong Ma | 联合作者 |
| Li Su | 联合作者 |
| **Kai Zeng (曾凯)** | 联合作者 |

> 论文标题：*Alibaba Hologres: A Cloud-Native Service for Hybrid Serving/Analytical Processing*
> 来源：[VLDB 2020, Vol 13, No 12](https://dl.acm.org/doi/10.14778/3415478.3415550) | [论文 PDF](https://kai-zeng.github.io/papers/hologres.pdf)

### 蒋晓伟（花名：量仔）— Hologres 核心架构师

**已知公开信息**：
- 阿里云研究员（Fellow 级别）
- Hologres VLDB 2020 论文第一作者
- 主导了 Hologres 的 HSAP（Hybrid Serving and Analytical Processing）架构设计
- 在多个技术会议上介绍 Hologres 的行列混存、计算存储分离等核心技术

**核心技术贡献**：
- 设计了 Hologres 的行列混存引擎——同一张表同时维护行存索引和列存文件
- 提出 HSAP 理念——在一个引擎中同时支持高并发点查（Serving）和复杂分析（Analytics）
- 推动 Hologres 与 MaxCompute 的深度集成（外部表加速查询）
- 设计了 Fixed Plan 写入优化——对已知模式的 INSERT 跳过优化器

> 来源：[Hologres VLDB 论文](https://kai-zeng.github.io/papers/hologres.pdf)、[数据仓库/数据湖/流批一体技术分析](https://zhuanlan.zhihu.com/p/140867025)

---

## 阿里云数据平台生态

MaxCompute 和 Hologres 是阿里云数据平台的核心组件：

| 产品 | 定位 | 关键场景 | 核心技术 |
|------|------|---------|---------|
| **MaxCompute** | 离线数仓 | EB 级批处理分析 | AliORC + 伏羲调度 + HBO 优化器 |
| **Hologres** | 实时数仓 | 实时分析与在线服务 | 行列混存 + HSAP + Fixed Plan |
| **Flink (实时计算)** | 流计算 | 实时 ETL 和流式处理 | 阿里 Blink → 合并回社区 |
| **AnalyticDB** | 分析数据库 | 高并发交互式分析 | MPP + 列存 |
| **PolarDB** | 云原生 OLTP | MySQL/PG 兼容 | 共享存储 + IMCI 列存索引 |

---

## 对引擎开发者的启示

1. **HSAP 架构（Hologres）**：在同一引擎中同时优化点查和分析是 HTAP 的进化——传统 HTAP 强调 OLTP+OLAP，HSAP 强调 Serving+Analytics，区别在于 Serving 场景的并发度比 OLTP 更高
2. **HBO 优化器（MaxCompute）**：基于历史执行统计优化后续查询，是对 CBO 的有力补充——在 ETL 管线中同一查询反复执行，HBO 利用上次的 runtime stats 生成更优计划
3. **论文驱动产品演进**：Hologres 的 VLDB 论文不只是学术发表，更是团队技术能力的外部验证。开源/论文是吸引人才的重要手段

---

*注：本页信息均来自公开渠道（学术论文、技术会议演讲、官方文档、招聘信息）。如有不准确之处欢迎指正。*
