# 更新 (UPDATE) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 基本 UPDATE SET | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 多表 UPDATE | ✅ JOIN | ✅ FROM | ❌ | ✅ 子查询 | ✅ FROM/JOIN | ✅ JOIN | ✅ MERGE | ✅ FROM | ❌ |
| UPDATE RETURNING | ❌ | ✅ | ✅ 3.35+ | ✅ RETURN | ✅ OUTPUT | ✅ 10.5+ | ✅ RETURNING | ✅ | ❌ |
| UPDATE FROM | ❌ | ✅ | ✅ 3.33+ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |
| CTE + UPDATE | ✅ 8.0+ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| UPDATE LIMIT | ✅ | ❌ | ❌ | ❌ | ✅ TOP | ✅ | ❌ | ❌ | ❌ |
| 子查询 SET | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CASE 表达式 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 基本 UPDATE | ✅ | ✅ | ✅ 事务表 | ✅ ACID | ⚠️ ALTER UPDATE | ✅ 3.0+ | ✅ | ✅ | ✅ | ✅ | ✅ Delta | ❌ |
| 多表 UPDATE | ✅ FROM | ✅ FROM | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ FROM | ❌ | ✅ FROM | ❌ | ❌ |
| UPDATE RETURNING | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |

### 特殊说明

| 数据库 | UPDATE 特点 |
|---|---|
| ClickHouse | 使用 ALTER TABLE ... UPDATE（异步执行 Mutation） |
| Hive | 仅 ACID 事务表支持 UPDATE |
| MaxCompute | 仅事务表支持 UPDATE |
| Flink | 流处理引擎，不支持传统 UPDATE |
| TDengine | 通过相同时间戳 INSERT 覆盖实现更新 |
| ksqlDB | 不支持传统 UPDATE，TABLE 通过新消息覆盖 |

## 关键差异

- **MySQL/MariaDB** 支持 UPDATE ... JOIN 多表更新语法
- **PostgreSQL/Redshift** 使用 UPDATE ... FROM 语法进行多表更新
- **SQL Server** 同时支持 UPDATE ... FROM 和 UPDATE ... JOIN
- **ClickHouse** UPDATE 是异步 Mutation 操作，不是即时的
- **Flink/ksqlDB** 流处理引擎不支持传统 UPDATE
- **TDengine** 通过相同时间戳覆盖写入实现隐式更新
- **大数据引擎**的 UPDATE 通常需要特定表格式支持（Delta/ACID/事务表）
