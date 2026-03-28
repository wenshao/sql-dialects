# TDSQL: UPDATE

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - [TDSQL Distributed Transaction Guide](https://cloud.tencent.com/document/product/557/10575)
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

## MySQL 风格的高级 UPDATE


## 带 LIMIT / ORDER BY

```sql
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;
```

## 多表 UPDATE（JOIN）

```sql
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;
```

## 子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

## CASE 表达式

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

## 自引用更新

```sql
UPDATE users SET age = age + 1;
```

## CTE + UPDATE


```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;
```

## 分布式 UPDATE 与 shardkey 路由

TDSQL 是分布式数据库，数据按 shardkey 分布到不同分片。
UPDATE 操作的路由行为取决于 WHERE 条件:
(1) WHERE 包含 shardkey（单分片路由，性能最优）:
假设 id 是 shardkey:

```sql
UPDATE users SET age = 30 WHERE id = 42;
```

## (2) WHERE 包含 shardkey 范围:

```sql
UPDATE users SET status = 1 WHERE id BETWEEN 100 AND 200;
```

## (3) WHERE 不包含 shardkey（全分片扫描，性能差）:

```sql
UPDATE users SET status = 1 WHERE email = 'alice@example.com';
```

## shardkey 列的更新限制


重要限制: 不能修改 shardkey 列的值！
原因: shardkey 决定了行的分片位置
如果修改 shardkey 值，行需要从一个分片迁移到另一个分片
TDSQL 不支持自动的跨分片行迁移
错误示例（假设 id 是 shardkey）:
UPDATE users SET id = 100 WHERE id = 42;  -- 执行失败或行为未定义
替代方案: DELETE + INSERT
DELETE FROM users WHERE id = 42;
INSERT INTO users (id, username, email, age) VALUES (100, 'alice', ...);
注意: 需要在事务中执行以保证原子性

## 跨分片 UPDATE 的分布式事务

当 UPDATE 涉及多个分片时，TDSQL 使用分布式事务:
(1) 两阶段提交（2PC）:
Phase 1: Coordinator 向所有参与者发送 PREPARE
Phase 2: 所有参与者就绪后发送 COMMIT
(2) 多表 JOIN UPDATE 的分布式行为:

```sql
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;
```

## 广播表的 UPDATE

广播表（小表广播）: 数据完整复制到每个分片节点
广播表的 UPDATE 特点:
UPDATE 同步发送到所有节点执行
使用分布式事务保证所有节点的一致性
适合维度表、配置表等小表
示例:
UPDATE sys_config SET config_value = '2000' WHERE config_key = 'max_connections';
所有分片同时执行此 UPDATE

## 批量更新策略


策略 1: 按 shardkey 范围分批更新（推荐）
先确定需要更新的 shardkey 范围
按 shardkey 范围分批 UPDATE（每批在单个分片内）
避免跨分片事务
策略 2: 临时表 + JOIN UPDATE
CREATE TEMPORARY TABLE update_batch (user_id BIGINT, new_status INT);
INSERT INTO update_batch VALUES (1, 1), (2, 1), ...;
UPDATE users u JOIN update_batch b ON u.id = b.user_id SET u.status = b.new_status;
DROP TEMPORARY TABLE update_batch;
策略 3: INSERT ... ON DUPLICATE KEY UPDATE
对于需要全量覆盖更新的场景:
INSERT INTO users (id, username, email, age)
VALUES (42, 'alice', 'new@example.com', 30)
ON DUPLICATE KEY UPDATE email = VALUES(email), age = VALUES(age);
注意: 所有策略都应考虑 shardkey 路由以获得最佳性能

## 横向对比: TDSQL vs 单机 MySQL UPDATE

语法兼容性: TDSQL UPDATE 语法与 MySQL 完全兼容
主要差异在执行层面:
单机 MySQL:
UPDATE 直接修改本地 InnoDB 页
可以修改任何列（包括主键）
行锁粒度，MVCC 并发控制
TDSQL:
UPDATE 按 shardkey 路由到分片
不能修改 shardkey 列
跨分片使用分布式事务（2PC）
多表 JOIN UPDATE 推荐 shardkey 对齐
迁移注意:
(1) 检查是否有 UPDATE shardkey 列的语句（需要改为 DELETE + INSERT）
(2) 大范围 UPDATE 需要按 shardkey 分批执行
(3) 多表 UPDATE 确保 JOIN 的表 shardkey 设计一致
