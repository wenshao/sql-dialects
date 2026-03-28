# ClickHouse: 累计/滚动合计（Running Total）

> 参考资料:
> - [1] ClickHouse Documentation - Window Functions
>   https://clickhouse.com/docs/en/sql-reference/window-functions


## 示例数据上下文

 假设表结构:
   transactions(txn_id UInt64, account_id UInt64, amount Decimal(10,2), txn_date Date, category String)
   ENGINE = MergeTree() ORDER BY (account_id, txn_date)

## 1. 累计求和


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

## 2. 累计平均值


```sql
SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg
FROM transactions;

```

## 3. 累计计数


```sql
SELECT txn_id, amount, txn_date,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

```

## 4. 分组累计


```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
       ) AS running_total_per_account
FROM transactions;

```

## 5. 滑动窗口


最近 7 行移动平均

```sql
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

```

## 6. 条件重置累计


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

## 7. ClickHouse 特色：runningAccumulate


使用 runningAccumulate（非窗口函数方式，ClickHouse 原生）

```sql
SELECT txn_id, amount, txn_date,
       runningAccumulate(sumState(amount)) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

```

 注意：窗口函数从 ClickHouse 21.1 开始支持
 旧版本使用 arrayJoin + arrayCumSum

## 8. 性能考量


ClickHouse 列式存储，窗口函数自动并行
窗口函数从 21.1 版本开始支持
表引擎的 ORDER BY 与窗口 ORDER BY 一致时最优
注意：RANGE 帧支持有限

```sql
CREATE INDEX idx_transactions_date ON transactions (txn_date) TYPE minmax GRANULARITY 8192;

```
