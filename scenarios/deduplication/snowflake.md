# Snowflake: 数据去重

> 参考资料:
> - [1] Snowflake Documentation - QUALIFY
>   https://docs.snowflake.com/en/sql-reference/constructs/qualify


## 1. 查找重复数据


```sql
SELECT email, COUNT(*) AS cnt
FROM users GROUP BY email HAVING COUNT(*) > 1;

```

## 2. QUALIFY 去重（Snowflake 推荐方式，最简洁）


保留每组最新的一行:

```sql
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) = 1;

```

QUALIFY + RANK（保留并列最新的所有行）:

```sql
SELECT user_id, email, username, created_at
FROM users
QUALIFY RANK() OVER (PARTITION BY email ORDER BY created_at DESC) = 1;

```

对比传统方式（子查询）:

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) WHERE rn = 1;

```

 QUALIFY 的优势:
   (a) 无需嵌套子查询 → SQL 更短更清晰
   (b) 优化器可以更好地理解查询意图
   (c) 是 Snowflake 中最简洁的去重方案

## 3. 删除重复数据


方式 A: DELETE + 子查询（直接删除，但对大表较慢）

```sql
DELETE FROM users
WHERE user_id NOT IN (
    SELECT user_id FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
        FROM users
    ) WHERE rn = 1
);

```

方式 B: CTAS + SWAP（推荐，对大表更高效）

```sql
CREATE TABLE users_deduped AS
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) = 1;

ALTER TABLE users SWAP WITH users_deduped;
```

 SWAP 是原子操作，瞬时完成，旧表进入 Time Travel 可恢复

 对引擎开发者的启示:
   Snowflake 的约束不执行（PK/UNIQUE 不强制），因此重复数据很常见。
   CTAS + SWAP 模式比 DELETE 更适合不可变微分区架构:
   DELETE 需要重写受影响的微分区（可能是大部分分区）
   CTAS 只生成新的去重后的微分区 → 更高效

## 4. 防止重复（MERGE）


```sql
MERGE INTO users target
USING (SELECT 'a@b.com' AS email, 'alice' AS username,
       CURRENT_TIMESTAMP() AS created_at) source
ON target.email = source.email
WHEN MATCHED THEN
    UPDATE SET target.username = source.username
WHEN NOT MATCHED THEN
    INSERT (email, username, created_at)
    VALUES (source.email, source.username, source.created_at);

```

## 5. 近似去重计数 (HyperLogLog)


```sql
SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct FROM users;

```

HLL 高级用法（跨分段合并）:

```sql
SELECT HLL_ESTIMATE(HLL_COMBINE(hll_val)) AS combined_approx
FROM (
    SELECT HLL_ACCUMULATE(email) AS hll_val
    FROM users GROUP BY DATE_TRUNC('month', created_at)
);

```

## 横向对比: 去重方案

| 方案          | Snowflake        | PostgreSQL       | MySQL |
|------|------|------|------|
| 查询去重      | QUALIFY ROW_NUM  | 子查询ROW_NUM    | 子查询ROW_NUM |
| 删除重复      | CTAS+SWAP        | DELETE+ctid      | DELETE+临时表 |
| 防止重复      | MERGE            | ON CONFLICT      | ON DUP KEY |
| 近似计数      | APPROX_COUNT_DIST| HLL扩展          | 不支持 |
| 约束防重      | 不支持(不执行)   | UNIQUE约束       | UNIQUE约束 |

