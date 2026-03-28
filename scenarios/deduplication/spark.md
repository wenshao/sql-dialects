# Spark SQL: 数据去重策略 (Deduplication)

> 参考资料:
> - [1] Spark SQL - Window Functions
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html


## 1. 查找重复数据


```sql
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

```

查看重复行的完整信息

```sql
SELECT u.*
FROM users u
JOIN (
    SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1
) dup ON u.email = dup.email
ORDER BY u.email, u.created_at;

```

## 2. ROW_NUMBER 去重（最通用的方法）


保留每组最新一条

```sql
SELECT * FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

```

 设计分析:
   ROW_NUMBER 去重是所有 SQL 引擎通用的方法。
   在 Spark 中，PARTITION BY email 决定了 Shuffle 的分区键。
   如果 email 的基数很高（百万级），Shuffle 开销较大。
   优化: 如果可以先按分区列（如日期）裁剪数据，可以大幅减少 Shuffle。

## 3. 删除重复数据


方案 A: Delta Lake DELETE（需要 Delta 表）

```sql
DELETE FROM users
WHERE user_id NOT IN (
    SELECT keep_id FROM (
        SELECT MAX(user_id) AS keep_id
        FROM users
        GROUP BY email
    ) keepers
);

```

方案 B: CTAS 重建（推荐用于非 Delta 表）

```sql
CREATE TABLE users_clean AS
SELECT * FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

```

DROP TABLE users;
ALTER TABLE users_clean RENAME TO users;

方案 C: INSERT OVERWRITE（原地去重）

```sql
INSERT OVERWRITE TABLE users
SELECT user_id, email, username, created_at FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) WHERE rn = 1;

```

 对比:
   MySQL:      DELETE + 自连接 或 临时表方式
   PostgreSQL: DELETE USING 或 ctid 去重
   Spark:      CTAS 或 INSERT OVERWRITE 是最佳方式（无行级 DELETE 时）

## 4. DISTINCT vs GROUP BY


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;
```

两者在 Spark 中的执行计划几乎相同（Catalyst 优化器统一处理）

GROUP BY 可以附带聚合

```sql
SELECT email, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM users
GROUP BY email;

```

## 5. 近似去重计数


```sql
SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct
FROM users;

```

 HyperLogLog 精度 ~2%，但在亿级数据上比 COUNT(DISTINCT) 快 10-100 倍
 适用于: 数据量估算、Dashboard 指标、不需要精确值的场景

## 6. DataFrame API 去重


 df.dropDuplicates(['email'])        -- 保留第一条（非确定性）
 df.dropDuplicates()                 -- 全列去重
 df.distinct()                       -- 等价于 SELECT DISTINCT *

 dropDuplicates 比 ROW_NUMBER 更高效:
   ROW_NUMBER 需要排序（O(N log N)）
   dropDuplicates 使用 Hash 去重（O(N)），但不能控制保留哪条

## 7. 流式去重（Structured Streaming）


 流式去重使用 watermark + dropDuplicatesWithinWatermark:
 df.withWatermark("event_time", "1 hour") \
   .dropDuplicatesWithinWatermark(["user_id", "event_type"])
 在时间窗口内去重——超过 watermark 的重复不再检测

## 8. 版本演进

Spark 2.0: DISTINCT, GROUP BY, ROW_NUMBER 去重
Spark 2.0: DataFrame dropDuplicates
Spark 3.0: APPROX_COUNT_DISTINCT 优化
Spark 3.5: dropDuplicatesWithinWatermark（流式去重）

限制:
原生 Spark 表不支持 DELETE（无法直接删除重复行）
推荐 CTAS 或 INSERT OVERWRITE 方式去重
DataFrame dropDuplicates 不能控制保留哪条记录
APPROX_COUNT_DISTINCT 有 ~2% 误差

