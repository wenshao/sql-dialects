# 查询执行阶段 (Query Execution Phases)

一条 SQL 从字符串到结果集，要穿过解析、绑定、改写、规划、优化、代码生成、执行等十余个阶段——理解这些阶段的边界，是 DBA 调优的前提，也是引擎开发者的基本功。

## 没有 SQL 标准

SQL 标准（ISO/IEC 9075）只定义查询的语义结果，不规定引擎内部如何实现。因此每个数据库的查询执行管线都是各自独立设计的产物：PostgreSQL 的 Parser → Rewriter → Planner → Executor 与 Oracle 的 Parser → Optimizer → Row Source Generator → Executor 在阶段命名、职责划分、内部数据结构上几乎没有共同点。即便是同一家族（如 Postgres 与 Greenplum、MySQL 与 TiDB、Presto 与 Trino），随着各自演化，内部架构也在不断分化。

虽然没有标准，但工业界经过数十年沉淀，形成了一组事实上通用的"阶段抽象"：

1. **Lexer / Tokenizer**：把 SQL 文本切成 token 流
2. **Parser**：按文法构造抽象语法树（AST）
3. **Semantic Analyzer / Binder / Resolver**：解析名字（表、列、函数），做类型检查
4. **Rewriter / Rule-Based Optimizer (RBO)**：基于规则的等价改写（视图展开、谓词下推、子查询去关联）
5. **Logical Planner**：构造与物理实现无关的逻辑计划（关系代数树）
6. **Cost-Based Optimizer (CBO)**：基于代价模型搜索物理计划空间
7. **Physical Planner**：选择具体算子实现（Hash Join vs Merge Join、索引 vs 顺序扫描）
8. **Codegen / JIT**：把计划编译为机器码（LLVM、Java bytecode、C++）
9. **Executor**：实际驱动算子运行（迭代器模型、Volcano、push-based pipeline、morsel-driven）

不同引擎对这些阶段的"切分粒度"差异极大。本篇按阶段逐一对比 49 个数据库的实现选择，并对 9 个有代表性的引擎做深入剖析。

## 支持矩阵

### 阶段 1: Lexer / Parser

所有 SQL 引擎都有 Parser，区别在于实现技术（手写递归下降 vs 解析器生成器）和语法兼容性。

| 引擎 | Parser 实现 | 工具 / 技术 | 备注 |
|------|------------|------------|------|
| PostgreSQL | 解析器生成器 | Bison + Flex | `gram.y` 约 19,000 行 |
| MySQL | 解析器生成器 | Bison | `sql_yacc.yy` |
| MariaDB | 解析器生成器 | Bison | 派生自 MySQL |
| SQLite | 解析器生成器 | Lemon (自研) | `parse.y` |
| Oracle | 手写 | C | 闭源 |
| SQL Server | 手写 | C++ | 闭源 |
| DB2 | 手写 | C++ | 闭源 |
| Snowflake | 手写 | Java | 闭源 |
| BigQuery | 手写 | C++ | ZetaSQL（开源） |
| Redshift | 派生 | PostgreSQL fork | 兼容 PG 8.0 语法 |
| DuckDB | 解析器生成器 | libpg_query | 复用 PostgreSQL 解析器 |
| ClickHouse | 手写 | C++ 递归下降 | `Parsers/` 目录 |
| Trino | 解析器生成器 | ANTLR4 | `SqlBase.g4` |
| Presto | 解析器生成器 | ANTLR4 | 与 Trino 共源 |
| Spark SQL | 解析器生成器 | ANTLR4 | `SqlBase.g4` |
| Hive | 解析器生成器 | ANTLR3/4 | `HiveParser.g` |
| Flink SQL | 解析器生成器 | Apache Calcite (JavaCC) | `Parser.jj` |
| Databricks | 解析器生成器 | ANTLR4 | 继承 Spark |
| Teradata | 手写 | C | 闭源 |
| Greenplum | 解析器生成器 | Bison | 继承 PostgreSQL |
| CockroachDB | 解析器生成器 | goyacc | 派生自 PG 语法 |
| TiDB | 解析器生成器 | yacc (Go) | `parser.y` |
| OceanBase | 解析器生成器 | Bison | C++ |
| YugabyteDB | 解析器生成器 | Bison | 继承 PostgreSQL |
| SingleStore | 手写 | C++ | 闭源 |
| Vertica | 解析器生成器 | Bison | C++ |
| Impala | 解析器生成器 | JFlex + CUP | Java 前端 |
| StarRocks | 解析器生成器 | ANTLR4 | Java 前端 |
| Doris | 解析器生成器 | ANTLR4 | Java 前端（新版） |
| MonetDB | 解析器生成器 | Bison | C |
| CrateDB | 解析器生成器 | ANTLR4 | 派生 Presto 语法 |
| TimescaleDB | 解析器生成器 | Bison | 继承 PostgreSQL |
| QuestDB | 手写 | Java 递归下降 | 自研 |
| Exasol | 手写 | C++ | 闭源 |
| SAP HANA | 手写 | C++ | 闭源 |
| Informix | 手写 | C | 闭源 |
| Firebird | 解析器生成器 | Bison | C++ |
| H2 | 手写 | Java 递归下降 | 自研 |
| HSQLDB | 手写 | Java | 自研 |
| Derby | 解析器生成器 | JavaCC | `sqlgrammar.jj` |
| Amazon Athena | 解析器生成器 | ANTLR4 | 继承 Trino |
| Azure Synapse | 手写 | C++ | 继承 SQL Server |
| Google Spanner | 手写 | C++ | ZetaSQL |
| Materialize | 解析器生成器 | sqlparser-rs | Rust |
| RisingWave | 解析器生成器 | sqlparser-rs | Rust |
| InfluxDB (SQL) | 解析器生成器 | DataFusion sqlparser-rs | Rust |
| DatabendDB | 手写 | nom (Rust) | parser combinator |
| Yellowbrick | 派生 | PostgreSQL fork | 继承 PG |
| Firebolt | 解析器生成器 | ANTLR4 | Java/C++ 混合 |

> 关键观察：Bison/yacc 派系（PostgreSQL 谱系）与 ANTLR 派系（Presto/Spark 谱系）平分秋色。新一代 Rust 引擎（Materialize、RisingWave、Databend）几乎全部依赖 `sqlparser-rs`。

### 阶段 2: Semantic / Analyzer / Resolver

把 AST 中的名字（表、列、函数、类型）解析到 catalog 对象，做类型推导和权限检查。不同引擎的命名差异较大：PostgreSQL 称 "parse analysis"、SQL Server 称 "Binder + Algebrizer"、Oracle 称 "Semantic Check"、Spark/Calcite 称 "Analyzer/Validator"。

| 引擎 | 阶段名 | 是否独立模块 |
|------|--------|------------|
| PostgreSQL | Parse Analysis | 是（`parse_*.c`） |
| MySQL | Resolver | 是（`sql_resolver.cc`，8.0 拆出） |
| MariaDB | (隐式) | 与 Optimizer 混合 |
| SQLite | Name Resolution | 是（`resolve.c`） |
| Oracle | Semantic Check | 是 |
| SQL Server | Binder + Algebrizer | 是（独立两步） |
| DB2 | Semantic Analysis | 是 |
| Snowflake | Analyzer | 是 |
| BigQuery | Resolver | 是（ZetaSQL Resolver） |
| Redshift | 同 PG | 继承 |
| DuckDB | Binder | 是（`Binder` 类） |
| ClickHouse | Analyzer | 是（新 Analyzer 23.3+） |
| Trino | Analyzer | 是（`StatementAnalyzer`） |
| Presto | Analyzer | 是 |
| Spark SQL | Analyzer | 是（Catalyst Analyzer） |
| Hive | SemanticAnalyzer | 是 |
| Flink SQL | Validator | 是（Calcite Validator） |
| Databricks | Analyzer | 继承 Spark |
| Teradata | Resolver | 是 |
| Greenplum | Parse Analysis | 继承 PG |
| CockroachDB | Optbuilder | 是（解析+绑定一体） |
| TiDB | Preprocessor + Logical Plan Builder | 是 |
| OceanBase | Resolver | 是 |
| YugabyteDB | Parse Analysis | 继承 PG |
| SingleStore | Analyzer | 是 |
| Vertica | Resolver | 是 |
| Impala | Analyzer | 是（Java） |
| StarRocks | Analyzer | 是（新 Analyzer） |
| Doris | Analyzer (Nereids) | 是 |
| MonetDB | SQL→REL | 是 |
| CrateDB | Analyzer | 是 |
| TimescaleDB | 同 PG | 继承 |
| QuestDB | (隐式) | 与编译器混合 |
| Exasol | (闭源) | -- |
| SAP HANA | Semantic Analyzer | 是 |
| Informix | (闭源) | -- |
| Firebird | DSQL Parser | 是 |
| H2 | (隐式) | 与编译器混合 |
| HSQLDB | (隐式) | 与编译器混合 |
| Derby | Bind | 是 |
| Athena | 同 Trino | 继承 |
| Azure Synapse | 同 SQL Server | 继承 |
| Spanner | Resolver | ZetaSQL |
| Materialize | Planner | 与 Plan 一体 |
| RisingWave | Binder | 是 |
| InfluxDB | Analyzer | DataFusion |
| Databend | Binder | 是 |
| Yellowbrick | 同 PG | 继承 |
| Firebolt | Analyzer | 是 |

### 阶段 3: Rewriter / 规则改写

基于规则的等价变换：视图展开、子查询去关联（unnest）、谓词下推、常量折叠、布尔简化等。许多引擎将其与 RBO 合并称呼。

| 引擎 | Rewriter | 子查询去关联 | 备注 |
|------|----------|------------|------|
| PostgreSQL | 是（独立 `rewriteHandler`） | 部分 | 视图、规则系统 |
| MySQL | 8.0 重构 | 8.0+（半连接转换） | -- |
| MariaDB | 是 | 是 | -- |
| SQLite | 是 | 部分 | flattening |
| Oracle | 是（Query Transformation） | 完整 | 极强（CSU、JPPD、SU） |
| SQL Server | 是（Simplification） | 完整 | -- |
| DB2 | 是 | 完整 | Starburst 派系 |
| Snowflake | 是 | 完整 | -- |
| BigQuery | 是 | 完整 | -- |
| Redshift | 是 | 部分 | -- |
| DuckDB | 是 | 完整（2022+） | -- |
| ClickHouse | 是 | 部分 | -- |
| Trino | 是（Iterative Optimizer） | 完整 | -- |
| Presto | 是 | 部分 | -- |
| Spark SQL | 是（Catalyst Rules） | 完整 | -- |
| Hive | 是 | 部分 | -- |
| Flink SQL | 是（Calcite RBO） | 完整 | -- |
| Databricks | 是 | 完整 | -- |
| Teradata | 是 | 完整 | -- |
| Greenplum | 是 | 完整 | ORCA |
| CockroachDB | 是（Norm Rules） | 完整 | Optgen DSL |
| TiDB | 是（Logical Optimize） | 完整 | -- |
| OceanBase | 是 | 完整 | -- |
| YugabyteDB | 同 PG | 部分 | -- |
| SingleStore | 是 | 完整 | -- |
| Vertica | 是 | 完整 | -- |
| Impala | 是 | 部分 | -- |
| StarRocks | 是（CBO 前 RBO） | 完整 | -- |
| Doris | 是（Nereids） | 完整 | -- |
| MonetDB | 是（rel optimizer） | 部分 | -- |
| CrateDB | 是 | 部分 | -- |
| TimescaleDB | 同 PG | -- | -- |
| QuestDB | 是 | -- | -- |
| Exasol | 是 | 完整 | -- |
| SAP HANA | 是 | 完整 | -- |
| Informix | 是 | -- | -- |
| Firebird | 是 | 部分 | -- |
| H2 | 是 | -- | -- |
| HSQLDB | 是 | -- | -- |
| Derby | 是 | -- | -- |
| Athena | 同 Trino | -- | -- |
| Azure Synapse | 同 SQL Server | -- | -- |
| Spanner | 是 | 完整 | -- |
| Materialize | 是 | 完整 | LIR rules |
| RisingWave | 是 | 完整 | -- |
| InfluxDB | 是 | -- | DataFusion rules |
| Databend | 是 | 完整 | -- |
| Yellowbrick | 同 PG | -- | -- |
| Firebolt | 是 | 完整 | -- |

### 阶段 4: Logical Planner

把改写后的查询树转换为关系代数（逻辑算子树），与具体物理实现解耦。

| 引擎 | 是否有独立逻辑层 | 表示 |
|------|----------------|------|
| PostgreSQL | 否（Query 树直转 Plan） | -- |
| MySQL | 否（8.0 之前） | -- |
| MySQL 8.0 | 是（Hypergraph 之下） | -- |
| SQLite | 否 | -- |
| Oracle | 是 | 内部 IR |
| SQL Server | 是 | Logical Operator Tree |
| DB2 | 是 | QGM |
| Snowflake | 是 | -- |
| BigQuery | 是 | ResolvedAST |
| Redshift | 部分 | -- |
| DuckDB | 是 | `LogicalOperator` |
| ClickHouse | 是 | QueryPlan |
| Trino | 是 | `PlanNode` |
| Presto | 是 | -- |
| Spark SQL | 是 | `LogicalPlan` |
| Hive | 是 | Operator Tree |
| Flink SQL | 是 | Calcite RelNode |
| Databricks | 是 | -- |
| Teradata | 是 | -- |
| Greenplum | 是 | ORCA Memo |
| CockroachDB | 是 | RelExpr |
| TiDB | 是 | LogicalPlan |
| OceanBase | 是 | -- |
| YugabyteDB | 否 | 同 PG |
| SingleStore | 是 | -- |
| Vertica | 是 | -- |
| Impala | 是 | -- |
| StarRocks | 是 | OptExpression |
| Doris | 是 | Nereids LogicalPlan |
| MonetDB | 是 | rel_*  |
| CrateDB | 是 | LogicalPlan |
| TimescaleDB | 同 PG | -- |
| QuestDB | 部分 | -- |
| Exasol | 是 | -- |
| SAP HANA | 是 | -- |
| Informix | 部分 | -- |
| Firebird | 部分 | -- |
| H2 | 否 | -- |
| HSQLDB | 否 | -- |
| Derby | 是 | -- |
| Athena | 同 Trino | -- |
| Azure Synapse | 同 SQL Server | -- |
| Spanner | 是 | -- |
| Materialize | 是 | MIR / LIR |
| RisingWave | 是 | -- |
| InfluxDB | 是 | DataFusion LogicalPlan |
| Databend | 是 | -- |
| Yellowbrick | 同 PG | -- |
| Firebolt | 是 | -- |

### 阶段 5: Cost-Based Optimizer (CBO)

基于统计信息和代价模型，在等价的物理计划空间中做搜索。这是现代查询优化器的核心。

| 引擎 | CBO | 框架/算法 | 默认开启 | 备注 |
|------|-----|----------|---------|------|
| PostgreSQL | 是 | System R + 动态规划 | 是 | 大表用遗传算法 |
| MySQL | 是 | 贪心 | 是 | 8.0+ Hypergraph 实验 |
| MariaDB | 是 | 贪心 | 是 | -- |
| SQLite | 是 | 简化 | 是 | NGQP（下一代查询规划器） |
| Oracle | 是 | 自研 + bushy | 是 | 业界最成熟之一 |
| SQL Server | 是 | Cascades 派生 | 是 | -- |
| DB2 | 是 | Starburst | 是 | -- |
| Snowflake | 是 | 自研 | 是 | -- |
| BigQuery | 是 | 自研 | 是 | -- |
| Redshift | 是 | 派生 PG | 是 | -- |
| DuckDB | 是 | 动态规划 + JoinOrder | 是 | -- |
| ClickHouse | 部分 | 启发式 | 部分 | 23+ 引入 RBO+CBO 混合 |
| Trino | 是 | Iterative + CBO | 是 | -- |
| Presto | 是 | -- | 是 | -- |
| Spark SQL | 是 | Catalyst CBO | 否 | 默认仅 RBO |
| Hive | 是 | Calcite CBO | 是 | -- |
| Flink SQL | 是 | Calcite Volcano | 是 | -- |
| Databricks | 是 | -- | 是 | -- |
| Teradata | 是 | -- | 是 | -- |
| Greenplum | 是 | ORCA (Cascades) | 是 | -- |
| CockroachDB | 是 | Cascades 派生 | 是 | Optgen DSL |
| TiDB | 是 | 动态规划 | 是 | -- |
| OceanBase | 是 | -- | 是 | -- |
| YugabyteDB | 是 | 同 PG | 是 | -- |
| SingleStore | 是 | -- | 是 | -- |
| Vertica | 是 | -- | 是 | -- |
| Impala | 是 | -- | 是 | -- |
| StarRocks | 是 | Cascades | 是 | -- |
| Doris | 是 | Cascades (Nereids) | 是 | -- |
| MonetDB | 部分 | -- | -- | -- |
| CrateDB | 是 | -- | 是 | -- |
| TimescaleDB | 同 PG | -- | 是 | -- |
| QuestDB | 否 | -- | -- | RBO only |
| Exasol | 是 | -- | 是 | -- |
| SAP HANA | 是 | -- | 是 | -- |
| Informix | 是 | -- | 是 | -- |
| Firebird | 部分 | -- | -- | -- |
| H2 | 是（简化） | -- | 是 | -- |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 是 | -- | 是 | -- |
| Athena | 同 Trino | -- | 是 | -- |
| Azure Synapse | 同 SQL Server | -- | 是 | -- |
| Spanner | 是 | -- | 是 | -- |
| Materialize | 是 | -- | 是 | -- |
| RisingWave | 是 | -- | 是 | -- |
| InfluxDB | 部分 | DataFusion | 是 | -- |
| Databend | 是 | Cascades | 是 | -- |
| Yellowbrick | 同 PG | -- | 是 | -- |
| Firebolt | 是 | -- | 是 | -- |

### 阶段 6: Physical Planner

| 引擎 | 是否独立物理层 | 备注 |
|------|--------------|------|
| PostgreSQL | 与 Plan 合并 | Plan 即物理计划 |
| Oracle | 是 | Row Source Generator |
| SQL Server | 是 | -- |
| DB2 | 是 | LOLEPOP/POP |
| Snowflake | 是 | -- |
| BigQuery | 是 | -- |
| DuckDB | 是 | `PhysicalOperator` |
| ClickHouse | 是 | QueryPipeline |
| Trino | 是 | Stage Plan |
| Spark SQL | 是 | `SparkPlan` |
| Flink SQL | 是 | ExecNode |
| CockroachDB | 是 | DistSQL Plan |
| TiDB | 是 | PhysicalPlan |
| Greenplum | 是 | -- |
| StarRocks | 是 | -- |
| Doris | 是 | Nereids PhysicalPlan |
| Materialize | 是 | LIR |

> 其余引擎多采用"逻辑+物理一体"或闭源未公开。

### 阶段 7: Codegen / JIT

| 引擎 | JIT/Codegen | 技术 | 引入版本 |
|------|------------|------|---------|
| PostgreSQL | 是 | LLVM | 11 (2018)，jit=on 默认 12+ |
| MySQL | 否 | -- | -- |
| MariaDB | 否 | -- | -- |
| SQLite | 否 | -- | -- |
| Oracle | 否 | -- | -- |
| SQL Server | 否 | -- | 仅 In-Memory OLTP 有 NCSP |
| DB2 | 否（公开层面） | -- | -- |
| Snowflake | 部分 | -- | 闭源 |
| BigQuery | 部分 | -- | 闭源 |
| Redshift | 是 | C++ codegen | 早期 |
| DuckDB | 否 | -- | 故意选择解释执行 |
| ClickHouse | 部分 | LLVM | 表达式 JIT |
| Trino | 是 | Java bytecode | -- |
| Presto | 是 | Java bytecode | -- |
| Spark SQL | 是 | Whole-Stage Codegen (Java) | 2.0+ |
| Hive | 否 | -- | -- |
| Flink SQL | 是 | Janino (Java) | -- |
| Databricks | 是 | Photon (C++) | -- |
| Teradata | 否 | -- | -- |
| Greenplum | 是 | LLVM (可选) | -- |
| CockroachDB | 否 | -- | -- |
| TiDB | 否 | -- | -- |
| OceanBase | 否 | -- | -- |
| Impala | 是 | LLVM | 1.0 起 |
| MonetDB | 是 | LLVM (MAL) | -- |
| StarRocks | 部分 | LLVM 表达式 | -- |
| Doris | 部分 | LLVM 表达式 | -- |
| Vertica | 是 | -- | -- |
| Materialize | 否 | -- | -- |
| Databend | 部分 | LLVM 表达式 | -- |
| Firebolt | 是 | -- | -- |

### 阶段 8: Interpreter vs Compiled

| 引擎 | 模式 |
|------|------|
| PostgreSQL | 解释器 + 可选 JIT |
| MySQL | 解释器 |
| MariaDB | 解释器 |
| SQLite | 字节码 VM (VDBE) |
| Oracle | 解释器 |
| SQL Server | 解释器（OLTP 模块例外） |
| DB2 | 解释器 |
| DuckDB | 解释器（向量化） |
| ClickHouse | 解释器（向量化）+ 表达式 JIT |
| Trino | JVM 字节码编译 |
| Spark SQL | JVM 字节码编译（Whole-Stage） |
| Impala | LLVM 全编译 |
| MonetDB | 全编译 |
| Photon | C++ 全编译 |
| TiDB | 解释器 |
| CockroachDB | 解释器（向量化） |
| Greenplum | 解释器 + LLVM |

### 阶段 9: Vectorized Execution

向量化（一次处理一批 rows，而非一次一行）是过去 15 年最重要的执行模型变革，源自 MonetDB/X100（Boncz et al., 2005）。

| 引擎 | 向量化 | 批大小 | 备注 |
|------|--------|--------|------|
| PostgreSQL | 否 | -- | 仍是行迭代 |
| MySQL | 否 | -- | -- |
| MariaDB | 否 | -- | -- |
| SQLite | 否 | -- | -- |
| Oracle | 部分 | -- | In-Memory Column Store |
| SQL Server | 是（部分） | -- | Batch Mode（列存表） |
| DB2 | 是（BLU） | -- | -- |
| Snowflake | 是 | -- | -- |
| BigQuery | 是 | -- | -- |
| Redshift | 是 | -- | -- |
| DuckDB | 是 | 2048 | -- |
| ClickHouse | 是 | 65536 | SIMD 极致优化 |
| Trino | 部分 | -- | Page 模型 |
| Presto | 部分 | -- | -- |
| Spark SQL | 部分 | 4096 | Parquet/ORC 读取向量化 |
| Photon | 是 | -- | C++ |
| Hive | 是 | 1024 | LLAP |
| Flink SQL | 是（部分） | -- | -- |
| Databricks | 是 | -- | Photon |
| Teradata | -- | -- | -- |
| Greenplum | 是 | -- | -- |
| CockroachDB | 是 | -- | ColExec |
| TiDB | 是 | -- | TiFlash 列存 |
| OceanBase | 是 | -- | -- |
| YugabyteDB | 否 | -- | -- |
| SingleStore | 是 | -- | -- |
| Vertica | 是 | -- | -- |
| Impala | 部分 | -- | LLVM 编译 |
| StarRocks | 是 | -- | C++ SIMD |
| Doris | 是 | -- | C++ SIMD |
| MonetDB | 是 | 列整列 | 始祖 |
| CrateDB | 否 | -- | -- |
| TimescaleDB | 否 | -- | -- |
| QuestDB | 是 | -- | SIMD |
| Exasol | 是 | -- | -- |
| SAP HANA | 是 | -- | -- |
| Informix | 否 | -- | -- |
| Firebird | 否 | -- | -- |
| H2 | 否 | -- | -- |
| HSQLDB | 否 | -- | -- |
| Derby | 否 | -- | -- |
| Athena | 部分 | -- | 同 Trino |
| Azure Synapse | 是 | -- | -- |
| Spanner | 是 | -- | -- |
| Materialize | 部分 | -- | -- |
| RisingWave | 是 | -- | -- |
| InfluxDB | 是 | -- | DataFusion + Arrow |
| Databend | 是 | -- | -- |
| Yellowbrick | 是 | -- | -- |
| Firebolt | 是 | -- | -- |

### 阶段 10: Executor 模型（迭代器 / Volcano / Pipeline / Morsel）

| 引擎 | 执行模型 | 备注 |
|------|---------|------|
| PostgreSQL | Volcano 迭代器（pull） | -- |
| MySQL | 迭代器（8.0 重写） | 之前是嵌套循环硬编码 |
| MariaDB | 迭代器 | -- |
| SQLite | 字节码 VM | VDBE |
| Oracle | Volcano 迭代器 | -- |
| SQL Server | Volcano 迭代器 + Batch Mode | -- |
| DB2 | Volcano | -- |
| Snowflake | Push-based pipeline | -- |
| BigQuery | Dremel pipeline | -- |
| Redshift | Push-based | -- |
| DuckDB | Push-based morsel-driven | 借鉴 HyPer |
| ClickHouse | Push-based pipeline | -- |
| Trino | Pull-based pipeline | -- |
| Presto | Pull-based pipeline | -- |
| Spark SQL | Whole-Stage Codegen pipeline | Volcano + 编译融合 |
| Hive | Tez DAG | -- |
| Flink SQL | Streaming dataflow | -- |
| Databricks | Photon push pipeline | -- |
| Teradata | -- | -- |
| Greenplum | Volcano + 分布式 motion | -- |
| CockroachDB | Volcano + ColExec push | DistSQL |
| TiDB | Volcano + TiFlash MPP | -- |
| OceanBase | Volcano | -- |
| YugabyteDB | Volcano（PG） | -- |
| SingleStore | Push pipeline | LLVM |
| Vertica | Push pipeline | -- |
| Impala | Push (LLVM 编译) | -- |
| StarRocks | Pipeline (push) | -- |
| Doris | Pipeline (push) | 2.0+ |
| MonetDB | Operator-at-a-time | 列整列处理 |
| CrateDB | Volcano | -- |
| TimescaleDB | Volcano | -- |
| QuestDB | Push | -- |
| Exasol | Push | -- |
| SAP HANA | Push pipeline | -- |
| Materialize | Differential dataflow | Timely |
| RisingWave | Streaming dataflow | -- |
| InfluxDB | DataFusion pipeline | Arrow |
| Databend | Push pipeline | -- |
| Firebolt | Push pipeline | -- |

## 主要引擎深入剖析

### PostgreSQL：经典的 Parser → Rewriter → Planner → Executor

PostgreSQL 把查询执行划分为四个清晰的阶段，源代码目录与命名一一对应：

```
src/backend/parser/    -- Parser + Parse Analysis
src/backend/rewrite/   -- Rewriter (规则系统、视图展开)
src/backend/optimizer/ -- Planner (RBO + CBO)
src/backend/executor/  -- Executor (Volcano 迭代器)
```

阶段流转：

```
SQL 文本
  └─ raw_parser()              -- Bison 生成的 yyparse
       └─ RawStmt (抽象语法树)
  └─ parse_analyze()           -- 名字解析、类型推导
       └─ Query (语义化的查询树)
  └─ pg_rewrite_query()        -- 视图展开、规则改写
       └─ Query (重写后)
  └─ pg_plan_query()           -- 优化器
       ├─ subquery_planner()
       ├─ grouping_planner()
       ├─ query_planner() -> make_one_rel() -- 连接顺序枚举
       └─ Plan (物理计划)
  └─ ExecutorStart/Run/End()   -- Volcano 迭代器执行
       └─ ExecProcNode() pull 一行
```

执行器是经典的 Volcano 迭代器（Goetz Graefe, 1994）：每个算子实现 `ExecProcNode()`，父算子调用子算子获取下一行。这种模型代码简洁、组合性极好，但每行都有虚函数调用的开销——这正是 PostgreSQL 11 引入 LLVM JIT 的动机：把表达式求值（例如 `WHERE a + b > 10`）编译成机器码，去掉解释器的间接跳转。从 12 开始 `jit=on` 是默认值，但只有当代价超过 `jit_above_cost`（默认 100000）才真正触发。

PostgreSQL 没有独立的"逻辑/物理"分层：`Plan` 节点直接就是物理算子（`SeqScan`、`IndexScan`、`HashJoin`、`MergeJoin`、`NestLoop`），优化器在搜索过程中直接构造 `Plan`。这种"扁平化"是 PostgreSQL 优化器代码可读性高的原因，也是它难以引入 Cascades 风格全局变换的原因。

### Oracle：Parser → Optimizer → Row Source Generator → Executor

Oracle 使用 cursor 概念组织整个查询生命周期。一条 SQL 进入服务器后：

```
SQL → 软解析 (library cache 命中?)
       └─ 否 → 硬解析:
              ├─ Syntax Check (Parser)
              ├─ Semantic Check (绑定 catalog)
              ├─ Query Transformation (改写)
              ├─ Optimization (CBO)
              └─ Row Source Generation
       └─ 是 → 复用执行计划
       
执行: Open Cursor → Fetch (Row Source 迭代) → Close
```

Oracle 的 Optimizer（CBO）以查询变换的强大而著称：CSU（complex view merging）、JPPD（join predicate pushdown）、SU（subquery unnesting）、JPP（join elimination）等数十种变换可以把一个嵌套深的 SQL 改写得面目全非。Row Source Generator 是把优化后的逻辑计划转换为可执行的"行源树"——本质上是物理 plan 节点，每个节点暴露 `open / fetch / close` 三接口，构成 Volcano 迭代器。

Oracle 没有引入 JIT 编译执行器，但通过 In-Memory Column Store（12c+）支持向量化扫描和 SIMD 谓词求值。

### SQL Server：Parser → Binder → Algebrizer → Optimizer → QEE

SQL Server 把 PostgreSQL 的 "Parse Analysis" 拆成两个明确阶段：

1. **Binder**：解析名字到 catalog 对象
2. **Algebrizer**：构造关系代数树（Logical Operator Tree），同时做类型推导

之后的 Optimizer 是 Cascades 风格（Graefe 1995）的代价优化器，是业界 Cascades 框架最完整的工业实现之一。Memo 数据结构、规则驱动的等价类探索、自顶向下分支限界搜索都齐全。

执行引擎（Query Execution Engine）历史上是行迭代器，2012 引入 Columnstore 后增加了 **Batch Mode**：每次处理 ~900 行的批，配合列存压缩可达 10x-100x 提速。SQL Server 本身没有 LLVM JIT，但 In-Memory OLTP 模块（Hekaton）会把 T-SQL 存储过程编译成 C 再编译成 DLL（Native Compiled Stored Procedures），这是另一条路径。

### MySQL：Parser → Resolver → Optimizer → Executor

MySQL 是少数早期版本中 "Optimizer 与 Executor 边界模糊" 的引擎。在 5.x 之前，连接执行直接是 `JOIN::exec()` 中嵌套循环的硬编码，并没有真正的迭代器。8.0 做了两件大事：

1. **Iterator executor**：把执行重写成迭代器树（`RowIterator::Read()`），与 PostgreSQL 类似的 Volcano 模型
2. **Hypergraph optimizer**（实验性）：基于 DPhyp 算法（Moerkotte & Neumann 2008）的连接顺序枚举，理论上能处理任意连接图（包括非内连接）。但目前默认关闭，需要 `SET optimizer_switch='hypergraph_optimizer=on'`。

老优化器是贪心的："left-deep tree only" 加 search depth 启发式裁剪。Hypergraph 优化器的目标是用十年的时间替换它。

### ClickHouse：Parser → Analyzer → Planner → Pipeline Executor

ClickHouse 把执行管线设计成显式的 `QueryPipeline` 数据结构：一组 `Processor` 通过端口（input/output port）连接，调度器按 push 模式驱动。每个 `Processor` 一次处理一个 `Chunk`（默认 65536 行的列式块），表达式求值大量使用 SIMD intrinsics（SSE4/AVX2/AVX512）。

ClickHouse 23.3 引入了 New Analyzer（替换老的 InterpreterSelectQuery 直接执行模型），使得"语义分析→逻辑计划→物理计划"的边界终于变清晰。表达式 JIT 通过可选的 LLVM 编译聚合函数和算术表达式。

### DuckDB：Parser → Binder → Logical Planner → Optimizer → Physical Planner → Executor

DuckDB 借鉴了 HyPer（TUM）的 morsel-driven 并行模型：

- Plan 被切分成 pipeline（Source → Operator* → Sink）
- 每个 pipeline 的 source 数据被切分成 morsel（约 100K 行）
- 工作线程从全局队列抢 morsel 处理，自然实现 NUMA-aware 负载均衡
- 算子内部用 vector（默认 2048 行）做向量化执行

DuckDB 故意选择**不使用 JIT**：作者 Mark Raasveldt 多次撰文论证，对于 OLAP 工作负载，向量化解释器 + 良好的算子内联已经能达到 JIT 编译执行 90% 的性能，但开发与维护成本远低于 LLVM 集成。

DuckDB 还复用了 PostgreSQL 的语法解析器（`libpg_query`），这使得它天然兼容 PostgreSQL SQL 语法。

### Spark SQL：Parser → Analyzer → Optimizer → Planner → Execution

Spark SQL 的 Catalyst 优化器是函数式编程风格树重写的典范实现（Scala）：

```
Unresolved Logical Plan
    → Analyzer (resolve names against catalog)
    → Optimized Logical Plan (Catalyst rules: pushdown, constant folding, etc.)
    → Physical Plan (SparkPlan, 生成多个候选)
    → Selected Physical Plan (按代价选择)
    → RDD execution (Whole-Stage Codegen 或解释执行)
```

Catalyst 的核心思想是：所有变换都是 `LogicalPlan => LogicalPlan` 的纯函数，规则可以无限组合。**Whole-Stage Codegen**（2.0 引入）把整个 pipeline 算子融合成一个 Java 函数（避免虚函数调用），这是它达到接近手写 C++ 性能的关键。

### Trino：Parser → Analyzer → Rewriter → Planner → Optimizer → Distributed Scheduler

Trino 分布式分阶段（pre-2017 称 Presto）：

```
ANTLR4 Parser → AST
StatementAnalyzer → Analysis (resolved names)
LogicalPlanner → PlanNode tree
IterativeOptimizer → Optimized PlanNode (CBO + 规则迭代)
PlanFragmenter → SubPlan (按 Exchange 切分 Stage)
SqlQueryScheduler → 分布式执行
```

执行端是 pull-based pipeline：每个 worker 上的 task 由若干 driver 组成，每个 driver 跑一段 pipeline。表达式编译成 JVM bytecode 提速。Trino 没有 morsel-driven 调度，而是依赖 Coordinator 静态切分 Stage 后 Worker 内部用 split scheduler 抓取数据分片。

### CockroachDB：Parser → Optbuilder → CBO → DistSQL

CockroachDB 的优化器全部用 **Optgen** 这门 DSL 写成。Optgen 把规则定义编译成 Go 代码，类似 Cascades 但更工程化：

```
SQL → goyacc Parser → AST
    → Optbuilder (绑定 + 构造 RelExpr)
    → Memo (Cascades 风格等价类)
    → Norm Rules (规范化变换，固定点)
    → Explore Rules (探索性变换，全局搜索)
    → Best Expression (按代价选择)
    → DistSQL Physical Plan (按 range 分布算子)
    → 各节点 Executor (Volcano + ColExec 向量化)
```

CockroachDB 同时维护两条执行路径：行迭代器（兼容性）和 ColExec 列向量化（性能）。优化器决定用哪条。

## Volcano、Morsel-Driven、向量化：三种执行模型的本质区别

### Volcano 迭代器 (Graefe, 1994)

```
parent.Next() → child.Next() → grandchild.Next() → ...
```

每个算子实现 `Open / Next / Close`，父算子 pull 一行，子算子在被调用时计算并返回。优点：组合性极好，新算子只要实现三个方法即可加入；并行化通过 Exchange 算子插入。缺点：每行都有虚函数调用，分支预测难，cache locality 差。

### 向量化（MonetDB/X100, Boncz 2005）

每次 `Next()` 返回一批行（vector，几百到几万行），算子内部用紧密循环处理整个 vector：

```cpp
for (int i = 0; i < vector_size; i++) {
    output[i] = a[i] + b[i];  // 编译器自动向量化为 SIMD
}
```

vector 大小要刚好放进 L1/L2 cache。这是 ClickHouse、DuckDB、Snowflake、Photon 共用的核心思想。相比 Volcano，单次虚函数调用的开销被分摊到几千行上，IPC（每周期指令数）通常提升 5-10x。

### Morsel-Driven 并行（HyPer, Leis et al. 2014）

向量化解决了"单线程效率"，morsel-driven 解决了"并行调度"：

- 一个 pipeline 被多个 worker thread 共同执行
- Source 数据被切成 morsel（约 10K-100K 行）
- worker 从全局队列抢 morsel，自己消费完一个再抢下一个
- 没有静态切分，自然均衡负载，对数据倾斜鲁棒
- 哈希表等共享数据结构需 lock-free 设计

DuckDB 是最纯粹的 morsel-driven 实现；HyPer（被 Tableau 收购）是发明者；Umbra 是 HyPer 的继任者。

### Whole-Stage Codegen vs 向量化解释器

Spark/Photon/Impala 走 "把整个 pipeline 编译成一个紧密循环" 的路线，DuckDB/ClickHouse 走 "向量化解释器" 路线。两者性能在 OLAP 上接近，但开发维护成本差异巨大：

- Codegen：调试难，编译延迟（首次执行慢），但峰值性能高
- 向量化解释器：开发简单，易调试，无编译延迟，性能略低

Mark Raasveldt（DuckDB）和 Andy Pavlo（CMU）都有公开演讲论证：对绝大多数工作负载，向量化解释器是更好的工程权衡。

## JIT 编译：谁有，谁没有，为什么

| 引擎 | JIT 状态 | 技术细节 |
|------|---------|---------|
| PostgreSQL | LLVM JIT 表达式 + tuple deform，11 引入，12+ 默认 on | 仅当 `total_cost > jit_above_cost` 才触发 |
| Oracle | 无 | 专注 In-Memory Column Store + SIMD |
| SQL Server | 无（QEE）| Hekaton OLTP 例外（Native Compiled Stored Procedures） |
| MySQL | 无 | -- |
| Spark | Whole-Stage Codegen (Java) | 编译为 JVM bytecode |
| Trino | 表达式编译 (JVM bytecode) | -- |
| Impala | LLVM 全计划编译 | 1.0 起 |
| MonetDB | LLVM (MAL 中间语言) | 始祖之一 |
| ClickHouse | LLVM 表达式 JIT | 可选 |
| Greenplum | LLVM (可选) | -- |
| DuckDB | 无（明确选择不做） | 向量化解释器 |
| Materialize | 无 | -- |
| Photon (Databricks) | C++ 全编译 | 不算 JIT，是 AOT |

PostgreSQL 引入 JIT 的故事很有代表性：Andres Freund 在 2017 年提议，2018 年 11 版本合并。LLVM 编译表达式后，移除了解释器中大量分支和虚函数调用，对宽表的复杂 WHERE/聚合可达 20%-50% 提速；但对短查询，编译延迟反而成本高，所以 `jit_above_cost`、`jit_inline_above_cost`、`jit_optimize_above_cost` 三个阈值都要调。

SQL Server 不做 JIT 的原因之一是 Batch Mode 已经把列存查询拉到了接近 JIT 的水平，而 Batch Mode 实现起来比 LLVM 集成简单得多。Oracle 同理。

## 关键发现

1. **没有标准，但有共识**：49 个引擎的执行管线都能映射到 Lexer→Parser→Analyzer→Rewriter→Logical→CBO→Physical→Executor 这套抽象，区别在阶段是否独立、命名差异、是否有 JIT。

2. **Bison vs ANTLR 的派系分裂**：Postgres 谱系（PG/Greenplum/Redshift/CockroachDB/TiDB）几乎全用 yacc 家族；Java 谱系（Hive/Spark/Trino/Flink/Impala/StarRocks）几乎全用 ANTLR。新一代 Rust 引擎（Materialize、RisingWave、Databend、InfluxDB）则统一选择 `sqlparser-rs`。

3. **DuckDB 复用 PostgreSQL 解析器**是工业界少见的高质量 fork：它通过 `libpg_query` 直接复用 Bison 文法，免费获得了与 PostgreSQL 兼容的 SQL 方言。

4. **Volcano 迭代器仍是主流**（30 年后仍未过时）：PostgreSQL/Oracle/SQL Server/MySQL/Greenplum/CockroachDB/TiDB/OceanBase 全部基于 Volcano。但执行细节上，几乎所有现代 OLAP 引擎都加上了向量化或 morsel-driven 改造。

5. **向量化是过去 15 年最大的执行模型变革**：源自 MonetDB/X100（2005），被 ClickHouse、DuckDB、Snowflake、Photon、StarRocks、Doris 等全部采纳。OLAP 引擎不向量化几乎等于落后一代。

6. **Morsel-Driven 是并行调度的范式转变**：HyPer 2014 论文之后，DuckDB、Photon、CockroachDB ColExec、Doris 2.0、StarRocks Pipeline 都向这个模型靠拢。它解决了"动态数据倾斜下的负载均衡"难题。

7. **JIT 是一种工程权衡，不是必然选项**：LLVM JIT 在 PostgreSQL/Impala/MonetDB/ClickHouse 上证明可行，但 DuckDB 故意拒绝 JIT，理由是向量化解释器达到 90% 的性能而开发成本只有 10%。Oracle 与 SQL Server 同样不做执行器 JIT，转而投资 In-Memory Column Store 与 Batch Mode。

8. **Spark Catalyst 是函数式优化器设计的标杆**：树重写规则的可组合性，使得加新优化规则只需写几十行 Scala。这种风格被 CockroachDB Optgen、Doris Nereids、StarRocks CBO 部分借鉴。

9. **Cascades 框架（Graefe 1995）的工业化**：SQL Server、Greenplum ORCA、CockroachDB、StarRocks、Doris Nereids、Databend 都基于 Cascades。它提供了"规则驱动 + 全局 Memo + 自顶向下搜索"的统一框架，但实现复杂度极高。

10. **MySQL 8.0 的 Hypergraph 优化器**仍是实验状态（默认关闭），是 MySQL 摆脱传统贪心连接顺序的长期努力，可能要等 9.x 才默认开启。

11. **PostgreSQL 没有独立的"逻辑/物理"分层**是它和 Cascades 派系最大的架构差别——这既是它代码可读性高的原因，也是它难以做全局变换的限制。

12. **闭源商业引擎（Oracle、SQL Server、Teradata、SAP HANA、Snowflake、BigQuery、Redshift、Vertica、Exasol、Firebolt）** 在论文与文档中只暴露阶段名，内部数据结构和算法细节几乎都不公开，研究者只能通过 EXPLAIN 输出和性能行为反推。

13. **"无 CBO" 引擎几乎已经绝迹**：49 个引擎中只剩 QuestDB、HSQLDB 等少数明确不做 CBO；连嵌入式 SQLite 都有 NGQP（下一代查询规划器）。
