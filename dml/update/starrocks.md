# StarRocks: UPDATE

> 参考资料:
> - [1] StarRocks Documentation - UPDATE
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. UPDATE: Primary Key 模型支持

 StarRocks UPDATE 仅支持 Primary Key / Unique Key 模型。
 Primary Key 模型通过内存 HashIndex 定位旧行 → 高效更新。

## 2. 基本 UPDATE

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
UPDATE users SET email = 'new@e.com', age = 26 WHERE username = 'alice';
UPDATE users SET age = age + 1;

UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

```

## 3. 多表 JOIN 更新

```sql
UPDATE users u JOIN orders o ON u.id = o.user_id
SET u.status = 1 WHERE o.amount > 1000;

WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;

```

## 4. Partial Update (部分列更新)

 Primary Key 模型支持部分列更新:
 Stream Load: curl -H "partial_update:true" -H "columns:id,email" ...

## 5. StarRocks vs Doris UPDATE 差异

 功能基本相同。差异在模型名:
   StarRocks: PRIMARY KEY 模型(语义更清晰)
   Doris:     UNIQUE KEY + MoW(语义模糊)

 限制相同: 不能更新 Key 列/分区键，不支持 ORDER BY/LIMIT。

 对引擎开发者的启示:
   列存引擎的 UPDATE 核心挑战:
### 1. 定位旧行(主键索引) → 内存 HashIndex

### 2. 标记旧行删除 → 写入 Delete Bitmap

### 3. 写入新行 → 追加到新的 Segment

### 4. 空间回收 → 后台 Compaction

Partial Update 的优化: 只读取/写入变更的列，减少 I/O。

