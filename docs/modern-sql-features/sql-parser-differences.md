# SQL 解析器差异 (SQL Parser Differences)

同一段 `SELECT * FROM Users WHERE name = "Alice"`，在 PostgreSQL 里会因 `"Alice"` 被当作列名而报错，在 MySQL 里却能正常返回结果——这种"看起来一样的 SQL，实际语义截然不同"的差异，正是迁移和兼容层最常踩的坑。SQL 解析器差异是数据库可移植性的第一道天花板。

## 为什么解析器差异很重要

任何跨数据库工具——ORM、BI 报表、数据迁移、SQL 转译器、查询路由层、跨源联邦查询引擎——都必须面对这样一个事实：**SQL 标准只定义了语法的一部分，而每一个数据库都对解析器做了自己的取舍**。具体表现为：

1. **迁移成本**：把 Oracle 应用迁到 PostgreSQL，仅"标识符大小写"一项就可能让 90% 的存量 SQL 失效
2. **兼容层的天花板**：Babelfish (PG 模拟 SQL Server)、TiDB (模拟 MySQL)、OceanBase (Oracle 兼容模式) 都要在解析阶段就分流不同方言
3. **SQL 转译器的痛点**：sqlglot、jOOQ、Apache Calcite、ZetaSQL 必须为每种方言维护独立的词法+语法规则
4. **"看不见的"运行时错误**：标识符 `Order` 在 PG 中是保留字、在 MySQL 中可用、在 Oracle 中可用但需要小心，迁移后会以晦涩报错的形式出现
5. **安全漏洞**：注释风格差异可能被用于 SQL 注入绕过 (例如 MySQL 的 `#` 和 `-- ` 与标准的 `--` 行为不同)
6. **工具链碎片化**：连最简单的"SQL 美化器"和"SQL Lint"都必须为每种方言单独适配
7. **测试矩阵爆炸**：跨方言库的测试矩阵从单一变成 N 倍，CI 时间随方言数线性增长

本文系统对比 45+ 数据库引擎在词法层与解析层的关键差异，覆盖大小写折叠、标识符引号、字符串字面量、注释风格、保留字、Unicode、转义序列等十余个维度。

## SQL 标准是怎么说的

ISO/IEC 9075-2 (SQL/Foundation) 在第 5 章 "Lexical elements" 定义了 SQL 词法基础。简化后的 BNF 如下：

```bnf
<identifier>            ::= <regular identifier> | <delimited identifier>
<regular identifier>    ::= <identifier start> [ <identifier part>... ]
<delimited identifier>  ::= <double quote> <delimited identifier body> <double quote>
<character string literal> ::= [ <introducer> <character set specification> ]
                               <quote> [ <character representation>... ] <quote>
                               [ { <separator>... <quote> [ <character representation>... ] <quote> }... ]
<comment>               ::= <simple comment> | <bracketed comment>
<simple comment>        ::= <simple comment introducer> [ <comment character>... ] <newline>
<simple comment introducer> ::= <minus sign> <minus sign> [ <minus sign>... ]
<bracketed comment>     ::= <slash> <asterisk> ... <asterisk> <slash>
```

标准的关键规则：

1. **字符串字面量用单引号 `'...'`**（双引号留给标识符）
2. **标识符用双引号 `"..."`** 进行分隔（delimited identifier）
3. **未引号标识符（regular identifier）应被折叠为大写**（folded to uppercase）以便区分大小写比较
4. **行注释用 `--`**，块注释用 `/* ... */`（嵌套是 SQL:1999 起的可选特性 T351）
5. **保留字列表**由 ISO 9075 附录 (Annex E) 给出，分为 `<reserved word>` 与 `<non-reserved word>`
6. **字面量字符串中嵌入单引号用两个单引号 `''` 表示**，没有反斜杠转义
7. **`Unicode delimited identifier`** `U&"..."` 是 SQL:2003 引入的特性，用于在标识符中表达 Unicode 码点
8. **字符串串接**：相邻字符串字面量自动拼接 (`'foo' 'bar'` 等价于 `'foobar'`)，但中间必须有空白和换行

> 真相是：**几乎没有任何主流数据库 100% 遵循这套规则**。PostgreSQL 故意把"折叠为大写"改成"折叠为小写"，MySQL 用反引号取代双引号、用 `\\` 反斜杠转义，SQL Server 用 `[brackets]` 包标识符，Oracle 几乎完全遵循但又加了 PL/SQL 大量私有扩展。下面我们把这些差异系统铺开。

## 支持矩阵 (45+ 数据库)

为方便阅读，下面把 12 个维度拆成 6 张表，每张表覆盖全部 49 个引擎。

### 1. 标识符大小写折叠（未引号）

未引号的 `MyTable` 在不同引擎里实际指向哪个名字？

| 引擎 | 折叠方向 | 引号保留大小写？ | 备注 |
|------|---------|-----------------|------|
| PostgreSQL | lower | 是 | 故意背离标准 |
| MySQL | preserve | 是 | 取决于 `lower_case_table_names` |
| MariaDB | preserve | 是 | 同 MySQL |
| SQLite | preserve | 是 | 比较时不敏感 |
| Oracle | UPPER | 是 | 严格遵循标准 |
| SQL Server | preserve | 是 | 取决于排序规则 (collation) |
| DB2 (LUW) | UPPER | 是 | 严格遵循标准 |
| Snowflake | UPPER | 是 | 同 Oracle |
| BigQuery | preserve | 是 | 区分大小写比较 |
| Redshift | lower | 是 | 继承 PG |
| DuckDB | lower | 是 | 继承 PG，但比较不敏感 |
| ClickHouse | preserve | 是 | 严格区分 |
| Trino | lower | 是 | 继承 PG 行为 |
| Presto | lower | 是 | 同 Trino |
| Spark SQL | preserve | 是 | 默认 caseSensitive=false |
| Hive | lower | 是 | 元数据层强制小写 |
| Flink SQL | preserve | 是 | catalog 决定 |
| Databricks | preserve | 是 | 同 Spark |
| Teradata | UPPER | 是 | 默认 NOT CASESPECIFIC |
| Greenplum | lower | 是 | 继承 PG |
| CockroachDB | lower | 是 | 继承 PG |
| TiDB | preserve | 是 | 兼容 MySQL |
| OceanBase | UPPER/preserve | 是 | 取决于 Oracle/MySQL 模式 |
| YugabyteDB | lower | 是 | 继承 PG |
| SingleStore | preserve | 是 | 兼容 MySQL |
| Vertica | preserve | 是 | 不折叠 |
| Impala | lower | 是 | 元数据小写 |
| StarRocks | preserve | 是 | 同 MySQL |
| Doris | preserve | 是 | 同 MySQL |
| MonetDB | lower | 是 | 类 PG 行为 |
| CrateDB | lower | 是 | 类 PG 行为 |
| TimescaleDB | lower | 是 | 继承 PG |
| QuestDB | preserve | 是 | -- |
| Exasol | UPPER | 是 | 严格遵循标准 |
| SAP HANA | UPPER | 是 | 严格遵循标准 |
| Informix | lower | 是 | 历史原因 |
| Firebird | UPPER | 是 | 严格遵循标准 |
| H2 | UPPER | 是 | 默认遵循标准 |
| HSQLDB | UPPER | 是 | 严格遵循标准 |
| Derby | UPPER | 是 | 严格遵循标准 |
| Amazon Athena | lower | 是 | 继承 Trino/Presto |
| Azure Synapse | preserve | 是 | 同 SQL Server |
| Google Spanner | preserve | 是 | 严格区分 |
| Materialize | lower | 是 | 继承 PG |
| RisingWave | lower | 是 | 继承 PG |
| InfluxDB (SQL) | preserve | 是 | 类 IOx 实现 |
| DatabendDB | preserve | 是 | 默认区分 |
| Yellowbrick | lower | 是 | 继承 PG |
| Firebolt | preserve | 是 | 区分大小写 |

> 统计：约 11 个引擎遵循标准 `UPPER`，约 17 个引擎采用 PG 风格 `lower`，约 21 个引擎选择 `preserve`（保留原样）。

### 2. 关键字大小写敏感性

`SELECT` vs `select` vs `Select`，能否混用？

| 引擎 | 关键字大小写 | 备注 |
|------|-------------|------|
| PostgreSQL | 不敏感 | 习惯用大写 |
| MySQL | 不敏感 | -- |
| MariaDB | 不敏感 | -- |
| SQLite | 不敏感 | 极宽松 |
| Oracle | 不敏感 | -- |
| SQL Server | 不敏感 | -- |
| DB2 | 不敏感 | -- |
| Snowflake | 不敏感 | -- |
| BigQuery | 不敏感 | 但函数名敏感 |
| Redshift | 不敏感 | -- |
| DuckDB | 不敏感 | -- |
| ClickHouse | **大部分敏感** | 函数名/类型名严格大小写 |
| Trino | 不敏感 | -- |
| Presto | 不敏感 | -- |
| Spark SQL | 不敏感 | -- |
| Hive | 不敏感 | -- |
| Flink SQL | 不敏感 | -- |
| Databricks | 不敏感 | -- |
| Teradata | 不敏感 | -- |
| Greenplum | 不敏感 | -- |
| CockroachDB | 不敏感 | -- |
| TiDB | 不敏感 | -- |
| OceanBase | 不敏感 | -- |
| YugabyteDB | 不敏感 | -- |
| SingleStore | 不敏感 | -- |
| Vertica | 不敏感 | -- |
| Impala | 不敏感 | -- |
| StarRocks | 不敏感 | -- |
| Doris | 不敏感 | -- |
| MonetDB | 不敏感 | -- |
| CrateDB | 不敏感 | -- |
| TimescaleDB | 不敏感 | -- |
| QuestDB | 不敏感 | -- |
| Exasol | 不敏感 | -- |
| SAP HANA | 不敏感 | -- |
| Informix | 不敏感 | -- |
| Firebird | 不敏感 | -- |
| H2 | 不敏感 | -- |
| HSQLDB | 不敏感 | -- |
| Derby | 不敏感 | -- |
| Amazon Athena | 不敏感 | -- |
| Azure Synapse | 不敏感 | -- |
| Google Spanner | 不敏感 | -- |
| Materialize | 不敏感 | -- |
| RisingWave | 不敏感 | -- |
| InfluxDB (SQL) | 不敏感 | -- |
| DatabendDB | 不敏感 | -- |
| Yellowbrick | 不敏感 | -- |
| Firebolt | 不敏感 | -- |

> 统计：48/49 引擎对 SQL 关键字本身大小写不敏感；ClickHouse 是唯一在函数名/类型名上严格区分大小写的引擎（`toString()` 不能写成 `ToString()`）。

### 3. 字符串字面量与标识符引号

字符串字面量与标识符的引号字符。`'...'` vs `"..."` vs `` `...` `` vs `[...]`。

| 引擎 | 字符串字面量 | 标识符（标准） | 标识符（扩展） | $$ 美元引号 |
|------|------------|---------------|---------------|-------------|
| PostgreSQL | `'...'` | `"..."` | -- | 是 (8.0+) |
| MySQL | `'...'` 或 `"..."` | `` `...` `` | `"..."` (ANSI_QUOTES) | 否 |
| MariaDB | `'...'` 或 `"..."` | `` `...` `` | `"..."` (ANSI_QUOTES) | 否 |
| SQLite | `'...'` 或 `"..."` | `"..."` | `` `...` ``, `[...]` | 否 |
| Oracle | `'...'` | `"..."` | `q'[...]'` 自定义引号 | 否 |
| SQL Server | `'...'` | `"..."` (QUOTED_IDENT) | `[...]` | 否 |
| DB2 | `'...'` | `"..."` | -- | 否 |
| Snowflake | `'...'` | `"..."` | -- | `$$...$$` (代码块) |
| BigQuery | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Redshift | `'...'` | `"..."` | -- | 否 |
| DuckDB | `'...'` | `"..."` | -- | 是 |
| ClickHouse | `'...'` | `"..."` 或 `` `...` `` | -- | 否 |
| Trino | `'...'` | `"..."` | -- | 否 |
| Presto | `'...'` | `"..."` | -- | 否 |
| Spark SQL | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Hive | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Flink SQL | `'...'` | `` `...` `` | -- | 否 |
| Databricks | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Teradata | `'...'` | `"..."` | -- | 否 |
| Greenplum | `'...'` | `"..."` | -- | 是 (继承 PG) |
| CockroachDB | `'...'` | `"..."` | -- | 是 |
| TiDB | `'...'` 或 `"..."` | `` `...` `` | `"..."` (ANSI_QUOTES) | 否 |
| OceanBase | `'...'` (Oracle 模式)/`'...'` 或 `"..."` (MySQL 模式) | `"..."` 或 `` `...` `` | -- | 否 |
| YugabyteDB | `'...'` | `"..."` | -- | 是 (继承 PG) |
| SingleStore | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Vertica | `'...'` | `"..."` | -- | 否 |
| Impala | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| StarRocks | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Doris | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| MonetDB | `'...'` | `"..."` | -- | 否 |
| CrateDB | `'...'` | `"..."` | -- | 否 |
| TimescaleDB | `'...'` | `"..."` | -- | 是 (继承 PG) |
| QuestDB | `'...'` | `"..."` | -- | 否 |
| Exasol | `'...'` | `"..."` | -- | 否 |
| SAP HANA | `'...'` | `"..."` | -- | 否 |
| Informix | `'...'` 或 `"..."` | `"..."` | -- | 否 |
| Firebird | `'...'` | `"..."` | -- | 否 |
| H2 | `'...'` | `"..."` | -- | 否 |
| HSQLDB | `'...'` | `"..."` | -- | 否 |
| Derby | `'...'` | `"..."` | -- | 否 |
| Amazon Athena | `'...'` | `"..."` | `` `...` `` (Hive 兼容) | 否 |
| Azure Synapse | `'...'` | `"..."` | `[...]` | 否 |
| Google Spanner | `'...'` 或 `"..."` | `` `...` `` | -- | 否 |
| Materialize | `'...'` | `"..."` | -- | 是 |
| RisingWave | `'...'` | `"..."` | -- | 是 |
| InfluxDB (SQL) | `'...'` | `"..."` | -- | 否 |
| DatabendDB | `'...'` 或 `"..."` | `"..."` 或 `` `...` `` | -- | 是 (DECLARE) |
| Yellowbrick | `'...'` | `"..."` | -- | 是 (继承 PG) |
| Firebolt | `'...'` | `"..."` | -- | 否 |

> 三大阵营：(1) 严格遵循标准只用 `"..."` 标识符 (PG/Oracle/DB2/Snowflake/Trino...)；(2) MySQL 系用反引号 `` `...` `` (MySQL/MariaDB/TiDB/BigQuery/Spark/Hive/StarRocks/Doris...)；(3) SQL Server 系用方括号 `[...]`。Snowflake 用 `$$` 但其语义是"过程体定义"而不是 PG 那种通用字符串字面量。

### 4. 注释风格

| 引擎 | `-- 行` | `# 行` | `/* 块 */` | `/*! 条件 */` | 嵌套块注释 |
|------|---------|--------|-----------|---------------|------------|
| PostgreSQL | 是 | 否 | 是 | 否 | 是 |
| MySQL | 是 (后需空格) | 是 | 是 | 是 (版本门控) | 否 |
| MariaDB | 是 (后需空格) | 是 | 是 | 是 | 否 |
| SQLite | 是 | 否 | 是 | 否 | 否 |
| Oracle | 是 | 否 | 是 | 否 | 否 |
| SQL Server | 是 | 否 | 是 | 否 | 是 |
| DB2 | 是 | 否 | 是 | 否 | 否 |
| Snowflake | 是 | 否 | 是 | 否 | 否 |
| BigQuery | 是 | 是 | 是 | 否 | 否 |
| Redshift | 是 | 否 | 是 | 否 | 否 |
| DuckDB | 是 | 否 | 是 | 否 | 是 |
| ClickHouse | 是 | 是 | 是 | 否 | 否 |
| Trino | 是 | 否 | 是 | 否 | 否 |
| Presto | 是 | 否 | 是 | 否 | 否 |
| Spark SQL | 是 | 否 | 是 | 否 | 否 |
| Hive | 是 | 否 | 是 | 否 | 否 |
| Flink SQL | 是 | 否 | 是 | 否 | 否 |
| Databricks | 是 | 否 | 是 | 否 | 否 |
| Teradata | 是 | 否 | 是 | 否 | 否 |
| Greenplum | 是 | 否 | 是 | 否 | 是 |
| CockroachDB | 是 | 否 | 是 | 否 | 是 |
| TiDB | 是 | 是 | 是 | 是 | 否 |
| OceanBase | 是 | 是 | 是 | 是 (MySQL 模式) | 否 |
| YugabyteDB | 是 | 否 | 是 | 否 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 否 |
| Vertica | 是 | 否 | 是 | 否 | 否 |
| Impala | 是 | 否 | 是 | 否 | 否 |
| StarRocks | 是 | 是 | 是 | 是 | 否 |
| Doris | 是 | 是 | 是 | 是 | 否 |
| MonetDB | 是 | 否 | 是 | 否 | 是 |
| CrateDB | 是 | 否 | 是 | 否 | 否 |
| TimescaleDB | 是 | 否 | 是 | 否 | 是 |
| QuestDB | 是 | 否 | 是 | 否 | 否 |
| Exasol | 是 | 否 | 是 | 否 | 否 |
| SAP HANA | 是 | 否 | 是 | 否 | 否 |
| Informix | 是 | 否 | 是 | 否 | 否 |
| Firebird | 是 | 否 | 是 | 否 | 否 |
| H2 | 是 | 否 | 是 | 否 | 否 |
| HSQLDB | 是 | 否 | 是 | 否 | 否 |
| Derby | 是 | 否 | 是 | 否 | 否 |
| Amazon Athena | 是 | 否 | 是 | 否 | 否 |
| Azure Synapse | 是 | 否 | 是 | 否 | 是 |
| Google Spanner | 是 | 是 | 是 | 否 | 否 |
| Materialize | 是 | 否 | 是 | 否 | 是 |
| RisingWave | 是 | 否 | 是 | 否 | 是 |
| InfluxDB (SQL) | 是 | 否 | 是 | 否 | 否 |
| DatabendDB | 是 | 是 | 是 | 否 | 否 |
| Yellowbrick | 是 | 否 | 是 | 否 | 是 |
| Firebolt | 是 | 否 | 是 | 否 | 否 |

> `#` 行注释最常出现在 MySQL 系（含 TiDB / OceanBase MySQL 模式 / SingleStore / StarRocks / Doris / OceanBase / BigQuery / ClickHouse / Spanner）。注意：MySQL 的 `--` 后必须跟一个空白字符才能被识别为注释，否则会被解析为减号——这是与 PG 兼容性的常见陷阱。

### 5. 字符串转义、Unicode 与多行

| 引擎 | C 风格 `\n` `\t` | 双单引号 `''` | Unicode 前缀 | 多行字符串 |
|------|------------------|---------------|--------------|------------|
| PostgreSQL | 仅 `E'...'` 中 | 是 | `U&'...'` | `'..\n..'` 不行；`E'...'` 可，或 `$$...$$` |
| MySQL | 默认是 (`\n`,`\t`,`\\`) | 是 | `_utf8'...'` | 隐式串接 |
| MariaDB | 默认是 | 是 | `_utf8'...'` | 隐式串接 |
| SQLite | 否 | 是 | -- | 隐式串接 |
| Oracle | 否 | 是 | `N'...'`, `nq'[...]'` | `q'[...]'` |
| SQL Server | 否 | 是 | `N'...'` | 隐式串接 |
| DB2 | 否 | 是 | `UX'...'` | 隐式串接 |
| Snowflake | 是 (默认) | 是 | -- | `$$...$$`、隐式串接 |
| BigQuery | 是 | 是 | -- | `'''...'''`, `"""..."""` 三引号 |
| Redshift | 默认否 (可启用) | 是 | -- | -- |
| DuckDB | 是 (默认) | 是 | -- | 是 |
| ClickHouse | 是 | 是 | -- | -- |
| Trino | 否 | 是 | `U&'...'` | -- |
| Presto | 否 | 是 | -- | -- |
| Spark SQL | 是 | 是 | -- | `'''...'''` 三引号 |
| Hive | 是 | 是 | -- | -- |
| Flink SQL | 是 | 是 | -- | -- |
| Databricks | 是 | 是 | -- | `'''...'''`, `"""..."""` |
| Teradata | 否 | 是 | -- | -- |
| Greenplum | 仅 `E'...'` | 是 | -- | `$$...$$` |
| CockroachDB | 仅 `E'...'` | 是 | `U&'...'` | `$$...$$` |
| TiDB | 是 (默认 MySQL 行为) | 是 | -- | 隐式串接 |
| OceanBase | 取决于模式 | 是 | `N'...'` (Oracle) | -- |
| YugabyteDB | 仅 `E'...'` | 是 | `U&'...'` | `$$...$$` |
| SingleStore | 是 | 是 | -- | -- |
| Vertica | 是 | 是 | -- | -- |
| Impala | 是 | 是 | -- | -- |
| StarRocks | 是 | 是 | -- | -- |
| Doris | 是 | 是 | -- | -- |
| MonetDB | 否 | 是 | -- | -- |
| CrateDB | 否 | 是 | -- | -- |
| TimescaleDB | 仅 `E'...'` | 是 | `U&'...'` | `$$...$$` |
| QuestDB | 否 | 是 | -- | -- |
| Exasol | 否 | 是 | -- | -- |
| SAP HANA | 否 | 是 | -- | -- |
| Informix | 取决于配置 | 是 | -- | -- |
| Firebird | 否 | 是 | `_UTF8'...'` | -- |
| H2 | 否 | 是 | -- | -- |
| HSQLDB | 否 | 是 | -- | -- |
| Derby | 否 | 是 | -- | -- |
| Amazon Athena | 否 | 是 | -- | -- |
| Azure Synapse | 否 | 是 | `N'...'` | -- |
| Google Spanner | 是 | 是 | -- | `'''...'''`, `"""..."""` |
| Materialize | 仅 `E'...'` | 是 | `U&'...'` | `$$...$$` |
| RisingWave | 仅 `E'...'` | 是 | `U&'...'` | `$$...$$` |
| InfluxDB (SQL) | 是 | 是 | -- | -- |
| DatabendDB | 是 | 是 | -- | -- |
| Yellowbrick | 仅 `E'...'` | 是 | -- | `$$...$$` |
| Firebolt | 是 | 是 | -- | -- |

> 关键观察：(1) 标准的 `''` 双单引号转义所有引擎都支持。(2) C 风格反斜杠转义大致分两派：MySQL 系默认开启，PG 系必须显式 `E'...'`。(3) 多行字符串：PG 系靠 `$$...$$`，BigQuery/Spark/Spanner 靠三引号 `'''...'''`，Oracle 靠 `q'[...]'`。

### 6. 终止符、分隔符与脚本特性

| 引擎 | 单语句必需 `;` | `DELIMITER` 命令 | Unicode 标识符 | 反斜杠续行 |
|------|---------------|-----------------|---------------|------------|
| PostgreSQL | 多语句必需 | 否 | 是 | 否 |
| MySQL | 通常必需 | 是 (`DELIMITER //`) | 是 | 否 |
| MariaDB | 通常必需 | 是 | 是 | 否 |
| SQLite | 多语句必需 | 否 | 是 | 否 |
| Oracle | 取决于客户端 | 是 (SQL*Plus `/`) | 是 | 否 |
| SQL Server | 不强制 | 是 (`GO` 批分隔) | 是 | 否 |
| DB2 | 取决于客户端 | 是 (`@` 等) | 是 | 否 |
| Snowflake | 多语句必需 | 否 | 是 | 否 |
| BigQuery | 多语句必需 | 否 | 是 | 否 |
| Redshift | 多语句必需 | 否 | 是 | 否 |
| DuckDB | 多语句必需 | 否 | 是 | 否 |
| ClickHouse | 多语句必需 | 否 | 是 | 否 |
| Trino | 多语句必需 | 否 | 是 | 否 |
| Presto | 多语句必需 | 否 | 是 | 否 |
| Spark SQL | 多语句必需 | 否 | 是 | 否 |
| Hive | 多语句必需 | 否 | 是 | 否 |
| Flink SQL | 多语句必需 | 否 | 是 | 否 |
| Databricks | 多语句必需 | 否 | 是 | 否 |
| Teradata | 多语句必需 | 是 (BTEQ `.` 命令) | 是 | 否 |
| Greenplum | 多语句必需 | 否 | 是 | 否 |
| CockroachDB | 多语句必需 | 否 | 是 | 否 |
| TiDB | 通常必需 | 是 | 是 | 否 |
| OceanBase | 通常必需 | 是 | 是 | 否 |
| YugabyteDB | 多语句必需 | 否 | 是 | 否 |
| SingleStore | 通常必需 | 是 | 是 | 否 |
| Vertica | 多语句必需 | 否 | 是 | 否 |
| Impala | 多语句必需 | 否 | 是 | 否 |
| StarRocks | 通常必需 | 是 | 是 | 否 |
| Doris | 通常必需 | 是 | 是 | 否 |
| MonetDB | 多语句必需 | 否 | 是 | 否 |
| CrateDB | 多语句必需 | 否 | 是 | 否 |
| TimescaleDB | 多语句必需 | 否 | 是 | 否 |
| QuestDB | 多语句必需 | 否 | 是 | 否 |
| Exasol | 多语句必需 | 否 | 是 | 否 |
| SAP HANA | 多语句必需 | 否 | 是 | 否 |
| Informix | 多语句必需 | 否 | 是 | 否 |
| Firebird | 多语句必需 | 是 (`SET TERM`) | 是 | 否 |
| H2 | 多语句必需 | 否 | 是 | 否 |
| HSQLDB | 多语句必需 | 否 | 是 | 否 |
| Derby | 多语句必需 | 否 | 是 | 否 |
| Amazon Athena | 单语句不需 | 否 | 是 | 否 |
| Azure Synapse | 不强制 | 是 (`GO`) | 是 | 否 |
| Google Spanner | 多语句必需 | 否 | 是 | 否 |
| Materialize | 多语句必需 | 否 | 是 | 否 |
| RisingWave | 多语句必需 | 否 | 是 | 否 |
| InfluxDB (SQL) | 多语句必需 | 否 | 是 | 否 |
| DatabendDB | 多语句必需 | 否 | 是 | 否 |
| Yellowbrick | 多语句必需 | 否 | 是 | 否 |
| Firebolt | 多语句必需 | 否 | 是 | 否 |

> `DELIMITER` 是一个**客户端命令**而非 SQL 语句本身。它存在的根本原因是：MySQL 风格的存储过程体内部含有 `;`，需要临时把语句结束符换成 `//` 以避免被客户端切碎。SQL Server 用 `GO` 实现类似功能但语义不同 (`GO` 是批分隔，不是终止符)。Oracle SQL*Plus 用单独一行 `/` 提交 PL/SQL 块。

## 各引擎详解

下面按"行为代表性"挑出 10 个引擎做更深入的解析器风格对比。

### PostgreSQL：把"折叠为大写"改成"折叠为小写"

PostgreSQL 是少数明确背离 SQL 标准的引擎。标准说未引号标识符应该折叠为大写，但 PostgreSQL 折叠为**小写**：

```sql
-- PostgreSQL
CREATE TABLE MyUsers (Id INT, UserName TEXT);
-- 实际创建的是 "myusers" 表，列 "id"、"username"

SELECT * FROM MyUsers;     -- OK: 折叠为 myusers
SELECT * FROM "MyUsers";   -- 报错: relation "MyUsers" does not exist
SELECT * FROM "myusers";   -- OK
```

PostgreSQL 8.0 (2005) 引入的**美元引号字符串** `$$...$$` 是它最有辨识度的扩展之一，专门为函数体中嵌入复杂字符串而设计：

```sql
CREATE FUNCTION add_one(int) RETURNS int AS $$
    SELECT $1 + 1;
$$ LANGUAGE SQL;

-- 也支持带标签，避免内嵌冲突
CREATE FUNCTION foo() RETURNS text AS $body$
    SELECT $marker$ contains "single" and 'double' quotes $marker$;
$body$ LANGUAGE SQL;
```

字符串字面量的反斜杠转义需要显式 `E` 前缀：

```sql
SELECT 'a\nb';        -- 'a\nb' (字面量的 4 字符串，参数 standard_conforming_strings=on)
SELECT E'a\nb';       -- 包含真正的换行符（C 风格转义）
SELECT U&'\0041';     -- Unicode 转义，得到 'A'
```

PostgreSQL 还有几个少为人知的解析器特色：

1. **运算符可由用户自定义**：`CREATE OPERATOR === (...)` 后 `===` 在词法层就被识别为操作符，词法器是动态扩展的
2. **类型转换语法多种** (`CAST(x AS int)`, `int(x)`, `x::int`)，最后一种 `::` 是 PG 特色
3. **隐式数组类型**：`int[]` 在标识符上下文中也合法，与列名 `int` 不冲突
4. **`PG_CATALOG.` schema 隐式可见**：所有内置对象都在该 schema 下，但解析器隐式注入到 search_path

### MySQL：反引号、`#` 注释与文件系统大小写陷阱

MySQL 用反引号包围标识符，这是它最显眼的非标准扩展：

```sql
CREATE TABLE `Order` (`id` INT, `select` VARCHAR(10));
-- 反引号让 `Order`、`select` 这种保留字也能当列名
```

MySQL 表名的大小写敏感性由系统变量 `lower_case_table_names` 控制，且**默认值取决于操作系统**：

| `lower_case_table_names` | 存储 | 比较 | 默认操作系统 |
|--------------------------|------|------|--------------|
| 0 | 原样 | 区分 | Linux |
| 1 | 全小写 | 不区分 | Windows |
| 2 | 原样 | 不区分 | macOS |

这是**最经典的"在 macOS 上跑得好好的，部署到 Linux 就崩了"故障源**：开发者在本地 macOS 写 `SELECT * FROM Users`，本地 `lower_case_table_names=2` 不区分大小写，跑得通；一上 Linux 服务器 `=0`，区分大小写就找不到表。

MySQL 还支持 `#` 行注释和**条件版本注释** `/*! ... */`，后者在指定 MySQL 版本以上才执行：

```sql
SELECT * FROM users; # 这是行注释
SELECT /*!50710 SQL_NO_CACHE */ * FROM big_table;  -- 仅 5.7.10+ 执行
```

`/*!50710 ... */` 这种"对 MySQL 是 SQL，对其他数据库是注释"的设计，被 mysqldump 等工具用来生成"伪兼容"的迁移脚本。但同时它也是 SQL 注入 WAF 绕过的常见武器。

最后注意 MySQL `--` 后必须跟空白字符才被识别为注释：`SELECT 1--2` 会得到 `3`，而 `SELECT 1-- 2` 才是 `1`。这与标准 SQL 不同。

MySQL 还内置了 **SQL Mode** 来动态调整解析器行为，常见的几个：

```sql
SET sql_mode = 'ANSI_QUOTES';  -- 把 " 当成标识符引号而不是字符串
SET sql_mode = 'NO_BACKSLASH_ESCAPES';  -- 关闭 \n \t 反斜杠转义
SET sql_mode = 'PIPES_AS_CONCAT';  -- || 当字符串拼接而不是 OR
SET sql_mode = 'IGNORE_SPACE';     -- 函数名后允许空格
```

`IGNORE_SPACE` 这个开关特别有趣：默认情况下 `count (*)` (注意 count 后有空格) 在 MySQL 中不合法，因为词法器会把 `count` 识别为标识符；开启 `IGNORE_SPACE` 后才允许函数名与括号之间有空格。

### Oracle：永远折叠为大写，PL/SQL 完全独立的解析器

Oracle 是 SQL 标准的"模范生"：未引号标识符**总是**折叠为大写，无例外：

```sql
CREATE TABLE MyUsers (Id NUMBER);
SELECT * FROM MYUSERS;     -- OK
SELECT * FROM myusers;     -- OK (折叠后等价)
SELECT * FROM "MyUsers";   -- 报错: 表不存在
SELECT * FROM "MYUSERS";   -- OK
```

Oracle 独有的**自定义引号字符串** `q'[...]'` 让字符串中嵌入引号变得简单，左右分隔符可以是 `[]`、`{}`、`()`、`<>` 或任意非空白字符：

```sql
SELECT q'[It's a "test"]' FROM dual;  -- 包含单双引号
SELECT q'!That's it!' FROM dual;       -- 用 ! 做定界符
SELECT N'中文'         FROM dual;       -- N 前缀走 NCHAR 字符集
SELECT nq'[中文]'      FROM dual;       -- 两者结合
```

更深的差异是 Oracle 有两个解析器：**SQL 解析器**（处理 `SELECT`/`DML`/`DDL`）和 **PL/SQL 解析器**（处理 `BEGIN ... END;` 程序块）。同一段代码在两个解析器里行为不同（如 `:=` 仅在 PL/SQL 中是赋值），SQL*Plus 客户端要靠空行或单独的 `/` 行来切换上下文：

```sql
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM dual;
    DBMS_OUTPUT.PUT_LINE('count=' || v_count);
END;
/   -- 这一行是 SQL*Plus 的提交命令，不是 SQL
```

PL/SQL 还引入了 SQL 解析器没有的语法元素：

- `:=` 赋值
- `LOOP ... END LOOP`、`FOR i IN 1..10 LOOP`
- `EXCEPTION WHEN ... THEN`
- `%TYPE`、`%ROWTYPE` 类型引用
- `&substitution_var` 在 SQL*Plus 的替换变量
- `:bind_var` 主机变量

这些只在 PL/SQL 块上下文中合法，纯 SQL 解析器会报错。Oracle 的 OCI 驱动程序据语句首字符判断是 SQL 还是 PL/SQL（`BEGIN`/`DECLARE` 开头送 PL/SQL 解析器）。

### Microsoft SQL Server：方括号标识符与 Unicode 字面量

SQL Server 默认行为更接近 Sybase，标识符引号是方括号 `[...]`，但开启 `SET QUOTED_IDENTIFIER ON` 后也支持双引号：

```sql
SELECT [Order Date], [Customer ID] FROM [Sales Orders];
SELECT "Order Date" FROM "Sales Orders";  -- 需 QUOTED_IDENTIFIER ON
```

Unicode 字符串字面量必须加 `N` 前缀，否则会被当作 `varchar` 走代码页转换、丢失非 ASCII 字符：

```sql
INSERT INTO t VALUES ('中文');   -- 可能丢字符（取决于排序规则）
INSERT INTO t VALUES (N'中文');  -- 走 nvarchar，安全
```

SQL Server 用 `GO` 作为**批分隔符**（不是 SQL 终止符），sqlcmd 客户端识别后把代码切成多个 batch 提交。同样的代码贴到 SSMS 直接执行就会因为 `GO` 不是 T-SQL 关键字而报错——除非 SSMS 也认识它。

```sql
USE master;
GO
CREATE DATABASE foo;
GO
USE foo;
GO
```

T-SQL 的解析器还有几个独有特性：

- `@variable` 是局部变量（PL/SQL 中没有 `@` 前缀）
- `@@variable` 是系统变量（如 `@@VERSION`）
- `#tempTable` / `##globalTempTable` 通过命名前缀区分作用域
- `[bracket]` 内部可以嵌入 `]`，必须用 `]]` 转义（与字符串的 `''` 类似）

### DB2：严格遵循标准

DB2 (LUW) 是除 Oracle 外最严格遵循 SQL 标准的引擎之一。未引号标识符折叠为大写，标识符引号为双引号，字符串字面量双单引号转义，没有 C 风格反斜杠转义。它有少数扩展（如 `UX'...'` Unicode 十六进制字面量），但整体上与标准接近。

```sql
CREATE TABLE MYTAB (ID INT);
SELECT * FROM mytab;        -- OK 折叠为 MYTAB
SELECT * FROM "MYTAB";      -- OK
SELECT * FROM "mytab";      -- 报错: SQLCODE -204
```

DB2 z/OS 与 DB2 LUW 在解析器行为上有细微差异；前者为追求向后兼容大型主机程序，对某些过时语法更宽容，例如允许 `FOR FETCH ONLY` 这种历史写法。

### SQLite：极宽松、几乎接受一切

SQLite 是宽松型解析器的极致：未引号标识符**保留**大小写但比较时不敏感；字符串字面量同时接受 `'...'` 和 `"..."`（如果 `"..."` 不能解析为已知列名，会被当作字符串）；标识符同时接受 `"..."`、`` `...` ``、`[...]`——以最大化与其他数据库的复制兼容性。

```sql
-- 这些在 SQLite 里全部合法
SELECT "Hello", `world`, [foo] FROM mytable;
SELECT * FROM MyTable WHERE name = "Alice";
-- 注意：因为 "Alice" 不是已知列名，被当作字符串字面量；这是个**陷阱**
```

这种宽松带来一个微妙的危险：在 PG 中 `WHERE name = "Alice"` 会被解释为列名比较并报错，发现 bug；在 SQLite 中却被默默接受为字符串字面量，逻辑悄悄变了。

SQLite 还有个独有的特性：**任意类型可以存任意值**（声明类型是"亲和性"而非约束），这与解析器关系不大但与"宽松哲学"一脉相承。

### ClickHouse：唯一在函数名上严格大小写敏感的主流引擎

ClickHouse 的标识符默认区分大小写，关键字本身不敏感，但**内置函数名严格大小写敏感**：

```sql
SELECT toString(123);   -- OK
SELECT ToString(123);   -- 报错: function ToString not found
SELECT TOSTRING(123);   -- 报错
SELECT length('abc');   -- OK
SELECT LENGTH('abc');   -- 报错
```

少数函数有大小写不敏感的别名（如 `count` / `COUNT`），但绝大多数函数必须按 camelCase 精确写。这是 ClickHouse 与几乎所有其他 SQL 引擎最显著的区别。

ClickHouse 解析器还有些俄式特色：

- `FROM ... ARRAY JOIN`、`FROM ... ASOF JOIN` 这种自定义 JOIN 修饰
- `SAMPLE 0.1` 跟在 `FROM` 后而不是 `TABLESAMPLE`
- `PREWHERE` 在 `WHERE` 之前的早期过滤
- `SETTINGS ...` 可以追加在任何 `SELECT` 末尾
- 函数式调用 `arrayMap(x -> x*2, my_array)` 用 lambda 语法

### BigQuery：反引号 + 三引号字符串 + 区分大小写列

BigQuery 借鉴 GoogleSQL/ZetaSQL，用反引号包围"项目.数据集.表"这种长名字：

```sql
SELECT user_id FROM `my-project.analytics.events`;
```

字符串字面量同时接受 `'...'` 和 `"..."`，并支持**三引号多行字符串**：

```sql
SELECT '''
Multi
Line
''';
SELECT """Also multi-line""";
SELECT R'\n';   -- 原始字符串，不解释转义
SELECT B'abc';  -- BYTES 字面量
```

BigQuery 的**列名比较是区分大小写的**（`SELECT UserID` 与 `SELECT userid` 引用不同的列），但表名在数据集层面通常被规范化。ZetaSQL 解析器（开源在 google/zetasql）是 BigQuery / Spanner / Cloud SQL for PostgreSQL 等多个 Google 产品共用的语法前端。

### Snowflake：默认折叠为大写，但内部更严格

Snowflake 与 Oracle 一样，未引号标识符折叠为**大写**：

```sql
CREATE TABLE MyTab (Id INT);
SELECT * FROM mytab;       -- OK 折叠为 MYTAB
SELECT * FROM "MYTAB";     -- OK
SELECT * FROM "mytab";     -- 报错
```

Snowflake 的 `$$...$$` 不是 PG 那种通用字符串字面量，而是**过程体定义专用**：

```sql
CREATE PROCEDURE foo() RETURNS STRING LANGUAGE JAVASCRIPT AS $$
    return 'hello';
$$;
```

Snowflake 还独有 `IDENTIFIER('table_name')` 内置函数把字符串"提升"为标识符，常用于动态 SQL：

```sql
SELECT * FROM IDENTIFIER('MY_DB.PUBLIC.MY_TABLE');
SELECT * FROM IDENTIFIER($table_var);  -- 用变量
```

### Trino / Presto：双引号标识符 + 严格大小写比较

Trino 用标准的双引号标识符，未引号标识符折叠为小写 (PG 风格)，字符串列名比较**严格区分大小写**：

```sql
SELECT user_id FROM "Orders" WHERE "User Id" = 1;
-- 列 "User Id" 必须精确匹配大小写
```

Trino 的另一个特色是**绝不接受单引号包围标识符、绝不接受双引号包围字符串字面量**——这是它对 SQL 标准的"严格守护"。把 MySQL 的 `WHERE name = "Alice"` 直接搬到 Trino 立刻报错。

Trino 还有几个值得注意的解析器特性：

- 完全支持 `WITH RECURSIVE`、`UNION` 默认是 `UNION DISTINCT`
- `LAMBDA` 函数语法 `x -> x*2`
- 行字面量 `ROW(1, 'a', true)` 与字段访问 `r.field`
- `INTERVAL '1' DAY` 标准语法

## 大小写折叠约定深入

我们把 49 个引擎按"未引号标识符如何折叠"分成三大流派：

| 流派 | 代表 | 数量 | 优点 | 缺点 |
|------|------|------|------|------|
| **UPPER (标准派)** | Oracle, DB2, Snowflake, Teradata, Exasol, SAP HANA, Firebird, H2, HSQLDB, Derby | ~11 | 严格遵循 ISO 9075 | 引号后大小写陷阱多 |
| **lower (PG 派)** | PostgreSQL, Redshift, DuckDB, Trino/Presto, Hive, Impala, CockroachDB, Greenplum, YugabyteDB, Materialize, RisingWave, TimescaleDB, Yellowbrick, Athena | ~17 | 与编程语言习惯一致 | 与标准不一致 |
| **preserve (MySQL 派)** | MySQL, MariaDB, SQLite, SQL Server, BigQuery, ClickHouse, Spark, TiDB, SingleStore, Vertica, StarRocks, Doris, Spanner, Synapse, Firebolt | ~21 | 直观 | 受 OS/排序规则影响 |

**陷阱矩阵**（同一段 SQL 在不同引擎中实际访问的对象）：

```sql
CREATE TABLE MyTab (Id INT, MyCol INT);
SELECT MyCol FROM MyTab;
```

| 引擎 | 实际表名 | 实际列名 |
|------|---------|---------|
| Oracle | `MYTAB` | `MYCOL` |
| PostgreSQL | `mytab` | `mycol` |
| SQL Server | `MyTab` | `MyCol` (区分性取决于排序规则) |
| MySQL/Linux | `MyTab` | `MyCol` |
| MySQL/macOS | `mytab` | `MyCol` |

跨数据库迁移时，`SELECT * FROM information_schema.tables` 拿到的表名拼写在不同引擎下不一致，这就是 ORM 元数据反射出来的字段大小写经常"不对"的根因。

### 从历史看为什么会有 lower vs UPPER 分歧

SQL 标准选 `UPPER` 是因为最早的大型机数据库（System R, DB2）只有大写字母。1986 年 SQL-86 标准化时全部用大写关键字和大写标识符是历史惯例。

PostgreSQL 1996 年从 Postgres 项目转向 SQL 时，**作者认为大写折叠很丑陋**（与 Unix/C 习惯不一致），主动选择了小写折叠。这成为 PG 整个社区的标志，后续所有 PG fork（Greenplum, Redshift, CockroachDB, YugabyteDB, Materialize, RisingWave, TimescaleDB...）都继承下来。

MySQL 的 `preserve` 选择源于 MyISAM 表名直接对应文件系统文件名——文件系统区分大小写则表名区分，反之则不区分。这种"实现决定语义"的设计是 MySQL 兼容性问题的根源。

SQL Server 的 `preserve` 来自 Sybase，Sybase 自身延续到 Microsoft 后被命名为 SQL Server。

## 保留字之坑

每个引擎都有自己的保留字列表，且差异很大。以下是几个常见单词在主流引擎里的"是否保留"对比：

| 单词 | SQL:2016 | PostgreSQL | MySQL | Oracle | SQL Server | Snowflake | BigQuery | Trino |
|------|----------|------------|-------|--------|------------|-----------|----------|-------|
| `USER` | 保留 | 保留 (函数) | 非保留 | 保留 (伪列) | 保留 | 保留 | 保留 | 保留 |
| `DATE` | 保留 | 非保留 | 非保留 | 保留 | 非保留 | 保留 | 保留 | 保留 |
| `LEVEL` | 非保留 | 非保留 | 非保留 | **保留** (CONNECT BY) | 非保留 | 保留 | 非保留 | 非保留 |
| `RANK` | 保留 | 非保留 | 非保留 | 非保留 | 保留 | 保留 | 保留 | 保留 |
| `WINDOW` | 保留 | 保留 | 保留 | 非保留 | 非保留 | 保留 | 保留 | 保留 |
| `INTERVAL` | 保留 | 保留 | 保留 | 保留 | 非保留 | 保留 | 保留 | 保留 |
| `SCHEMA` | 保留 | 非保留 | 保留 | 非保留 | 非保留 | 保留 | 保留 | 非保留 |
| `LIMIT` | 非保留 | 保留 | 保留 | 非保留 | 非保留 | 保留 | 保留 | 保留 |
| `TOP` | 非保留 | 非保留 | 非保留 | 非保留 | 保留 | 非保留 | 非保留 | 非保留 |
| `ROWNUM` | 非保留 | 非保留 | 非保留 | **保留** | 非保留 | 非保留 | 非保留 | 非保留 |
| `MERGE` | 保留 | 非保留 | 非保留 | 保留 | 保留 | 保留 | 保留 | 非保留 |
| `QUALIFY` | 非保留 | 非保留 | 非保留 | 非保留 | 非保留 | 保留 | 保留 | 非保留 |
| `MATCH_RECOGNIZE` | 保留 | 非保留 | 非保留 | 保留 | 非保留 | 非保留 | 非保留 | 保留 |

> 总数对比：PostgreSQL 约 460 个关键字（其中 ~110 是完全保留）；MySQL 约 800 个关键字（其中 ~260 完全保留）；Oracle 约 270 个保留字；SQL Server 约 220 个保留字 + ODBC 保留字；Snowflake 约 50 个完全保留；BigQuery 约 100 个保留字；Trino 约 150 个保留字。

**实战建议**：

1. 永远不要把 `user`、`order`、`date`、`level`、`schema`、`group`、`role` 用作表名/列名
2. 如果迁移源数据有这种字段，要用引号包起来，并切换到目标方言的引号
3. 自动化工具（dbt、sqlglot）通常会维护 per-dialect 保留字表来自动加引号
4. 升级数据库版本时检查"新增保留字"——例如 PG 添加 `MERGE` (15+) 后，原来作列名的 `merge` 全部失效

### 完全保留 vs 非保留：PostgreSQL 的四级分类

PG 文档把每个关键字分为四级，是研究保留字最细的引擎：

| 类别 | 含义 | 能否做表名 | 能否做列名 |
|------|------|-----------|-----------|
| reserved | 完全保留 | 否 | 否 |
| reserved (can be function or type) | 保留但允许函数/类型用 | 否 | 否 |
| non-reserved (cannot be function or type) | 非保留但有限制 | 是 | 是 |
| non-reserved | 完全非保留 | 是 | 是 |

例如 `DATE` 在 PG 是 "non-reserved (cannot be function or type)"，所以 `CREATE TABLE date(id INT)` 合法，但 `SELECT date(now())` 必须 `SELECT pg_catalog.date(now())`。

## C 风格转义与字符串安全

PostgreSQL 和 MySQL 在反斜杠转义上的差异是 SQL 注入的常见根源。

```sql
-- PostgreSQL (standard_conforming_strings=on，自 9.1 起默认)
SELECT 'O\'Brien';   -- 报错：单引号未闭合
SELECT 'O''Brien';   -- OK: O'Brien
SELECT E'O\'Brien';  -- OK: O'Brien (C 风格转义)

-- MySQL 默认
SELECT 'O\'Brien';   -- OK: O'Brien
SELECT 'O''Brien';   -- OK: O'Brien
```

历史上 PG 8.x 之前 `'\'` 也被解释为转义，导致 SQL 注入工具假定 `'\''` 能闭合所有数据库。9.1 起 PG 默认关闭这个行为，老代码迁移时会遇到"客户端拼接的字符串突然报错"的问题。

不同引擎的 SQL 注入"拐点"也不同：

```sql
-- 攻击向量：包含字符串 admin' --
SELECT * FROM users WHERE name = 'admin' --';

-- MySQL: 因为 -- 后必须跟空格，这种在 MySQL 上不会作为注释，但 admin' ; DROP TABLE 仍可
-- PostgreSQL: -- 后空格不强制要求，注释直到行尾
-- SQL Server: 同 PG
-- 防御：始终使用参数化查询，不要手工拼接
```

## Unicode 标识符与字符集

ISO/IEC 9075 自 SQL:2003 起允许 `<identifier start>` 包含 Unicode 类别 `Lu, Ll, Lt, Lm, Lo, Nl`（即所有字母与字母数字）。所有 49 个引擎都至少在引号内允许 Unicode 标识符：

```sql
-- 这些都合法
CREATE TABLE "用户" ("姓名" TEXT, "年龄" INT);
SELECT "姓名" FROM "用户";
```

但**未引号 Unicode 标识符**支持度参差：

- PostgreSQL: 默认允许（locale 决定字符集），需要 server_encoding=UTF8
- MySQL: 默认允许
- Oracle: 允许
- SQL Server: 取决于排序规则
- DB2: 允许但需要 UNICODE 数据库
- ClickHouse: 严格区分

`U&'\0041'` Unicode 字符串字面量是 SQL:2003 引入的标准特性，但只有 PostgreSQL、Trino、CockroachDB、Materialize、RisingWave、YugabyteDB、TimescaleDB 等 PG 系完全支持。其他引擎要么不支持，要么用自己的语法（如 SQL Server 的 `NCHAR(0x4E2D)`、Oracle 的 `UNISTR('\4E2D')`）。

## 关键发现 / 关键发现

1. **没有任何主流数据库 100% 遵循 SQL:2016 词法标准**。哪怕最严格的 Oracle/DB2 也有大量私有扩展。
2. **大小写折叠分三派**：Oracle/标准派 `UPPER`、PostgreSQL 派 `lower`、MySQL/SQL Server 派 `preserve`。"我创建了 `MyTab` 为什么找不到"是迁移最常见错误。
3. **MySQL `lower_case_table_names`** 默认值取决于操作系统（Windows/macOS 默认 1 或 2，Linux 默认 0），是"在我电脑上能跑"故障的头号根源。
4. **PostgreSQL 美元引号** `$$...$$` 是 8.0 (2005) 引入的独有特性，迁移时需要全部展开为 `'...'` + 双单引号转义。
5. **SQL Server `N'...'` Unicode 前缀** 不加会丢非 ASCII 字符。从 MySQL/PG 迁到 SQL Server 是"编码丢失"的高频场景。
6. **MySQL `--` 后必须跟空格** 才被识别为注释，与标准 SQL 兼容性不完全。
7. **MySQL 条件注释 `/*!50710 ... */`** 是 mysqldump 生成"伪兼容"脚本的核心机制，但同时是 WAF 绕过的常见武器。
8. **ClickHouse 是唯一对函数名严格大小写敏感** 的主流引擎：`toString` 不能写成 `tostring`。
9. **BigQuery / Spark / Spanner / Databricks 支持三引号字符串** `'''...'''`、`"""..."""`，这是 PG/Oracle/SQL Server 都没有的特性。
10. **保留字差异巨大**：MySQL ~260 个完全保留，Snowflake ~50 个，差异 5 倍。`USER`、`DATE`、`MERGE`、`QUALIFY`、`LEVEL` 是迁移高发雷点。
11. **SQLite 极端宽松**：同时接受 `"..."`、`` `...` ``、`[...]` 三种标识符引号，且当 `"Alice"` 不是列名时会被静默当作字符串——这是隐蔽的逻辑错误源。
12. **`DELIMITER` 是客户端命令而非 SQL**。MySQL `DELIMITER //`、SQL Server `GO`、Oracle SQL*Plus `/`、Firebird `SET TERM`、Teradata BTEQ `.` 都是为了"在脚本中嵌入含有分号的存储过程体"而设计的客户端协议。
13. **PostgreSQL `standard_conforming_strings`** 自 9.1 起默认开启，老代码 `'\''` 闭合方式会失效，迁移老应用时需要逐一检查。
14. **Oracle 有两个独立的解析器**（SQL 与 PL/SQL），同一段代码在两边语义不同。SQL*Plus 用空行/单独 `/` 切换上下文，OCI 驱动靠语句首字符判断。
15. **跨方言 SQL 转译器（如 sqlglot, jOOQ, Apache Calcite, ZetaSQL, Babelfish）** 必须为每种方言维护独立的词法 + 语法 + 保留字表，工程复杂度极高。
16. **解析器差异是数据库可移植性的第一道天花板**——比函数差异、SQL:1999 OLAP 特性差异都更基础、更难绕开。能做到"在词法层就识别方言"的工具，才能真正实现跨数据库的 SQL 转译。
17. **MySQL `sql_mode = 'ANSI_QUOTES'`** 可让 `"..."` 行为靠近标准（解析为标识符），是 MySQL 应用迁移到 PG 前的常用准备步骤。
18. **PostgreSQL 关键字四级分类** (reserved / reserved-can-be-fn-or-type / non-reserved-cannot-be-fn-or-type / non-reserved) 是所有引擎中最精细的，研究保留字的"教科书"。
19. **Unicode 标识符** 在引号内全引擎支持，但未引号支持参差，并受 server encoding/locale/排序规则影响——跨语言项目最好统一用 ASCII 标识符 + 中文注释。
20. **PG 系的 `U&'\0041'`** Unicode 字符串字面量是 SQL:2003 标准但只有 ~7 个引擎支持，大多数仍用各家私有语法。

> 工程建议：(1) 写 SQL 时永远显式加引号，统一用 `"..."` 风格，迁移时用脚本批量替换为目标方言；(2) 永远不要把保留字风险词用作标识符；(3) 跨数据库工具优先使用 sqlglot/Apache Calcite 这种已经内置 49+ 方言的解析器，而不是自己手写正则切分 SQL；(4) 测试时一定要在 Linux 上跑一遍 MySQL 集成测试，避开 macOS/Windows 默认 `lower_case_table_names` 的"伪绿"陷阱；(5) 任何接受用户输入的 SQL 都用参数化查询而不是字符串拼接，这是绕开"转义方言差异"最简单的方式。
