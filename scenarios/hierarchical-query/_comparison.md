# 层次查询与树形结构 (Hierarchical Query) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 递归 CTE | ✅ 8.0+ | ✅ 8.4+ | ✅ 3.8+ | ✅ 11gR2+ | ✅ 2005+ | ✅ 10.2+ | ✅ 2.1+ | ✅ | ✅ |
| CONNECT BY | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| SYS_CONNECT_BY_PATH | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CONNECT_BY_ISLEAF | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CONNECT_BY_ROOT | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ORDER SIBLINGS BY | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SEARCH DEPTH/BREADTH FIRST | ❌ | ✅ 14+ | ❌ | ✅ 11gR2+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CYCLE 检测子句 | ❌ | ✅ 14+ | ❌ | ✅ 11gR2+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| HierarchyID 类型 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 路径枚举模型 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ltree 扩展 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 嵌套集模型 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 递归 CTE | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ 3.0+ | ❌ |
| CONNECT BY | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 固定深度 JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 路径枚举模型 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 最大递归深度限制 | ✅ 500 | ❌ | — | — | ✅ | — | ✅ | — | — | ❌ | ✅ 100 | — |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 递归 CTE | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| CONNECT BY | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 固定深度 JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 路径枚举模型 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 递归 CTE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CONNECT BY | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| 路径枚举模型 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 递归 CTE | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| 路径枚举模型 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 超级表/子表层次 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **Oracle** 的 `CONNECT BY` 是最早的层次查询语法，提供 `SYS_CONNECT_BY_PATH`、`CONNECT_BY_ISLEAF`、`ORDER SIBLINGS BY` 等丰富的辅助功能
- **PostgreSQL 14+** 在递归 CTE 中新增了 `SEARCH DEPTH/BREADTH FIRST` 和 `CYCLE` 子句，接近 SQL 标准
- **PostgreSQL** 的 `ltree` 扩展提供原生的层次路径数据类型和 GiST 索引支持
- **SQL Server** 独有 `HierarchyID` 数据类型，内置深度、祖先判断等方法
- **Snowflake** 是少数支持 `CONNECT BY` 的大数据引擎（兼容 Oracle 语法）
- **Hive / MaxCompute / StarRocks / Doris / Flink** 不支持递归 CTE，只能用固定深度 JOIN 或路径枚举模型
- **Redshift / Impala / Derby** 不支持递归 CTE，需要应用层或存储过程实现
- **TDengine** 通过超级表 > 子表的层次结构天然支持设备层次管理
- **MySQL 5.x** 无递归 CTE，需用多层 JOIN（固定深度）或应用层递归
- **OceanBase / DamengDB** 兼容 Oracle 的 `CONNECT BY` 语法
- 通用的**路径枚举模型**（将路径存为字符串如 `1/2/4`）在所有方言中可用，但查询灵活性有限
