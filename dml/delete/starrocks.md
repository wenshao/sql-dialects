# StarRocks: DELETE

> 参考资料:
> - [1] StarRocks Documentation - DELETE
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. DELETE 的模型依赖 (与 Doris 同源)

 Primary Key 模型: 完整支持行级 DELETE
 Unique Key 模型:  DELETE 通过标记(后台清理)
 Duplicate/Aggregate: DELETE 条件限于 Key/分区列

 对比 Doris: 功能完全相同(同源架构)。
 StarRocks 的 PRIMARY KEY 模型 DELETE 性能更好
 (内存 HashIndex 快速定位目标行)。

## 2. Primary Key 模型 DELETE

```sql
DELETE FROM users WHERE username = 'alice';
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

```

多表 JOIN 删除

```sql
DELETE FROM users USING blacklist
WHERE users.email = blacklist.email;

```

CTE + DELETE

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

## 3. 非 Primary Key 模型 DELETE

```sql
DELETE FROM events WHERE event_date < '2023-01-01';
DELETE FROM events PARTITION p20240115 WHERE event_name = 'spam';

```

## 4. TRUNCATE / 分区删除

```sql
TRUNCATE TABLE users;
ALTER TABLE events DROP PARTITION p20240115;

```

## 5. StarRocks vs Doris DELETE 差异

 功能基本相同。核心差异在模型命名:
   StarRocks: PRIMARY KEY 模型(独立语法)
   Doris:     UNIQUE KEY + MoW(复用语法)

 性能差异:
   StarRocks Primary Key: 内存 HashIndex → O(1) 定位 → 删除快
   Doris Unique Key MoW: 类似实现

 对引擎开发者的启示:
   列存引擎的 DELETE 核心挑战:
1. 定位目标行: 需要主键索引(行存引擎用 B-Tree)

2. 标记删除: 不能原地删除(会破坏列存布局)

3. 空间回收: 延迟到 Compaction(后台合并)

DELETE 性能 = 主键索引查找 + 写入 Tombstone(非常快)。
空间回收 = Compaction 频率(影响读性能)。

