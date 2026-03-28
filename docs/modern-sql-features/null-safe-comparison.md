# NULL 安全比较

将 NULL 视为可比较的值——SQL:1999 标准的 IS [NOT] DISTINCT FROM 与各引擎的独特实现。

## 支持矩阵

| 引擎 | 语法 | 版本 | 备注 |
|------|------|------|------|
| PostgreSQL | `IS NOT DISTINCT FROM` / `IS DISTINCT FROM` | 8.0+ | **完全符合标准** |
| MySQL | `<=>` | 3.23+ | **最早实现**，独有运算符 |
| MariaDB | `<=>` + `IS NOT DISTINCT FROM` | `<=>` 早期; 标准语法 10.3+ | 两种都支持 |
| BigQuery | `IS NOT DISTINCT FROM` | GA | 也可用 `IFNULL` 变通 |
| DuckDB | `IS NOT DISTINCT FROM` | 0.3.0+ | 完整支持 |
| SQLite | `IS` / `IS NOT` | 3.0+ | 非标准但语义等价 |
| Trino | `IS NOT DISTINCT FROM` | 早期 | 完整支持 |
| Spark SQL | `<=>` + `IS NOT DISTINCT FROM` | 2.0+ | 两种都支持 |
| SQL Server | 不直接支持 | - | 需手写复合条件 |
| Oracle | 不直接支持 | - | 用 `DECODE` 或 `NVL` 变通 |
| ClickHouse | 不直接支持 | - | 用 `isNotDistinctFrom` 函数 (23.2+) |
| Snowflake | `IS NOT DISTINCT FROM` + `EQUAL_NULL` | GA | 两种都支持 |
| DB2 | `IS NOT DISTINCT FROM` | 9.7+ | 标准语法 |

## SQL 标准定义

SQL:1999 (SQL3) 引入了 `IS [NOT] DISTINCT FROM` 谓词，定义如下：

```
A IS NOT DISTINCT FROM B:
  - 如果 A 和 B 都是 NULL，返回 TRUE
  - 如果 A 和 B 只有一个是 NULL，返回 FALSE
  - 如果 A 和 B 都不是 NULL，返回 A = B 的结果

A IS DISTINCT FROM B:
  - IS NOT DISTINCT FROM 的取反
```

这与普通 `=` 的关键区别：

| 表达式 | `A = B` | `A IS NOT DISTINCT FROM B` |
|--------|---------|---------------------------|
| `1 = 1` | TRUE | TRUE |
| `1 = 2` | FALSE | FALSE |
| `NULL = NULL` | **UNKNOWN** | **TRUE** |
| `1 = NULL` | **UNKNOWN** | **FALSE** |
| `NULL = 1` | **UNKNOWN** | **FALSE** |

## 设计动机

### 问题: NULL 在比较中的"黑洞效应"

SQL 的三值逻辑（TRUE / FALSE / UNKNOWN）导致 NULL 在等值比较中产生意外行为：

```sql
-- 问题 1: WHERE 过滤中 NULL 行被静默丢弃
SELECT * FROM users WHERE status = 'active';   -- NULL status 的行被排除
SELECT * FROM users WHERE status != 'active';  -- NULL status 的行仍然被排除!

-- 问题 2: JOIN 中 NULL 不匹配 NULL
SELECT a.*, b.*
FROM table_a a
JOIN table_b b ON a.key = b.key;
-- 如果 a.key = NULL 且 b.key = NULL，不会 JOIN 上!

-- 问题 3: CASE WHEN 的 NULL 陷阱
CASE status
    WHEN 'active' THEN 1
    WHEN 'inactive' THEN 2
    WHEN NULL THEN 3         -- 永远不会匹配! CASE 用 = 比较
    ELSE 0
END
```

### 传统解决方案: 冗长且易错

```sql
-- 手写 NULL 安全比较（SQL Server / Oracle 中常见）
WHERE (a.key = b.key OR (a.key IS NULL AND b.key IS NULL))

-- 更多列时更痛苦
WHERE (a.col1 = b.col1 OR (a.col1 IS NULL AND b.col1 IS NULL))
  AND (a.col2 = b.col2 OR (a.col2 IS NULL AND b.col2 IS NULL))
  AND (a.col3 = b.col3 OR (a.col3 IS NULL AND b.col3 IS NULL))
```

### IS NOT DISTINCT FROM 的解决方案

```sql
-- 简洁、正确、可读
WHERE a.key IS NOT DISTINCT FROM b.key

-- 多列
WHERE a.col1 IS NOT DISTINCT FROM b.col1
  AND a.col2 IS NOT DISTINCT FROM b.col2
  AND a.col3 IS NOT DISTINCT FROM b.col3
```

## 语法对比

### PostgreSQL / BigQuery / DuckDB / Trino（标准语法）

```sql
-- 基本用法
SELECT * FROM t WHERE col IS NOT DISTINCT FROM 42;
SELECT * FROM t WHERE col IS NOT DISTINCT FROM NULL;  -- 等同于 col IS NULL

-- JOIN 条件
SELECT a.*, b.*
FROM table_a a
JOIN table_b b ON a.key IS NOT DISTINCT FROM b.key;

-- IS DISTINCT FROM (取反)
SELECT * FROM t WHERE col IS DISTINCT FROM 42;
-- 等同于: col != 42 OR col IS NULL

-- 在 UPSERT 变更检测中
INSERT INTO target (id, name, status)
VALUES (1, 'Alice', 'active')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name, status = EXCLUDED.status
WHERE target.name IS DISTINCT FROM EXCLUDED.name
   OR target.status IS DISTINCT FROM EXCLUDED.status;
-- 只在数据实际变化时才更新
```

### MySQL / MariaDB（<=> 运算符）

```sql
-- MySQL 独有的 <=> 运算符（NULL-safe equal）
SELECT * FROM t WHERE col <=> 42;
SELECT * FROM t WHERE col <=> NULL;  -- 等同于 col IS NULL

-- JOIN 条件
SELECT a.*, b.*
FROM table_a a
JOIN table_b b ON a.key <=> b.key;

-- 取反: 没有对应的 "NOT <=>" 运算符
-- 需要用 NOT (a <=> b)
SELECT * FROM t WHERE NOT (col <=> 42);

-- MariaDB 10.3+ 也支持标准语法
SELECT * FROM t WHERE col IS NOT DISTINCT FROM 42;  -- MariaDB only
```

### SQLite（IS / IS NOT）

```sql
-- SQLite 扩展了 IS 的语义: col IS 42 等同于 IS NOT DISTINCT FROM
SELECT * FROM t WHERE col IS 42;      -- NULL-safe equals
SELECT * FROM t WHERE col IS NOT 42;  -- NULL-safe not equals
-- 注意: 非标准 SQL，标准 IS 只用于 IS NULL / IS NOT NULL
```

### SQL Server / Oracle（无直接支持）

```sql
-- SQL Server 方案 1: 复合条件（最可靠）
WHERE (a.key = b.key OR (a.key IS NULL AND b.key IS NULL));
-- SQL Server 方案 2: INTERSECT 技巧（正确但晦涩）
WHERE EXISTS (SELECT a.key INTERSECT SELECT b.key);
-- 方案 3: ISNULL/NVL 哨兵值（有陷阱: 哨兵值可能是合法数据!）
WHERE ISNULL(a.key, -999) = ISNULL(b.key, -999);

-- Oracle 特有: DECODE（NULL-safe，无哨兵值问题）
WHERE DECODE(a.key, b.key, 1, 0) = 1;
```

### Snowflake

```sql
SELECT * FROM t WHERE col IS NOT DISTINCT FROM 42;
SELECT * FROM t WHERE EQUAL_NULL(col, 42);    -- 内置函数形式
```

## 典型用例

1. JOIN 条件中的 NULL 匹配

```sql
-- 需求: 两个来源的数据匹配，包括 NULL 维度
-- 例如维度表中 region = NULL 表示"全球"，需要与事实表匹配
SELECT f.*, d.region_name
FROM fact_table f
JOIN dim_region d ON f.region_id IS NOT DISTINCT FROM d.region_id;
```

2. UPSERT 的变更检测

```sql
-- 只在数据真正变化时更新（包括 NULL 变为非 NULL 或反之）
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED AND (
    t.name IS DISTINCT FROM s.name
    OR t.email IS DISTINCT FROM s.email
    OR t.phone IS DISTINCT FROM s.phone
)
THEN UPDATE SET t.name = s.name, t.email = s.email, t.phone = s.phone;
```

3. 分组去重中的 NULL 一致性

```sql
-- 找出"值相同的行对"（包括两个都是 NULL 的情况）
SELECT a.id AS id_a, b.id AS id_b
FROM records a
JOIN records b ON a.id < b.id
    AND a.col1 IS NOT DISTINCT FROM b.col1
    AND a.col2 IS NOT DISTINCT FROM b.col2;
```

## 对引擎开发者的实现建议

1. 语法解析

`IS [NOT] DISTINCT FROM` 是一个比较谓词，解析为二元表达式：

```
comparison_predicate:
    expr '=' expr
  | expr '<>' expr
  | expr IS [NOT] DISTINCT FROM expr    -- 新增
  | ...
```

AST 中表示为 `IsDistinctFrom(left, right)` 和 `IsNotDistinctFrom(left, right)` 节点。

如果要兼容 MySQL 的 `<=>` 运算符，在 lexer 中增加 `<=>` token，解析时转换为 `IsNotDistinctFrom` 即可。

2. 求值语义

```
IsNotDistinctFrom(a, b):
    if a IS NULL AND b IS NULL: return TRUE
    if a IS NULL OR b IS NULL: return FALSE
    return a = b

IsDistinctFrom(a, b):
    return NOT IsNotDistinctFrom(a, b)
```

注意: 这个函数本身**不会返回 NULL**——结果永远是 TRUE 或 FALSE。这与普通比较运算符不同（普通 `=` 可以返回 UNKNOWN/NULL）。

3. 优化器支持

IS NOT DISTINCT FROM 在优化器中需要特殊处理：

**索引使用**: `col IS NOT DISTINCT FROM 42` 可以像 `col = 42` 一样利用索引。但 `col IS NOT DISTINCT FROM NULL` 只有在索引包含 NULL 值时才能利用。

**JOIN 优化**: Hash Join 和 Sort-Merge Join 的探测函数需要支持 NULL-safe 比较模式。这意味着 hash 函数需要为 NULL 生成一个确定的 hash 值（通常用 0 或特殊常量）。

**谓词简化**: `col IS NOT DISTINCT FROM NULL` 可以简化为 `col IS NULL`。

4. 与 INTERSECT/EXCEPT 的关系

集合操作中的行比较隐式使用 IS NOT DISTINCT FROM 语义。如果引擎已经实现了集合操作中的 NULL 相等比较，可以复用相同的比较器。

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999 Section 8.12 `<distinct predicate>`
- PostgreSQL: [Comparison Operators](https://www.postgresql.org/docs/current/functions-comparison.html)
- MySQL: [NULL-Safe Equal](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_equal-to)
- BigQuery: [IS DISTINCT FROM](https://cloud.google.com/bigquery/docs/reference/standard-sql/operators#is_distinct)
- Snowflake: [EQUAL_NULL](https://docs.snowflake.com/en/sql-reference/functions/equal_null)
