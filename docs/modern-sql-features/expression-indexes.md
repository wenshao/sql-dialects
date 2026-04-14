# 表达式索引 (Expression / Function-Based Indexes)

当用户查询 `WHERE LOWER(email) = 'user@example.com'` 时，普通的 `email` 列索引完全失效——因为 `LOWER(email)` 是一个函数表达式，而不是列本身。表达式索引就是为这种场景而生的"秘密武器"：它允许对任意确定性表达式（函数调用、JSON 路径、算术运算、字符串拼接）建立 B-Tree 或哈希索引，把"查询时计算"变成"写入时计算 + 查询时查找"。本文横向对比 48 个主流数据库引擎的表达式索引支持情况，深入剖析 PostgreSQL、Oracle、MySQL 三种典型实现路线，并揭示优化器"表达式匹配"这一最容易踩坑的隐形陷阱。

## SQL 标准定义

**SQL 标准并未定义表达式索引**。ISO/IEC 9075 标准中的 `CREATE INDEX` 本身就不是标准的一部分——索引被视为纯物理实现细节，由各厂商自行扩展。因此：

1. 表达式索引完全是**厂商扩展**（vendor extension）
2. 不同引擎的语法差异巨大：PostgreSQL 用 `((expr))`，Oracle 直接写 `(expr)`，MySQL 8.0.13 引入 `((expr))`
3. 语义层面也存在差异：有的要求函数 `IMMUTABLE`（PostgreSQL）、有的要求 `DETERMINISTIC`（Oracle）、有的要求表达式返回类型明确（MySQL）
4. SQL:2003 引入的**生成列（Generated Column）** 成为模拟表达式索引的"准标准"路径——先建生成列，再对生成列建普通索引

这种"无标准 + 厂商各自扩展"的局面意味着：跨引擎迁移时，表达式索引往往是最难移植的物理对象之一。

## 支持矩阵

### 表达式索引基础支持

| 引擎 | 表达式索引 | 函数调用 (LOWER/UPPER) | JSON 路径索引 | 算术表达式 | 字符串拼接/SUBSTR | 确定性要求 | 生成列 + 索引 | 首次支持版本 |
|------|-----------|----------------------|--------------|-----------|------------------|-----------|--------------|-------------|
| PostgreSQL | 是 | 是 | 是 (jsonb_path_ops) | 是 | 是 | IMMUTABLE | 是 (12+) | 7.4 (2003) |
| MySQL | 是 | 是 | 是 (8.0+) | 是 | 是 | DETERMINISTIC | 是 (5.7+) | 8.0.13 (2018) |
| MariaDB | 否 (通过生成列) | 通过生成列 | 通过 JSON 生成列 | 通过生成列 | 通过生成列 | DETERMINISTIC | 是 (5.2+) | 5.2 (2012, 虚拟列) |
| SQLite | 是 | 是 | 是 (JSON1 扩展) | 是 | 是 | deterministic 标记 | 是 (3.31+) | 3.9 (2015) |
| Oracle | 是 | 是 | 是 (JSON_VALUE) | 是 | 是 | DETERMINISTIC | 是 (11g 虚拟列) | 8i (1999) |
| SQL Server | 否 (通过计算列) | 通过计算列 | 通过 JSON_VALUE 计算列 | 通过计算列 | 通过计算列 | 计算列确定性 | 是 (2000+) | 2000 (计算列 + 索引) |
| DB2 | 是 | 是 | 是 (10.5+) | 是 | 是 | DETERMINISTIC | 是 (生成列) | 10.5 (2013) |
| Snowflake | 否 (Search Optimization) | Search Opt Service | Search Opt JSON | -- | -- | -- | 否 | 否 (不同机制) |
| BigQuery | 否 | -- | 是 (Search Index) | -- | -- | -- | 否 | 否 |
| Redshift | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 隐式确定性 | 是 (GENERATED) | 0.8+ |
| ClickHouse | 否 (通过 MATERIALIZED/ALIAS) | MATERIALIZED 列 | MATERIALIZED 列 | MATERIALIZED 列 | MATERIALIZED 列 | -- | 否 (跳数索引) | 否 |
| Trino | 否 (计算层，无索引) | -- | -- | -- | -- | -- | 否 | 否 |
| Presto | 否 | -- | -- | -- | -- | -- | -- | 否 |
| Spark SQL | 否 (无索引) | -- | -- | -- | -- | -- | 否 | 否 |
| Hive | 否 (索引已废弃) | -- | -- | -- | -- | -- | 否 | 否 |
| Flink SQL | 否 (流) | -- | -- | -- | -- | -- | 否 | 否 |
| Databricks | 否 (Delta Z-Order) | -- | -- | -- | -- | -- | 否 | 否 |
| Teradata | 否 (通过 Join Index) | Expression 参与 | -- | 是 | 是 | DETERMINISTIC | 是 | 通过 Join Index |
| Greenplum | 是 | 是 | 是 | 是 | 是 | IMMUTABLE | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 是 (19.2+) | 是 | 是 | 隐式 IMMUTABLE | 是 (19.1+) | 19.1 (2019, 计算列) / 21.2 直接 |
| TiDB | 是 | 是 | 是 | 是 | 是 | DETERMINISTIC | 是 (5.7 兼容) | 5.0 (2021) |
| OceanBase | 是 | 是 | 是 | 是 | 是 | DETERMINISTIC | 是 | 2.2+ |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | IMMUTABLE | 是 | 继承 PG |
| SingleStore | 否 (通过持久化计算列) | 计算列 | 计算列 | 计算列 | 计算列 | PERSISTED | 是 | 通过 PERSISTED 列 |
| Vertica | 否 (投影替代) | 投影表达式 | -- | 投影表达式 | 投影表达式 | DETERMINISTIC | 否 | 否 (投影机制) |
| Impala | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| StarRocks | 是 (3.1+) | 是 | 是 | 是 | 是 | 隐式 | 是 | 3.1 (2023) |
| Doris | 是 (2.0+) | 是 | 是 | 是 | 是 | 隐式 | 是 | 2.0 (2023) |
| MonetDB | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| CrateDB | 否 (通过生成列) | 生成列 | 生成列 | 生成列 | 生成列 | DETERMINISTIC | 是 | 通过生成列 |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | IMMUTABLE | 是 | 继承 PG |
| QuestDB | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| Exasol | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | DETERMINISTIC | 是 | 1.0+ |
| Informix | 是 (functional index) | 是 | -- | 是 | 是 | DETERMINISTIC (用户函数) | 否 | 9.2 (2000) |
| Firebird | 是 | 是 | -- | 是 | 是 | DETERMINISTIC | 是 (3.0+) | 2.0 (2006) |
| H2 | 否 | -- | -- | -- | -- | -- | 是 (GENERATED ALWAYS AS) | 否 |
| HSQLDB | 否 | -- | -- | -- | -- | -- | 是 (GENERATED) | 否 |
| Derby | 否 | -- | -- | -- | -- | -- | 是 (GENERATED) | 否 |
| Amazon Athena | 否 (继承 Trino) | -- | -- | -- | -- | -- | 否 | 否 |
| Azure Synapse | 否 (通过计算列) | 计算列 | 计算列 | 计算列 | 计算列 | PERSISTED | 是 | 通过持久化计算列 |
| Google Spanner | 是 (通过生成列) | 生成列 + 索引 | JSON 生成列 | 生成列 | 生成列 | STORED | 是 | GA |
| Materialize | 否 (物化视图代替) | -- | -- | -- | -- | -- | 否 | 否 |
| RisingWave | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| InfluxDB (SQL) | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| DatabendDB | 否 (集群键/Bloom) | -- | -- | -- | -- | -- | 否 | 否 |
| Yellowbrick | 否 | -- | -- | -- | -- | -- | 否 | 否 |
| Firebolt | 否 (聚合索引替代) | -- | -- | -- | -- | -- | 否 | 否 |

> 统计：约 19 个引擎原生支持表达式索引 (PostgreSQL、Oracle、MySQL、SQLite、DB2、DuckDB、TiDB、OceanBase、CockroachDB、YugabyteDB、Greenplum、TimescaleDB、SAP HANA、Informix、Firebird、StarRocks、Doris、Spanner、MariaDB 的生成列间接方案)；另有约 6 个引擎通过"计算列 + 索引"等价支持 (SQL Server、Azure Synapse、SingleStore、H2、HSQLDB、Derby)；剩余引擎或通过其他物理结构 (ClickHouse 的 MATERIALIZED 列、Vertica 的投影、Snowflake 的 Search Optimization Service) 间接支持，或完全不支持 (Trino/Spark/Flink 等计算引擎)。

### 查询匹配能力矩阵

优化器是否能"自动识别"查询中的表达式与索引表达式相同是另一个容易被忽视的维度：

| 引擎 | 严格字符串匹配 | 规范化后匹配 | 等价表达式识别 | 大小写敏感 |
|------|-------------|-------------|---------------|-----------|
| PostgreSQL | -- | 是 (解析树比对) | 部分 (常量折叠后) | 不敏感 |
| Oracle | -- | 是 (查询重写) | 强 (QUERY_REWRITE) | 不敏感 |
| MySQL | -- | 是 (表达式 hash) | 弱 (要求严格等价) | 不敏感 |
| SQLite | -- | 是 (AST 比对) | 弱 | 不敏感 |
| SQL Server (计算列) | 需持久化 + 确定性 | 是 | 强 | 不敏感 |
| DB2 | -- | 是 | 强 | 不敏感 |
| TiDB | -- | 是 | 弱 (8.0 前严格) | 不敏感 |
| CockroachDB | -- | 是 | 中 | 不敏感 |

**关键教训**：虽然多数引擎都"解析树比对"，但细节千差万别。`LOWER(email)` 和 `lower(email)` 通常能匹配（大小写不敏感），但 `SUBSTR(col, 1, 10)` 和 `SUBSTRING(col FROM 1 FOR 10)` 在部分引擎中可能匹配失败。

## 各引擎详解

### PostgreSQL（表达式索引的"黄金标准"）

PostgreSQL 是最早提供表达式索引的主流关系数据库之一，7.4 版本（2003 年 11 月）正式支持 `CREATE INDEX ... ON table ((expression))`：

```sql
-- 大小写不敏感搜索的经典用法
CREATE INDEX idx_users_email_lower ON users ((LOWER(email)));

-- 查询时必须使用完全相同的表达式才能命中
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';  -- 命中索引
SELECT * FROM users WHERE email ILIKE 'alice@example.com';      -- 不命中 (ILIKE 不等价)

-- 算术表达式
CREATE INDEX idx_orders_total ON orders ((quantity * unit_price));
SELECT * FROM orders WHERE quantity * unit_price > 10000;

-- 字符串拼接
CREATE INDEX idx_users_fullname ON users ((first_name || ' ' || last_name));
SELECT * FROM users WHERE first_name || ' ' || last_name = 'John Doe';

-- JSON 路径表达式（jsonb）
CREATE INDEX idx_events_user_id ON events ((payload->>'user_id'));
SELECT * FROM events WHERE payload->>'user_id' = '12345';

-- 多列表达式 + 普通列混合
CREATE INDEX idx_mixed ON orders (customer_id, (EXTRACT(YEAR FROM created_at)));

-- 唯一表达式索引：强制 email 大小写不敏感唯一
CREATE UNIQUE INDEX idx_users_email_unique ON users ((LOWER(email)));
```

**IMMUTABLE 要求**：PostgreSQL 要求索引表达式中调用的所有函数必须是 `IMMUTABLE`（给定相同输入总是返回相同输出，不依赖数据库状态或外部因素）。函数的易变性分为三类：

- `IMMUTABLE`：纯函数，如 `LOWER`、`UPPER`、`ABS`、`||`、`->>` 等
- `STABLE`：在单次事务内结果稳定，但依赖搜索路径或会话参数，如 `NOW()`、`CURRENT_USER`、`to_char()` 的某些变体
- `VOLATILE`：结果可能随时变化，如 `RANDOM()`、`CLOCK_TIMESTAMP()`

**经典陷阱**：`to_char(timestamp, 'YYYY-MM-DD')` 在 PostgreSQL 中是 `STABLE`（因为受会话 `lc_time` 影响），无法直接用于表达式索引。解决方法：

```sql
-- 错误：STABLE 函数不能用于索引
CREATE INDEX idx_bad ON events ((to_char(created_at, 'YYYY-MM-DD')));
-- ERROR: functions in index expression must be marked IMMUTABLE

-- 正确做法 1：使用 IMMUTABLE 的类型转换
CREATE INDEX idx_good ON events ((created_at::date));

-- 正确做法 2：包装成 IMMUTABLE 函数（自担风险）
CREATE FUNCTION immutable_to_char_ymd(ts timestamp)
RETURNS text AS $$ SELECT to_char(ts, 'YYYY-MM-DD') $$
LANGUAGE sql IMMUTABLE;  -- 强制声明 IMMUTABLE
CREATE INDEX idx_wrap ON events ((immutable_to_char_ymd(created_at)));
```

**生成列替代方案（PostgreSQL 12+）**：

```sql
CREATE TABLE users (
    id serial PRIMARY KEY,
    email text NOT NULL,
    email_lower text GENERATED ALWAYS AS (LOWER(email)) STORED
);
CREATE INDEX idx_users_email_lower ON users (email_lower);
-- 查询时必须使用 email_lower，不能使用 LOWER(email)
SELECT * FROM users WHERE email_lower = 'alice@example.com';
```

### Oracle（最早的函数索引 + 虚拟列双路径）

Oracle 8i（1999 年）引入**函数索引**（function-based index），是业界最早的主流实现：

```sql
-- 8i 原始语法
CREATE INDEX idx_emp_upper_name ON employees (UPPER(last_name));

-- 必须启用查询重写（9i 前）
ALTER SESSION SET QUERY_REWRITE_ENABLED = TRUE;
ALTER SESSION SET QUERY_REWRITE_INTEGRITY = TRUSTED;

-- 收集统计信息
EXEC DBMS_STATS.GATHER_TABLE_STATS('HR', 'EMPLOYEES');

-- 查询
SELECT * FROM employees WHERE UPPER(last_name) = 'SMITH';
```

**DETERMINISTIC 要求**：用户自定义函数（PL/SQL function）若想用于函数索引，必须显式声明 `DETERMINISTIC`：

```sql
CREATE OR REPLACE FUNCTION normalize_phone(p VARCHAR2)
RETURN VARCHAR2
DETERMINISTIC  -- 关键字，告诉优化器此函数是确定性的
IS
BEGIN
    RETURN REGEXP_REPLACE(p, '[^0-9]', '');
END;
/

CREATE INDEX idx_customers_phone_norm
    ON customers (normalize_phone(phone));

SELECT * FROM customers WHERE normalize_phone(phone) = '8613800138000';
```

Oracle 不会验证 `DETERMINISTIC` 声明的真实性——开发者必须为此负责。若函数实际非确定性（如内部调用 `SYSDATE`），索引可能损坏。

**11g 虚拟列（Virtual Column）**：Oracle 11g（2007）引入虚拟列，提供比函数索引更优雅的抽象：

```sql
ALTER TABLE employees ADD (
    upper_last_name VARCHAR2(50)
        GENERATED ALWAYS AS (UPPER(last_name)) VIRTUAL
);

-- 对虚拟列建普通索引（内部仍是函数索引）
CREATE INDEX idx_upper_last ON employees (upper_last_name);

-- 优化器可同时匹配以下两种查询
SELECT * FROM employees WHERE upper_last_name = 'SMITH';
SELECT * FROM employees WHERE UPPER(last_name) = 'SMITH';  -- 也能命中
```

虚拟列的优势：可直接 `SELECT`、被 PL/SQL 代码引用、支持约束，且不占用存储空间（VIRTUAL）。12c 之后，JSON 数据的表达式索引通常结合虚拟列：

```sql
ALTER TABLE orders ADD (
    customer_vip VARCHAR2(10)
    GENERATED ALWAYS AS (JSON_VALUE(payload, '$.customer.vip')) VIRTUAL
);
CREATE INDEX idx_orders_vip ON orders (customer_vip);
```

### MySQL（生成列时代 → 原生函数索引）

MySQL 的表达式索引支持走过了典型的"两阶段"演进：

**阶段一：5.7（2015）引入生成列**

```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    email VARCHAR(255),
    email_lower VARCHAR(255)
        GENERATED ALWAYS AS (LOWER(email)) STORED,
    INDEX idx_email_lower (email_lower)
);

-- 查询必须使用生成列，不能直接写 LOWER(email)
SELECT * FROM users WHERE email_lower = 'alice@example.com';
```

生成列分 `VIRTUAL`（运行时计算，不占空间）和 `STORED`（持久化，占空间但查询更快）。**只有 `STORED` 生成列最初才能被 InnoDB 索引**；5.7.8 后 `VIRTUAL` 生成列也支持索引（InnoDB 称为"virtual secondary index"）。

**阶段二：8.0.13（2018 年 10 月）引入函数索引**

```sql
-- 直接对表达式建索引，无需显式生成列
CREATE TABLE users (
    id INT PRIMARY KEY,
    email VARCHAR(255),
    INDEX idx_email_lower ((LOWER(email)))  -- 双括号是必需的
);

-- 或 ALTER TABLE
ALTER TABLE users ADD INDEX idx_email_lower ((LOWER(email)));

-- 查询可直接写表达式，优化器会自动匹配
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';
```

MySQL 内部实现：函数索引其实就是自动创建一个"隐藏生成列"然后对其建索引——这也是为什么双括号语法 `((expr))` 是必需的（第一层括号表示列列表，第二层括号标识这是表达式而非列名）。

**MySQL 函数索引限制**：

1. 表达式必须是 `DETERMINISTIC`，不能使用 `NOW()`、`RAND()`、`UUID()` 等
2. 不能包含子查询、参数、变量、存储函数（5.7 引入的 SQL SECURITY 限制）
3. 不能对主键使用
4. 不能在外键约束中引用
5. `CREATE INDEX` 仅支持 `BTREE`，不支持 `HASH` 表达式索引
6. 索引列长度受限于 `innodb_large_prefix`（默认 3072 字节）

### MariaDB（始终通过生成列）

MariaDB 没有引入 MySQL 8.0.13 风格的函数索引语法，而是继续使用生成列路径：

```sql
CREATE TABLE orders (
    id INT PRIMARY KEY,
    payload JSON,
    customer_id VARCHAR(36) AS (JSON_UNQUOTE(JSON_EXTRACT(payload, '$.customer_id'))) VIRTUAL,
    INDEX idx_customer (customer_id)
);
```

MariaDB 10.5+ 支持对 `VIRTUAL` 生成列建索引；10.2+ 支持 JSON 相关函数作为表达式。与 MySQL 一样，查询必须使用生成列名。

### SQLite（最轻量的表达式索引）

SQLite 3.9（2015 年 10 月）引入**索引表达式**（indexes on expressions）：

```sql
CREATE INDEX idx_users_email_lower ON users (LOWER(email));

-- JSON1 扩展 + 表达式索引
CREATE INDEX idx_events_user_id ON events (json_extract(payload, '$.user_id'));
SELECT * FROM events WHERE json_extract(payload, '$.user_id') = '12345';

-- 复合：普通列 + 表达式
CREATE INDEX idx_mixed ON logs (level, substr(message, 1, 20));
```

SQLite 要求表达式中使用的函数必须标记为 "deterministic"。内置函数如 `LOWER`、`UPPER`、`SUBSTR`、`json_extract` 都是 deterministic；用户函数需在 `sqlite3_create_function_v2()` 调用时传入 `SQLITE_DETERMINISTIC` 标志。

### SQL Server（计算列 + 索引，2000 至今）

SQL Server 从未引入独立的"表达式索引"语法，而是依靠**计算列（computed column）**：

```sql
-- 非持久化计算列（运行时计算）
CREATE TABLE Users (
    Id INT PRIMARY KEY,
    Email NVARCHAR(255),
    EmailLower AS LOWER(Email)  -- 计算列，默认非持久化
);

-- 持久化计算列：值实际存储在表中
ALTER TABLE Users
    ADD EmailLower AS LOWER(Email) PERSISTED;

CREATE INDEX IX_Users_EmailLower ON Users (EmailLower);
```

**关键规则**：

1. 计算列被索引的前提是函数**必须是确定性且精确**（not imprecise）
2. 若计算列被标记为 `PERSISTED`，即使函数非精确（如 `FLOAT` 运算）也能建索引
3. 优化器能自动匹配：`WHERE LOWER(Email) = '...'` 会命中 `IX_Users_EmailLower`（自动"列表达式匹配"）
4. 2005 正式支持非持久化计算列索引（需满足确定性 + 精确）；2000 时代仅支持持久化计算列

```sql
-- JSON 值的表达式索引（SQL Server 2016+）
ALTER TABLE Orders
    ADD CustomerId AS CAST(JSON_VALUE(Payload, '$.customer_id') AS INT) PERSISTED;
CREATE INDEX IX_Orders_CustomerId ON Orders (CustomerId);
```

### DB2（一步到位的 expression-based index）

IBM DB2 10.5（2013 年）引入**表达式索引**：

```sql
CREATE INDEX idx_emp_upper_name ON employees (UPPER(last_name));

CREATE INDEX idx_orders_total ON orders (quantity * unit_price);

-- JSON 路径（DB2 JSON 函数）
CREATE INDEX idx_events_user ON events (JSON_VAL(payload, 'user_id', 's:32'));

-- 唯一表达式索引
CREATE UNIQUE INDEX idx_users_email_ci
    ON users (LOWER(email));
```

DB2 要求表达式中的函数为 `DETERMINISTIC`（默认内置函数均满足），用户函数需显式声明 `DETERMINISTIC`。

### ClickHouse（无表达式索引，但有 MATERIALIZED 列）

ClickHouse 是列存 OLAP 引擎，没有传统意义上的"次级索引"——它只有主键排序 + 稀疏索引 + 跳数索引。对需要"预计算表达式"的场景，ClickHouse 的解决方案是 **MATERIALIZED 列** 或 **ALIAS 列**：

```sql
CREATE TABLE events (
    user_id UInt64,
    event_time DateTime,
    payload String,
    user_id_from_json UInt64 MATERIALIZED JSONExtractUInt(payload, 'user_id'),
    INDEX idx_user_id user_id_from_json TYPE minmax GRANULARITY 4
) ENGINE = MergeTree()
ORDER BY (user_id, event_time);
```

- `MATERIALIZED`：写入时计算并持久化，读取时免费；可作为排序键或跳数索引的一部分
- `ALIAS`：查询时计算，不占存储；不能用于排序键或索引

ClickHouse 的跳数索引（minmax/set/bloom_filter/ngrambf）是"数据块级别"的粗粒度索引，与行级别的 B-Tree 表达式索引有本质区别。

### Snowflake（Search Optimization Service 是不同机制）

Snowflake 没有传统索引，但提供 **Search Optimization Service (SOS)**：

```sql
ALTER TABLE events ADD SEARCH OPTIMIZATION ON EQUALITY(SUBSTR(payload, 1, 10));
-- 或对 JSON 字段
ALTER TABLE events ADD SEARCH OPTIMIZATION ON EQUALITY(payload:user_id);
```

SOS 为等值查询构建内部数据结构，但它不是表达式索引——而是类似"倒排映射"的服务化结构，背后是"micro-partition 级别"的裁剪加速。

### CockroachDB（计算列 → 直接表达式）

```sql
-- 19.1 (2019)：必须先建计算列
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email STRING,
    email_lower STRING AS (LOWER(email)) STORED,
    INDEX idx_email_lower (email_lower)
);

-- 21.2+：支持直接对表达式建索引
CREATE INDEX idx_email_lower ON users (LOWER(email));
```

### TiDB（5.0 引入，MySQL 8.0 语法兼容）

```sql
-- TiDB 5.0+ 直接兼容 MySQL 8.0.13 的函数索引语法
CREATE TABLE users (
    id INT PRIMARY KEY,
    email VARCHAR(255),
    INDEX idx_email_lower ((LOWER(email)))
);

-- 需开启表达式索引开关（较早版本）
SET @@tidb_allow_function_for_expression_index = 1;
```

TiDB 的函数索引支持函数白名单（`lower/upper/substr/json_extract/etc.`），白名单外的函数无法用于表达式索引。

## PostgreSQL 表达式索引深度剖析

### IMMUTABLE 的严格性

PostgreSQL 对 `IMMUTABLE` 的要求极其严格。以下是一些"看起来应该能用但实际不能"的例子：

```sql
-- 时区转换：STABLE（依赖 TimeZone 参数）
CREATE INDEX bad ON events ((created_at AT TIME ZONE 'UTC'));
-- 依赖会话时区时是 STABLE，但给出具体时区名时是 IMMUTABLE

-- 类型转换：多数 IMMUTABLE，但 text→numeric 是 STABLE（依赖 lc_numeric）
CREATE INDEX idx ON t ((CAST(txt AS numeric)));
-- 报错：STABLE

-- 数组操作
CREATE INDEX idx ON t ((arr[1]));  -- IMMUTABLE，OK
CREATE INDEX idx ON t ((array_length(arr, 1)));  -- IMMUTABLE，OK
```

**绕过方法**：用户可通过 `ALTER FUNCTION ... IMMUTABLE` 将 `STABLE` 函数重新声明为 `IMMUTABLE`，但这是"未定义行为"——一旦函数行为实际依赖会话，索引可能产生错误结果。

### B-Tree vs GiST/GIN 表达式索引

PostgreSQL 允许对任意索引访问方法（`btree`/`hash`/`gist`/`gin`/`brin`/`spgist`）建表达式索引：

```sql
-- 全文搜索：对表达式结果建 GIN 索引
CREATE INDEX idx_posts_fts ON posts
    USING GIN (to_tsvector('english', title || ' ' || body));

-- 查询
SELECT * FROM posts
WHERE to_tsvector('english', title || ' ' || body) @@ plainto_tsquery('postgresql');

-- BRIN 表达式索引：用于超大表的范围查询
CREATE INDEX idx_logs_hour ON logs
    USING BRIN ((date_trunc('hour', created_at)));
```

### 查询匹配机制

PostgreSQL 的优化器在选择索引时，会**解析查询中的 `WHERE`/`ORDER BY` 表达式**，与索引定义中的表达式进行"解析树比对"。比对规则：

1. 函数名大小写不敏感（`LOWER` = `lower`）
2. 字面值常量折叠（`(x + 1) + 2` = `x + 3`）
3. 类型转换必须严格一致
4. 运算符优先级规范化

**陷阱**：`CAST(x AS text)` 与 `x::text` 虽然语义相同，但解析树表示不同——多数情况下能匹配，但在复杂表达式中偶尔失败。建议定义索引和写查询时使用同一套"规范写法"。

## MySQL 的渐进式演进路径

MySQL 的表达式索引发展线索清晰：

| 版本 | 年份 | 能力 |
|------|------|------|
| 5.7.5 | 2014 | 引入 STORED 生成列，支持索引 |
| 5.7.8 | 2015 | 引入 VIRTUAL 生成列索引（InnoDB） |
| 8.0.13 | 2018-10 | 引入函数索引 `INDEX ((expr))` |
| 8.0.16 | 2019 | 支持 JSON 多值索引 `INDEX ((CAST(data->'$.tags' AS UNSIGNED ARRAY)))` |
| 8.0.17 | 2019 | JSON 多值索引 GA |

**JSON 多值索引**（Multi-Valued Index）是 MySQL 表达式索引的独特能力：一个 JSON 数组元素映射到多个索引项。

```sql
CREATE TABLE customers (
    id INT PRIMARY KEY,
    profile JSON,
    INDEX idx_tags ((CAST(profile->'$.tags' AS UNSIGNED ARRAY)))
);

INSERT INTO customers VALUES (1, '{"tags": [10, 20, 30]}');
-- 索引中会有 3 个条目：(10, 1)、(20, 1)、(30, 1)

SELECT * FROM customers WHERE 20 MEMBER OF (profile->'$.tags');
SELECT * FROM customers
WHERE JSON_CONTAINS(profile->'$.tags', CAST('[20, 30]' AS JSON));
```

## Oracle 函数索引与虚拟列协同

Oracle 在 11g 之后，**推荐新项目使用虚拟列 + 普通索引** 而非直接函数索引，原因：

1. 虚拟列在数据字典中可见，便于维护
2. 优化器同时匹配 `virtual_col` 和 `UPPER(col)` 两种写法
3. 虚拟列可被多个索引、约束、视图共享
4. 虚拟列可配合 Oracle 12c 的 JSON 搜索索引使用

```sql
ALTER TABLE orders ADD (
    json_customer_vip VARCHAR2(10) GENERATED ALWAYS AS
        (JSON_VALUE(payload, '$.customer.vip' RETURNING VARCHAR2(10))) VIRTUAL,
    json_order_total NUMBER GENERATED ALWAYS AS
        (JSON_VALUE(payload, '$.total' RETURNING NUMBER)) VIRTUAL
);

CREATE INDEX idx_vip_total ON orders (json_customer_vip, json_order_total);

-- 两种写法都能命中索引
SELECT * FROM orders
WHERE json_customer_vip = 'GOLD' AND json_order_total > 1000;

SELECT * FROM orders
WHERE JSON_VALUE(payload, '$.customer.vip' RETURNING VARCHAR2(10)) = 'GOLD'
  AND JSON_VALUE(payload, '$.total' RETURNING NUMBER) > 1000;
```

## 查询匹配的隐形陷阱

表达式索引最令人沮丧的问题不是"建不出来"，而是"建出来了但没命中"。这通常源于查询表达式与索引表达式的"微妙差异"。

### 陷阱 1：参数顺序与默认参数

```sql
-- PostgreSQL 示例
CREATE INDEX idx ON users ((substr(email, 1, 5)));

SELECT * FROM users WHERE substr(email, 1, 5) = 'alice';  -- 命中
SELECT * FROM users WHERE substring(email, 1, 5) = 'alice';  -- 不命中！
-- substr 和 substring 虽然语义相同，但解析树中是不同的函数节点
```

### 陷阱 2：隐式类型转换

```sql
CREATE INDEX idx ON orders ((amount::text));

-- 查询使用 CAST 而非 ::
SELECT * FROM orders WHERE CAST(amount AS text) = '1000';
-- 通常能命中，但某些版本/某些类型组合下会失败

-- 查询使用自动类型转换
SELECT * FROM orders WHERE amount::text = 1000;  -- 右侧字面值被推断为整数
-- 不命中（因为右侧类型与索引不匹配）
```

### 陷阱 3：COLLATION 差异

```sql
-- PostgreSQL
CREATE INDEX idx ON users ((LOWER(email)));
-- 索引使用默认排序规则

SELECT * FROM users WHERE LOWER(email) = 'alice@example.com' COLLATE "C";
-- 不命中（COLLATE 子句改变了表达式树）
```

### 陷阱 4：MySQL 的类型长度不匹配

```sql
CREATE TABLE t (
    email VARCHAR(255),
    INDEX idx ((LOWER(email)))  -- 索引推断返回类型为 VARCHAR(255)
);

SELECT * FROM t WHERE LOWER(email) = 'alice@example.com';  -- 命中
SELECT * FROM t WHERE LOWER(CAST(email AS CHAR(100))) = 'alice';  -- 不命中
```

### 陷阱 5：NULL 语义与 IS DISTINCT FROM

表达式索引默认不索引表达式结果为 NULL 的行（PostgreSQL）或作为特殊 NULL 项（MySQL）。复杂表达式中内部字段为 NULL 时，结果行为可能与预期不同。

### 如何验证索引命中

- PostgreSQL: `EXPLAIN (ANALYZE, BUFFERS) SELECT ...`，查看 `Index Scan using idx_...`
- MySQL: `EXPLAIN FORMAT=TREE SELECT ...`，查看 `Using index lookup on ... using idx_...`
- Oracle: `EXPLAIN PLAN FOR SELECT ...; SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());`，查看 `INDEX RANGE SCAN` 行
- SQL Server: 执行计划中的 "Index Seek" 算子 + "Predicate" 显示匹配的表达式

## 其他值得关注的引擎

### SAP HANA

SAP HANA 支持表达式索引，主要用于列存表上的高选择性谓词：

```sql
CREATE INDEX idx_users_email_lower
    ON users (LOWER(email));

CREATE INDEX idx_orders_json_cust
    ON orders (JSON_VALUE(payload, '$.customer_id'));
```

HANA 对表达式索引的限制：不能使用 `STABLE` 函数、不能用于列存的"主键约束表达式"、JSON 表达式需配合 `JSON_TABLE` 或文档存储。

### Firebird

Firebird 2.0（2006）就支持了表达式索引：

```sql
CREATE INDEX idx_users_email_upper
    ON users COMPUTED BY (UPPER(email));

-- 降序表达式索引
CREATE DESCENDING INDEX idx_orders_discount
    ON orders COMPUTED BY (price * (1 - discount));
```

`COMPUTED BY` 语法是 Firebird 特有的，与"computed field"的语法保持一致。

### Informix

IBM Informix 9.2（2000）引入**functional indexes**：

```sql
CREATE INDEX idx_emp_upper
    ON employees (UPPER(last_name));

-- 用户定义函数（UDF）必须声明 NOT VARIANT
CREATE FUNCTION normalize_phone(p VARCHAR(50))
    RETURNING VARCHAR(20)
    WITH (NOT VARIANT)
    ...;

CREATE INDEX idx_cust_phone
    ON customers (normalize_phone(phone));
```

Informix 是"用户函数索引"的先驱——在 2000 年就允许将 C 编写的 DataBlade 函数用于索引。

### StarRocks 与 Doris

两个国产 OLAP 引擎在 2023 年前后加入表达式索引：

```sql
-- StarRocks 3.1+（2023）
CREATE INDEX idx_lower_email ON users ((LOWER(email))) USING BITMAP;

-- Doris 2.0+（2023）
CREATE INDEX idx_json_uid ON events ((json_extract_string(payload, '$.user_id')))
    USING INVERTED;
```

这两个引擎的表达式索引主要结合 BITMAP / INVERTED 索引使用，服务于高基数低选择度的等值过滤场景。

### Google Spanner

Spanner 通过**生成列**支持表达式索引：

```sql
CREATE TABLE Users (
    UserId INT64 NOT NULL,
    Email STRING(MAX),
    EmailLower STRING(MAX) AS (LOWER(Email)) STORED,
) PRIMARY KEY (UserId);

CREATE INDEX UsersByEmailLower ON Users (EmailLower);
```

Spanner 要求生成列表达式必须是"确定性 + 不引用其他表"，这与其全球强一致性的设计紧密相关。

### YugabyteDB / CockroachDB：分布式中的表达式索引

两个 NewSQL 引擎都支持表达式索引，但分布式索引维护成本更高：

```sql
-- YugabyteDB（继承 PostgreSQL 语法）
CREATE INDEX idx_users_email_lower ON users ((LOWER(email)));

-- CockroachDB 21.2+
CREATE INDEX idx_users_email_lower ON users (LOWER(email));
```

分布式场景的额外约束：索引分片可能与主数据不在同一 Range/Tablet，更新表达式索引需要跨节点事务；故建议**尽量选择低更新频率的列**作为表达式索引的输入。

## 部分索引 + 表达式索引的组合（PostgreSQL 独有）

PostgreSQL 允许在同一个索引中同时使用表达式 + WHERE 谓词（partial index），形成极强的"定向优化"能力：

```sql
-- 只为"活跃用户"的邮箱小写形式建索引
CREATE INDEX idx_active_users_email_lower
    ON users ((LOWER(email)))
    WHERE status = 'active' AND deleted_at IS NULL;

-- 只对过去 7 天的事件建 JSON 路径索引
CREATE INDEX idx_recent_event_user
    ON events ((payload->>'user_id'))
    WHERE created_at > NOW() - INTERVAL '7 days';
-- 注意：WHERE 中的 NOW() 在创建时计算一次，不会自动滚动
```

这种组合在"90% 的查询只访问 10% 的数据"的场景下能节约大量索引空间和写入开销。

## 存储引擎视角：表达式索引的代价

表达式索引并非"免费"，其额外代价体现在三个层面：

### 1. 写入开销

每次 `INSERT`/`UPDATE`/`DELETE` 涉及的表达式都要重新计算：

- PostgreSQL：每次更新索引对应列时，都要调用 `IMMUTABLE` 函数计算新值
- MySQL：VIRTUAL 生成列索引在更新时计算；STORED 列在写入时计算
- SQL Server：非持久化计算列在更新索引时计算；持久化计算列在写入表时计算

**示例**：一张 1000 万行的 `users` 表，`LOWER(email)` 表达式索引的维护代价大约是相同大小普通索引的 1.2-1.5 倍（LOWER 是非常廉价的 ASCII 转换）。若表达式是复杂的 JSON 解析，代价可能高达 5-10 倍。

### 2. 存储开销

- PostgreSQL B-Tree 表达式索引：索引只存计算结果 + tuple 指针，与同列普通索引存储大小相当
- MySQL STORED 生成列：**同时**存储原始列 + 计算结果 + 索引，空间开销最大
- MySQL VIRTUAL 生成列：只存原始列 + 索引，查询时从索引键反推计算结果
- Oracle 虚拟列：不存储计算结果，索引单独存储
- ClickHouse MATERIALIZED 列：计算结果物理化，作为普通列存储

### 3. 查询规划开销

优化器在选择索引时，必须对每个候选 WHERE 子表达式进行"解析树 vs 索引表达式"的结构化比对。当一张表有 10+ 个表达式索引时，规划时间会显著增加。PostgreSQL 的 `Bitmap Index Scan` 可同时使用多个表达式索引，但前提是每个索引都参与了规划阶段的匹配。

## 索引维护的特殊问题

### 重建索引与函数语义变更

若已有表达式索引依赖某个用户函数，而后函数定义被 `ALTER FUNCTION` 修改，会发生什么？

- PostgreSQL：已构建的索引项不会自动重新计算；后续查询可能返回错误结果；必须 `REINDEX`
- Oracle：同上，需 `ALTER INDEX REBUILD`
- MySQL：函数索引依赖的表达式是 SQL 表达式（不支持用户函数），不存在此问题

**最佳实践**：表达式索引中若使用用户函数，一旦函数语义变更，立刻 `REINDEX`。

### 排序规则变更

系统 ICU 或 glibc 的排序规则库升级后，基于 `LOWER()`/`UPPER()` 的索引可能出现键序错乱。PostgreSQL 14+ 引入了 `provider icu` 排序规则，允许在数据库内部管理排序规则版本，缓解这一问题。

### 索引膨胀监控

表达式索引比普通索引更容易"走样"——因为表达式计算结果可能与原数据分布差异很大，导致 B-Tree 节点分裂频繁。建议监控：

- PostgreSQL: `pg_stat_user_indexes` + `pgstattuple` 扩展
- MySQL: `INFORMATION_SCHEMA.INNODB_INDEXES` + `ANALYZE TABLE`
- Oracle: `DBMS_STATS.GATHER_INDEX_STATS` + `INDEX_STATS` 视图

## 关键发现

1. **表达式索引完全是厂商扩展**。SQL 标准甚至没有定义 `CREATE INDEX`，因此不同引擎的语法、语义、命中规则千差万别。生成列 + 普通索引是跨引擎最可移植的替代路径。

2. **PostgreSQL 和 Oracle 是"表达式索引元老"**。PostgreSQL 7.4 (2003) 和 Oracle 8i (1999) 确立了两大路径：PostgreSQL 偏纯声明式（`((expression))`），Oracle 偏混合式（函数索引 + 虚拟列）。

3. **MySQL 花了 15 年才追上**。从 2003 年到 2018 年，MySQL 用户只能通过生成列 + 索引间接实现；8.0.13 才引入原生函数索引，内部实现仍是"隐藏生成列"。

4. **SQL Server 走了完全不同的路线**。微软从 2000 年起就押注于"计算列"这一抽象，`PERSISTED + 索引`至今仍是 SQL Server 用户的唯一选择。这种设计的优势是计算列可被查询直接引用、可用于约束/触发器，劣势是语法冗长。

5. **确定性是硬约束但厂商声明风格不同**。PostgreSQL 用 `IMMUTABLE`（严格纯函数），Oracle/DB2/MySQL 用 `DETERMINISTIC`（给定输入产生相同输出）。`IMMUTABLE` 比 `DETERMINISTIC` 更严格：`IMMUTABLE` 禁止依赖任何数据库状态（包括会话参数），而 `DETERMINISTIC` 通常只禁止内部调用随机/时间函数。

6. **查询匹配机制是隐形杀手**。建了索引不等于能命中。`substr` vs `substring`、`::text` vs `CAST AS text`、大写小写、参数默认值——任何细微差异都可能导致优化器无法匹配。最佳实践：在 schema 定义旁边放一个"规范查询写法"注释。

7. **JSON 路径索引是近 10 年的新兴需求**。PostgreSQL (9.4, 2014)、MySQL (8.0, 2018)、Oracle (12c, 2013)、DB2 (10.5, 2013)、SQL Server (2016) 各自独立实现，语法差异巨大。MySQL 8.0.17 的多值索引（`MEMBER OF`）是这一领域的独特创新。

8. **云数仓普遍放弃表达式索引**。Snowflake、BigQuery、Redshift、Databricks、Firebolt 等没有 B-Tree 表达式索引——它们依赖列存 + 微分区裁剪 + Bloom/Zone Map 达到类似效果。这反映了 OLAP 场景的"扫描密集 + 宽谓词"特性：优化少量点查不如加速全表聚合。

9. **流/计算引擎完全不支持**。Trino、Presto、Spark SQL、Flink、Impala、Hive 作为纯计算层，没有持久化索引概念——它们的"表达式优化"发生在下推到存储层（如 Iceberg/Delta）的谓词时。

10. **ClickHouse 的 MATERIALIZED 列是"最 OLAP"的表达式索引替代**。它结合了"预计算 + 排序键参与 + 跳数索引"三重优势，在写多读多的大数据场景下比传统 B-Tree 表达式索引更划算。

11. **生成列是"准标准"桥梁**。SQL:2003 定义的 `GENERATED ALWAYS AS (expr) [STORED|VIRTUAL]` 被几乎所有主流关系数据库采纳（PostgreSQL、MySQL、MariaDB、SQLite、Oracle、SQL Server、DB2、SAP HANA 均支持），是跨引擎迁移表达式索引逻辑的最可靠中介层。

12. **不同引擎的"确定性声明真实性"检查严格度不同**。PostgreSQL 信任开发者的 `IMMUTABLE` 声明但会在某些操作中验证（如立即执行函数）；Oracle 完全信任 `DETERMINISTIC` 声明；MySQL 会在创建函数索引时拒绝已知的非确定性内置函数（如 `NOW()`），但信任用户函数声明。

## 参考资料

- PostgreSQL: [Indexes on Expressions](https://www.postgresql.org/docs/current/indexes-expressional.html)
- PostgreSQL: [Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html)
- Oracle: [Function-Based Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html#GUID-1CB45FA7-2F4A-43A9-A98F-A7E4AC5A7DAE)
- Oracle: [Virtual Columns](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TABLE.html#GUID-F9CE0CC3-13AE-4744-A43C-EAC7A71AAAB6)
- MySQL: [Functional Key Parts](https://dev.mysql.com/doc/refman/8.0/en/create-index.html#create-index-functional-key-parts)
- MySQL: [Multi-Valued Indexes](https://dev.mysql.com/doc/refman/8.0/en/create-index.html#create-index-multi-valued)
- MariaDB: [Generated Columns](https://mariadb.com/kb/en/generated-columns/)
- SQLite: [Indexes On Expressions](https://www.sqlite.org/expridx.html)
- SQL Server: [Computed Columns](https://learn.microsoft.com/en-us/sql/relational-databases/tables/specify-computed-columns-in-a-table)
- SQL Server: [Indexes on Computed Columns](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/indexes-on-computed-columns)
- DB2: [Expression-Based Indexes](https://www.ibm.com/docs/en/db2/11.5?topic=indexes-expression-based)
- CockroachDB: [Expression Indexes](https://www.cockroachlabs.com/docs/stable/expression-indexes)
- TiDB: [Expression Index](https://docs.pingcap.com/tidb/stable/sql-statement-create-index#expression-index)
- ClickHouse: [MATERIALIZED Columns](https://clickhouse.com/docs/en/sql-reference/statements/create/table#materialized)
- Snowflake: [Search Optimization Service](https://docs.snowflake.com/en/user-guide/search-optimization-service)
- Informix: [Functional Indexes](https://www.ibm.com/docs/en/informix-servers)
- Firebird: [Computed By Fields and Expression Indexes](https://firebirdsql.org/refdocs/langrefupd25-create-index.html)
- SAP HANA: [CREATE INDEX](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d5ba8475191014b4bfacef28931d4a.html)
