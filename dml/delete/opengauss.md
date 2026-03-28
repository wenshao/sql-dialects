# openGauss/GaussDB: DELETE

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)
> - [openGauss MOT (Memory-Optimized Table) Guide](https://docs.opengauss.org/zh/docs/latest/docs/Developerguide/mot.html)


## 基本 DELETE


## 单行删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 多条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01'::date;
```

## 删除所有行

```sql
DELETE FROM users;
```

## 快速清空表（DDL 操作，但在 openGauss 中可回滚）

```sql
TRUNCATE TABLE users;
TRUNCATE TABLE users RESTART IDENTITY;    -- 同时重置序列
TRUNCATE TABLE users CASCADE;             -- 级联截断
```

## USING 子句（PostgreSQL 风格多表删除）


## USING 关联删除

```sql
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;
```

## 多表 USING

```sql
DELETE FROM users
USING blacklist, spam_reports
WHERE users.email = blacklist.email
   OR users.email = spam_reports.email;
```

## 子查询与 EXISTS


## IN 子查询

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## EXISTS 关联删除

```sql
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);
```

## NOT EXISTS（删除没有订单的用户）

```sql
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

## RETURNING 子句


## 返回被删除的行

```sql
DELETE FROM users WHERE status = 0 RETURNING id, username;
```

## RETURNING 所有列

```sql
DELETE FROM users WHERE id = 42 RETURNING *;
```

## RETURNING + 归档（CTE + DELETE + INSERT 原子操作）

```sql
WITH deleted AS (
    DELETE FROM users WHERE status = 0
    RETURNING id, username, email, age
)
INSERT INTO users_archive (id, username, email, age, archived_at)
SELECT id, username, email, age, now() FROM deleted;
```

## CTE (WITH) + DELETE


```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

## 多层 CTE

```sql
WITH
    target_ids AS (
        SELECT user_id FROM orders
        GROUP BY user_id HAVING SUM(amount) < 100
    ),
    to_delete AS (
        SELECT id FROM users
        WHERE id IN (SELECT user_id FROM target_ids) AND status = 0
    )
DELETE FROM users WHERE id IN (SELECT id FROM to_delete);
```

## MOT (Memory-Optimized Table) 的 DELETE 行为

openGauss 的 MOT 引擎是基于内存优化的 OLTP 存储引擎:
MOT 表数据常驻内存，DELETE 操作具有特殊行为:
(1) MOT DELETE 性能特征:
DELETE 是原地操作（in-place），不产生 dead tuples
比 heap 表的 DELETE 快 2-5 倍（无 MVCC 版本链维护）
不需要 VACUUM 回收空间（内存直接释放）
(2) MOT DELETE 的限制:
不支持 RETURNING 子句
不支持 CTE + DELETE
不支持 USING 子句（需用子查询替代）
外键引用的表必须是 MOT 表（不能混合 MOT 和 heap 表）
(3) MOT 表创建与删除:
CREATE TABLE users_mot (...) WITH (MEMORY_OPTIMIZED = ON);
DELETE FROM users_mot WHERE status = 0;
语法与普通表相同，但执行路径不同
(4) MOT 的事务隔离:
MOT 使用乐观并发控制（OCC），而非 MVCC
DELETE 在提交时检测冲突: 如果其他事务修改了同一行，提交失败
适合高并发短事务场景，不适合长事务大批量删除

## 列存储表的 DELETE 行为

openGauss/GaussDB 的列存储表（Column Store）DELETE 特性:
(1) 标记删除（Delete Bitmap）:
列存储表的 DELETE 不是立即物理删除
而是在 delete bitmap 中标记该行已删除
查询时跳过标记的行（但不回收空间）
(2) 空间回收:
需要执行 VACUUM FULL 或 gs_ctl compact 来回收空间
大量 DELETE 后如果不回收，查询性能会下降
(3) 性能影响:
大量标记删除会降低查询性能（需要扫描并跳过标记行）
列存储表更适合批量加载 + 少量更新的分析场景
频繁 DELETE 是列存储表的反模式

## GaussDB 分布式版本的 DELETE

GaussDB 分布式版本中，数据按分布键分布在多个 DN 节点上:
(1) 分布键在 WHERE 条件中:
DELETE FROM users WHERE id = 42;  -- id 是分布键
路由到单个 DN 节点执行，性能最优
(2) 分布键不在 WHERE 条件中:
DELETE FROM users WHERE email = 'alice@example.com';
需要向所有 DN 节点下发查询，收集结果后执行删除
性能较差，应尽量避免
(3) 跨节点 DELETE:
涉及多表关联的 DELETE 使用分布式执行计划
使用 FQS（Fast Query Shipping）或 Stream 执行框架
(4) 分布式事务保证:
GaussDB 使用两阶段提交（2PC）保证跨节点事务一致性
GTM（Global Transaction Manager）协调全局事务

## 批量删除策略


策略 1: 分批删除（heap 表推荐）
DO $$
BEGIN
LOOP
DELETE FROM logs WHERE created_at < '2023-01-01' LIMIT 10000;
EXIT WHEN NOT FOUND;
COMMIT;
END LOOP;
END $$;
策略 2: DROP PARTITION（分区表推荐，O(1) 操作）
ALTER TABLE logs DROP PARTITION p2020;
不产生 dead tuples，不阻塞查询
策略 3: TRUNCATE（清空整表）
最快，但会清空所有数据
策略 4: VACUUM 回收空间
大量 DELETE 后执行:
VACUUM users;           -- 普通回收，不锁表
VACUUM FULL users;      -- 完全回收，锁表但最彻底
ANALYZE users;          -- 更新统计信息
