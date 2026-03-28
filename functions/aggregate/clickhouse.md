# ClickHouse: 聚合函数

> 参考资料:
> - [1] ClickHouse SQL Reference - Aggregate Functions
>   https://clickhouse.com/docs/en/sql-reference/aggregate-functions
> - [2] ClickHouse SQL Reference - GROUP BY
>   https://clickhouse.com/docs/en/sql-reference/statements/select/group-by


基本聚合

```sql
SELECT count() FROM users;                               -- 注意：小写函数名
SELECT count(DISTINCT city) FROM users;
SELECT uniq(city) FROM users;                            -- HyperLogLog 近似去重
SELECT uniqExact(city) FROM users;                       -- 精确去重
SELECT sum(amount) FROM orders;
SELECT avg(amount) FROM orders;
SELECT min(amount) FROM orders;
SELECT max(amount) FROM orders;

```

GROUP BY

```sql
SELECT city, count() AS cnt, avg(age) AS avg_age
FROM users
GROUP BY city;

```

HAVING

```sql
SELECT city, count() AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;                                         -- 可以引用别名

```

GROUP BY WITH ROLLUP / CUBE / TOTALS

```sql
SELECT city, status, count()
FROM users
GROUP BY ROLLUP(city, status);

SELECT city, status, count()
FROM users
GROUP BY CUBE(city, status);

SELECT city, count()
FROM users
GROUP BY city WITH TOTALS;                               -- ClickHouse 特有：附加合计行

```

字符串聚合

```sql
SELECT groupArray(username) FROM users;                  -- 收集为数组
SELECT groupUniqArray(city) FROM users;                  -- 去重数组
SELECT arrayStringConcat(groupArray(username), ', ') FROM users;  -- 拼接字符串

```

-If 组合器（条件聚合，ClickHouse 核心特性）

```sql
SELECT
    count() AS total,
    countIf(age < 30) AS young,
    sumIf(amount, status = 'active') AS active_amount,
    avgIf(amount, city = 'Beijing') AS bj_avg
FROM users;

```

-Array 组合器（对数组聚合）

```sql
SELECT sumArray([1, 2, 3]);                              -- 6
SELECT avgArray([1, 2, 3]);                              -- 2

```

-State / -Merge 组合器（增量聚合）

```sql
SELECT uniqState(user_id) FROM events;                   -- 返回中间状态
SELECT uniqMerge(state) FROM agg_table;                  -- 合并中间状态

```

-ForEach 组合器

```sql
SELECT sumForEach([1, 2, 3], [4, 5, 6]);                 -- 对数组逐元素聚合

```

近似聚合（ClickHouse 强项）

```sql
SELECT uniq(user_id) FROM events;                        -- HyperLogLog（默认）
SELECT uniqHLL12(user_id) FROM events;                   -- HLL 12 位
SELECT uniqCombined(user_id) FROM events;                -- 组合算法
SELECT uniqCombined64(user_id) FROM events;              -- 64 位组合
SELECT uniqTheta(user_id) FROM events;                   -- Theta Sketch

```

百分位 / 分位数

```sql
SELECT median(amount) FROM orders;                       -- 中位数
SELECT quantile(0.5)(amount) FROM orders;                -- 近似分位数（reservoir sampling）
SELECT quantiles(0.25, 0.5, 0.75)(amount) FROM orders;   -- 多个分位数
SELECT quantileTDigest(0.5)(amount) FROM orders;         -- T-Digest 近似
SELECT quantileExact(0.5)(amount) FROM orders;           -- 精确分位数

```

统计函数

```sql
SELECT stddevPop(amount) FROM orders;                    -- 总体标准差
SELECT stddevSamp(amount) FROM orders;                   -- 样本标准差
SELECT varPop(amount) FROM orders;                       -- 总体方差
SELECT varSamp(amount) FROM orders;                      -- 样本方差
SELECT corr(x, y) FROM data;                             -- 相关系数
SELECT covarPop(x, y) FROM data;                         -- 总体协方差
SELECT covarSamp(x, y) FROM data;                        -- 样本协方差
SELECT entropy(city) FROM users;                         -- 信息熵
SELECT kurtPop(amount) FROM orders;                      -- 总体峰度
SELECT skewPop(amount) FROM orders;                      -- 总体偏度

```

TopK

```sql
SELECT topK(10)(city) FROM users;                        -- TOP 10 最频繁值
SELECT topKWeighted(10)(city, population) FROM cities;   -- 加权 TOP K

```

其他

```sql
SELECT any(name) FROM users;                             -- 任意值
SELECT anyLast(name) FROM users;                         -- 最后一个值
SELECT argMin(name, age) FROM users;                     -- age 最小时的 name
SELECT argMax(name, age) FROM users;                     -- age 最大时的 name
SELECT minMap(keys, values) FROM t;                      -- Map 聚合
SELECT maxMap(keys, values) FROM t;
SELECT sumMap(keys, values) FROM t;

```

位聚合

```sql
SELECT groupBitAnd(flags) FROM settings;
SELECT groupBitOr(flags) FROM settings;
SELECT groupBitXor(flags) FROM settings;

```

注意：函数名驼峰命名（与 SQL 标准不同）
注意：-If / -Array / -State / -Merge 组合器是 ClickHouse 独有的强大特性
注意：WITH TOTALS 是 ClickHouse 特有的合计行功能
注意：uniq 系列提供多种近似去重算法
注意：quantile 系列支持多种分位数算法

