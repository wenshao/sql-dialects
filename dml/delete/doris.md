# Apache Doris: DELETE

 Apache Doris: DELETE

 参考资料:
   [1] Doris Documentation - DELETE
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. DELETE 的数据模型依赖

 Doris 的 DELETE 行为取决于数据模型:
   Unique Key (MoW):  完整支持标准 DELETE(行级删除)
   Unique Key (MoR):  DELETE 通过标记实现(后台 Compaction 清理)
   Duplicate Key:     DELETE 条件限于 Key 列或分区列
   Aggregate Key:     DELETE 条件限于 Key 列或分区列

 设计理由:
   列存引擎的删除不是"原地删除"而是"标记删除"(Tombstone)。
   Duplicate/Aggregate 模型没有唯一标识行的能力，
   所以只能按 Key/分区列条件删除(物理上是删除整个数据块)。

 对比:
   StarRocks:  Primary Key 模型完整 DELETE，其他模型受限(同源)
   ClickHouse: ALTER TABLE DELETE(异步 Mutation，不是实时删除)
   MySQL:      标准 DELETE(行级实时删除)
   BigQuery:   标准 DELETE(列式但支持行级)

## 2. Unique Key 模型 DELETE

```sql
DELETE FROM users WHERE username = 'alice';
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

```

多表 JOIN 删除(2.0+)

```sql
DELETE FROM users USING blacklist
WHERE users.email = blacklist.email;

```

CTE + DELETE(2.1+)

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';
DELETE FROM users;  -- 删除所有行

```

## 3. 非 Unique Key 模型 DELETE (有限制)

条件必须是 Key 列或分区列

```sql
DELETE FROM events WHERE event_date < '2023-01-01';
DELETE FROM events PARTITION p20240115 WHERE event_name = 'spam';

```

## 4. TRUNCATE (清空全表)

```sql
TRUNCATE TABLE users;

```

## 5. 分区级删除 (最高效)

```sql
ALTER TABLE events DROP PARTITION p20240115;

```

 临时分区原子替换:
 ALTER TABLE events ADD TEMPORARY PARTITION tp1 VALUES LESS THAN ('2024-02-01');
 -- 导入新数据到临时分区
 ALTER TABLE events REPLACE PARTITION (p2024_01) WITH TEMPORARY PARTITION (tp1);

## 6. 删除策略对比

DELETE WHERE:    行级删除(Unique Key 模型)，最灵活但最慢
TRUNCATE TABLE:  清空全表，快速
DROP PARTITION:   删除整个分区，最快(元数据操作)
临时分区替换:    原子替换分区数据，适合数据修复

限制:
不支持 DELETE ... ORDER BY / LIMIT
不支持 DELETE ... RETURNING(PostgreSQL 特有)
非 Unique Key 模型的 DELETE 条件受限

