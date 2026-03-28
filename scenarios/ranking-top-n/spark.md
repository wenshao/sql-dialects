# Spark SQL: Top-N 查询 (Ranking & Top-N)

> 参考资料:
> - [1] Spark SQL - Window Functions
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html


## 1. 全局 Top-N

```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

```

 分布式执行: 每个分区取 top 10 -> 合并到 Driver -> 最终 top 10
 注意: ORDER BY + LIMIT 导致最终结果收集到单个分区/Driver

## 2. 分组 Top-N（ROW_NUMBER）

```sql
SELECT * FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;

```

ROW_NUMBER vs RANK vs DENSE_RANK:
ROW_NUMBER: 严格不重复序号 (1,2,3)——适合"每组恰好 N 条"
RANK:       相同值同排名，有间隔 (1,1,3)——适合"允许并列"
DENSE_RANK: 相同值同排名，无间隔 (1,1,2)——适合"TOP N 个不同值"


```sql
SELECT * FROM (
    SELECT *, RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rnk
    FROM orders
) WHERE rnk <= 3;

SELECT * FROM (
    SELECT *, DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS drnk
    FROM orders
) WHERE drnk <= 3;

```

## 3. CTE 方式（更清晰）

```sql
WITH ranked_orders AS (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount, order_date
FROM ranked_orders
WHERE rn <= 3;

```

## 4. Spark 特色: LATERAL VIEW + 数组方式


使用 COLLECT_LIST + SORT_ARRAY + SLICE 实现分组 Top-N

```sql
SELECT customer_id, top_order.*
FROM (
    SELECT customer_id,
           slice(
               sort_array(collect_list(struct(amount, order_id, order_date)), false),
               1, 3
           ) AS top_orders
    FROM orders
    GROUP BY customer_id
)
LATERAL VIEW EXPLODE(top_orders) AS top_order;

```

 这种方法避免了窗口函数的排序开销（用 Hash 聚合 + 数组操作替代）
 但当每组数据量大时，COLLECT_LIST 可能 OOM

## 5. 关联子查询方式

```sql
SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

```

## 6. 性能考量


 窗口函数 Top-N 的 Spark 执行:
1. PARTITION BY customer_id 触发 Shuffle（按 customer_id 分区）

2. 每个分区内 ORDER BY amount DESC 排序

3. ROW_NUMBER 分配序号

4. WHERE rn <= N 过滤


 优化建议:
   使用分区表减少数据扫描范围
   AQE 自动优化 Shuffle 分区数
   如果只需要全局 Top-N（无分组），ORDER BY + LIMIT 更高效
   全局 ORDER BY + LIMIT 使用 TakeOrderedAndProject 算子（优化过的 Top-K）

## 7. 版本演进

Spark 2.0: 窗口函数 Top-N, ORDER BY + LIMIT
Spark 3.0: AQE 优化 Shuffle
Spark 3.4: OFFSET 支持

限制:
无 QUALIFY 子句（不能直接 WHERE 过滤窗口函数结果）
无 FETCH FIRST N ROWS WITH TIES（Spark 3.4 之前）
ORDER BY + LIMIT 全局排序使用单个分区（大数据集瓶颈）
COLLECT_LIST 方式在大分组上可能 OOM

