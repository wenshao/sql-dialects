# ClickHouse: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [1] ClickHouse - Migration Guides
>   https://clickhouse.com/docs/en/getting-started/example-datasets
> - [2] ClickHouse - MaterializedMySQL / MaterializedPostgreSQL
>   https://clickhouse.com/docs/en/engines/database-engines


## 从 MySQL/PostgreSQL 迁移到 ClickHouse 的常见问题


### 1. 数据类型映射

 MySQL INT              → Int32 或 UInt32
 MySQL BIGINT           → Int64 或 UInt64
 MySQL VARCHAR(255)     → String
 MySQL DECIMAL(10,2)    → Decimal64(2)
 MySQL DATETIME         → DateTime
 MySQL TIMESTAMP        → DateTime（ClickHouse 不做时区转换）
 MySQL BOOLEAN          → UInt8 或 Bool（21.12+）
 MySQL ENUM             → Enum8 或 LowCardinality(String)
 MySQL JSON             → String（JSON 函数操作）或 Tuple/Map
 PostgreSQL SERIAL      → 无自增（用 UUID 或外部生成）
 PostgreSQL UUID        → UUID（ClickHouse 原生类型）
 PostgreSQL ARRAY       → Array(Type)（原生支持）
 PostgreSQL JSONB       → String 或 Map/Tuple

### 2. DDL 差异

 MySQL:      CREATE TABLE t (...) ENGINE=InnoDB;
 ClickHouse: CREATE TABLE t (...) ENGINE = MergeTree() ORDER BY (col);
 → ORDER BY 是必须的（定义排序键和主键）
 → ENGINE 是必须的（MergeTree 是最常用的引擎）

### 3. DML 差异（最大的迁移挑战!）

 MySQL:      UPDATE t SET col=val WHERE id=1;        → 即时生效
 ClickHouse: ALTER TABLE t UPDATE col=val WHERE id=1; → 异步 mutation
 MySQL:      DELETE FROM t WHERE id=1;               → 即时生效
 ClickHouse: ALTER TABLE t DELETE WHERE id=1;        → 异步 mutation
 MySQL:      INSERT ON DUPLICATE KEY UPDATE          → 即时 UPSERT
 ClickHouse: 无 UPSERT（用 ReplacingMergeTree + INSERT 新版本）

### 4. NULL 行为

 MySQL/PostgreSQL: 默认允许 NULL
 ClickHouse:       默认 NOT NULL! 需要 Nullable(Type) 显式声明

### 5. 事务

 MySQL: BEGIN; UPDATE...; UPDATE...; COMMIT;  → 完整 ACID
 ClickHouse: 无多语句事务（单语句原子性 + 分区替换）

## 实时迁移方案


 MaterializedMySQL（从 MySQL 实时复制）:
 CREATE DATABASE mysql_replica ENGINE = MaterializedMySQL(
     'mysql-host:3306', 'source_db', 'repl_user', 'repl_pass'
 );
 → 自动消费 binlog，实时同步所有表

 MaterializedPostgreSQL（从 PostgreSQL 实时复制）:
 CREATE DATABASE pg_replica ENGINE = MaterializedPostgreSQL(
     'pg-host:5432', 'source_db', 'repl_user', 'repl_pass'
 );

 批量迁移: FORMAT 子句
cat mysql_export.csv | clickhouse-client --query="INSERT INTO t FORMAT CSV"
 clickhouse-client --query="INSERT INTO t FORMAT JSONEachRow" < data.json

## 对比与引擎开发者启示

ClickHouse 迁移的核心挑战:
UPDATE/DELETE 语义完全不同 → 需要重新设计数据管道
默认 NOT NULL → 数据清洗必须在迁移前完成
无事务 → ETL 逻辑需要用分区替换保证原子性
ORDER BY 必须 → 需要理解排序键对查询性能的影响

对引擎开发者的启示:
提供 MaterializedMySQL/PostgreSQL 类的实时复制引擎
是降低迁移门槛的最有效方案。
FORMAT 子句（直接导入 CSV/JSON）减少了对外部 ETL 工具的依赖。

