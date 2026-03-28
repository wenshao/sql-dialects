# MaxCompute (ODPS): 累计/滚动合计

> 参考资料:
> - [1] MaxCompute Documentation - Window Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/window-functions


## 1. 累计求和


```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

```

显式帧定义（等价于默认帧）

```sql
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;

```

## 2. 分组累计


```sql
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id ORDER BY txn_date
       ) AS running_total_per_account
FROM transactions;

```

 分布式执行: PARTITION BY 将不同 account 分配到不同 Reducer
 每个 Reducer 内独立计算累计和 — 完全并行

## 3. 累计平均值 / 累计计数


```sql
SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

```

## 4. 滑动窗口（Moving Average）


7 日移动平均

```sql
SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS moving_avg_7d
FROM transactions;

```

3 行滑动求和

```sql
SELECT txn_id, amount,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
       ) AS centered_sum_3
FROM transactions;

```

## 5. 条件重置累计


每次 amount < 0 时重置累计和

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

 原理: 用条件累加创建分组标识 → PARTITION BY 分组标识 → 组内独立累计

## 6. 百分比累计


```sql
SELECT txn_id, amount,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total,
       ROUND(SUM(amount) OVER (ORDER BY txn_date)
           / SUM(amount) OVER () * 100, 2) AS running_pct
FROM transactions;

```

## 7. 横向对比与引擎开发者启示


 累计和支持: 所有支持窗口函数的引擎均支持
 MaxCompute 特点:
   分区级并行: PARTITION BY 利用分布式优势
   无 PARTITION BY: 所有数据到一个 Reducer — 性能瓶颈
   ROWS 帧: 完整支持
   RANGE 帧: 部分版本支持
   GROUPS 帧: 不支持

 对引擎开发者:
### 1. 累计和/移动平均是最常用的窗口计算 — 应重点优化

### 2. ROWS 帧的实现比 RANGE 帧简单得多 — 优先实现

### 3. 条件重置累计（分组技巧）是常见需求 — 可以考虑原生支持

### 4. 无 PARTITION BY 的窗口导致单节点瓶颈 — 应有性能警告

