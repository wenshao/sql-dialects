# 删除 (DELETE) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 基本 DELETE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| TRUNCATE TABLE | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| DELETE RETURNING | ❌ | ✅ | ✅ 3.35+ | ✅ RETURN | ✅ OUTPUT | ✅ 10.5+ | ✅ RETURNING | ✅ OLD TABLE | ❌ |
| DELETE JOIN | ✅ | ✅ USING | ❌ | ❌ | ✅ FROM/JOIN | ✅ | ❌ | ❌ | ❌ |
| DELETE LIMIT | ✅ | ❌ | ❌ | ❌ | ✅ TOP | ✅ | ❌ | ❌ | ❌ |
| CTE + DELETE | ✅ 8.0+ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 多表 DELETE | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 基本 DELETE | ✅ | ✅ | ✅ 事务表 | ✅ ACID | ⚠️ ALTER DELETE | ✅ 3.0+ | ✅ | ✅ | ✅ | ✅ | ✅ Delta | ❌ |
| TRUNCATE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| DELETE RETURNING | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |

### 特殊说明

| 数据库 | DELETE 特点 |
|---|---|
| ClickHouse | 使用 ALTER TABLE ... DELETE（异步 Mutation）或轻量级 DELETE（23.3+） |
| Hive | 仅 ACID 事务表支持 DELETE |
| Flink | 流处理引擎，不支持传统 DELETE |
| TDengine | 支持按时间范围或子表删除，不支持条件删除 |
| ksqlDB | 通过发送 tombstone 消息（null value）实现逻辑删除 |

## 关键差异

- **MySQL/MariaDB** 支持 DELETE ... JOIN 多表删除和 DELETE ... LIMIT
- **PostgreSQL** 使用 DELETE ... USING 进行关联删除
- **ClickHouse** DELETE 是异步 Mutation，23.3+ 新增轻量级 DELETE
- **大数据引擎** DELETE 通常需要特定表格式支持（Delta/ACID/事务表）
- **SQLite** 不支持 TRUNCATE，需用 DELETE FROM（无 WHERE）
- **Flink/ksqlDB** 不支持传统 DELETE 操作
