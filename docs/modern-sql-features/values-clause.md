# VALUES 作为独立查询

SQL 标准定义的行构造器——不依赖任何表，直接从字面量构造结果集。

## 支持矩阵

| 引擎 | 语法 | 版本 | 备注 |
|------|------|------|------|
| PostgreSQL | `VALUES (1, 'a'), (2, 'b')` | 8.2+ | **最完整实现**，可独立查询或作为 FROM 子句 |
| SQL Server | `VALUES (1, 'a'), (2, 'b')` | 2008+ | FROM 中必须加别名和列名 |
| MySQL | `VALUES ROW(1, 'a'), ROW(2, 'b')` | 8.0.19+ | 需要 `ROW()` 包装，列名为 `column_0`, `column_1` |
| MariaDB | `VALUES (1, 'a'), (2, 'b')` | 10.3+ | 语法接近标准 |
| SQLite | `VALUES (1, 'a'), (2, 'b')` | 3.8.3+ | 可独立使用 |
| DuckDB | `VALUES (1, 'a'), (2, 'b')` | 0.1+ | 完整支持 |
| Oracle | 不支持独立 VALUES | - | 需 `SELECT ... FROM DUAL UNION ALL` |
| Trino | `VALUES (1, 'a'), (2, 'b')` | 早期 | 完整支持 |
| ClickHouse | `VALUES` 仅用于 `INSERT` | - | 查询需用 `SELECT ... UNION ALL` |
| BigQuery | 不支持独立 VALUES | - | 需 `UNNEST` 或子查询 |
| Snowflake | `VALUES (1, 'a'), (2, 'b')` | GA | 需在 FROM 中使用 |
| Hive / Spark SQL | `VALUES (1, 'a'), (2, 'b')` | Hive 1.2+ / Spark 2.0+ | 需在 FROM 中配合别名 |

## SQL 标准定义

SQL:1999 标准定义了 `<table value constructor>`，允许 VALUES 在任何需要"表表达式"的地方使用：

```sql
-- SQL 标准语法
VALUES (1, 'Alice', 90),
       (2, 'Bob',   85),
       (3, 'Carol', 92);
```

这是一个独立的查询，返回 3 行 3 列的结果集。VALUES 本质上是一个匿名的行集合构造器，语义等同于多个 `SELECT ... UNION ALL`。

## 设计动机

### 问题: 构造临时数据集太繁琐

在没有 VALUES 子句时，构造一个小的临时数据集需要：

```sql
-- 传统写法: UNION ALL 堆叠
SELECT 1 AS id, 'Active'   AS status UNION ALL
SELECT 2,       'Inactive'           UNION ALL
SELECT 3,       'Pending';
```

这种写法有几个问题：

1. **冗余**: 每行都要写 `SELECT ... UNION ALL`
2. **列名不一致**: 只有第一个 SELECT 的列名有效，后续的列名被忽略
3. **可读性差**: 数据和语法结构混杂在一起
4. **Oracle 更痛苦**: 每个 SELECT 都要加 `FROM DUAL`

### VALUES 的解决方案

```sql
-- VALUES 写法: 简洁直观
VALUES (1, 'Active'),
       (2, 'Inactive'),
       (3, 'Pending');
```

数据与结构分离，像构造一个"内联表"。

## 语法对比

### PostgreSQL（最完整）

PostgreSQL 的 VALUES 可以在几乎所有需要表的地方使用：

```sql
-- 1. 独立查询
VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol');
-- 列名默认为 column1, column2, ...

-- 2. 作为 FROM 子句（推荐: 可指定列名）
SELECT id, name
FROM (VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol')) AS t(id, name);

-- 3. 在 INSERT 中（最常见用法）
INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob');

-- 4. 在 CTE 中
WITH status_map(code, label) AS (
    VALUES (1, 'Active'), (2, 'Inactive'), (3, 'Pending')
)
SELECT o.order_id, s.label
FROM orders o
JOIN status_map s ON o.status_code = s.code;

-- 5. 在 JOIN 中直接使用
SELECT e.emp_name, d.dept_name
FROM employees e
JOIN (VALUES (10, 'Engineering'), (20, 'Sales')) AS d(dept_id, dept_name)
    ON e.dept_id = d.dept_id;

-- 6. 配合 LATERAL
SELECT v.id, generate_series(1, v.n)
FROM (VALUES (1, 3), (2, 5)) AS v(id, n);
```

### SQL Server

```sql
-- FROM 中使用 VALUES 必须加别名和列定义
SELECT id, name
FROM (VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol')) AS t(id, name);

-- 在 MERGE 的 USING 中非常实用
MERGE INTO target_table AS t
USING (VALUES (1, 'Alice', 90), (2, 'Bob', 85)) AS s(id, name, score)
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.score = s.score
WHEN NOT MATCHED THEN INSERT (id, name, score) VALUES (s.id, s.name, s.score);

-- 不支持独立的 VALUES 查询（不在 FROM 中）
-- VALUES (1, 'a'), (2, 'b');  -- 错误!
```

### MySQL 8.0.19+

```sql
-- MySQL 的 VALUES 需要 ROW() 关键字
VALUES ROW(1, 'Alice'), ROW(2, 'Bob'), ROW(3, 'Carol');
-- 列名默认为 column_0, column_1（注意从 0 开始，与 PostgreSQL 不同）

-- 在 FROM 中使用
SELECT t.column_0 AS id, t.column_1 AS name
FROM (VALUES ROW(1, 'Alice'), ROW(2, 'Bob')) AS t;

-- 配合 INSERT（传统语法，不需要 ROW）
INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob');
-- 注意: INSERT 中的 VALUES 和独立查询的 VALUES ROW 语法不统一!
```

### Oracle（不支持独立 VALUES）

```sql
-- Oracle 必须用 DUAL + UNION ALL 模拟
SELECT 1 AS id, 'Alice' AS name FROM DUAL UNION ALL
SELECT 2,       'Bob'            FROM DUAL UNION ALL
SELECT 3,       'Carol'          FROM DUAL;

-- 或用集合构造器（PL/SQL 范畴）
-- 在纯 SQL 中没有行构造器语法

-- 在 INSERT 中可以用 INSERT ALL
INSERT ALL
    INTO users (id, name) VALUES (1, 'Alice')
    INTO users (id, name) VALUES (2, 'Bob')
    INTO users (id, name) VALUES (3, 'Carol')
SELECT 1 FROM DUAL;
```

### BigQuery

```sql
-- BigQuery 没有 VALUES 作为独立查询
-- 需要用 UNNEST + STRUCT 数组
SELECT *
FROM UNNEST([
    STRUCT(1 AS id, 'Alice' AS name),
    STRUCT(2 AS id, 'Bob'   AS name),
    STRUCT(3 AS id, 'Carol' AS name)
]);

-- 或用 UNION ALL
SELECT 1 AS id, 'Alice' AS name UNION ALL
SELECT 2,       'Bob'           UNION ALL
SELECT 3,       'Carol';
```

### DuckDB

```sql
-- DuckDB 完整支持标准 VALUES，且支持类型推导
VALUES (1, 'Alice', DATE '2024-01-01'),
       (2, 'Bob',   DATE '2024-06-15');

-- 在 FROM 中使用
SELECT * FROM (VALUES (1, 'a'), (2, 'b')) AS t(id, code);

-- 支持在 CTE 中使用，且列名推导友好
WITH data AS (VALUES (1, 100.5), (2, 200.3))
SELECT column0 AS id, column1 AS amount FROM data;
```

## 典型用例

### 1. 内联测试数据

```sql
-- 快速构造测试数据，无需创建临时表
SELECT t.id, t.name, t.score,
       RANK() OVER (ORDER BY t.score DESC) AS rank
FROM (VALUES
    (1, 'Alice', 92),
    (2, 'Bob',   85),
    (3, 'Carol', 92),
    (4, 'Dave',  78)
) AS t(id, name, score);
```

### 2. 小型查找表（替代 CASE WHEN）

```sql
-- 传统: CASE WHEN 映射
SELECT order_id,
    CASE status
        WHEN 1 THEN 'Pending'
        WHEN 2 THEN 'Shipped'
        WHEN 3 THEN 'Delivered'
    END AS status_label
FROM orders;

-- VALUES 查找表: 更清晰，尤其映射项很多时
SELECT o.order_id, m.label AS status_label
FROM orders o
JOIN (VALUES (1, 'Pending'), (2, 'Shipped'), (3, 'Delivered'))
    AS m(code, label) ON o.status = m.code;
```

### 3. 参数化批量操作

```sql
-- 批量 UPDATE: 用 VALUES 构造参数，JOIN 更新
UPDATE products p
SET price = v.new_price
FROM (VALUES
    (101, 29.99),
    (102, 49.99),
    (103, 19.99)
) AS v(product_id, new_price)
WHERE p.product_id = v.product_id;

-- 批量 UPSERT（PostgreSQL）
INSERT INTO config (key, value)
VALUES ('timeout', '30'), ('retries', '3'), ('debug', 'false')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

### 4. 生成序列（简易方式）

```sql
-- 当 generate_series 不可用时，用 VALUES 构造小序列
SELECT d.day_offset, CURRENT_DATE + d.day_offset AS date
FROM (VALUES (0), (1), (2), (3), (4), (5), (6)) AS d(day_offset);
```

## 对引擎开发者的实现建议

### 1. 语法解析

VALUES 子句在语法中的位置需要同时支持两种场景：

```
-- 作为独立查询语句
query_statement:
    select_statement
  | values_statement              -- 新增

-- 作为表表达式（FROM 子句中的子查询）
table_ref:
    table_name
  | '(' select_statement ')' [AS alias]
  | '(' values_statement ')' AS alias(col_list)    -- 新增
```

VALUES 语句的产生式：

```
values_statement:
    VALUES row_list

row_list:
    row_constructor (',' row_constructor)*

row_constructor:
    '(' expr (',' expr)* ')'
  | ROW '(' expr (',' expr)* ')'     -- MySQL 兼容
```

### 2. 类型推导

VALUES 的列类型需要从所有行的对应位置推导。规则：

1. 检查所有行在同一列位置的表达式类型
2. 找到这些类型的公共超类型（common supertype）
3. 所有行在该列位置的值都隐式转换到超类型

```sql
-- 类型推导示例
VALUES (1, 'hello'),       -- INT, VARCHAR
       (2.5, NULL);        -- DECIMAL, NULL
-- 结果类型: DECIMAL, VARCHAR
```

### 3. 执行计划

VALUES 在执行计划中映射为一个 `ValuesNode`（常量表扫描）：

```
ValuesScan
  rows: [(1, 'Alice'), (2, 'Bob'), (3, 'Carol')]
  output_types: [INT, VARCHAR]
```

这是最简单的执行节点之一——不需要磁盘 IO，直接从内存中产出行。

### 4. 优化器考量

- **常量折叠**: VALUES 中的表达式可以在编译期求值
- **行数估计**: 行数是确定的（VALUES 中的行数），有利于优化器选择 JOIN 策略
- **内联展开**: 小的 VALUES 可以被优化器内联到 JOIN 条件中（类似 IN 列表展开）
- **大 VALUES 优化**: 当行数很大时（如 1000+ 行），考虑构建临时的内存哈希表

### 5. MySQL ROW() 兼容

如果引擎想同时兼容标准 VALUES 和 MySQL 的 `VALUES ROW()` 语法：

- 解析器同时接受 `(expr_list)` 和 `ROW(expr_list)` 两种行构造形式
- 列名默认规则需要可配置（`column1` 还是 `column_0`）

## 设计讨论: 为什么 Oracle 和 ClickHouse 不支持

Oracle 历史上使用 `DUAL` 作为单行虚拟表，结合 `UNION ALL` 可以构造任意行集。虽然更繁琐，但 Oracle 认为这已经满足需求，且引入新语法会增加 parser 复杂度。

ClickHouse 的 `VALUES` 关键字仅用于 INSERT 语句中指定数据格式。ClickHouse 的查询模型更偏向于列存引擎优化，独立的行构造器使用场景不多。

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999 Section 7.2 `<table value constructor>`
- PostgreSQL: [VALUES](https://www.postgresql.org/docs/current/sql-values.html)
- SQL Server: [Table Value Constructor](https://learn.microsoft.com/en-us/sql/t-sql/queries/table-value-constructor-transact-sql)
- MySQL: [VALUES Statement](https://dev.mysql.com/doc/refman/8.0/en/values.html)
- DuckDB: [VALUES clause](https://duckdb.org/docs/sql/query_syntax/values)
