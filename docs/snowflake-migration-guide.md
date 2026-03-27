# Snowflake 语法迁移指南

面向 SQL 引擎开发者（兼容 Snowflake 语法）和数据工程师（从/向 Snowflake 迁移数据和查询）。

## Snowflake 的设计哲学

Snowflake 是"云原生 + 用户友好"路线的代表：

1. **分离存储和计算**: 数据存在 S3/Azure Blob/GCS，计算用 Virtual Warehouse
2. **零管理**: 无索引、无 VACUUM、无表空间——用户只写 SQL
3. **VARIANT 半结构化**: JSON/XML/Avro/Parquet 数据无需 ETL 直接查询
4. **Time Travel**: 所有数据变更自动保留历史（1-90 天）
5. **零拷贝克隆**: CLONE 不复制数据，只复制元数据指针

## Snowflake 独特语法

### VARIANT 类型（半结构化数据核心）

详见 [types/json/snowflake.sql](../types/json/snowflake.sql)

```sql
-- VARIANT 可以存 JSON/XML/任意嵌套结构
CREATE TABLE events (
    id NUMBER AUTOINCREMENT,
    data VARIANT,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 路径访问（: 运算符，Snowflake 独有）
SELECT data:user:name::STRING AS user_name,
       data:items[0]:price::NUMBER AS first_item_price
FROM events;

-- FLATTEN 展开嵌套数据（类似 UNNEST/explode）
SELECT e.id, f.value:product::STRING AS product
FROM events e, LATERAL FLATTEN(input => e.data:items) f;
```

- `:` 路径运算符是 Snowflake 独有（其他引擎用 `->` 或 `.`）
- `::TYPE` 用于类型转换（和 PostgreSQL 相同）
- `FLATTEN` = BigQuery 的 `UNNEST` = Hive 的 `LATERAL VIEW explode`
- **对引擎开发者**: VARIANT 的实现需要自描述的列式存储格式，Snowflake 内部使用自研格式

### QUALIFY 子句

详见 [query/window-functions/snowflake.sql](../query/window-functions/snowflake.sql)

```sql
-- QUALIFY: 在窗口函数计算后过滤（省去子查询）
SELECT *
FROM orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

-- 等价于（没有 QUALIFY 时需要子查询包装）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) WHERE rn <= 3;
```

- Teradata 最先发明 QUALIFY，Snowflake/BigQuery/DuckDB/Databricks 也支持
- MySQL/PostgreSQL/Oracle/SQL Server 不支持
- **对引擎开发者**: 实现成本很低（在窗口函数计算后加一层过滤），用户价值很大，推荐支持

### Time Travel 和 CLONE

详见 [advanced/transactions/snowflake.sql](../advanced/transactions/snowflake.sql)

```sql
-- Time Travel: 查询历史数据
SELECT * FROM users AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP);
SELECT * FROM users BEFORE(STATEMENT => '01a2b3c4-...');

-- UNDROP: 恢复已删除的表/数据库/Schema
DROP TABLE users;
UNDROP TABLE users;

-- CLONE: 零拷贝克隆（瞬间完成，不占额外存储）
CREATE TABLE users_backup CLONE users;
CREATE TABLE users_snapshot CLONE users AT(TIMESTAMP => '2024-01-15'::TIMESTAMP);
CREATE DATABASE dev_db CLONE prod_db;
```

- Time Travel 基于微分区的不可变性（写入创建新分区，旧分区保留）
- CLONE 只复制元数据指针，数据在 COW（Copy-on-Write）时才真正复制
- **对引擎开发者**: 这需要存储层支持 MVCC + 不可变文件（Iceberg/Delta Lake 类似原理）

### 三种 TIMESTAMP 类型

详见 [types/datetime/snowflake.sql](../types/datetime/snowflake.sql)

```sql
-- TIMESTAMP_NTZ: 无时区（等于 MySQL DATETIME）
-- TIMESTAMP_LTZ: 本地时区（存 UTC，按会话时区显示）
-- TIMESTAMP_TZ:  带时区偏移（存值 + 偏移量）
-- TIMESTAMP 默认映射到 TIMESTAMP_NTZ（可通过 TIMESTAMP_TYPE_MAPPING 改）
```

- 三种 TIMESTAMP 类型是 Snowflake 独特设计
- PostgreSQL 只有两种（TIMESTAMP vs TIMESTAMPTZ）
- MySQL 只有两种（DATETIME vs TIMESTAMP）
- **TIMESTAMP_TYPE_MAPPING**: Snowflake 会话参数，控制 `TIMESTAMP` 关键字默认映射到哪种类型（NTZ/LTZ/TZ）。默认为 NTZ。迁移时需确认源系统语义与目标映射一致。
- **对引擎开发者**: 两种（带时区/不带时区）通常足够，三种增加认知负担

### 约束（信息性，不执行）

详见 [ddl/constraints/snowflake.sql](../ddl/constraints/snowflake.sql)

```sql
CREATE TABLE orders (
    id NUMBER NOT NULL,           -- NOT NULL 是唯一执行的约束！
    customer_id NUMBER,
    PRIMARY KEY (id),             -- 不执行唯一性检查
    FOREIGN KEY (customer_id) REFERENCES customers(id)  -- 不执行引用完整性
);
-- CHECK 约束完全不支持
```

- NOT NULL 是唯一强制执行的约束
- PRIMARY KEY/UNIQUE/FOREIGN KEY 仅作为优化器提示（帮助消除冗余 JOIN）
- **对引擎开发者**: 这是 Serverless 数仓的普遍选择（BigQuery 也是），因为分布式强制唯一性代价太高

## 从 Snowflake 迁移到其他引擎

| Snowflake 语法 | PostgreSQL | MySQL | BigQuery | Hive/Spark |
|---------------|-----------|-------|---------|-----------|
| `VARIANT` | `JSONB` | `JSON` | `JSON` / `STRUCT` | `STRING` (JSON) |
| `data:key::TYPE` | `data->>'key'` | `data->>'$.key'` | `data.key` | `get_json_object(data,'$.key')` |
| `FLATTEN(input=>arr)` | `UNNEST(arr)` | `JSON_TABLE(...)` | `UNNEST(arr)` | `LATERAL VIEW explode(arr)` |
| `QUALIFY ...` | 子查询包装 | 子查询包装 | `QUALIFY ...` | 子查询包装 |
| `CLONE` | 无等价 | 无等价 | 表快照 `SNAPSHOT` | 无等价 |
| `AT(TIMESTAMP=>...)` | 无（需 extension） | 无 | Time Travel `FOR SYSTEM_TIME` | Delta Lake Time Travel |
| `AUTOINCREMENT` | `GENERATED AS IDENTITY` | `AUTO_INCREMENT` | 无 | 无 |
| `NUMBER` | `NUMERIC` | `DECIMAL` | `NUMERIC` | `DECIMAL` |
| `TRY_TO_NUMBER(x)` | 自定义函数 | 无 | `SAFE_CAST(x AS NUMERIC)` | `CAST(x AS DECIMAL)` |
| `ILIKE` | `ILIKE` | `LIKE`(默认CI) | 无 | 无 |
| `IFF(cond, a, b)` | `CASE WHEN` | `IF(cond, a, b)` | `CASE WHEN cond THEN a ELSE b END` | `IF(cond, a, b)` |
| `LISTAGG(col, ',')` | `STRING_AGG(col, ',')` | `GROUP_CONCAT(col)` | `STRING_AGG(col, ',')` | `CONCAT_WS(',', COLLECT_LIST(col))` |
| `PARSE_JSON(str)` | `str::JSONB` | `CAST(str AS JSON)` | `JSON str` | `FROM_JSON(str, schema)` |

## 从其他引擎迁移到 Snowflake

| 常见问题 | 说明 |
|---------|------|
| VARCHAR(n) → VARCHAR | Snowflake VARCHAR 默认 16MB，通常不需要指定长度 |
| 索引 | 不支持也不需要，用 CLUSTER BY 代替 |
| 存储过程 | 支持 SQL/JavaScript/Python，但语法与 PL/pgSQL 或 T-SQL 不同 |
| 事务 | 每个语句自动事务，多语句事务需 BEGIN...COMMIT |
| 临时表 | 支持 TEMPORARY 和 TRANSIENT 表 |
| 分区 | 自动微分区（Micro-Partition），用 CLUSTER BY 优化 |
| MERGE | 完整支持 SQL 标准 MERGE |
| 窗口函数 | 完整支持，包括 QUALIFY |

> **Dynamic Tables（2024 GA）**: Snowflake 于 2024 年正式发布 Dynamic Tables，支持声明式数据管道（`CREATE DYNAMIC TABLE ... AS SELECT ...`，自动增量刷新）。替代了传统的 Task + Stream 组合模式，迁移 ETL 管道时推荐优先使用。
