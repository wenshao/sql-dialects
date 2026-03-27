# 引擎开发者阅读指南

本文档帮助 SQL 引擎开发者高效使用本项目。

## 你是谁？

### 场景 A: 我要设计某个 SQL 特性

> "我要给 MaxCompute/StarRocks/自研引擎 添加 UPSERT / 窗口函数 / 分区表 功能"

**阅读路径：**

1. **先看设计总览** → 该模块的 `_comparison.md`（如 [`dml/upsert/_comparison.md`](../dml/upsert/_comparison.md)），快速了解各引擎的方案选择
2. **再看 SQL 标准** → 该模块的 `sql-standard.sql`，了解标准怎么定义的
3. **然后看 3-5 个代表性引擎**:
   - MySQL（OLTP 基准）
   - PostgreSQL（功能最全的开源引擎）
   - Oracle（企业级参考）
   - ClickHouse 或 BigQuery（如果你的引擎是分析型的）
   - 你的兼容目标引擎（如果做兼容）
4. **最后看 README.md** → 该模块的"引擎开发者视角"部分，有实现建议

### 场景 B: 我在做某个引擎的兼容层

> "我们要兼容 MySQL / PostgreSQL / Oracle 协议"

**阅读路径：**

1. **先看兼容性指南** → [`docs/mysql-compat-guide.md`](mysql-compat-guide.md)（或 pg/oracle 版）
2. **然后看方言索引页** → [`dialects/mysql.md`](../dialects/mysql.md)，纵览该方言在所有模块中的文件
3. **重点看迁移速查** → [`scenarios/migration-cheatsheet/mysql.sql`](../scenarios/migration-cheatsheet/mysql.sql)
4. **逐模块对照** → 打开你关心的模块，对比目标方言和你当前引擎的差异

### 场景 C: 我在做技术调研

> "我想了解各引擎在事务/索引/类型系统上的设计差异"

**阅读路径：**

1. **从 INDEX.md 开始** → [`INDEX.md`](../INDEX.md)，"按设计主题导航" 和 "关键设计决策速查表"
2. **看分类 README** → 如 [`advanced/README.md`](../advanced/README.md)，有该类别的关键差异概述
3. **深入感兴趣的主题** → 如 [`advanced/transactions/`](../advanced/transactions/)，看几个代表性引擎的深度文件

### 场景 D: 我在评估技术选型

> "我要选一个数据库，需要了解各自的优劣"

**阅读路径：**

1. **看兼容性族谱** → [`INDEX.md`](../INDEX.md) 的"兼容性族谱"部分，了解各引擎的定位
2. **看方言索引** → [`dialects/`](../dialects/)，选几个候选引擎的页面
3. **看关键模块的对比表** → 如事务、分区、JSON 等你最关心的功能

## 项目结构速览

```
sql-dialects/
├── docs/                    ← 你现在在这里（开发指南）
├── dialects/                ← 按方言浏览（45 个方言索引页）
├── INDEX.md                 ← 全局导航（设计主题 + 决策速查表）
│
├── ddl/                     ← 7 个数据定义模块
├── dml/                     ← 4 个数据操作模块
├── query/                   ← 8 个查询模块
├── types/                   ← 5 个数据类型模块
├── functions/               ← 6 个函数模块
├── advanced/                ← 10 个高级特性模块
├── scenarios/               ← 11 个实战场景模块
│
├── REFERENCES.md            ← 官方文档链接索引
└── CONTRIBUTING.md          ← 贡献指南
```

每个模块目录下：
```
dml/upsert/
├── README.md                ← 模块说明 + 引擎开发者视角
├── _comparison.md           ← 横向对比表（快速总览）
├── mysql.sql                ← MySQL 的 UPSERT（深度分析）
├── postgres.sql             ← PostgreSQL 的 ON CONFLICT（深度分析）
├── clickhouse.sql           ← ClickHouse 的引擎级去重（深度分析）
├── ... (45 个方言)
└── sql-standard.sql         ← SQL 标准的 MERGE 定义
```

## 推荐阅读顺序（新引擎开发者）

如果你正在从零设计一个新的 SQL 引擎，建议按以下顺序了解各设计决策：

### 第一阶段：核心语义

1. [`ddl/create-table/`](../ddl/create-table/) — 类型系统、约束、存储模型
2. [`dml/insert/`](../dml/insert/) — 写入路径、批量加载
3. [`query/joins/`](../query/joins/) — JOIN 算法选择
4. [`advanced/transactions/`](../advanced/transactions/) — 事务模型（MVCC vs 锁）

### 第二阶段：查询能力

5. [`query/window-functions/`](../query/window-functions/) — 现代 SQL 分水岭
6. [`query/cte/`](../query/cte/) — 递归查询、物化策略
7. [`query/subquery/`](../query/subquery/) — 优化器设计
8. [`functions/aggregate/`](../functions/aggregate/) — GROUP BY 语义

### 第三阶段：差异化特性

9. [`types/json/`](../types/json/) — 半结构化数据支持
10. [`dml/upsert/`](../dml/upsert/) — UPSERT 语法选择
11. [`advanced/partitioning/`](../advanced/partitioning/) — 数据分布策略
12. [`ddl/indexes/`](../ddl/indexes/) — 索引体系设计

### 第四阶段：生态完善

13. [`advanced/permissions/`](../advanced/permissions/) — 权限模型
14. [`advanced/explain/`](../advanced/explain/) — 执行计划输出
15. [`advanced/stored-procedures/`](../advanced/stored-procedures/) — 可编程性
16. [`types/array-map-struct/`](../types/array-map-struct/) — 复合类型

## 每个 SQL 文件的阅读方法

深度文件（>150 行）的结构：

```
1. 基本语法        — 快速了解语法形式（可跳过）
2. 设计分析        — WHY: 为什么选择这种设计？trade-off 是什么？
3. 实现细节        — HOW: 内部存储、锁行为、优化器处理
4. 常见陷阱        — GOTCHA: 容易踩的坑
5. 横向对比        — VS: 其他引擎怎么做？各自优劣？
6. 版本演进        — HISTORY: 这个特性的演化历程
7. 引擎开发者启示  — SO WHAT: 对你设计新引擎的具体建议
```

**引擎开发者通常可以跳过第 1 部分（基本语法），直接看第 2-7 部分。**
