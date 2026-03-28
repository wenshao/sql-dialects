# Firebird: 累计/滚动合计（Running Total）

> 参考资料:
> - [Firebird Documentation - Window Functions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)


## 示例数据上下文

假设表结构:
transactions(txn_id INTEGER, account_id INTEGER, amount DECIMAL(10,2), txn_date DATE)

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

## Firebird 2.x 替代方案（无窗口函数）


## 关联子查询

```sql
SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1
ORDER BY t1.txn_date;
```

## 窗口函数需要 Firebird 3.0+

## 性能考量


## 窗口函数从 Firebird 3.0 开始支持

```sql
CREATE INDEX idx_transactions_date ON transactions (txn_date);
```
