# Flink SQL: 累计求和

> 参考资料:
> - [Flink Documentation - Over Aggregation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/over-agg/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 示例数据上下文

假设表结构:
  transactions(txn_id INT, account_id INT, amount DECIMAL(10,2), txn_time TIMESTAMP(3),
         WATERMARK FOR txn_time AS txn_time - INTERVAL '5' SECOND)

## 累计求和


```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;

```

## 累计平均值


```sql
SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg
FROM transactions;

```

## 累计计数


```sql
SELECT txn_id, amount, txn_date,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

```

## 分组累计


```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
       ) AS running_total_per_account
FROM transactions;

```

## 滑动窗口


```sql
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

```

## 条件重置累计


```sql
WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS grp
    FROM transactions
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date) AS running_total_reset
FROM groups;

```

## Flink 特色：OVER 窗口聚合（流式累计）


Flink 的 OVER 窗口是增量计算的
按时间范围的累计（流式场景推荐）
```sql
SELECT txn_id, account_id, amount, txn_time,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_time
           RANGE BETWEEN INTERVAL '1' HOUR PRECEDING AND CURRENT ROW
       ) AS rolling_sum_1h
FROM transactions;

```

按行数的累计
```sql
SELECT txn_id, account_id, amount, txn_time,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_time
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;

```

**注意:** Flink 的 OVER 窗口必须有 PARTITION BY 和 ORDER BY

## 性能考量


Flink 的 OVER 聚合是增量计算（流式场景）
必须有 PARTITION BY 和 ORDER BY
支持 ROWS 和 RANGE 帧
**注意:** 无界 PRECEDING 状态会无限增长，注意设置 TTL
