# Teradata: DELETE

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)
> - [Teradata Performance Optimization Guide](https://docs.teradata.com/r/Teradata-VantageTM-Database-Administration)


## 1. 基本 DELETE


单行删除
```sql
DELETE FROM users WHERE username = 'alice';
```


多条件删除
```sql
DELETE FROM users WHERE status = 0 AND last_login < DATE '2023-01-01';
```


删除所有行（逐行删除，产生事务日志）
```sql
DELETE FROM users;
```


快速删除所有行（Teradata 特有，不产生日志）
```sql
DELETE users ALL;
```


TRUNCATE（较新版本支持）
TRUNCATE TABLE users;

## 2. 子查询与关联删除


IN 子查询
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```


EXISTS 关联删除
```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);
```


NOT EXISTS（删除没有订单的用户）
```sql
DELETE FROM users
WHERE NOT EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);
```


相关子查询
```sql
DELETE FROM users
WHERE age < (
    SELECT AVG(age) - 50 FROM users u2 WHERE u2.city = users.city
);
```


## 3. SAMPLE 删除（删除部分行）


随机删除 100 行（使用 SAMPLE）
```sql
DELETE FROM users WHERE username IN (
    SELECT username FROM users SAMPLE 100
);
```


百分比采样删除
```sql
DELETE FROM users WHERE id IN (
    SELECT id FROM users SAMPLE 0.1   -- 随机选取 0.1% 的行
);
```


分层采样删除（按城市分层，每层删除 10 行）
```sql
DELETE FROM users WHERE id IN (
    SELECT id FROM users
    SAMPLE WHEN city = 'Beijing' THEN 10
           WHEN city = 'Shanghai' THEN 10
           ELSE 5
    END
);
```


## 4. 归档 + 删除（两步操作）


先归档再删除
```sql
INSERT INTO users_archive SELECT * FROM users WHERE status = 0;
DELETE FROM users WHERE status = 0;
```


使用 VOLATILE 表优化大批量删除
```sql
CREATE VOLATILE TABLE vt_delete_ids (id INTEGER) PRIMARY INDEX (id) ON COMMIT PRESERVE ROWS;
INSERT INTO vt_delete_ids SELECT id FROM users WHERE last_login < DATE '2023-01-01';
DELETE FROM users WHERE id IN (SELECT id FROM vt_delete_ids);
DROP TABLE vt_delete_ids;
```


## 5. PRIMARY INDEX 与 DELETE 性能

Teradata 的数据分布基于 PRIMARY INDEX (PI):

(1) WHERE 条件包含 PI 列（single-AMP 操作，最优）:
```sql
DELETE FROM users WHERE id = 123;  -- id 是 UPI
```

操作只路由到 id=123 所在的 AMP
最快的 DELETE 方式

(2) WHERE 条件不包含 PI 列（all-AMP 操作，性能差）:
```sql
DELETE FROM users WHERE email = 'alice@example.com';
```

所有 AMP 都需要扫描数据
大表中性能非常差

(3) 大批量删除的 PI 策略:
先按 PI 列查出需要删除的 ID:
CREATE VOLATILE TABLE vt_ids AS (
SELECT id FROM users WHERE status = 0
) WITH DATA PRIMARY INDEX (id) ON COMMIT PRESERVE ROWS;
DELETE FROM users WHERE id IN (SELECT id FROM vt_ids);
这样 DELETE 走 PI 路由，每个 AMP 只处理自己的数据

## 6. 大规模 DELETE 的最佳实践

(1) 使用 PI 列作为 WHERE 条件:
确保 DELETE 操作路由到最少的 AMP

(2) 分区表的 DELETE:
如果表按分区组织（PPI），DELETE 可以利用分区裁剪
DELETE FROM logs WHERE log_date BETWEEN DATE '2023-01-01' AND DATE '2023-01-31';
如果 log_date 是 PPI 列，只扫描对应分区

(3) DROP PARTITION 替代 DELETE（最高效）:
ALTER TABLE logs DROP RANGE PARTITION p202001;
直接删除分区元数据，不产生事务日志，O(1) 操作

(4) 大量 DELETE 后收集统计信息:
-- COLLECT STATISTICS ON users COLUMN (status);
-- COLLECT STATISTICS ON users INDEX (id);
删除大量数据后，统计信息过时会导致查询计划不优

## 7. DELETE 与 Teradata 并行架构

Teradata 的 BYNET 互联架构:
all-AMP DELETE: 所有 AMP 并行删除各自 vdisk 上的数据
single-AMP DELETE: 只涉及一个 AMP

事务日志:
DELETE 操作产生 Transient Journal（TJ）
大批量 DELETE 会占用大量 TJ 空间
DELETE ALL 不产生 TJ（但也是不可回滚的）

并发考虑:
DELETE 和 INSERT/UPDATE 可能竞争同一行的锁
Teradata 使用行哈希锁（row-hash lock）
大批量 DELETE 可能阻塞其他操作

## 8. 横向对比: Teradata vs 其他数据仓库 DELETE

- **Teradata**: 支持 DELETE（行级），all-AMP 操作性能差
DELETE ALL 快速但不产生日志
需要 COLLECT STATISTICS 维护统计信息
- **Redshift**: 支持 DELETE，但大数据量删除产生大量 vacuum 开销
- **推荐**: DROP PARTITION 或 INSERT INTO + TRUNCATE + RENAME
- **Snowflake**: 支持 DELETE，自动回收空间（Time Travel 保留历史版本）
不需要手动维护统计信息（自动统计）
- **BigQuery**: 支持 DELETE，但有 DML 配额限制
- **推荐**: WHERE 过滤 + 覆盖写入
- **Hive**: 支持 ACID DELETE（需 ORC + 事务表 + 分桶）
DELETE 性能差，产生大量 delta 文件需要 compaction
- **Spark**: 不支持直接 DELETE（需要 overwrite 或 merge）

- **结论**: 数据仓库场景下，应使用分区策略（DROP PARTITION）替代大量 DELETE
