# SQLite: 累计汇总

> 参考资料:
> - [SQLite Documentation - Window Functions](https://www.sqlite.org/windowfunctions.html)

## 示例数据上下文

假设表结构:
  transactions(txn_id INTEGER PRIMARY KEY, account_id INTEGER, amount REAL, txn_date TEXT, category TEXT)

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

最近 7 行移动平均
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

## SQLite 3.24 及以下替代方案（无窗口函数）

关联子查询
```sql
SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1
ORDER BY t1.txn_date;
```

窗口函数需要 SQLite 3.25.0+（2018-09-15）

## 性能考量

窗口函数需要 SQLite 3.25.0+
SQLite 是嵌入式数据库，适合小数据集
关联子查询在小数据集上性能可接受
```sql
CREATE INDEX idx_transactions_date ON transactions (txn_date);
CREATE INDEX idx_transactions_account_date ON transactions (account_id, txn_date);
```
