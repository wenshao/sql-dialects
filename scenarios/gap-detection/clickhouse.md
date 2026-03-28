# ClickHouse: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [1] ClickHouse Documentation - Window Functions
>   https://clickhouse.com/docs/en/sql-reference/window-functions
> - [2] ClickHouse Documentation - numbers()
>   https://clickhouse.com/docs/en/sql-reference/table-functions/numbers


## 准备数据


```sql
CREATE TABLE orders (id UInt32, info String)
ENGINE = MergeTree() ORDER BY id;
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date Date, amount Decimal(10,2))
ENGINE = MergeTree() ORDER BY sale_date;
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);

```

## 1. 使用 LAG/LEAD（ClickHouse 21.3+ 部分支持窗口函数）


使用 leadInFrame（ClickHouse 特有）

```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id,
           leadInFrame(id, 1, 0) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS next_id
    FROM orders
) WHERE next_id > 0 AND next_id - id > 1;

```

使用标准 LEAD（ClickHouse 22.6+）

```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
) WHERE next_id IS NOT NULL AND next_id - id > 1;

```

## 2. 查找日期间隙


```sql
SELECT sale_date, next_date,
       toUInt32(next_date - sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE next_date IS NOT NULL AND next_date - sale_date > 1;

```

## 3. 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) GROUP BY grp ORDER BY island_start;

```

## 4. 数组方法（ClickHouse 特有的向量化方法）


使用 arrayJoin 和 neighbor 函数

```sql
SELECT id, neighbor(id, 1) AS next_id,
       neighbor(id, 1) - id - 1 AS gap_size
FROM orders
ORDER BY id
HAVING next_id > 0 AND gap_size > 0;

```

## 5. 使用 numbers() 表函数生成序列


缺失的 id

```sql
SELECT number + (SELECT MIN(id) FROM orders) AS missing_id
FROM numbers(
    toUInt64((SELECT MAX(id) FROM orders) - (SELECT MIN(id) FROM orders) + 1)
)
WHERE missing_id NOT IN (SELECT id FROM orders)
ORDER BY missing_id;

```

缺失的日期

```sql
WITH toDate('2024-01-01') AS start_date
SELECT start_date + number AS missing_date
FROM numbers(
    toUInt64((SELECT MAX(sale_date) FROM daily_sales) - (SELECT MIN(sale_date) FROM daily_sales) + 1)
)
WHERE (start_date + number) NOT IN (SELECT sale_date FROM daily_sales)
ORDER BY missing_date;

```

## 6. 综合示例


```sql
WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, count() AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id IS NOT NULL AND next_id - id > 1
ORDER BY range_start;

```

注意：完整窗口函数支持需要 ClickHouse 22.6+
注意：早期版本使用 leadInFrame / lagInFrame 替代 LEAD / LAG
注意：numbers() 是 ClickHouse 高效的序列生成表函数
注意：neighbor() 函数可以访问相邻行的值
注意：ClickHouse 日期相减直接返回天数差值

