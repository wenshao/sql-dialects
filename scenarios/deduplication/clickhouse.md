# ClickHouse: 数据去重策略（Deduplication）

> 参考资料:
> - [1] ClickHouse Documentation - ReplacingMergeTree
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree
> - [2] ClickHouse Documentation - Window Functions
>   https://clickhouse.com/docs/en/sql-reference/window-functions
> - [3] ClickHouse Documentation - uniq Functions
>   https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference/uniq


## 示例数据上下文

 假设表结构:
   users(user_id UInt64, email String, username String, created_at DateTime)
   ENGINE = MergeTree() ORDER BY user_id

## 1. 查找重复数据


```sql
SELECT email, count() AS cnt
FROM users
GROUP BY email
HAVING count() > 1;

```

## 2. 保留每组一行（ROW_NUMBER，ClickHouse 21.1+）


```sql
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

```

## 3. ReplacingMergeTree（ClickHouse 核心去重机制）


建表时使用 ReplacingMergeTree

```sql
CREATE TABLE users_replacing (
    user_id    UInt64,
    email      String,
    username   String,
    created_at DateTime
)
ENGINE = ReplacingMergeTree(created_at)     -- 按 created_at 保留最新行
ORDER BY email;                              -- 按 email 去重

```

插入数据（包括重复的）

```sql
INSERT INTO users_replacing VALUES (1, 'a@b.com', 'alice', '2024-01-01 00:00:00');
INSERT INTO users_replacing VALUES (2, 'a@b.com', 'alice2', '2024-06-01 00:00:00');

```

查询时使用 FINAL 强制去重（触发合并）

```sql
SELECT * FROM users_replacing FINAL;

```

或手动触发合并

```sql
OPTIMIZE TABLE users_replacing FINAL;

```

## 4. argMax / argMin（ClickHouse 特色聚合函数）


按 email 分组，取 created_at 最新的每个字段值

```sql
SELECT email,
       argMax(user_id, created_at) AS latest_user_id,
       argMax(username, created_at) AS latest_username,
       max(created_at) AS latest_created_at
FROM users
GROUP BY email;

```

## 5. LIMIT BY 去重


每个 email 只保留最新的 1 条

```sql
SELECT user_id, email, username, created_at
FROM users
ORDER BY email, created_at DESC
LIMIT 1 BY email;

```

## 6. 删除重复数据


ClickHouse 不支持传统 DELETE（MergeTree 是追加写入）
使用 ALTER TABLE DELETE（异步后台执行）

```sql
ALTER TABLE users DELETE
WHERE (email, created_at) NOT IN (
    SELECT email, max(created_at)
    FROM users
    GROUP BY email
);

```

更推荐：CTAS 方式（创建新表 + RENAME）

```sql
CREATE TABLE users_clean AS
SELECT user_id, email, username, created_at
FROM users
ORDER BY email, created_at DESC
LIMIT 1 BY email;

RENAME TABLE users TO users_backup, users_clean TO users;

```

## 7. 近似去重（uniq 系列函数）


uniq：HyperLogLog 近似计数（误差 ~1-2%）

```sql
SELECT uniq(email) AS approx_distinct_emails FROM users;

```

uniqExact：精确计数（等价于 COUNT(DISTINCT)）

```sql
SELECT uniqExact(email) AS exact_distinct_emails FROM users;

```

uniqHLL12：12 位 HyperLogLog

```sql
SELECT uniqHLL12(email) AS hll_distinct FROM users;

```

uniqCombined：自适应算法（小数据精确，大数据近似）

```sql
SELECT uniqCombined(email) AS combined_distinct FROM users;

```

状态函数（可持久化、可合并）

```sql
SELECT uniqState(email) FROM users;

```

## 8. DISTINCT vs GROUP BY


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

```

## 9. 性能考量


ReplacingMergeTree 是 ClickHouse 原生去重方案
FINAL 会触发即时合并，影响查询性能
argMax/argMin 配合 GROUP BY 比窗口函数更高效
LIMIT BY 是 ClickHouse 最简洁的去重查询方式
uniq 系列函数性能远优于 COUNT(DISTINCT)
ALTER TABLE DELETE 是异步操作（mutation），大表可能需要几分钟
注意：MergeTree 合并是后台异步的，查询可能暂时看到重复数据

