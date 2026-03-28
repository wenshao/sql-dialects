# Flink SQL: 间隔检测

> 参考资料:
> - [Flink Documentation - Window Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/window-agg/)
> - [Flink Documentation - Over Aggregation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/over-agg/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 准备数据（Flink SQL 表定义）


```sql
CREATE TABLE orders (
    id    INT,
    info  STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH ('connector' = 'filesystem', 'path' = '/data/orders', 'format' = 'csv');

CREATE TABLE daily_sales (
    sale_date DATE,
    amount    DECIMAL(10,2),
    PRIMARY KEY (sale_date) NOT ENFORCED
) WITH ('connector' = 'filesystem', 'path' = '/data/sales', 'format' = 'csv');

```

## 使用 LAG/LEAD 查找数值间隙（Flink 批模式）


Flink SQL 支持 OVER 窗口中的 LAG/LEAD
```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id,
           LEAD(id, 1) OVER (ORDER BY id) AS next_id
    FROM orders
) WHERE next_id - id > 1;

```

## 查找日期间隙


```sql
SELECT sale_date, next_date,
       DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date, 1) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE DATEDIFF(next_date, sale_date) > 1;

```

## 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) GROUP BY grp;

```

## 自连接方法


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1;

```

## Flink SQL 的流处理间隙检测


在流模式下，可以使用 Session Window 检测间隙
Session Window 自动按时间间隙分组
SELECT
    SESSION_START(rowtime, INTERVAL '1' DAY)  AS session_start,
    SESSION_END(rowtime, INTERVAL '1' DAY)    AS session_end,
    COUNT(*) AS cnt
FROM events
GROUP BY SESSION(rowtime, INTERVAL '1' DAY);

## 综合示例


```sql
WITH gaps AS (
    SELECT id, LEAD(id, 1) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Gap' AS type, id + 1 AS range_start, next_id - 1 AS range_end,
       next_id - id - 1 AS size
FROM gaps WHERE next_id IS NOT NULL AND next_id - id > 1;

```

**注意:** Flink SQL 窗口函数在批模式和流模式下行为不同
**注意:** Flink SQL 不支持递归 CTE
**注意:** 流模式下优先使用 Session Window 进行间隙检测
**注意:** Flink SQL 中 OVER 窗口的排序字段需要是时间属性或 PROCTIME()
