# Hive: 累计/滚动合计 (Running Total, 0.11+)

> 参考资料:
> - [1] Apache Hive - Window Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics


## 1. 累计求和

```sql
SELECT txn_id, amount, txn_date,
    SUM(amount) OVER (ORDER BY txn_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM transactions;

```

简写（默认帧就是 UNBOUNDED PRECEDING → CURRENT ROW）

```sql
SELECT txn_id, amount, txn_date,
    SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

```

## 2. 分组累计

```sql
SELECT txn_id, account_id, amount, txn_date,
    SUM(amount) OVER (
        PARTITION BY account_id ORDER BY txn_date
    ) AS account_running_total
FROM transactions;

```

## 3. 累计平均与计数

```sql
SELECT txn_id, amount, txn_date,
    ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg,
    COUNT(*) OVER (ORDER BY txn_date) AS running_count
FROM transactions;

```

## 4. 滑动窗口

最近 3 行滑动求和

```sql
SELECT txn_id, amount,
    SUM(amount) OVER (ORDER BY txn_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
    AS sliding_sum_3
FROM transactions;

```

最近 7 天滑动平均 (RANGE 帧, 2.1+)

```sql
SELECT txn_id, amount, txn_date,
    AVG(amount) OVER (ORDER BY txn_date
        RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW) AS ma_7d
FROM transactions;

```

## 5. 百分比贡献

```sql
SELECT txn_id, amount,
    amount / SUM(amount) OVER () AS pct_of_total,
    SUM(amount) OVER (ORDER BY amount DESC) / SUM(amount) OVER () AS cumulative_pct
FROM transactions;

```

## 6. 设计分析: Hive 是大数据窗口函数的先驱

 Hive 0.11 (2013) 引入窗口函数，是大数据 SQL 引擎中最早的实现之一。
 这一时间节点对整个生态影响深远:
 Spark SQL、Impala、Presto 都在之后快速跟进支持了窗口函数。
 在此之前，大数据场景中实现累计求和需要写自定义 MapReduce 程序。

## 7. 跨引擎对比

 引擎          窗口函数    ROWS 帧   RANGE 帧   GROUPS 帧
 MySQL(8.0+)   支持        支持      支持       不支持
 PostgreSQL    支持        支持      支持       支持(11+)
 Hive(0.11+)   支持        支持      支持(2.1+) 不支持
 Spark SQL     支持        支持      支持       不支持
 BigQuery      支持        支持      支持       不支持

## 8. 对引擎开发者的启示

### 1. 窗口函数的 ROWS/RANGE 帧是分析引擎的基础能力

### 2. 累计求和的分布式执行: PARTITION BY 决定了数据分布，

    每个分区在一个 Reducer 中计算，大分区可能导致 OOM
### 3. IGNORE NULLS 选项应该被支持: 在时间序列场景中用于 forward fill

