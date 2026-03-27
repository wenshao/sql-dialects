# 贡献指南

感谢你对 sql-dialects 项目的关注！本指南将帮助你了解项目结构和贡献规范。

## 项目定位

本项目面向 **SQL 引擎开发者**（如 MaxCompute/StarRocks/Doris 的语法设计和开发人员），不是普通的 SQL 语法教程。

**好的内容**应该像 `ddl/create-table/mysql.sql` 那样：
- 分析**为什么** MySQL 选择 AUTO_INCREMENT 而不是 SEQUENCE（设计决策）
- 对比各方言在同一问题上的不同选择和 **trade-off**
- 给出**对引擎开发者的启示**（如果你在设计新引擎应该怎么选？）
- 讨论**实现细节**（innodb_autoinc_lock_mode 的三种模式）
- 总结**设计教训**（CHECK 约束"接受但不执行"是最差的设计选择）

**差的内容**只是罗列语法示例，没有观点和分析，随便一个官方文档或 ChatGPT 就能生成。

覆盖 45 种数据库方言和 51 个功能模块。

### 目录结构

```
sql-dialects/
├── ddl/                    # 数据定义语言
│   ├── create-table/       # 建表
│   ├── alter-table/        # 改表
│   ├── indexes/            # 索引
│   ├── constraints/        # 约束
│   ├── views/              # 视图
│   └── sequences/          # 序列与自增
├── dml/                    # 数据操作语言
│   ├── insert/             # 插入
│   ├── update/             # 更新
│   ├── delete/             # 删除
│   └── upsert/             # 插入或更新
├── query/                  # 查询
│   ├── joins/              # 连接查询
│   ├── subquery/           # 子查询
│   ├── window-functions/   # 窗口函数
│   ├── cte/                # 公共表表达式
│   ├── pagination/         # 分页
│   ├── full-text-search/   # 全文搜索
│   ├── set-operations/     # 集合操作
│   └── pivot-unpivot/      # 行列转换
├── types/                  # 数据类型
│   ├── string/             # 字符串类型
│   ├── numeric/            # 数值类型
│   ├── datetime/           # 日期时间类型
│   └── json/               # JSON 类型
├── functions/              # 内置函数
│   ├── string-functions/   # 字符串函数
│   ├── date-functions/     # 日期函数
│   ├── aggregate/          # 聚合函数
│   ├── conditional/        # 条件函数
│   ├── math-functions/     # 数学函数
│   └── type-conversion/    # 类型转换
├── advanced/               # 高级特性
│   ├── stored-procedures/  # 存储过程
│   ├── triggers/           # 触发器
│   ├── transactions/       # 事务
│   ├── permissions/        # 权限管理
│   ├── explain/            # 执行计划
│   ├── temp-tables/        # 临时表
│   ├── partitioning/       # 分区
│   ├── dynamic-sql/        # 动态 SQL
│   └── error-handling/     # 错误处理
├── scenarios/              # 实战场景
│   ├── ranking-top-n/      # TopN 查询
│   ├── running-total/      # 累计求和
│   ├── deduplication/      # 数据去重
│   ├── gap-detection/      # 区间缺失检测
│   ├── hierarchical-query/ # 层级查询
│   ├── date-series-fill/   # 日期序列填充
│   ├── string-split-to-rows/ # 字符串拆分
│   ├── json-flatten/       # JSON 展开
│   ├── slowly-changing-dim/# 缓慢变化维
│   └── migration-cheatsheet/ # 迁移速查
├── README.md               # 项目说明
├── REFERENCES.md           # 参考资料索引
└── CONTRIBUTING.md         # 贡献指南（本文件）
```

### 覆盖的 45 种方言

| 分类 | 方言 |
|---|---|
| 传统 RDBMS | MySQL, PostgreSQL, SQLite, Oracle, SQL Server, MariaDB, Firebird, IBM Db2, SAP HANA |
| 大数据/分析引擎 | BigQuery, Snowflake, MaxCompute, Hive, ClickHouse, StarRocks, Trino, Hologres, Doris, DuckDB, Spark SQL, Flink SQL |
| 云数仓 | Redshift, Synapse, Databricks, Greenplum, Impala, Vertica, Teradata |
| 分布式/NewSQL | TiDB, OceanBase, CockroachDB, Spanner, YugabyteDB, PolarDB, openGauss, TDSQL |
| 国产数据库 | DamengDB (达梦), KingbaseES (人大金仓) |
| 流处理 | Flink SQL, ksqlDB, Materialize |
| 时序数据库 | TimescaleDB, TDengine |
| 嵌入式/轻量 | H2, Derby |
| SQL 标准 | sql-standard.sql |

## 如何添加新方言

### 文件命名规范

每个方言的文件名必须全小写，使用以下固定名称：

| 方言 | 文件名 |
|---|---|
| MySQL | `mysql.sql` |
| PostgreSQL | `postgres.sql` |
| SQLite | `sqlite.sql` |
| Oracle | `oracle.sql` |
| SQL Server | `sqlserver.sql` |
| MariaDB | `mariadb.sql` |
| Firebird | `firebird.sql` |
| IBM Db2 | `db2.sql` |
| SAP HANA | `saphana.sql` |
| BigQuery | `bigquery.sql` |
| Snowflake | `snowflake.sql` |
| MaxCompute | `maxcompute.sql` |
| Hive | `hive.sql` |
| ClickHouse | `clickhouse.sql` |
| StarRocks | `starrocks.sql` |
| Trino | `trino.sql` |
| Hologres | `hologres.sql` |
| Doris | `doris.sql` |
| DuckDB | `duckdb.sql` |
| Spark SQL | `spark.sql` |
| Flink SQL | `flink.sql` |
| Redshift | `redshift.sql` |
| Synapse | `synapse.sql` |
| Databricks | `databricks.sql` |
| Greenplum | `greenplum.sql` |
| Impala | `impala.sql` |
| Vertica | `vertica.sql` |
| Teradata | `teradata.sql` |
| TiDB | `tidb.sql` |
| OceanBase | `oceanbase.sql` |
| CockroachDB | `cockroachdb.sql` |
| Spanner | `spanner.sql` |
| YugabyteDB | `yugabytedb.sql` |
| PolarDB | `polardb.sql` |
| openGauss | `opengauss.sql` |
| TDSQL | `tdsql.sql` |
| DamengDB | `dameng.sql` |
| KingbaseES | `kingbase.sql` |
| TimescaleDB | `timescaledb.sql` |
| TDengine | `tdengine.sql` |
| ksqlDB | `ksqldb.sql` |
| Materialize | `materialize.sql` |
| H2 | `h2.sql` |
| Derby | `derby.sql` |
| SQL 标准 | `sql-standard.sql` |

### 添加新方言的步骤

1. 在**每个模块目录**下创建对应的 SQL 文件（命名参照上表）
2. 按照下方的文件格式规范编写内容
3. 更新每个模块目录下的 `_comparison.md` 对比表
4. 更新 `REFERENCES.md` 添加该方言的官方文档链接
5. 更新 `README.md` 中的方言列表和项目规模数据

## 如何添加新模块

### 步骤

1. 在对应的分类目录下创建新目录（如 `query/new-module/`）
2. 为所有 45 种方言创建 SQL 文件
3. 创建 `_comparison.md` 对比总览表
4. 更新 `README.md` 中的目录结构部分

### 模块目录命名规范

- 全小写，使用连字符 `-` 分隔单词
- 名称应简洁明确，反映核心功能
- 示例：`window-functions`、`full-text-search`、`string-split-to-rows`

## 文件格式规范

### SQL 文件格式

每个 SQL 文件必须包含以下部分：

```sql
-- 方言名: 模块中文名（英文名）
--
-- 参考资料:
--   [1] 官方文档名称
--       https://official-doc-url
--   [2] 另一个参考链接
--       https://another-url

-- ============================================================
-- 示例数据上下文（或 准备数据）
-- ============================================================
-- 假设表结构:
--   table_name(col1 TYPE, col2 TYPE, ...)

-- ============================================================
-- 1. 第一个知识点
-- ============================================================

-- 说明注释
SELECT ...;

-- ============================================================
-- 2. 第二个知识点
-- ============================================================

-- 说明注释
SELECT ...;
```

#### 文件头（必需）

```sql
-- MySQL: 分页
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - SELECT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html
```

- 第一行：`-- 方言名: 模块中文名`
- 空注释行
- 参考资料部分：编号 `[1]`、`[2]`...，每个参考资料占两行（名称 + URL）

#### 参考资料（必需）

- 必须引用**官方文档**，不可引用第三方博客或教程
- 链接必须有效且指向当前版本的文档
- 推荐引用 2-3 个最相关的官方文档页面

#### 版本注释

在特性首次出现的版本旁标注版本号：

```sql
-- QUALIFY 直接过滤（Databricks Runtime 12.2+）
SELECT ...
QUALIFY ROW_NUMBER() OVER (...) <= 3;

-- MySQL 8.0+ 的窗口函数
SELECT ..., ROW_NUMBER() OVER (...) AS rn ...;

-- MySQL 5.7 及以下的替代方案（无窗口函数）
SELECT @rn := ... ;
```

- 版本标注格式：`方言名 版本号+`，如 `MySQL 8.0+`、`PostgreSQL 9.4+`、`Oracle 12c+`
- 旧版本的替代方案也应给出，并标注适用版本

#### 示例数据上下文

每个文件应在头部说明示例所用的表结构：

```sql
-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)
```

或提供可直接执行的建表和插入语句：

```sql
-- ============================================================
-- 准备数据
-- ============================================================
CREATE TABLE orders (...);
INSERT INTO orders VALUES ...;
```

#### 章节分隔

使用统一的分隔线格式：

```sql
-- ============================================================
-- N. 章节标题
-- ============================================================
```

#### 末尾注意事项（建议）

文件末尾可添加版本兼容性和性能相关的注释：

```sql
-- 注意：窗口函数需要 MySQL 8.0+
-- 注意：MySQL 默认递归深度 1000（cte_max_recursion_depth）
-- 注意：MySQL 5.x 只能用多层 JOIN 或应用层实现
```

### 对比表文件格式 (`_comparison.md`)

```markdown
# 模块中文名 (英文名) — 方言对比

## 语法支持对比

### 传统 RDBMS
| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 特性1 | ✅ | ✅ 8.4+ | ❌ | ✅ 12c+ | ⚠️ | ... |

### 大数据 / 分析引擎
(12 种方言)

### 云数据仓库
(7 种方言)

### 分布式 / NewSQL
(10 种方言)

### 特殊用途
(6 种方言)

## 关键差异
- 关键差异点 1
- 关键差异点 2
```

#### 对比表符号

| 符号 | 含义 |
|---|---|
| ✅ | 完全支持 |
| ✅ 版本号+ | 从指定版本开始支持（如 `✅ 8.0+`） |
| ❌ | 不支持 |
| ⚠️ | 部分支持 / 有限制 / 需要变通方案 |

#### 五个分类

对比表固定分为五个类别，每个类别包含固定的方言集合：

1. **传统 RDBMS**（9 种）：MySQL, PostgreSQL, SQLite, Oracle, SQL Server, MariaDB, Firebird, Db2, SAP HANA
2. **大数据 / 分析引擎**（12 种）：BigQuery, Snowflake, MaxCompute, Hive, ClickHouse, StarRocks, Trino, Hologres, Doris, DuckDB, Spark, Flink
3. **云数据仓库**（7 种）：Redshift, Synapse, Databricks, Greenplum, Impala, Vertica, Teradata
4. **分布式 / NewSQL**（10 种）：TiDB, OceanBase, CockroachDB, Spanner, YugabyteDB, PolarDB, openGauss, TDSQL, DamengDB, KingbaseES
5. **特殊用途**（6 种）：TimescaleDB, TDengine, ksqlDB, Materialize, H2, Derby

## 质量标准

### 准确性

- 所有 SQL 示例必须语法正确，能在对应数据库中实际执行
- 不支持的特性必须明确标注，不可给出错误的替代方案
- 版本号必须准确，参照官方发布说明

### 版本标注

- 标注特性首次支持的版本号
- 使用 `+` 后缀表示"及以上版本"
- 常见版本标注：
  - MySQL: `5.7`, `8.0+`, `8.0.4+`, `8.0.14+`
  - PostgreSQL: `8.4+`, `9.3+`, `9.4+`, `9.5+`, `11+`, `13+`, `14+`, `15+`
  - Oracle: `8i+`, `10g+`, `11g+`, `11gR2+`, `12c+`, `19c+`, `21c+`, `23c+`
  - SQL Server: `2005+`, `2008+`, `2012+`, `2016+`, `2017+`, `2019+`, `2022+`
  - SQLite: `3.8+`, `3.24+`, `3.25+`, `3.28+`, `3.35+`

### 官方文档引用

- 每个 SQL 文件必须引用官方文档
- 优先引用最新的稳定版文档
- 以下是各方言官方文档的 URL 格式：

| 方言 | 文档根 URL |
|---|---|
| MySQL | `https://dev.mysql.com/doc/refman/8.0/en/` |
| PostgreSQL | `https://www.postgresql.org/docs/current/` |
| SQLite | `https://www.sqlite.org/` |
| Oracle | `https://docs.oracle.com/en/database/oracle/oracle-database/` |
| SQL Server | `https://learn.microsoft.com/en-us/sql/` |
| BigQuery | `https://cloud.google.com/bigquery/docs/reference/standard-sql/` |
| Snowflake | `https://docs.snowflake.com/en/sql-reference/` |
| ClickHouse | `https://clickhouse.com/docs/en/sql-reference/` |
| Hive | `https://cwiki.apache.org/confluence/display/Hive/` |
| Spark SQL | `https://spark.apache.org/docs/latest/sql-ref.html` |

完整的参考资料索引请参阅 [REFERENCES.md](REFERENCES.md)。

### 内容深度（核心要求）

每个文件应包含以下层次的内容：

1. **语法示例**：正确的、可执行的 SQL 语法
2. **设计决策分析**：WHY — 为什么这个方言选择了这种语法设计？trade-off 是什么？
3. **横向对比**：同一问题在其他方言中怎么解决？各方案优劣？
4. **对引擎开发者的启示**：如果你在设计新引擎（如 MaxCompute），应该怎么选？
5. **实现细节**：锁模式、存储格式、优化器行为等引擎内部机制
6. **设计教训**：哪些设计被证明是错误的或有问题的？
7. **版本演进**：该特性在各版本中的变化历史

不要只写语法示例。**观点和分析比语法本身更有价值。**

### 横向对比（必需）

每个文件末尾必须包含"横向对比"部分，对比该方言与其他主要方言在同一主题上的差异：

```sql
-- ============================================================
-- 横向对比: MySQL vs 其他方言
-- ============================================================
-- 自增策略:
--   MySQL: AUTO_INCREMENT（简单，但分布式不适用）
--   PostgreSQL: SERIAL → IDENTITY（10+，SQL 标准）
--   Oracle: SEQUENCE → IDENTITY（12c+）
--   ...
```

### 内容完整性

每个方言的 SQL 文件应包含：

1. **推荐方式**：该方言中最佳/最惯用的写法
2. **标准方式**：符合 SQL 标准的写法（如果方言支持）
3. **替代方案**：旧版本或特殊场景的变通写法
4. **性能考量**：索引建议、执行计划提示等
5. **注意事项**：常见陷阱、版本限制、不支持的特性

## 审查清单

提交 PR 前请确认：

**内容深度：**
- [ ] 包含设计决策分析（WHY，不只是 HOW）
- [ ] 包含横向对比部分（vs 其他方言）
- [ ] 包含对引擎开发者的启示或建议
- [ ] 有观点和分析，不只是语法罗列

**准确性：**
- [ ] SQL 语法正确，可在对应数据库中执行
- [ ] 版本号标注准确（已查证官方发布说明）
- [ ] 参考资料链接指向官方文档且可访问
- [ ] 不支持的特性有明确标注

**格式：**
- [ ] SQL 文件命名符合规范（全小写，使用固定名称）
- [ ] 文件头包含方言名、模块名和参考资料
- [ ] 章节分隔使用统一的 `====` 格式
- [ ] `_comparison.md` 对比表已更新（如适用）
