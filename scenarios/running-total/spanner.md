# Spanner: 累计求和

> 参考资料:
> - [Spanner Documentation - Analytic Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/analytic-function-concepts)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 示例数据上下文

假设表结构:
  transactions(txn_id INT64, account_id INT64, amount NUMERIC, txn_date DATE)

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

## 性能考量


Spanner 全球分布式，自动分片
使用二级索引优化排序
