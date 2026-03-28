# MaxCompute (ODPS): Top-N 查询

> 参考资料:
> - [1] MaxCompute Documentation - Window Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/window-functions


## 1. 全局 Top-N


```sql
SELECT order_id, customer_id, amount
FROM orders ORDER BY amount DESC LIMIT 10;

```

 伏羲执行: ORDER BY + LIMIT = Top-K 优化
   每个 Map 节点维护 size=10 的小顶堆
   Reduce 阶段合并所有 Map 的结果
   复杂度: O(N log K) 而非 O(N log N)

## 2. 分组 Top-N（最常用模式）


ROW_NUMBER: 严格 Top-N（无并列）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY customer_id ORDER BY amount DESC
    ) AS rn
    FROM orders
) ranked WHERE rn <= 3;

```

RANK: 允许并列（可能返回超过 N 行）

```sql
SELECT * FROM (
    SELECT *, RANK() OVER (
        PARTITION BY customer_id ORDER BY amount DESC
    ) AS rnk
    FROM orders
) ranked WHERE rnk <= 3;

```

DENSE_RANK: 允许并列，连续排名

```sql
SELECT * FROM (
    SELECT *, DENSE_RANK() OVER (
        PARTITION BY customer_id ORDER BY amount DESC
    ) AS drnk
    FROM orders
) ranked WHERE drnk <= 3;

```

## 3. CTE 版本（更清晰的写法）


```sql
WITH ranked_orders AS (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id ORDER BY amount DESC
           ) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount, order_date
FROM ranked_orders WHERE rn <= 3;

```

## 4. 分区表 Top-N（生产中最常用）


只对特定分区做 Top-N（避免全表扫描）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY customer_id ORDER BY amount DESC
    ) AS rn
    FROM orders WHERE dt = '20240115'       -- 分区裁剪!
) ranked WHERE rn <= 3;

```

## 5. 不支持 QUALIFY（需要子查询包装）


BigQuery/Snowflake 的简洁写法（MaxCompute 不支持）:
SELECT * FROM orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

MaxCompute 必须用子查询包装:

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) t WHERE rn <= 3;

```

## 6. 性能注意事项


 全局 ORDER BY + LIMIT: Top-K 优化，性能可接受
 分组 Top-N (窗口函数):
   PARTITION BY 分散到多个 Reducer — 并行执行
   每个 Reducer 内排序 + 取前 N — 效率高
   无 PARTITION BY 的 ORDER BY: 所有数据到一个 Reducer — 瓶颈

 分区表: 始终在 WHERE 中加分区条件减少扫描量
 不支持: LATERAL / CROSS APPLY / QUALIFY / FETCH FIRST

## 7. 横向对比与引擎开发者启示


 对比:
MaxCompute: ROW_NUMBER + 子查询    | BigQuery: QUALIFY（最简洁）
Snowflake:  QUALIFY（最简洁）      | PostgreSQL: ROW_NUMBER + 子查询
MySQL 8.0:  ROW_NUMBER + 子查询    | Oracle: ROW_NUMBER 或 FETCH FIRST

 对引擎开发者:
1. QUALIFY 语法将 Top-N 从 3 层嵌套简化为 1 层 — 强烈推荐实现

2. Top-K 优化（堆排序）是 ORDER BY + LIMIT 的基础优化

3. 分组 Top-N 是数据分析中使用频率最高的模式之一

4. 窗口函数的 PARTITION BY 自然实现了分布式并行

