# DuckDB 创始人 - Mark Raasveldt & Hannes Muhleisen

DuckDB 是一个嵌入式分析数据库，被称为"分析领域的 SQLite"。
它由两位荷兰 CWI 研究员 Mark Raasveldt 和 Hannes Muhleisen 创建。

## CWI 与 Database Architectures 组

CWI（Centrum Wiskunde & Informatica）是荷兰国家数学与计算机科学研究中心，
位于阿姆斯特丹。CWI 的 Database Architectures 研究组
有着深厚的数据库研究传统，最著名的成果是 MonetDB——
世界上第一个列式数据库系统。

Raasveldt 和 Muhleisen 都在 CWI 的 Database Architectures 组工作，
在 MonetDB 团队的学术环境中成长。

## Mark Raasveldt

Mark Raasveldt 在 CWI 获得博士学位，研究方向包括
数据库与数据科学工具的集成。他的博士论文研究了
如何让数据库系统更好地服务于数据科学工作流程。

他是 DuckDB 的核心架构师，负责了查询引擎和存储层的设计。
在 DuckDB Labs 担任 CEO。

## Hannes Muhleisen

Hannes Muhleisen 是 CWI 的研究员，研究兴趣包括
数据管理、数据集成和数据库系统架构。

他在学术界发表了大量论文，涉及数据库系统的各个方面。
在 DuckDB Labs 担任首席科学家。

### 2025 荷兰 ICT 研究奖

Hannes Muhleisen 获得了 2025 年荷兰 ICT 研究奖（ICT Research Award），
这是对他在数据管理领域学术贡献的认可。

## DuckDB 的诞生 (2018-2019)

### 从 MonetDB 到 DuckDB

Raasveldt 和 Muhleisen 最初尝试修改 MonetDB 以更好地支持
嵌入式使用场景——例如在 R 或 Python 中直接使用数据库功能。
但他们发现 MonetDB 的客户端-服务器架构不适合嵌入式部署。

他们决定从零开始构建一个新的系统，专门为以下场景设计：
- 嵌入式部署（无需独立服务器）
- 分析查询（OLAP）
- 与数据科学工具的深度集成

这就是 DuckDB 的由来——名字来源于一种常见的鸭子品种，
也暗示了"duck typing"的灵活性。

### 关键设计决策

DuckDB 的架构融合了多年的数据库研究成果：
- **向量化执行引擎**：受 MonetDB/X100 论文的影响
- **单文件存储**：类似 SQLite 的简洁部署
- **进程内运行**：无需独立的数据库服务器
- **支持复杂分析查询**：窗口函数、CTE、复杂聚合
- **零外部依赖**：完全自包含的 C++ 代码库

## DuckDB Labs (2021)

2021 年，Raasveldt 和 Muhleisen 创立了 DuckDB Labs，
作为 CWI 的 spin-off 公司。DuckDB Labs 负责 DuckDB 的
商业化开发和长期维护。

公司采用了类似 SQLite 的商业模式——核心引擎开源（MIT 许可证），
通过企业支持和定制开发获取收入。

DuckDB Labs 获得了风险投资，但团队保持了相对精简的规模，
专注于核心引擎的质量和性能。

## 技术贡献

### SQL 方言

DuckDB 的 SQL 方言注重开发者体验，包含多项创新：
- **友好的 SQL 语法**：如 `SELECT * EXCLUDE (col)`, `COLUMNS` 表达式
- **LIST 和 STRUCT 类型**：原生支持嵌套数据
- **直接查询文件**：`SELECT * FROM 'data.parquet'`
- **Friendly SQL**：容错的 SQL 解析，`GROUP BY ALL` 等便利语法

### 生态集成

DuckDB 在与数据科学工具的集成方面做了大量工作：
- Python（pandas/polars DataFrame 直接查询）
- R（DBI 接口）
- Node.js、Java、Rust 等多语言绑定
- Parquet、CSV、JSON 等文件格式的原生支持

## 学术论文

Raasveldt 和 Muhleisen 发表了多篇关于 DuckDB 的学术论文，包括：
- "DuckDB: an Embeddable Analytical Database"（SIGMOD 2019 Demo）
- 关于向量化执行、数据集成、存储格式等主题的论文

## 影响

DuckDB 的出现填补了嵌入式分析数据库的空白：
- 在数据科学和数据工程社区获得了快速采用
- 证明了嵌入式数据库不仅可以做 OLTP，也能做 OLAP
- 推动了"本地优先"数据分析的理念
- 其友好的 SQL 方言设计影响了其他数据库的语法扩展

从 CWI 的学术研究到全球广泛使用的开源项目，
DuckDB 是数据库学术研究成功转化为工业产品的又一个范例。
