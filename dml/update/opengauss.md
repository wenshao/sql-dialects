# openGauss/GaussDB: UPDATE

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)
> - [openGauss MOT (Memory-Optimized Table) Guide](https://docs.opengauss.org/zh/docs/latest/docs/Developerguide/mot.html)
> - [openGauss Column Store Guide](https://docs.opengauss.org/zh/docs/latest/docs/Developerguide/column-store.html)
> - ============================================================
> - 1. 基本 UPDATE
> - ============================================================
> - 单列更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## 多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## 全表更新

```sql
UPDATE users SET status = 1;
```

## FROM 子句（PostgreSQL 风格多表更新）


## 使用 FROM 引用其他表

```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```

## FROM 多表

```sql
UPDATE users SET city = o.shipping_city
FROM orders o, addresses a
WHERE users.id = o.user_id AND users.id = a.user_id AND a.verified = true;
```

## 子查询更新


## 标量子查询

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

## 相关子查询

```sql
UPDATE users u SET total_orders = (
    SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id
);
```

## IN 子查询

```sql
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);
```

## CASE 表达式


```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

## RETURNING 子句


## 返回更新后的行

```sql
UPDATE users SET age = 26 WHERE username = 'alice'
RETURNING id, username, age;
```

## RETURNING 表达式

```sql
UPDATE users SET age = age + 1
RETURNING id, username, age, age - 1 AS old_age;
```

## CTE (WITH) + UPDATE


```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2 WHERE id IN (SELECT user_id FROM vip);
```

## MOT (Memory-Optimized Table) 的 UPDATE 行为

openGauss 的 MOT 引擎是基于内存优化的 OLTP 存储引擎:
MOT 表数据常驻内存，UPDATE 操作具有特殊行为:
(1) MOT UPDATE 性能特征:
UPDATE 是原地操作（in-place update），直接修改内存中的数据
不创建新版本（无 MVCC 版本链），比 heap 表快 2-5 倍
使用乐观并发控制（OCC）: 在提交时检测冲突
不产生 dead tuples，不需要 VACUUM
(2) MOT UPDATE 的限制:
不支持 RETURNING 子句
不支持 CTE + UPDATE
不支持 FROM 子句
部分数据类型不支持（如大对象类型）
(3) MOT 并发控制:
乐观并发控制（OCC）: 读取时不加锁，提交时验证
适合高并发短事务场景（如金融交易）
不适合长事务或大量行更新的场景（冲突率高）
示例:
CREATE TABLE accounts_mot (
id INT PRIMARY KEY,
balance DECIMAL(18,2)
) WITH (MEMORY_OPTIMIZED = ON);
UPDATE accounts_mot SET balance = balance - 100 WHERE id = 42;
语法与普通表相同，但执行路径通过 MOT 引擎

## 列存储表（Column Store）的 UPDATE 行为

openGauss/GaussDB 的列存储表 UPDATE 特性:
(1) UPDATE = DELETE + INSERT:
列存储表的 UPDATE 不是原地修改，而是标记删除旧行 + 插入新行
旧行在 delete bitmap 中标记为删除
新行追加到最新的 CUDesc（Column Unit Descriptor）中
(2) 性能影响:
单行 UPDATE 性能差（需要标记 + 追加 + 更新所有列）
批量 UPDATE 性能更差（每次 UPDATE 都产生新的 CU）
列存储表的设计目标是批量读、少量写，不适合频繁 UPDATE
(3) 推荐 UPDATE 策略（列存储表）:
避免频繁的行级 UPDATE
使用 INSERT + DELETE 替代（先插入新数据，再删除旧数据）
或使用分区表: DROP 旧分区 + ADD 新分区
(4) 行存储 vs 列存储 UPDATE 对比:
行存储（Heap）: 原地更新（MVCC 新版本），适合 OLTP
列存储（CStore）: 标记删除 + 追加插入，适合 OLAP

## GaussDB 分布式版本的 UPDATE

GaussDB 分布式版本中，数据按分布键分布在多个 DN 节点上:
(1) 分布键在 WHERE 条件中:
UPDATE users SET age = 30 WHERE id = 42;  -- id 是分布键
路由到单个 DN 节点执行，性能最优
(2) 分布键不在 WHERE 条件中:
UPDATE users SET age = 30 WHERE email = 'alice@example.com';
需要向所有 DN 节点下发查询和更新
性能较差，应尽量避免
(3) 修改分布键值:
UPDATE users SET id = 100 WHERE id = 42;
行需要从旧 DN 节点迁移到新 DN 节点（跨节点数据重分布）
GaussDB 可能禁止直接修改分布键值
推荐: DELETE + INSERT 替代
(4) 分布式事务保证:
跨节点 UPDATE 使用两阶段提交（2PC）保证一致性
GTM（Global Transaction Manager）协调全局快照

## 批量更新策略与性能优化


(1) heap 表分批更新:
DO $$
BEGIN
LOOP
UPDATE users SET status = 1
WHERE status = 0 AND id IN (
SELECT id FROM users WHERE status = 0 LIMIT 5000
);
EXIT WHEN NOT FOUND;
COMMIT;
END LOOP;
END $$;
(2) 列存储表更新策略:
不适合频繁 UPDATE，应使用 INSERT + DELETE 策略
或使用分区表的 EXCHANGE PARTITION 操作
(3) 更新统计信息:
大量 UPDATE 后执行 ANALYZE:
ANALYZE users;
VACUUM users;      -- 回收 dead tuples
VACUUM FULL users; -- 完全回收（锁表）
