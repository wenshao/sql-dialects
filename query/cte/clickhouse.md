# ClickHouse: CTE（公共表表达式）

> 参考资料:
> - [1] ClickHouse SQL Reference - WITH Clause
>   https://clickhouse.com/docs/en/sql-reference/statements/select/with


## 1. 基本 CTE（ClickHouse 的 WITH 有两种用法）


### 1.1 标准 CTE（子查询别名）

```sql
WITH active_users AS (
    SELECT id, username FROM users WHERE status = 1
)
SELECT u.username, count() AS order_count
FROM active_users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

```

多个 CTE

```sql
WITH
    active AS (SELECT * FROM users WHERE status = 1),
    recent AS (SELECT * FROM orders WHERE order_date >= '2024-01-01')
SELECT a.username, sum(r.amount)
FROM active a JOIN recent r ON a.id = r.user_id
GROUP BY a.username;

```

### 1.2 表达式别名（ClickHouse 独有用法）

```sql
WITH toDate('2024-01-01') AS start_date
SELECT * FROM orders WHERE order_date >= start_date;

WITH 100 AS min_amount
SELECT * FROM orders WHERE amount > min_amount;

```

 设计分析:
   ClickHouse 的 WITH 可以定义标量表达式（不仅仅是子查询）。
   这在复杂计算中很有用: 一次定义，多处引用，避免重复。
   其他数据库不支持这种"表达式 CTE"。

## 2. 递归 CTE（20.5+，实验性）


ClickHouse 20.5+ 支持递归 CTE（需要设置）:
SET allow_experimental_analyzer = 1;

数列生成（ClickHouse 有更好的替代: numbers()）
WITH RECURSIVE cnt AS (
SELECT 1 AS x
UNION ALL
SELECT x + 1 FROM cnt WHERE x < 100
)
SELECT x FROM cnt;

推荐替代: numbers() 表函数（ClickHouse 专用，性能更好）

```sql
SELECT number + 1 AS x FROM numbers(100);

```

 层级查询
 WITH RECURSIVE org AS (
     SELECT id, name, manager_id, 0 AS depth FROM employees WHERE manager_id = 0
     UNION ALL
     SELECT e.id, e.name, e.manager_id, o.depth + 1
     FROM employees e JOIN org o ON e.manager_id = o.id
 )
 SELECT * FROM org;

 设计分析:
   递归 CTE 在 ClickHouse 中是实验性的，因为:
   (a) OLAP 场景很少需要递归查询
   (b) ClickHouse 的查询模型是批量扫描，递归逐行处理违反设计
   (c) numbers()/arrayJoin() 等表函数覆盖了大部分序列生成需求

## 3. ClickHouse 的 CTE 替代方案


### 3.1 子查询（最常用）

```sql
SELECT u.username, stats.total_amount
FROM users u
JOIN (
    SELECT user_id, sum(amount) AS total_amount
    FROM orders GROUP BY user_id
) stats ON u.id = stats.user_id;

```

### 3.2 表函数替代递归 CTE

```sql
SELECT number FROM numbers(100);                      -- 0-99 序列
SELECT toDate('2024-01-01') + number AS d FROM numbers(31); -- 日期序列
SELECT arrayJoin([1, 2, 3, 4, 5]) AS x;              -- 数组展开

```

### 3.3 字典查找替代 CTE JOIN

```sql
SELECT dictGet('user_dict', 'username', user_id) AS username, amount
FROM orders;

```

## 4. CTE 的物化行为


 ClickHouse 的 CTE 默认是内联的（不物化）:
 每次引用 CTE 都会重新执行子查询。
 如果 CTE 被多次引用，考虑使用临时表替代:
 CREATE TEMPORARY TABLE tmp AS SELECT ...;
 然后在多个查询中引用 tmp。

## 5. 对比与引擎开发者启示

ClickHouse CTE 的设计:
(1) 表达式 CTE → 标量值别名（独有）
(2) 默认内联 → 不物化（与 PostgreSQL 12+ 类似）
(3) 递归 CTE → 实验性（OLAP 很少需要）
(4) numbers()/arrayJoin() → 替代递归序列生成

对引擎开发者的启示:
OLAP 引擎可以延迟实现递归 CTE:
表函数（numbers/range）覆盖了大部分序列生成需求。
表达式别名（WITH x AS scalar_expr）是低成本高价值的功能。

