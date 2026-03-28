# SQL Server: 累计汇总

> 参考资料:
> - [SQL Server - Window Functions OVER Clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql)

## 累计求和（2012+ 推荐方式）

```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;
```

关键: 显式指定 ROWS 帧（不要依赖默认帧）
默认帧是 RANGE（处理重复值时与 ROWS 行为不同，且性能更差）

## 分组累计

```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date ROWS UNBOUNDED PRECEDING
       ) AS running_total_per_account
FROM transactions;
```

## 累计平均 / 累计计数 / 累计最大

```sql
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_avg,
       COUNT(*)    OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count,
       MAX(amount) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_max
FROM transactions;
```

## 滑动窗口（Moving Average）

```sql
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
           AS moving_avg_7
FROM transactions;
```

设计分析（对引擎开发者）:
  ROWS vs RANGE 帧的性能差异:
  ROWS: O(n) 增量计算（维护一个滑动窗口）
  RANGE: O(n log n)（需要找到值相等的行边界）

  SQL Server 的默认帧是 RANGE（历史原因），这导致:
  SUM(x) OVER (ORDER BY date)  -- 隐式 RANGE, 较慢
  应该写成:
  SUM(x) OVER (ORDER BY date ROWS UNBOUNDED PRECEDING)  -- 显式 ROWS, 更快

  SQL Server 不支持 RANGE + INTERVAL:
  PostgreSQL: RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
  SQL Server: 不支持——必须用 ROWS 或自连接实现日期范围窗口

## 条件重置累计

```sql
;WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date ROWS UNBOUNDED PRECEDING
           ) AS grp
    FROM transactions
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date ROWS UNBOUNDED PRECEDING)
           AS running_total_reset
FROM groups;
```

## 2005-2008 替代方案（无 ROWS 帧）

CROSS APPLY + 子查询（O(n^2)，大表慢）
```sql
SELECT t.txn_id, t.amount, t.txn_date, rt.running_total
FROM transactions t
CROSS APPLY (
    SELECT SUM(amount) AS running_total
    FROM transactions t2 WHERE t2.txn_date <= t.txn_date
) rt ORDER BY t.txn_date;
```

递归 CTE（O(n)，但受 MAXRECURSION 限制）
```sql
;WITH ordered AS (
    SELECT txn_id, amount, txn_date,
           ROW_NUMBER() OVER (ORDER BY txn_date) AS rn
    FROM transactions
),
running AS (
    SELECT txn_id, amount, txn_date, rn, amount AS running_total
    FROM ordered WHERE rn = 1
    UNION ALL
    SELECT o.txn_id, o.amount, o.txn_date, o.rn, r.running_total + o.amount
    FROM ordered o JOIN running r ON o.rn = r.rn + 1
)
SELECT * FROM running ORDER BY txn_date OPTION (MAXRECURSION 0);
```

## 性能优化

```sql
CREATE INDEX ix_txn_date ON transactions (txn_date) INCLUDE (amount);
CREATE INDEX ix_acct_date ON transactions (account_id, txn_date) INCLUDE (amount);
```

2019+: Batch Mode on Rowstore
窗口函数自动使用批处理模式（即使没有列存索引），性能提升 2-10x

对引擎开发者的启示:
  累计计算是窗口函数的核心应用场景。
  引擎实现要点:
  (1) ROWS 帧使用增量计算（O(n)），不要每行重新聚合
  (2) RANGE 帧需要处理相同值边界（更复杂）
  (3) 批处理/向量化执行对窗口函数性能至关重要
