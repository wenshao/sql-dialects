# Spark SQL / Databricks 关键人物

## Matei Zaharia — Apache Spark 创始人、Databricks CTO

**背景与教育**：
- 罗马尼亚裔加拿大计算机科学家
- 滑铁卢大学本科，ACM ICPC 2005 金牌（北美第一、世界第四）
- UC Berkeley 博士（AMPLab），2014 ACM 博士论文奖

**Apache Spark 的诞生**：
- 2009 年在 UC Berkeley AMPLab 创建 Apache Spark，作为 MapReduce 的更快替代
- 核心创新：RDD（弹性分布式数据集）——内存计算框架，比 MapReduce 快 10-100×
- Spark 论文被引用超过 15,000 次，是大数据领域最具影响力的论文之一

**Databricks**：
- 2013 年联合创立 Databricks（与 Ion Stoica、Ali Ghodsi、Andy Konwinski 等）
- 担任 CTO，主导了 Delta Lake、MLflow、Dolly 等项目
- 2022 年 Forbes 估值净资产 16 亿美元

**当前角色**：
- UC Berkeley 副教授（此前在 Stanford），Sky Lab 研究大规模计算和 AI
- 美国总统早期职业科学家和工程师奖（PECASE）获得者

> GitHub: [github.com/mateiz](https://github.com/mateiz)
> 学术主页: [people.eecs.berkeley.edu/~matei](https://people.eecs.berkeley.edu/~matei/)

---

## Michael Armbrust — Spark SQL 核心设计者

**Spark SQL 与 Catalyst 优化器**：
- 2013 年加入 Databricks，主导了 Spark SQL 的开发
- 设计了 **Catalyst 优化器**——基于 Scala 模式匹配的可扩展查询优化框架
- 共同作者：Spark SQL SIGMOD 2015 论文（与 Reynold Xin、Matei Zaharia 等）
- Catalyst 将其他系统需要数千行代码实现的优化规则简化为数十行

**Delta Lake**：
- 主导了 Delta Lake 的设计——为数据湖增加 ACID 事务、Time Travel、Schema Evolution
- Delta Lake 成为 Databricks Lakehouse 架构的核心

**当前角色**：
- Databricks VP of Engineering
- 持续推动 Spark SQL 的标准合规性（ANSI 模式、SQL:2003 窗口函数等）

---

## Reynold Xin (辛湜) — Spark SQL 联合创建者

**贡献**：
- UC Berkeley AMPLab 博士（Matei 的学弟），Spark SQL 论文联合第一作者
- 主导了 Spark 2.0 的 DataFrame API 和 Tungsten 执行引擎（二进制内存管理 + 代码生成）
- 推动了 Spark 从学术项目到企业级产品的转型

**当前角色**：
- Databricks 联合创始人，Chief Architect
- 主导 Photon 引擎（C++ 向量化执行，替代 JVM 执行层）

> GitHub: [github.com/rxin](https://github.com/rxin)

---

## Ion Stoica — Databricks 联合创始人

**背景**：
- UC Berkeley 教授，计算机系统领域的顶级学者
- 除 Spark 和 Databricks 外，还创建了 Apache Mesos 和 Anyscale（Ray 背后的公司）
- 罗马尼亚裔美国人，与 Matei Zaharia 同为 AMPLab 核心成员

---

## 对 SQL 引擎开发者的启示

1. **学术到产业的路径**：Spark 从 UC Berkeley 的论文 → 开源项目 → Databricks 商业化，是学术转化最成功的案例之一
2. **Catalyst 的设计哲学**：利用宿主语言（Scala）的高级特性（模式匹配、准引号）简化优化器实现——对比传统的 visitor pattern 模式，代码量减少 10×
3. **Lakehouse 路线**：Matei Zaharia 提出的 Lakehouse 架构（Delta Lake + Spark SQL）正在重塑数据仓库的定义——数据湖 + 事务 + BI 查询的统一

## 参考资料

- [Spark SQL: Relational Data Processing in Spark (SIGMOD 2015)](https://people.csail.mit.edu/matei/papers/2015/sigmod_spark_sql.pdf)
- [Deep Dive into Catalyst Optimizer (Databricks Blog)](https://www.databricks.com/blog/2015/04/13/deep-dive-into-spark-sqls-catalyst-optimizer.html)
- [Matei Zaharia - Wikipedia](https://en.wikipedia.org/wiki/Matei_Zaharia)
