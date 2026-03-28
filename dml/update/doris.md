# Apache Doris: UPDATE

 Apache Doris: UPDATE

 参考资料:
   [1] Doris Documentation - UPDATE
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. UPDATE 的模型依赖: 仅 Unique Key 模型支持

 Doris UPDATE 仅支持 Unique Key 模型表。
 Duplicate Key / Aggregate Key 模型不支持直接 UPDATE。

 实现原理:
   UPDATE = DELETE(标记旧行) + INSERT(写入新行)
   Merge-on-Write 模型: 实时更新(写入时定位旧行)
   Merge-on-Read 模型:  延迟更新(Compaction 时合并)

 对比:
   StarRocks:  Primary Key 模型支持(同源但语法更清晰)
   ClickHouse: ALTER TABLE UPDATE(异步 Mutation，非实时)
   MySQL:      标准 UPDATE(行级实时)
   BigQuery:   标准 UPDATE(列式但支持行级)

## 2. 基本 UPDATE

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
UPDATE users SET email = 'new@e.com', age = 26 WHERE username = 'alice';
UPDATE users SET age = age + 1;

```

CASE 表达式

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

```

## 3. 多表 JOIN 更新 (2.0+)

```sql
UPDATE users u JOIN orders o ON u.id = o.user_id
SET u.status = 1 WHERE o.amount > 1000;

```

CTE + UPDATE (2.1+)

```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;

```

子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

```

## 4. Partial Column Update (2.0+，部分列更新)

 只更新指定列，其他列保持不变(Merge-on-Write Unique Key 模型)。
 SET enable_unique_key_partial_update = true;
 INSERT INTO users (id, email) VALUES (1, 'new@e.com');
 或 Stream Load: curl -H "partial_columns:true" ...

 设计分析:
   Partial Update 避免了"读取旧行全部列 → 修改 → 写回"的开销。
   对比 StarRocks: 也支持 Partial Update(Primary Key 模型)。
   对比 ClickHouse: 不支持部分列更新。

## 5. 限制

仅 Unique Key 模型支持
不支持更新 Key 列(排序键)
不支持更新分区键
不支持 ORDER BY / LIMIT
不支持 UPDATE ... RETURNING(PostgreSQL 特有)

