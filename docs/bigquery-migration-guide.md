# BigQuery 语法迁移指南

当你的引擎需要兼容 BigQuery 语法，或者用户要从 BigQuery 迁移过来/迁移过去时的参考。

## BigQuery 的设计哲学

BigQuery 是"Serverless + SQL 标准"路线的代表。理解其设计哲学有助于做兼容：

1. **按扫描计费**: 没有索引（不需要用户管理），靠分区和聚集优化
2. **列式存储**: 内部使用 Capacitor 格式，天然适合分析查询
3. **STRUCT/ARRAY 一等公民**: 鼓励嵌套数据而非 JOIN（反范式）
4. **强类型命名**: INT64 而非 INT/BIGINT/INTEGER，STRING 而非 VARCHAR/TEXT
5. **约束不执行**: PRIMARY KEY/FOREIGN KEY 是优化器提示，不强制唯一性

## BigQuery 独特语法（其他引擎没有或不同）

### 类型命名

| BigQuery | 标准 SQL / 其他引擎 | 说明 |
|----------|-------------------|------|
| `INT64` | `INTEGER` / `BIGINT` | BigQuery 只有一种整数 |
| `FLOAT64` | `DOUBLE` / `DOUBLE PRECISION` | BigQuery 只有一种浮点 |
| `NUMERIC` | `DECIMAL` | 精确数值，BigQuery 最大 29 位整数 + 9 位小数 |
| `BIGNUMERIC` | 无直接等价 | 76.76 位精度（38 位整数 + 38 位小数） |
| `STRING` | `VARCHAR` / `TEXT` | 无长度限制 |
| `BYTES` | `VARBINARY` / `BYTEA` | 二进制 |
| `BOOL` | `BOOLEAN` | 相同语义 |
| `DATE` / `TIME` / `DATETIME` / `TIMESTAMP` | 同名但语义不同 | DATETIME 无时区，TIMESTAMP 有时区（UTC） |

**对引擎开发者**: 如果要兼容 BigQuery，需要在 parser 中把 INT64/FLOAT64/STRING 映射到内部类型。

### STRUCT 和 ARRAY

详见 [types/array-map-struct/bigquery.sql](../types/array-map-struct/bigquery.sql)

```sql
-- BigQuery 鼓励用 STRUCT 代替 JOIN（反范式设计）
CREATE TABLE orders (
    order_id INT64,
    customer STRUCT<name STRING, email STRING>,
    items ARRAY<STRUCT<product STRING, qty INT64, price NUMERIC>>
);

-- 查询嵌套数据
SELECT
    order_id,
    customer.name,
    item.product,
    item.qty * item.price AS line_total
FROM orders, UNNEST(items) AS item;
```

- `UNNEST` 是展开 ARRAY 的唯一方式（不支持 LATERAL VIEW/explode）
- STRUCT 字段用 `.` 访问（不需要 JSON 路径语法）
- **对引擎开发者**: STRUCT/ARRAY 作为列类型的支持复杂度不低（嵌套类型的存储、序列化、JOIN 处理）

### 分区和聚集

详见 [ddl/create-table/bigquery.sql](../ddl/create-table/bigquery.sql)

```sql
CREATE TABLE events (
    event_id INT64,
    user_id INT64,
    event_time TIMESTAMP,
    event_type STRING
)
PARTITION BY DATE(event_time)         -- 分区: 减少扫描量
CLUSTER BY user_id, event_type;       -- 聚集: 排列相关数据
```

- 分区只支持: DATE/TIMESTAMP 列、INTEGER RANGE、或 _PARTITIONTIME（摄入时间）
- 聚集最多 4 列，顺序影响效果（最左前缀原则）
- 无索引——分区裁剪 + 聚集跳过 = BigQuery 的"索引"
- **对引擎开发者**: 这种"无索引"模式适合 Serverless 场景——用户不需要管理索引，引擎自动优化

### 安全函数（SAFE_ 前缀）

```sql
SELECT SAFE_CAST('abc' AS INT64);        -- NULL（不报错）
SELECT SAFE_DIVIDE(10, 0);               -- NULL（不报错）
SELECT SAFE.SUBSTR('hello', 10, 5);      -- NULL（不报错）
```

- 几乎每个函数都有 SAFE_ 版本
- 替代 TRY_CAST (SQL Server) / TRY_TO_NUMBER (Snowflake)
- **对引擎开发者**: SAFE_ 前缀是一种优雅的错误处理设计，实现成本低但用户体验好

### DML 限制

详见 [dml/insert/bigquery.sql](../dml/insert/bigquery.sql)

- 每个表有并发 DML 限制（同时最多约 5 个 DML 语句）
- INSERT/UPDATE/DELETE/MERGE 都消耗 DML 配额
- MERGE 是推荐的 UPSERT 方式
- **对引擎开发者**: BigQuery 的 DML 限制源于其 MVCC 实现——每次 DML 创建表的新快照

## 从 BigQuery 迁移到其他引擎

| BigQuery 语法 | PostgreSQL | MySQL | Hive/Spark |
|--------------|-----------|-------|-----------|
| `INT64` | `BIGINT` | `BIGINT` | `BIGINT` |
| `FLOAT64` | `DOUBLE PRECISION` | `DOUBLE` | `DOUBLE` |
| `STRING` | `TEXT` | `VARCHAR(n)` 或 `TEXT` | `STRING` |
| `STRUCT<...>` | 复合类型或 JSON | JSON | `STRUCT<...>` |
| `ARRAY<T>` | `T[]` | JSON | `ARRAY<T>` |
| `UNNEST(arr)` | `UNNEST(arr)` | `JSON_TABLE` | `LATERAL VIEW explode(arr)` |
| `SAFE_CAST(x AS T)` | 无（需自定义函数） | 无 | `CAST(x AS T)` (返回 NULL) |
| `DATE_DIFF(a, b, DAY)` | `a - b` (返回整数天) | `DATEDIFF(a, b)` | `DATEDIFF(a, b)` |
| `FORMAT_DATE('%Y-%m', d)` | `TO_CHAR(d, 'YYYY-MM')` | `DATE_FORMAT(d, '%Y-%m')` | `DATE_FORMAT(d, 'yyyy-MM')` |
| `GENERATE_DATE_ARRAY(...)` | `generate_series(...)` | 递归 CTE | `sequence(...)` |
| `QUALIFY ROW_NUMBER() OVER(...) = 1` | 子查询包装 | 子查询包装 | 子查询包装 |
| `CONTAINS_SUBSTR(col, 'text')` | `col ILIKE '%text%'` | `col LIKE '%text%'` | `col LIKE '%text%'` |

## 从其他引擎迁移到 BigQuery

| 常见问题 | 说明 |
|---------|------|
| VARCHAR(n) → STRING | BigQuery 没有长度限制的字符串 |
| AUTO_INCREMENT / IDENTITY | BigQuery 无自增，用 `GENERATE_UUID()` |
| 索引 | 不需要也不支持，用分区+聚集替代 |
| 事务 | 多语句事务有限制，优先用 MERGE |
| 存储过程 | BigQuery 支持 scripting（BEGIN...END），但功能有限；2024 年 GA 的存储过程支持带参数的 CREATE PROCEDURE，使用 SQL 或 JavaScript body |
| 外键 | 信息性的，不执行 |
| 临时表 | 用 `CREATE TEMP TABLE` 或 CTE |
| Time Travel | 支持 `FOR SYSTEM_TIME AS OF` 查询历史数据（表级 7 天），类似 Snowflake Time Travel 但保留期较短 |
