# ClickHouse: 分页

> 参考资料:
> - [1] ClickHouse SQL Reference - LIMIT
>   https://clickhouse.com/docs/en/sql-reference/statements/select/limit
> - [2] ClickHouse - LIMIT BY
>   https://clickhouse.com/docs/en/sql-reference/statements/select/limit-by


## 1. LIMIT / OFFSET


```sql
SELECT * FROM users ORDER BY id LIMIT 10;
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

## 2. LIMIT BY: ClickHouse 独有的分组分页


LIMIT N BY col: 每组最多返回 N 行

```sql
SELECT user_id, order_date, amount
FROM orders
ORDER BY order_date DESC
LIMIT 3 BY user_id;
```

→ 每个用户返回最近的 3 个订单

LIMIT N, M BY col: 每组跳过 N 行后取 M 行

```sql
SELECT user_id, order_date, amount
FROM orders
ORDER BY order_date DESC
LIMIT 3, 3 BY user_id;
```

 → 每个用户的第 4~6 个订单

 设计分析:
   LIMIT BY 是 ClickHouse 独有的语法（其他数据库没有）。
   等价于 ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY date DESC) <= 3
   但语法更简洁，不需要子查询或 CTE。
   非常适合 Top-N per group 查询。

 对比:
   MySQL:      子查询 + ROW_NUMBER() 或 LATERAL JOIN
   PostgreSQL: LATERAL JOIN 或 DISTINCT ON
   BigQuery:   QUALIFY ROW_NUMBER() OVER (...) <= N

## 3. OLAP 分页的特殊考虑


ClickHouse 不适合传统的 OFFSET 分页:
(a) 列存引擎: OFFSET 100000 需要解压并跳过 100000 行的列数据
(b) 分布式: 每个 shard 返回 OFFSET+LIMIT 行，再由协调节点合并排序
→ OFFSET 100000 LIMIT 10 实际上每个 shard 返回 100010 行!

推荐: 游标分页

```sql
SELECT * FROM events
WHERE (event_time, id) < ('2024-01-15 10:00:00', 999999)
ORDER BY event_time DESC, id DESC
LIMIT 10;

```

 或使用 WHERE + LIMIT 替代 OFFSET:
 前端传递 last_seen_id 和 last_seen_time

## 4. WITH TIES（返回排名相同的行）


 ClickHouse 不支持 WITH TIES（但可以用 LIMIT BY 部分替代）
 PostgreSQL: FETCH FIRST 10 ROWS WITH TIES
 BigQuery: 不支持

## 5. 对比与引擎开发者启示

ClickHouse 分页的设计:
(1) LIMIT BY → 分组分页（独有，非常实用）
(2) OFFSET 在分布式下低效 → 推荐游标分页
(3) 无 WITH TIES → 可用 LIMIT BY 部分替代

对引擎开发者的启示:
LIMIT BY 是值得借鉴的语法设计:
Top-N per group 是 OLAP 最常见的查询模式之一。
比 ROW_NUMBER() + 子查询更简洁，也更容易优化。
分布式引擎的 OFFSET 放大问题（每个 shard 多返回数据）
是所有分布式数据库都需要面对的挑战。

