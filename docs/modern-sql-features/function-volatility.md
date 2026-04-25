# 函数波动性 (Function Volatility: IMMUTABLE / STABLE / VOLATILE)

`SELECT * FROM orders WHERE created_at > now() - interval '1 day'` 这条查询，优化器能不能把 `now()` 的结果缓存起来只计算一次？它能不能作为索引表达式？能不能在并行 worker 之间共享？能不能在物化视图增量刷新时复用？这些看似具体的工程问题，背后都指向同一个被很多使用者忽略的概念——**函数波动性（Function Volatility）**。

波动性是一个函数对优化器做出的"契约"：在给定相同输入时，它承诺返回什么结果、能否被缓存、是否读写数据、能否并行执行。SQL:1999 标准只给了一个二元分类 `DETERMINISTIC` / `NOT DETERMINISTIC`，PostgreSQL 进一步细化为 `IMMUTABLE` / `STABLE` / `VOLATILE` 三级，Oracle 有 `DETERMINISTIC` + `PARALLEL_ENABLE` 双轴，SQL Server 用 `WITH SCHEMABINDING` 推断，MySQL 把 `DETERMINISTIC` 与 `NO SQL` / `READS SQL DATA` / `MODIFIES SQL DATA` 正交组合——各家引擎的模型都不一样。

本文系统梳理各引擎的波动性分类、对优化器的影响（常量折叠、函数索引、并行查询、计划缓存）、以及实现上的取舍。

## 为什么波动性对优化器如此重要

### 常量折叠（Constant Folding）

```sql
-- IMMUTABLE 函数 + 常量参数 → 查询计划生成时直接求值
SELECT * FROM events WHERE ts > '2025-01-01'::timestamp + interval '7 days';
-- 优化器在 planning 阶段把右侧直接算成 '2025-01-08'，省去每行都求值一次

-- VOLATILE 函数 → 每行都必须调用一次
SELECT * FROM events WHERE ts > now() - interval '1 day';
-- 如果 now() 是 VOLATILE，每行重新调用；PostgreSQL 将 now() 标为 STABLE，
-- 在同一事务内只算一次，但不能作为索引表达式
```

### 索引使用（Index Usage）

函数索引（functional / expression index）只能建立在 IMMUTABLE 函数上。这是因为：
- STABLE 函数跨事务返回值可能变化，索引与值的对应关系会崩溃。
- VOLATILE 函数连同一事务内都可能返回不同值。
- 只有 IMMUTABLE 能保证"相同输入 → 相同输出"这一索引的基本前提。

```sql
-- IMMUTABLE 的 lower() → 可建索引
CREATE INDEX idx_email_lower ON users (lower(email));
SELECT * FROM users WHERE lower(email) = 'foo@bar.com';  -- 可走索引

-- 用 VOLATILE 函数建索引 → 报错
CREATE INDEX idx_bad ON events (random_score(id));  -- ERROR: 函数必须 IMMUTABLE
```

### 并行查询（Parallel Query）

分布式执行、多线程 worker 并行扫描时，函数能否跨 worker 安全执行、能否跨分片共享缓存，取决于波动性与并行安全标志。

```sql
-- PostgreSQL 9.6+ 引入三级并行安全标志
CREATE FUNCTION safe_fn(int) RETURNS int AS $$ ... $$
  LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- PARALLEL RESTRICTED：可以并行，但只能在 leader 中执行
-- PARALLEL UNSAFE：整个查询退化为串行
```

### 计划缓存（Plan Cache）

- **绑定变量 + IMMUTABLE**：可以把函数结果 precompute 到计划里（PostgreSQL 的 prepared plan, Oracle 的 cursor cache）。
- **STABLE**：每次执行时计算一次，但同一次执行内部缓存。
- **VOLATILE**：每次调用都重算，通常阻止任何形式的子表达式消除（CSE）。

### 物化视图与增量刷新

只有基于 IMMUTABLE 函数的物化视图才能安全地做**增量刷新**（delta 合并）。STABLE/VOLATILE 会让增量结果与全量重算不一致。

### 小结

| 优化类型 | IMMUTABLE | STABLE | VOLATILE |
|---------|-----------|--------|----------|
| 常量折叠（planning 时） | 是 | 否 | 否 |
| 跨行 CSE（同一次执行内） | 是 | 是 | 否 |
| 作为索引表达式 | 是 | 否 | 否 |
| 在生成列（GENERATED）中 | 是 | 否 | 否 |
| 并行 worker 中执行 | 通常安全 | 通常安全 | 取决于副作用 |
| 物化视图增量刷新 | 是 | 否 | 否 |
| 用于分区键 | 是 | 否 | 否 |
| 约束表达式（CHECK） | 是 | 否 | 否 |

## SQL:1999 DETERMINISTIC 子句

SQL:1999（ISO/IEC 9075-4, SQL/PSM）在 `CREATE FUNCTION` 中引入了 `DETERMINISTIC` / `NOT DETERMINISTIC` 特性子句：

```sql
<routine characteristics> ::= [ <routine characteristic> ... ]
<routine characteristic> ::=
      <language clause>
    | <parameter style>
    | <deterministic characteristic>
    | <SQL-data access indication>
    | <null-call clause>
    | ...

<deterministic characteristic> ::= DETERMINISTIC | NOT DETERMINISTIC

<SQL-data access indication> ::=
      NO SQL
    | CONTAINS SQL
    | READS SQL DATA
    | MODIFIES SQL DATA
```

标准定义的关键语义：

1. **DETERMINISTIC**：给定相同输入 + 相同 SQL-data 状态，函数总是返回相同结果。
2. **NOT DETERMINISTIC**：可能返回不同结果（默认）。
3. 独立于 SQL-data 访问等级：`DETERMINISTIC` 与 `READS SQL DATA` 可以共存（读数据但结果由读到的数据决定）。
4. **NO SQL**：函数体不访问任何 SQL 数据。
5. **CONTAINS SQL**：执行 SQL 但不读写任何表（如 SET 会话变量）。
6. **READS SQL DATA**：只读查询。
7. **MODIFIES SQL DATA**：包含 INSERT/UPDATE/DELETE/DDL。

然而标准的二元分类（DETERMINISTIC vs NOT DETERMINISTIC）不足以区分"结果在同一事务内稳定但跨事务可能变化"（如 `now()`、`current_user`），因此 PostgreSQL 等引擎在标准之外增加了 STABLE 级别。

## 支持矩阵（综合）

### 波动性分类模型

| 引擎 | 分类模型 | 关键字 | 默认值 | 版本 |
|------|---------|--------|--------|------|
| PostgreSQL | 三级 | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 7.2+ (2002) |
| Oracle | 二元 + 辅助 | `DETERMINISTIC`（无此关键字即非确定性） | 非确定性 | 8i+ (1998) |
| SQL Server | 三状态推断 | `SCHEMABINDING` / `ISDETERMINISTIC` / `ISPRECISE` | 非确定性 | 2000+ |
| MySQL | 二元 + SQL-data | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 5.0+ |
| MariaDB | 与 MySQL 相同 | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 5.0+ |
| DB2 | 二元 + SQL-data | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 7.0+ |
| SQLite | 二元 | `SQLITE_DETERMINISTIC` 标志 | 非确定性 | 3.8.3+ |
| Snowflake | 二元 | `IMMUTABLE` / `VOLATILE` | VOLATILE | GA |
| BigQuery | 二元 | `DETERMINISTIC` / `NOT DETERMINISTIC`（隐式） | 隐式 | GA |
| Redshift | 二元 | `IMMUTABLE` / `STABLE` / `VOLATILE`（Python UDF） | VOLATILE | 2015+ |
| DuckDB | 二元 | 函数属性（内部） | -- | GA |
| ClickHouse | 二元 | `is_deterministic` 内部标志 | -- | GA |
| Trino | 二元 | `DETERMINISTIC` / `NOT DETERMINISTIC` | -- | 419+ |
| Spark SQL | 二元 | UDF 的 `deterministic` 属性 | true | 1.x+ |
| Databricks | 二元 | UDF `deterministic` 标志 | true | GA |
| Hive | 二元 | `@UDFType(deterministic = true/false)` | true | 0.7+ |
| Flink SQL | 二元 | `isDeterministic()` 方法 | true | 1.x+ |
| CockroachDB | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 22.2+ |
| YugabyteDB | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 2.0+ |
| Greenplum | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 全版本 |
| TimescaleDB | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 继承 PG |
| SAP HANA | 二元 | `DETERMINISTIC` / 非关键字 | 非确定性 | 1.0+ |
| Teradata | 二元 | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | V2R5+ |
| Vertica | 二元 | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 7.0+ |
| Informix | 二元 | `VARIANT` / `NOT VARIANT`（反向） | VARIANT | 9.x+ |
| Firebird | 二元 | `DETERMINISTIC` | 非确定性 | 2.1+ |
| H2 | 二元 | `DETERMINISTIC` | 非确定性 | 1.0+ |
| HSQLDB | 二元 | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 2.x+ |
| Derby | 二元 | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 10.5+ |
| TiDB | 二元 | `DETERMINISTIC` / `NOT DETERMINISTIC` | NOT DETERMINISTIC | 兼容 MySQL |
| OceanBase | 二元 | `DETERMINISTIC`（MySQL/Oracle 模式） | 兼容源 | 3.0+ |
| Doris | 二元 | 函数注册时声明 | -- | 1.2+ |
| StarRocks | 二元 | 函数注册时声明 | -- | 2.2+ |
| TDengine | 二元 | UDF 属性 | -- | 3.0+ |
| MaxCompute | 二元 | `@Deterministic` 注解 | -- | GA |
| Hologres | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 兼容 PG |
| Impala | 二元 | UDF 创建时声明 | -- | 2.0+ |
| PolarDB | 继承兼容源 | 兼容 PG / MySQL | -- | 兼容源 |
| openGauss | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | 1.0+ |
| KingbaseES | 三级（PG 兼容） | `IMMUTABLE` / `STABLE` / `VOLATILE` | VOLATILE | V8+ |
| 达梦 (DM) | 二元 | `DETERMINISTIC` | 非确定性 | V7+ |
| TDSQL | 继承 MySQL | `DETERMINISTIC` | 兼容源 | 兼容源 |
| Synapse | 三状态推断 | 继承 SQL Server | 非确定性 | GA |
| Amazon Athena | 二元 | 继承 Trino | -- | GA |
| Materialize | 二元 | 内部标志 | -- | GA |
| RisingWave | 二元 | 内部标志 | -- | GA |
| Firebolt | 二元 | 内部推断 | -- | GA |
| SingleStore (MemSQL) | 二元 | `DETERMINISTIC` | NOT DETERMINISTIC | 7.x+ |
| YellowBrick | 继承 PG | 三级 | VOLATILE | GA |

> 注：部分引擎（如 DuckDB、ClickHouse）不向用户暴露波动性声明关键字，内部为内置函数维护静态标志表；用户 UDF 通常被当作非确定性处理。

### 并行安全标志

| 引擎 | 并行标志模型 | 关键字 | 默认值 | 版本 |
|------|------------|--------|--------|------|
| PostgreSQL | 三级 | `PARALLEL SAFE` / `PARALLEL RESTRICTED` / `PARALLEL UNSAFE` | UNSAFE | 9.6+ (2016) |
| Oracle | 二元 | `PARALLEL_ENABLE` / `NOT PARALLEL_ENABLE` | 非并行 | 8i+ |
| SQL Server | 推断 | 优化器根据副作用和 UDF 类型推断 | -- | -- |
| DB2 | 二元 | `ALLOW PARALLEL` / `DISALLOW PARALLEL` | ALLOW | 7.0+ |
| Snowflake | 自动 | 平台自动处理 | -- | -- |
| BigQuery | 自动 | 平台自动处理 | -- | -- |
| Redshift | 自动 | 与 UDF 类型相关 | -- | -- |
| Spark SQL | 推断 | 基于 `deterministic` 标志 | -- | -- |
| Teradata | 二元 | `PARALLEL` 声明 | -- | V2R5+ |
| Vertica | 自动 | UDF 注册时声明 fenced/unfenced | fenced | 7.0+ |
| Greenplum | 三级 | 继承 PG | -- | 全版本 |
| CockroachDB | 继承 PG | 三级（但分布式执行有额外限制） | -- | 22.2+ |

### SQL-data 访问等级（SQL:1999）

| 引擎 | 支持 `NO SQL` | `CONTAINS SQL` | `READS SQL DATA` | `MODIFIES SQL DATA` | 默认值 |
|------|:-:|:-:|:-:|:-:|-------|
| PostgreSQL | 否（通过 STABLE/VOLATILE 暗示） | -- | -- | -- | -- |
| MySQL | 是 | 是 | 是 | 是 | CONTAINS SQL |
| MariaDB | 是 | 是 | 是 | 是 | CONTAINS SQL |
| Oracle | 否（依赖 PRAGMA）* | -- | -- | -- | -- |
| SQL Server | 否（推断） | -- | -- | -- | -- |
| DB2 | 是 | 是 | 是 | 是 | READS SQL DATA |
| Snowflake | 否 | -- | -- | -- | -- |
| BigQuery | 否 | -- | -- | -- | -- |
| Teradata | 是 | 是 | 是 | 是 | CONTAINS SQL |
| SAP HANA | 否 | -- | -- | -- | -- |
| Trino | 否（SQL routine 仅支持 `CONTAINS SQL` 语义） | -- | -- | -- | -- |
| Firebird | 否 | -- | -- | -- | -- |
| H2 | 是 | 是 | 是 | 是 | CONTAINS SQL |
| HSQLDB | 是 | 是 | 是 | 是 | CONTAINS SQL |
| Derby | 是 | 是 | 是 | 是 | CONTAINS SQL |
| CockroachDB | 否（忽略关键字） | -- | -- | -- | -- |

> * Oracle 通过 `PRAGMA RESTRICT_REFERENCES` 声明函数的 `WNDS`（写无数据库状态）、`RNDS`（读无数据库状态）、`WNPS`（写无包状态）、`RNPS`（读无包状态）纯度等级。

### 典型引擎的波动性分类对照

| 内置函数 | PostgreSQL | Oracle | SQL Server | MySQL | 说明 |
|---------|-----------|--------|-----------|-------|------|
| `abs(x)` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | 纯数学 |
| `lower(s)` / `upper(s)` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | 取决于区域设置；PG 中为 IMMUTABLE（依赖 collation） |
| `now()` / `current_timestamp` | STABLE | 非确定性 | 非确定性 | NOT DETERMINISTIC | 同事务内稳定 |
| `clock_timestamp()` | VOLATILE | -- | -- | -- | 每次调用不同（PG 特有） |
| `random()` / `rand()` | VOLATILE | 非确定性 | 非确定性 | NOT DETERMINISTIC | 必须每次调用不同 |
| `nextval('seq')` | VOLATILE | 非确定性 | 非确定性 | -- | 有副作用 |
| `current_user` | STABLE | DETERMINISTIC | 非确定性 | DETERMINISTIC | 会话内不变 |
| `current_setting('tz')` | STABLE | -- | -- | -- | 会话内不变 |
| `length(s)` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | -- |
| `to_char(ts, fmt)` | STABLE | 非确定性 | -- | -- | 依赖会话 timezone/lc_time |
| `json_extract` | IMMUTABLE | DETERMINISTIC | IsDeterministic=1 | DETERMINISTIC | -- |
| `uuid_generate_v4()` | VOLATILE | -- | 非确定性 | -- | 随机性 |
| `pg_backend_pid()` | STABLE | -- | -- | -- | 会话标识 |

## 各引擎波动性模型详解

### PostgreSQL 三级模型（2002 年引入）

PostgreSQL 7.2（2002 年）引入 IMMUTABLE / STABLE / VOLATILE 三级分类，是业界最细致的模型：

```sql
-- IMMUTABLE: 相同输入永远相同输出，完全无副作用
-- 示例：纯数学、字符串操作、JSON 解析
CREATE FUNCTION my_hash(text) RETURNS bigint
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT hashtext($1)::bigint $$;

-- STABLE: 同一次查询（快照）内稳定，跨快照可能变化
-- 示例：now()、current_user、依赖会话设置的函数
CREATE FUNCTION current_tz_now() RETURNS timestamptz
  LANGUAGE sql STABLE PARALLEL SAFE
  AS $$ SELECT now() AT TIME ZONE current_setting('TimeZone') $$;

-- VOLATILE: 每次调用可能不同
-- 示例：random()、clock_timestamp()、nextval()、有副作用的函数
CREATE FUNCTION log_and_return(int) RETURNS int
  LANGUAGE plpgsql VOLATILE
  AS $$ BEGIN INSERT INTO audit_log VALUES ($1); RETURN $1; END; $$;

-- 默认是 VOLATILE（保守），手动指定可提升性能
```

#### PostgreSQL 波动性对比

| 特性 | IMMUTABLE | STABLE | VOLATILE |
|------|-----------|--------|----------|
| 常量参数下计划时折叠 | 是 | 否 | 否 |
| 同一次执行内多行 CSE | 是 | 是 | 否 |
| 作为索引表达式 | 是 | 否 | 否 |
| 作为生成列表达式 | 是 | 否 | 否 |
| 作为分区键表达式 | 是 | 否 | 否 |
| `CHECK` 约束中 | 是 | 否 | 否 |
| 在 `WHERE` 中随 planning 求值 | 是（若参数也是常量） | 否 | 否 |
| 在 `LIKE 'foo' \|\| f(x)` 推断 prefix 索引 | 是 | 否 | 否 |
| 用作 FDW push-down 条件 | 是 | 看 FDW 实现 | 否 |

#### PARALLEL SAFE/RESTRICTED/UNSAFE（9.6+）

PostgreSQL 9.6（2016）引入独立于波动性的并行安全标签：

```sql
CREATE FUNCTION safe_calc(int) RETURNS int
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT $1 * 2 $$;

-- PARALLEL SAFE: 可在 worker 中安全执行
-- PARALLEL RESTRICTED: 必须在 leader 中执行（但其他算子可并行）
-- PARALLEL UNSAFE: 整个查询退化为串行

-- 默认是 PARALLEL UNSAFE，用户显式声明才能启用并行
```

并行安全性与波动性**正交**：
- IMMUTABLE 函数通常是 PARALLEL SAFE（但不绝对——访问线程全局状态的 IMMUTABLE C 函数可能 UNSAFE）
- VOLATILE 函数也可以是 PARALLEL SAFE（如 `random()`，尽管结果不同但多 worker 执行不会错）
- 但访问临时表、修改 session state、写 WAL 的函数必须 UNSAFE

#### 常见 PostgreSQL 内置函数的分类

```sql
-- 查询波动性
SELECT proname, provolatile, proparallel
FROM pg_proc
WHERE proname IN ('now', 'clock_timestamp', 'random', 'abs', 'lower');

--    proname      | provolatile | proparallel
-- ----------------+-------------+-------------
--  now            | s (stable)  | s (safe)
--  clock_timestamp| v (volatile)| s (safe)
--  random         | v (volatile)| r (restricted)
--  abs            | i (immutable)| s (safe)
--  lower          | i (immutable)| s (safe)
```

注意 `random()` 是 PARALLEL RESTRICTED——多 worker 共享的伪随机序列会导致重复。

### Oracle：DETERMINISTIC 关键字 + PARALLEL_ENABLE

Oracle 采用 SQL:1999 的二元分类，用 `DETERMINISTIC` 关键字声明：

```sql
CREATE OR REPLACE FUNCTION tax_rate(p_region VARCHAR2)
  RETURN NUMBER DETERMINISTIC
IS
BEGIN
  CASE p_region
    WHEN 'US' THEN RETURN 0.08;
    WHEN 'EU' THEN RETURN 0.20;
    ELSE RETURN 0.10;
  END CASE;
END;
/

-- 作为函数索引（Function-Based Index）的基础
CREATE INDEX idx_tax ON invoices(tax_rate(region_code));

-- 并行执行允许
CREATE OR REPLACE FUNCTION expensive_calc(n NUMBER)
  RETURN NUMBER DETERMINISTIC PARALLEL_ENABLE
IS BEGIN RETURN n * n; END;
/
```

Oracle 的特殊机制：

#### `PRAGMA RESTRICT_REFERENCES`（11g 之前）
```sql
CREATE OR REPLACE PACKAGE pure_pkg AS
  FUNCTION pure_fn(x NUMBER) RETURN NUMBER;
  PRAGMA RESTRICT_REFERENCES(pure_fn, WNDS, WNPS, RNDS, RNPS);
  -- WNDS: Writes No Database State
  -- WNPS: Writes No Package State
  -- RNDS: Reads No Database State
  -- RNPS: Reads No Package State
END;
/
```
11g 起优化器自动推断函数纯度，RESTRICT_REFERENCES 仅用于向后兼容。

#### Result Cache（11g+）
```sql
CREATE OR REPLACE FUNCTION expensive_lookup(id NUMBER)
  RETURN VARCHAR2 DETERMINISTIC RESULT_CACHE
IS
  v_result VARCHAR2(100);
BEGIN
  SELECT name INTO v_result FROM lookup_table WHERE id = id;
  RETURN v_result;
END;
/
```
DETERMINISTIC + RESULT_CACHE 组合：结果在 SGA 中缓存，跨会话共享。

#### PARALLEL_ENABLE 的限制
```sql
-- PARALLEL_ENABLE 子句支持分区策略
CREATE OR REPLACE FUNCTION my_tab_fn(cur SYS_REFCURSOR)
  RETURN my_tab PIPELINED
  PARALLEL_ENABLE(PARTITION cur BY HASH (id))
  CLUSTER cur BY (customer_id)
IS ...
```

### SQL Server：WITH SCHEMABINDING 与 isdeterministic

SQL Server 没有直接的 DETERMINISTIC 声明，而是通过一组规则自动推断：

```sql
-- 没有 WITH SCHEMABINDING 的 UDF 默认被视为非确定性
CREATE FUNCTION dbo.square(@x INT)
RETURNS INT
AS BEGIN RETURN @x * @x; END;
-- OBJECTPROPERTY(OBJECT_ID('dbo.square'), 'IsDeterministic') = 0

-- WITH SCHEMABINDING 后再按规则判断
CREATE FUNCTION dbo.square(@x INT)
RETURNS INT
WITH SCHEMABINDING
AS BEGIN RETURN @x * @x; END;
-- IsDeterministic = 1（因为函数体纯）

-- 查询确定性属性
SELECT
  OBJECTPROPERTY(OBJECT_ID('dbo.square'), 'IsDeterministic') AS is_deterministic,
  OBJECTPROPERTY(OBJECT_ID('dbo.square'), 'IsPrecise') AS is_precise,
  OBJECTPROPERTY(OBJECT_ID('dbo.square'), 'IsSystemVerified') AS is_verified;
```

#### SQL Server 的确定性判定规则

UDF 被视为确定性当且仅当：
1. 声明了 `WITH SCHEMABINDING`
2. 不调用任何非确定性内置函数（NEWID, RAND, GETDATE, CURRENT_TIMESTAMP 等）
3. 不访问扩展存储过程
4. 不引用带 `SCHEMABINDING` 的其他非确定性函数
5. 函数体不使用非确定性字段（如 TIMESTAMP 列）

#### 用于持久化计算列和索引
```sql
-- 确定性的 UDF 可作为持久化计算列
CREATE TABLE orders (
  id INT PRIMARY KEY,
  amount DECIMAL(10,2),
  tax_amount AS (dbo.calc_tax(amount)) PERSISTED
);

-- 可对计算列建索引
CREATE INDEX idx_tax ON orders(tax_amount);
-- 只有当 calc_tax 是确定性 + 精确 + schema-bound 时才允许
```

#### IsPrecise 属性
另一个维度：某函数是否精确（不依赖浮点近似）。持久化计算列必须同时满足 `IsDeterministic=1` 且 `IsPrecise=1`。

### MySQL / MariaDB：DETERMINISTIC + SQL-data 访问等级

MySQL 严格遵循 SQL:1999 的正交组合：

```sql
DELIMITER //

-- 纯函数
CREATE FUNCTION my_square(x INT)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
  RETURN x * x;
END //

-- 读表的确定性函数
CREATE FUNCTION get_tax(region VARCHAR(2))
RETURNS DECIMAL(5,4)
DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE rate DECIMAL(5,4);
  SELECT tax_rate INTO rate FROM regions WHERE code = region;
  RETURN rate;
END //

-- 非确定性函数（含 NOW()）
CREATE FUNCTION age_days(birthdate DATE)
RETURNS INT
NOT DETERMINISTIC
NO SQL
BEGIN
  RETURN DATEDIFF(CURRENT_DATE, birthdate);
END //

DELIMITER ;
```

#### 二进制日志的特殊限制（Binlog）

MySQL 的 statement-based binlog 要求确定性：

```sql
-- 如果 binlog_format = STATEMENT
-- 任何 NOT DETERMINISTIC + MODIFIES SQL DATA 的函数都会被拒绝
-- 除非显式设置 log_bin_trust_function_creators = 1
```

这是 MySQL 特有的限制，其他引擎没有。

#### 默认值陷阱
```sql
-- 如果不显式声明，MySQL 默认 NOT DETERMINISTIC
-- 导致函数索引、某些优化失效
-- 最佳实践：总是显式声明 DETERMINISTIC（如果确实如此）
```

### DB2：严格的 SQL:1999 实现

```sql
CREATE FUNCTION calc_bonus(salary DECIMAL(10,2))
  RETURNS DECIMAL(10,2)
  LANGUAGE SQL
  DETERMINISTIC
  NO EXTERNAL ACTION
  CONTAINS SQL
  RETURN salary * 0.15;

-- 完整的修饰符列表：
--   DETERMINISTIC / NOT DETERMINISTIC
--   EXTERNAL ACTION / NO EXTERNAL ACTION
--   NO SQL / CONTAINS SQL / READS SQL DATA / MODIFIES SQL DATA
--   ALLOW PARALLEL / DISALLOW PARALLEL
--   FENCED / NOT FENCED（外部函数隔离）
```

#### EXTERNAL ACTION 的独特语义
DB2 引入了 `EXTERNAL ACTION` 概念：函数是否对外部世界（非 DB2 数据库之外）有影响——如发送邮件、写文件、调用 Web 服务。

```sql
-- NO EXTERNAL ACTION：无外部影响
--   优化器可以消除重复调用、改变调用次数
CREATE FUNCTION pure_calc() ... NO EXTERNAL ACTION ...;

-- EXTERNAL ACTION：有外部影响
--   优化器必须保证每次必要调用都执行
CREATE FUNCTION send_email(addr VARCHAR(100)) ... EXTERNAL ACTION ...;
```

### Spark SQL：deterministic 标志

Spark 的 UDF 通过 `deterministic()` 方法声明：

```scala
// Scala UDF API
import org.apache.spark.sql.expressions.UserDefinedFunction

val myUDF = udf((x: Int) => x * 2).asNonDeterministic()
// 或
val deterministicUDF = udf((x: Int) => x * 2)  // 默认 deterministic
```

```python
# PySpark
from pyspark.sql.functions import udf

my_udf = udf(lambda x: x * 2)
my_udf.asNondeterministic()  # 显式标记为非确定性
```

确定性 UDF 允许的优化：
1. **谓词下推**：可以下推到数据源
2. **常量折叠**：常量参数时计划时求值
3. **CSE**：同一表达式消除
4. **投影裁剪**：Spark Catalyst 的优化

非确定性 UDF 的影响：
- 不会被下推到数据源
- 不做 CSE
- 自适应查询执行（AQE）的某些优化被禁用

### Hive：@UDFType 注解

```java
import org.apache.hadoop.hive.ql.exec.UDF;
import org.apache.hadoop.hive.ql.udf.UDFType;

@UDFType(deterministic = true, stateful = false)
public class MyHashUDF extends UDF {
    public long evaluate(String input) {
        return input.hashCode();
    }
}

@UDFType(deterministic = false)
public class RandomUDF extends UDF {
    public double evaluate() {
        return Math.random();
    }
}
```

- `deterministic`：是否确定性
- `stateful`：是否有状态（如跨行累加）。stateful UDF 强制禁用某些优化

### ClickHouse：内置函数的 `is_deterministic`

ClickHouse 不向用户暴露波动性声明，但内部对每个函数维护标志：

```sql
-- 查询系统表
SELECT name, is_deterministic
FROM system.functions
WHERE name IN ('rand', 'now', 'plus', 'length')
ORDER BY name;

-- 返回:
-- length   | 1
-- now      | 0
-- plus     | 1
-- rand     | 0
```

is_deterministic = 0 的函数阻止：
- 物化视图的自动刷新
- `final` 的优化
- 某些子查询重写

### SQLite：SQLITE_DETERMINISTIC 标志

SQLite 通过 C API 注册 UDF 时传递标志位：

```c
sqlite3_create_function_v2(
    db, "my_hash", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
    NULL, my_hash_impl, NULL, NULL, NULL);
```

确定性 UDF 可用于：
- 表达式索引（`CREATE INDEX ... ON t(my_hash(col))`）
- 生成列（Generated Columns）
- `CHECK` 约束
- 部分索引的 `WHERE` 表达式

### Snowflake：IMMUTABLE / VOLATILE 二级

```sql
CREATE OR REPLACE FUNCTION add_tax(amt NUMBER)
RETURNS NUMBER
LANGUAGE SQL
IMMUTABLE
AS $$
  amt * 1.10
$$;

CREATE OR REPLACE FUNCTION current_rate()
RETURNS NUMBER
LANGUAGE SQL
VOLATILE
AS $$
  (SELECT rate FROM rates ORDER BY ts DESC LIMIT 1)
$$;
```

- IMMUTABLE：结果对查询优化器是可缓存的
- VOLATILE：每次调用都执行
- 默认 VOLATILE

### BigQuery：隐式推断

BigQuery 没有显式的 DETERMINISTIC 声明，但根据函数体语义自动分类：

- 引用 `CURRENT_TIMESTAMP()`, `RAND()`, `GENERATE_UUID()` 等 → 非确定性
- 引用外部资源（如 `NET.HOST()`）→ 非确定性
- 纯计算 → 确定性

影响：
- 物化视图只支持确定性表达式
- 查询缓存对非确定性查询禁用

### Trino / Presto：`DETERMINISTIC` 关键字（SQL routine）

Trino 419+（2023）引入了 SQL routine，支持 DETERMINISTIC：

```sql
CREATE FUNCTION add_tax(amt DOUBLE)
RETURNS DOUBLE
LANGUAGE SQL
DETERMINISTIC
RETURN amt * 1.10;
```

Trino 内部函数也有 `deterministic` 标志，通过 `@ScalarFunction(deterministic = true)` 注解声明。

### Flink SQL：流处理的特殊挑战

```java
public class MyUDF extends ScalarFunction {
    @Override
    public boolean isDeterministic() {
        return true;  // 默认 true
    }

    public Integer eval(Integer x) {
        return x * 2;
    }
}
```

流处理中非确定性函数的影响更大：
- **状态恢复**：非确定性函数在 checkpoint 恢复后可能产生与之前不同的结果
- **幂等性**：Exactly-once 语义要求非确定性函数必须谨慎处理
- **反应式计算**：非确定性函数阻止某些增量计算优化

### Teradata：DETERMINISTIC + PARALLEL 声明

```sql
REPLACE FUNCTION calc_hash(input VARCHAR(100))
RETURNS VARCHAR(32)
LANGUAGE SQL
DETERMINISTIC
CONTAINS SQL
RETURN SUBSTR(hashrow(input), 1, 32);
```

### Vertica：PG 风格三级

```sql
CREATE FUNCTION add_tax(amt NUMERIC) RETURN NUMERIC
AS BEGIN
  RETURN amt * 1.10;
END;
-- 默认 VOLATILE
-- 可声明 IMMUTABLE / STABLE / VOLATILE
```

### SAP HANA：DETERMINISTIC 关键字

```sql
CREATE FUNCTION calc_bonus(salary DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
AS BEGIN
  RETURN :salary * 0.15;
END;
```

## IMMUTABLE 函数与索引

### 函数索引（Functional / Expression Index）

几乎所有支持表达式索引的引擎都要求 IMMUTABLE/DETERMINISTIC。

```sql
-- PostgreSQL：要求 IMMUTABLE
CREATE INDEX idx_lower ON users (lower(email));
-- 因为 lower() 是 IMMUTABLE，PG 允许建索引

-- 尝试用 STABLE 函数（now()）建索引 → 错误
CREATE INDEX idx_bad ON events (make_timestamp(year, month, day));
-- 如果 make_timestamp 依赖 session timezone 而非 IMMUTABLE 的 collation, 会失败

-- 正确做法：用 IMMUTABLE collation
CREATE INDEX idx_email_ci ON users (lower(email) COLLATE "C");
```

### 为什么要求 IMMUTABLE

```
索引 B+ 树存的是函数输出 → 键
如果函数输出不稳定：
  1. INSERT 时计算 = A，存入索引
  2. 第二天同样输入，查询时函数输出 = B
  3. 索引中找不到，或找到错误的行
  4. 一致性崩溃
```

因此索引键必须依赖 IMMUTABLE 函数 + IMMUTABLE collation。

### 常见陷阱

```sql
-- 陷阱 1：依赖会话 timezone
-- PostgreSQL 中 to_char(ts, 'YYYY-MM-DD') 是 STABLE
-- 因为 session TimeZone 变化会导致不同输出
CREATE INDEX idx_day ON events (to_char(ts, 'YYYY-MM-DD'));  -- 会报错

-- 解决方案：显式时区
CREATE INDEX idx_day ON events ((ts AT TIME ZONE 'UTC')::date);

-- 陷阱 2：LC_COLLATE 影响字符串比较
CREATE INDEX idx_name ON users (lower(name));
-- 不同 locale 下 lower('İ')（土耳其 I）结果不同

-- 解决方案：指定 "C" collation
CREATE INDEX idx_name ON users (lower(name COLLATE "C"));

-- 陷阱 3：自定义函数默认 VOLATILE
CREATE FUNCTION normalize(text) RETURNS text AS
$$ SELECT lower(trim($1)) $$ LANGUAGE sql;  -- 默认 VOLATILE

CREATE INDEX idx_norm ON users (normalize(email));  -- 失败

-- 解决方案：显式声明
CREATE OR REPLACE FUNCTION normalize(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT lower(trim($1)) $$;

CREATE INDEX idx_norm ON users (normalize(email));  -- 成功
```

### Oracle：函数索引的限制

Oracle 的函数索引（Function-Based Index, FBI）要求：
1. 函数必须声明为 DETERMINISTIC
2. 函数所属 schema 的 `QUERY REWRITE` 权限
3. 会话参数 `QUERY_REWRITE_ENABLED = TRUE`, `QUERY_REWRITE_INTEGRITY = TRUSTED`

```sql
CREATE INDEX idx_upper_name ON employees(UPPER(last_name));
-- UPPER 是内置 DETERMINISTIC 函数

-- 自定义函数必须显式声明
CREATE OR REPLACE FUNCTION clean_name(n VARCHAR2)
  RETURN VARCHAR2 DETERMINISTIC
IS BEGIN RETURN UPPER(TRIM(n)); END;
/

CREATE INDEX idx_clean ON employees(clean_name(last_name));
```

### SQL Server：持久化计算列 + 索引

```sql
ALTER TABLE Orders ADD tax_amount AS (dbo.calc_tax(amount)) PERSISTED;
CREATE INDEX idx_tax ON Orders(tax_amount);
-- 要求 calc_tax 必须：
-- 1. WITH SCHEMABINDING
-- 2. IsDeterministic = 1
-- 3. IsPrecise = 1
-- 4. UDF 不访问任何表（或仅访问同 schema 的 schema-bound 表）
```

### MySQL：函数索引（8.0.13+）

```sql
-- 8.0.13 前：只能对普通列建索引
-- 8.0.13+：支持函数索引（内部转换为隐藏生成列）
CREATE TABLE users (
  id INT PRIMARY KEY,
  email VARCHAR(255),
  INDEX idx_lower ((LOWER(email)))
);

-- 限制：表达式必须 DETERMINISTIC
-- NOW()、RAND()、UUID() 等不允许
```

## 并行查询与波动性

### PostgreSQL 并行规则

9.6（2016）引入并行查询后，PostgreSQL 严格区分波动性和并行安全性：

```sql
-- 并行安全的 IMMUTABLE 函数：最理想
CREATE FUNCTION safe_hash(x int) RETURNS int
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT x * 31 $$;

-- 并行查询会让所有 worker 执行这个函数
-- 多个 worker 独立运行不会互相影响

-- 并行限制的 STABLE 函数
CREATE FUNCTION restricted_stable() RETURNS int
  LANGUAGE sql STABLE PARALLEL RESTRICTED
  AS $$ SELECT count(*) FROM some_session_state $$;

-- 并行不安全的 VOLATILE 函数
CREATE FUNCTION unsafe_logger(msg text) RETURNS void
  LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE
  AS $$ BEGIN INSERT INTO log VALUES (msg); END; $$;
-- 若出现在查询中，整个查询退化为串行
```

### 不可并行的情况

- 修改数据（INSERT/UPDATE/DELETE 子查询）
- 访问临时表
- 修改会话状态（SET）
- 写入 WAL（某些扩展功能）
- 调用某些系统函数（如 `pg_advisory_lock`）

### 其他引擎的并行规则

**Oracle**：
```sql
CREATE OR REPLACE FUNCTION safe_calc(x NUMBER)
  RETURN NUMBER DETERMINISTIC PARALLEL_ENABLE
IS BEGIN RETURN x * 2; END;
/
```
没有 PARALLEL_ENABLE 的 PL/SQL 函数默认强制串行执行，即使查询本身可并行。

**Spark / Databricks**：分布式执行天然并行。非确定性 UDF 在 worker 上执行结果可能每次不同，但 Spark 不阻止这种行为，由用户负责。

**Snowflake / BigQuery**：托管服务，平台自动处理并行安全，用户无需关心。

## 计划缓存与波动性

### PostgreSQL prepared plan

```sql
PREPARE my_query AS
  SELECT * FROM orders WHERE status = $1 AND amount > calc_min_amount($2);

-- 如果 calc_min_amount 是 IMMUTABLE，结果可在计划中预先求值
-- 如果是 STABLE，每次执行求值一次，但计划可以固化（generic plan）
-- 如果是 VOLATILE，每次行都求值，且可能阻止 generic plan
```

### Oracle cursor cache

```sql
-- DETERMINISTIC + RESULT_CACHE：结果存在 SGA 中
CREATE OR REPLACE FUNCTION fn_cached(id NUMBER)
  RETURN VARCHAR2 DETERMINISTIC RESULT_CACHE
IS
  v VARCHAR2(100);
BEGIN
  SELECT name INTO v FROM items WHERE item_id = id;
  RETURN v;
END;
/

-- 后续相同参数调用直接返回缓存，无需重新执行函数体
```

### SQL Server plan cache

```sql
-- 持久化计算列 + 索引需要确定性 UDF
-- 查询计划中的 UDF 调用成本评估依赖 IsDeterministic

-- 非确定性 UDF 的查询在某些版本（尤其是 2017 之前）
-- 可能导致查询串行化（cardinality estimation 出错）
```

### MySQL query cache（已废弃）

MySQL 5.6/5.7 的 query cache 对 `NOT DETERMINISTIC` 函数完全禁用缓存。8.0 移除了 query cache 功能，改用 InnoDB buffer pool 的细粒度缓存。

### 结果缓存与波动性的关系

| 引擎 | 结果缓存机制 | 对波动性的要求 |
|------|-------------|--------------|
| PostgreSQL | Memoize 算子（14+） | IMMUTABLE/STABLE |
| Oracle | RESULT_CACHE | DETERMINISTIC |
| MySQL | InnoDB buffer pool | 不区分波动性 |
| SQL Server | Persisted Computed Column | IsDeterministic=1 |
| Snowflake | 自动结果缓存 | IMMUTABLE + 查询条件完全相同 |
| BigQuery | 自动结果缓存（24 小时） | DETERMINISTIC |
| ClickHouse | Query result cache (23.1+) | is_deterministic=1 |

## 物化视图与波动性

物化视图的增量刷新依赖确定性：

```sql
-- PostgreSQL
CREATE MATERIALIZED VIEW order_summary AS
SELECT DATE_TRUNC('day', ts) AS day, SUM(amount) AS total
FROM orders GROUP BY 1;
-- DATE_TRUNC 是 IMMUTABLE → 可以安全刷新

CREATE MATERIALIZED VIEW bad_mv AS
SELECT id, now() - ts AS age FROM events;
-- now() 是 STABLE → 每次 REFRESH 结果不同
-- 不能做增量刷新
```

### Oracle Materialized View

Oracle 的 FAST REFRESH（增量刷新）严格要求：
1. 所有涉及的 UDF 必须 DETERMINISTIC
2. 不含 `SYSDATE`、`CURRENT_TIMESTAMP`、`ROWNUM`、`LEVEL`、`USER`
3. 不含非确定性的分析函数

### SQL Server Indexed View

```sql
CREATE VIEW dbo.order_summary
WITH SCHEMABINDING
AS
SELECT customer_id, COUNT_BIG(*) AS cnt, SUM(amount) AS total
FROM dbo.orders
GROUP BY customer_id;

CREATE UNIQUE CLUSTERED INDEX idx_cv ON dbo.order_summary(customer_id);
-- 要求所有 UDF IsDeterministic = 1 且 IsPrecise = 1
```

### BigQuery / Snowflake Materialized View

- BigQuery：仅支持确定性查询。非确定性函数（CURRENT_TIMESTAMP、RAND）直接禁止
- Snowflake：增量维护，不允许非确定性函数

## 波动性与分布式执行

分布式引擎中，波动性的影响被放大：

```
分布式场景下非确定性函数的风险：
  1. 不同分片 worker 执行 → 每个 worker 结果不同
  2. 重试（retry）或重算 → 结果与原始不一致
  3. Exactly-once 语义冲突
  4. 全局排序时破坏一致性

建议：
  - 避免在分布式查询的 WHERE 谓词中使用 VOLATILE 函数
  - 用 CTE 在 leader 预计算 VOLATILE 部分
  - 流处理中非确定性 UDF 必须幂等
```

### CockroachDB 分布式规则

```sql
-- CockroachDB 继承 PG 的三级模型
-- 但分布式执行层面有额外限制：
--   VOLATILE 函数 + SQL 副作用 → 强制 gateway 节点执行
--   IMMUTABLE 函数 → 可以下推到任何节点
--   STABLE 函数 → 当前事务快照下可下推
```

### Spark / Databricks 的非确定性 UDF 处理

```python
# 非确定性 UDF 阻止的优化：
# 1. 谓词下推到 Parquet/ORC reader
# 2. 动态分区裁剪
# 3. 列裁剪（如果 UDF 访问多列）
# 4. 代码生成（Whole-stage codegen 回退到解释模式）
```

## 常见设计陷阱

### 陷阱 1：默认值太保守或太激进

```sql
-- PostgreSQL: 默认 VOLATILE（保守）
-- 结果：用户忘记声明 → 错失优化机会

-- MySQL: 默认 NOT DETERMINISTIC（保守）
-- 但 statement-based binlog 严格阻止

-- Spark: 默认 deterministic=true（激进）
-- 用户写了 lambda: return random.random() 但忘记标记 → 静默产生错误结果
```

### 陷阱 2：依赖会话状态

```sql
-- 错误：将以下函数标为 IMMUTABLE
CREATE FUNCTION my_now()
  RETURNS timestamptz
  LANGUAGE sql IMMUTABLE  -- 错！应为 STABLE
  AS $$ SELECT now() $$;

CREATE INDEX idx_bad ON events (my_now());
-- 运行时 now() 变化，索引失效
```

### 陷阱 3：collation 的隐藏影响

```sql
-- lower() 在 PG 中是 IMMUTABLE 但依赖 collation
-- 不同数据库的 collation 设置不同 → 结果可能不同

-- 解决：显式 collation
CREATE INDEX idx_lower ON users (lower(email COLLATE "C"));
```

### 陷阱 4：数学函数的浮点精度

```sql
-- SQRT、POW、EXP 在不同 CPU / 编译器下可能有微小差异
-- 严格来说不是 100% "确定性"
-- 但多数引擎将其归为 IMMUTABLE/DETERMINISTIC
-- SQL Server 用 IsPrecise 属性区分
```

### 陷阱 5：JSON 解析的平台依赖

```sql
-- JSON_EXTRACT 是否 DETERMINISTIC？
-- MySQL: DETERMINISTIC
-- PostgreSQL: IMMUTABLE
-- 但 JSON 键顺序在不同存储格式下可能不同
-- 应用层依赖顺序的代码会踩坑
```

### 陷阱 6：dictionary / lookup 函数

```sql
-- PostgreSQL 内置类型转换 cast_to_regclass 是 STABLE
-- 因为依赖 search_path 和 pg_class 内容

-- 如果用户自定义类似函数
CREATE FUNCTION code_to_name(code text) RETURNS text
  LANGUAGE sql IMMUTABLE  -- 错！读表的函数不能 IMMUTABLE
  AS $$ SELECT name FROM codes WHERE c = code $$;
-- 正确：STABLE（同快照内稳定）
```

## 对引擎开发者的实现建议

### 1. 建立内置函数的波动性目录

```
核心数据结构：函数属性表
{
  function_id: UUID,
  name: String,
  volatility: enum { IMMUTABLE, STABLE, VOLATILE },
  parallel_safety: enum { SAFE, RESTRICTED, UNSAFE },
  sql_data_access: enum { NONE, CONTAINS, READS, MODIFIES },
  strict: bool,             // NULL 输入是否直接返回 NULL
  leakproof: bool,          // 是否泄漏输入信息（RLS）
  is_precise: bool,         // 是否精确（无浮点近似）
  external_action: bool,    // 是否影响 DB 外部
}

实现要点：
- 所有内置函数必须显式标注，不能留空
- 新增函数时必须评估波动性，纳入审查流程
- 用户可通过 pg_proc / information_schema 查询
```

### 2. 优化器中利用波动性的点

```
1. 常量折叠（Constant Folding）
   IF fn IS IMMUTABLE AND all_args_constant:
       result = evaluate(fn, args)
       replace_expr(result)

2. 公共子表达式消除（CSE）
   IF fn IS IMMUTABLE or STABLE:
       cache_key = (fn, args_hash)
       IF cache.has(key): reuse
       ELSE: execute + cache

3. 谓词下推
   IF fn IS IMMUTABLE:
       push down to scan / storage layer
   ELSE IF fn IS STABLE and can_see_snapshot:
       push to scan with snapshot context
   ELSE: keep at higher level

4. 索引表达式匹配
   IF expr uses only IMMUTABLE fns + columns:
       check functional index match

5. 分区裁剪
   IF partition pruning expr is IMMUTABLE:
       evaluate at planning time

6. Materialize / Memoize
   IF fn IS IMMUTABLE or STABLE:
       insert Memoize node in plan
       key = args, value = result
```

### 3. 并行执行的安全检查

```
对每个查询计划节点，递归检查：
1. 若节点含有 PARALLEL UNSAFE 函数 → 整个查询串行化
2. 若节点含有 PARALLEL RESTRICTED 函数 → 该节点不能在 worker 执行
3. 若节点仅含 PARALLEL SAFE 函数 → 可自由并行

实现要点：
- 用户 UDF 默认应为 PARALLEL UNSAFE（保守）
- 内置函数的标注需要仔细评估：访问全局缓存、修改会话状态均为 UNSAFE
- 提供工具（如 EXPLAIN）让用户理解为何不能并行
```

### 4. 索引与生成列的校验

```
CREATE INDEX idx ON t(expr) 或
CREATE TABLE t (c GENERATED ALWAYS AS (expr)) 时：

递归检查 expr：
1. 若 expr 只含常量、列引用、IMMUTABLE 函数 → 允许
2. 若 expr 含 STABLE 函数 → 拒绝，报告具体函数名
3. 若 expr 含 VOLATILE 函数 → 拒绝
4. 隐藏陷阱：依赖 COLLATE 的函数如 lower() 必须同时检查
   所用 collation 是否也 IMMUTABLE（"C" locale 是，其他 locale 不是）
```

### 5. 物化视图刷新策略

```
CREATE MATERIALIZED VIEW mv AS query;

检查 query 中的函数：
- 全 IMMUTABLE → 可以增量刷新
- 含 STABLE → 只能全量刷新（每次 refresh 可能返回不同结果）
- 含 VOLATILE → 拒绝创建或警告用户

REFRESH 策略：
- IMMUTABLE-only MV: 可通过 delta log 增量合并
- 其他: REFRESH 必须重新执行全量查询
```

### 6. 用户 UDF 的自动推断

```
对用户创建的 SQL 函数（LANGUAGE SQL），可以自动推断：
  - 函数体分析 AST
  - 若所有引用都是 IMMUTABLE 函数 → 可以推断为 IMMUTABLE
  - 若有 STABLE 引用 → 降级为 STABLE
  - 若有 VOLATILE 引用 → VOLATILE

然而 PostgreSQL 不做自动推断，让用户显式声明：
  优点：语义明确，兼容性好
  缺点：用户容易忘记声明，错失优化

Trino 做自动推断（对 SQL routine）
SQL Server 对 schema-bound UDF 做自动推断
这是两条不同的设计哲学。
```

### 7. 分布式场景的额外考虑

```
分布式 OLAP 引擎的额外限制：
1. VOLATILE 函数在 gateway（coordinator）节点预计算，结果广播到 worker
   - PostgreSQL Citus: 对 VOLATILE 函数生成 extern params
   - Spark: 非确定性 UDF 会被标记为需要在 driver 执行

2. 多次执行同一查询（重试、重算）时：
   - IMMUTABLE: 无影响
   - STABLE: 取决于快照管理（MVCC）
   - VOLATILE: 结果可能不同 → 需要应用层处理

3. 副本一致性：
   - 如果主副本执行了 VOLATILE 函数，结果必须广播而非让副本独立重算
```

### 8. 流处理引擎的特殊要求

```
流处理对波动性的要求比批处理更严格：
1. 状态恢复（Checkpoint）：
   - 重放 input 时，非确定性 UDF 结果不一致 → 状态损坏
   - 解决：记录 UDF 输出到 log，而非重新计算

2. Exactly-once 语义：
   - 非确定性 UDF + 重试 → 幂等性破坏
   - 解决：幂等 sink、TransactionId 配对

3. 窗口函数与时间：
   - 使用 now() 而非 event_time → 结果不可重放
   - 强制使用 event_time 作为确定性时钟

Flink、Spark Structured Streaming 都有专门文档告诫用户。
```

### 9. 向量化执行的优化

```
向量化引擎（DuckDB、Velox、Arrow）中：
1. IMMUTABLE 函数 → 整个 batch 一次计算，SIMD 友好
2. STABLE 函数 → 同 batch 内缓存一次
3. VOLATILE 函数 → 必须每行独立调用，破坏向量化

实现要点：
- 内置函数尽量实现为 SIMD-friendly 的 IMMUTABLE 变体
- 如 lower_ascii() 为 IMMUTABLE + SIMD，lower() 因依赖 locale 只能标量
```

### 10. 测试与验证

```
单元测试：
- 对每个内置函数，验证声明的波动性与实际行为一致
- 包括：同参数多次调用、跨事务、跨会话、跨节点的输出一致性

集成测试：
- 确认 IMMUTABLE 函数能建索引
- 确认 STABLE 函数在同快照下稳定
- 确认 VOLATILE 函数每次调用都执行（无 CSE 消除）

性能测试：
- 对比显式声明 vs 默认（VOLATILE）的计划差异
- 衡量并行查询的加速比（PARALLEL SAFE vs UNSAFE）
```

## 关键发现

### 1. 三级模型的价值被低估

PostgreSQL 2002 年引入的 IMMUTABLE/STABLE/VOLATILE 三级模型是最完整的。但二十多年过去，大多数引擎仍然停留在 SQL:1999 的二元模型，错过了 STABLE 级别带来的"同事务内稳定"的优化机会。

### 2. 默认值的保守与激进

各引擎默认值的差异反映了设计哲学的分歧：
- PG/MySQL/Oracle：默认保守（VOLATILE / NOT DETERMINISTIC），以安全为先
- Spark：默认激进（deterministic=true），以性能为先但风险大
- SQL Server：推断式，需要 SCHEMABINDING 才启用优化

用户对默认值的误解是最大的 bug 来源之一。

### 3. 波动性与并行安全正交

PostgreSQL 是唯一把两者清晰分开的主流引擎。许多引擎把"可并行"与"确定性"混为一谈，导致：
- IMMUTABLE 的 C 函数可能并不是并行安全的（共享全局状态）
- VOLATILE 的 random() 可能是并行安全的（只是结果不同而已）

### 4. Binlog 与波动性的耦合

MySQL statement-based binlog 严格要求 DETERMINISTIC，是少数将"日志复制"与"波动性"直接绑定的设计。这让 MySQL 的 DETERMINISTIC 声明成为强制性而非建议性的——其他引擎都只是优化提示。

### 5. 索引表达式要求 IMMUTABLE，但 collation 常被忽略

几乎所有引擎都要求索引表达式是 IMMUTABLE，但往往忽略 collation 的依赖关系。`lower(name)` 在美式 locale 和土耳其 locale 下对 'İ' 返回不同结果，严格来说它只在固定 collation 下才是 IMMUTABLE。最佳实践是显式指定 "C" locale。

### 6. 流处理放大了非确定性的风险

批处理中 VOLATILE 的代价是"失去优化机会"，而在流处理中它可能直接破坏 exactly-once 语义。Flink、Spark Structured Streaming 都专门警告用户避免非确定性 UDF。

### 7. 向量化执行对 IMMUTABLE 的依赖

DuckDB、Velox 等向量化引擎在 batch 级别的优化严重依赖 IMMUTABLE。STABLE 可以退化为 "per-batch 缓存"，但 VOLATILE 直接打破了向量化的基本假设，往往强制回退到标量执行。

### 8. 自动推断 vs 用户声明

- **用户声明**（PostgreSQL、Oracle、MySQL 主流派）：语义明确，但用户易忘
- **自动推断**（Trino、SQL Server schema-bound UDF、Snowflake）：用户友好，但复杂函数体推断困难
- **混合**（SQL Server 的 SCHEMABINDING + 自动）：可控性与自动化的平衡

SQL Server 的设计——用户声明 `WITH SCHEMABINDING` 开启推断，推断结果通过 `OBJECTPROPERTY()` 可查——是被低估的好设计。

### 9. RESULT_CACHE 让 DETERMINISTIC 值更多

Oracle 的 `RESULT_CACHE` 把 DETERMINISTIC 函数的输出缓存在 SGA 共享内存中，跨会话复用。这让"声明 DETERMINISTIC"不只是"允许优化"，而是"主动获得缓存"。PostgreSQL 的 Memoize 算子（14+）是类似思路但仅限单查询内。

### 10. 分布式执行让波动性更关键

分布式引擎（CockroachDB、TiDB、Spark、Trino）中，波动性决定了：
- 函数能否下推到存储层（IMMUTABLE 可以）
- 能否在 worker 并行执行（需要 PARALLEL SAFE）
- 重试时结果是否一致（VOLATILE 不一致）
- 副本间如何同步（VOLATILE 必须由 leader 执行并广播）

这些限制在单机引擎中往往被忽略，但在分布式下每一个都是正确性问题而不仅是性能问题。

### 11. 波动性是"契约"而非"标签"

用户声明 DETERMINISTIC 后，引擎相信并按此优化。如果函数体实际上不确定（如读取外部 API），引擎不会校验，只会产生错误结果。这是一个"契约式"设计——类似 Rust 的 `unsafe` 代码块，责任在用户。

## 总结对比矩阵

### 综合能力对比

| 能力 | PostgreSQL | Oracle | SQL Server | MySQL | DB2 | Snowflake | Spark | Trino |
|------|:---------:|:------:|:---------:|:-----:|:---:|:--------:|:-----:|:-----:|
| 三级波动性 | 是 | -- | -- | -- | -- | -- | -- | -- |
| 并行安全标志 | 是 | 部分 | 推断 | -- | 是 | 自动 | 推断 | -- |
| SQL-data 访问等级 | -- | PRAGMA | -- | 是 | 是 | -- | -- | -- |
| 函数索引 | 是 | 是 | 是（PC+索引） | 8.0.13+ | 是 | -- | -- | -- |
| 持久化计算列 | -- | -- | 是 | 是 | 是 | -- | -- | -- |
| 物化视图增量 | 是 | 是 | 是 | -- | 是 | 是 | -- | -- |
| Result cache | Memoize | RESULT_CACHE | -- | -- | -- | 是 | -- | -- |
| 自动推断 | -- | 部分 | schema-bound | -- | -- | -- | -- | 是 |
| Binlog 依赖 | -- | -- | -- | 严格 | -- | -- | -- | -- |

### 对使用者的建议

| 场景 | 建议 |
|------|------|
| 写 UDF | 总是显式声明波动性，不要依赖默认值 |
| 使用 now() / random() | 理解其波动性，不要在索引和分区键中使用 |
| 建函数索引 | 确保函数是 IMMUTABLE，显式指定 collation |
| 并行查询加速 | 标注 PARALLEL SAFE，或拆分查询让 UNSAFE 部分最小 |
| 物化视图 | 使用 IMMUTABLE 函数，避免 now() / user_id() |
| 分布式查询 | 避免在谓词中使用 VOLATILE 函数 |
| 流处理 | 严格禁用非确定性 UDF，或确保幂等 |
| 性能调优 | `EXPLAIN` 中如果看到函数被重复调用，检查其波动性 |

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-4, SQL/PSM, Section 11.60 "function characteristics"
- PostgreSQL: [Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html)
- PostgreSQL: [Parallel Safety](https://www.postgresql.org/docs/current/parallel-safety.html)
- Oracle: [DETERMINISTIC clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/DETERMINISTIC-clause.html)
- Oracle: [PARALLEL_ENABLE clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/PARALLEL_ENABLE-clause.html)
- Oracle: [RESULT_CACHE clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/RESULT_CACHE-clause.html)
- SQL Server: [Deterministic and Nondeterministic Functions](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/deterministic-and-nondeterministic-functions)
- SQL Server: [SCHEMABINDING](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql)
- MySQL: [CREATE FUNCTION Statement](https://dev.mysql.com/doc/refman/8.0/en/create-procedure.html)
- MySQL: [Stored Programs and Views](https://dev.mysql.com/doc/refman/8.0/en/stored-programs-logging.html)
- DB2: [CREATE FUNCTION (SQL scalar, table, or row)](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-function-sql-scalar-table-row)
- Snowflake: [CREATE FUNCTION - IMMUTABLE / VOLATILE](https://docs.snowflake.com/en/sql-reference/sql/create-function)
- BigQuery: [User-defined functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/user-defined-functions)
- Spark SQL: [UDF deterministic](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/sql/expressions/UserDefinedFunction.html)
- Hive: [UDFType annotation](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF)
- Flink: [User-Defined Functions](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/functions/udfs/)
- SQLite: [Create Or Redefine SQL Functions](https://www.sqlite.org/c3ref/create_function.html)
- Trino: [Routines and SQL routines](https://trino.io/docs/current/routines.html)
- Selinger, P.G., et al. "Access Path Selection in a Relational Database Management System" (1979), SIGMOD
