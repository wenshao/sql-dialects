# MaxCompute (ODPS): 数据去重

> 参考资料:
> - [1] MaxCompute Documentation - Window Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/window-functions


## 1. 查找重复数据


```sql
SELECT email, COUNT(*) AS cnt
FROM users GROUP BY email HAVING COUNT(*) > 1;

```

查看具体重复记录

```sql
SELECT u.*
FROM users u
JOIN (SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1) dup
ON u.email = dup.email
ORDER BY u.email, u.created_at;

```

## 2. ROW_NUMBER 去重 —— MaxCompute 最核心的去重模式


保留每组最新的一行

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rn
    FROM users
) ranked WHERE rn = 1;

```

 为什么 ROW_NUMBER 是 MaxCompute 去重的核心?
   普通表不支持 UNIQUE 约束 → 数据可能有重复
   普通表不支持 DELETE → 不能直接删除重复行
   ROW_NUMBER + INSERT OVERWRITE = 去重并持久化

## 3. 去重并持久化


INSERT OVERWRITE 方式（普通表的唯一选择）

```sql
INSERT OVERWRITE TABLE users
SELECT user_id, email, username, created_at FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rn
    FROM users
) ranked WHERE rn = 1;

```

CTAS 方式（创建新表）

```sql
CREATE TABLE users_clean AS
SELECT user_id, email, username, created_at FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rn
    FROM users
) ranked WHERE rn = 1;

```

事务表方式（如果是事务表）

```sql
DELETE FROM users
WHERE user_id NOT IN (
    SELECT MAX(user_id) FROM users GROUP BY email
);

```

## 4. 分区表去重（只处理特定分区）


```sql
INSERT OVERWRITE TABLE events PARTITION (dt = '20240115')
SELECT user_id, event_name, event_time FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY user_id, event_name ORDER BY event_time DESC
    ) AS rn
    FROM events WHERE dt = '20240115'
) ranked WHERE rn = 1;

```

 分区级去重的优势: 只重写一个分区（GB 级），不影响其他分区

## 5. DISTINCT vs GROUP BY vs ROW_NUMBER


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;
```

 两者等价，优化器通常生成相同的执行计划

 需要保留其他列时:
 DISTINCT: SELECT DISTINCT email, username FROM users（所有列参与去重）
 GROUP BY: SELECT email, MAX(username) FROM users GROUP BY email（需要聚合其他列）
 ROW_NUMBER: 最灵活（可以选择保留哪一行）

## 6. 近似去重（大数据场景）


```sql
SELECT APPROX_DISTINCT(email) AS approx_unique_emails FROM users;
```

 HyperLogLog 算法: ~2% 误差，O(1) 内存
 对 TB 级数据: COUNT(DISTINCT) 可能 OOM，APPROX_DISTINCT 是唯一选择

## 7. 增量去重（ETL 管道模式）


新数据到达后与已有数据合并去重

```sql
INSERT OVERWRITE TABLE users
SELECT user_id, email, username, created_at FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rn
    FROM (
        SELECT * FROM new_users           -- 新数据
        UNION ALL
        SELECT * FROM users               -- 已有数据
    ) combined
) ranked WHERE rn = 1;

```

## 8. 横向对比与引擎开发者启示


 去重方式:
   MaxCompute: ROW_NUMBER + INSERT OVERWRITE（核心模式）
   Hive:       相同方案
   PostgreSQL: DELETE FROM t WHERE ctid NOT IN (SELECT MIN(ctid) ...)
   MySQL:      DELETE JOIN 或临时表
   BigQuery:   ROW_NUMBER + MERGE 或 CREATE OR REPLACE TABLE
   Snowflake:  ROW_NUMBER + DELETE 或 QUALIFY（最简洁）
   ClickHouse: ReplacingMergeTree（后台自动去重）

 对引擎开发者:
1. QUALIFY 语法极大简化去重: QUALIFY ROW_NUMBER() OVER (...) = 1

2. ClickHouse ReplacingMergeTree 的异步去重是有趣的替代方案

3. APPROX_DISTINCT 是大数据引擎的必备功能

4. 分区级去重是 Hive 族引擎的最佳实践 — 避免全表重写

