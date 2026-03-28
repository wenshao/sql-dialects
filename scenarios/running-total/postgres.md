# PostgreSQL: 累计汇总

> 参考资料:
> - [PostgreSQL Documentation - Window Functions](https://www.postgresql.org/docs/current/tutorial-window.html)

## 累计求和

```sql
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;
```

显式帧（等价于默认行为）
```sql
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM transactions;
```

## 分组累计

```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY account_id ORDER BY txn_date) AS acct_running
FROM transactions;
```

## 滑动窗口

最近 7 行移动平均
```sql
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
FROM transactions;
```

最近 30 天移动总和（RANGE + INTERVAL，PostgreSQL 特有支持）
```sql
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date
           RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS sum_30d
FROM transactions;
```

设计分析: ROWS vs RANGE vs GROUPS
  ROWS:   按物理行数计算窗口（精确 N 行）
  RANGE:  按值范围计算窗口（支持 INTERVAL，PostgreSQL 特有优势）
  GROUPS: 按分组计算窗口（11+，每个分组是排序键相同的行集合）

  RANGE + INTERVAL 是 PostgreSQL 的优势:
    MySQL 不支持 RANGE + INTERVAL
    Oracle 支持 RANGE + INTERVAL
    SQL Server 不支持 RANGE + INTERVAL

## 累计百分比

```sql
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total,
       ROUND(SUM(amount) OVER (ORDER BY txn_date) * 100.0 /
             SUM(amount) OVER (), 2) AS running_pct
FROM transactions;
```

## 条件重置累计

```sql
WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date ROWS UNBOUNDED PRECEDING
           ) AS grp
    FROM transactions
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date) AS reset_total
FROM groups;
```

## 性能考量

```sql
CREATE INDEX idx_txn_date ON transactions (txn_date);
CREATE INDEX idx_txn_acct_date ON transactions (account_id, txn_date);
```

ROWS 帧 比 RANGE 帧 性能更好（RANGE 需要处理 peer rows）
窗口函数对 ORDER BY 列有索引时，可能避免排序
WINDOW 子句复用窗口定义（减少重复计算）:
```sql
SELECT txn_id, amount,
       SUM(amount) OVER w AS running_sum,
       AVG(amount) OVER w AS running_avg
FROM transactions
WINDOW w AS (ORDER BY txn_date);
```

## 对引擎开发者的启示

(1) RANGE + INTERVAL 是时序分析的关键能力:
    "最近30天移动平均"在日期有间隙时，ROWS 按行数不正确，
    RANGE 按日期范围才是正确语义。

(2) WINDOW 子句（命名窗口）减少了 SQL 冗余:
    多个窗口函数共享同一窗口定义时，
    PostgreSQL 可以优化为单次排序、多次聚合。

(3) 11+ 的 GROUPS 帧模式:
    介于 ROWS 和 RANGE 之间——按"排序键相同的行组"计数。
    配合 EXCLUDE 子句（EXCLUDE CURRENT ROW / TIES / GROUP）更灵活。
