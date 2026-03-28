# MySQL: UPDATE

> 参考资料:
> - [MySQL 8.0 Reference Manual - UPDATE](https://dev.mysql.com/doc/refman/8.0/en/update.html)
> - [MySQL 8.0 Reference Manual - InnoDB Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
> - [MySQL 8.0 Reference Manual - InnoDB Transaction Model](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-model.html)

## 基本语法

基本更新
```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

多列更新
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

带 LIMIT（MySQL 特有，其他主流数据库不支持）
> **注意**: 没有 ORDER BY 时更新哪些行是不确定的
```sql
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;
```

CASE 表达式实现条件更新
```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

自引用更新（SET 子句中引用同一行的其他列）
```sql
UPDATE users SET age = age + 1;
```

MySQL 特有行为: SET 子句从左到右求值，后面的列能看到前面的新值
UPDATE t SET a = a + 1, b = a;  -- b 得到的是更新后的 a（非标准行为）
PostgreSQL/SQL Server: SET 子句同时求值，b 得到的是更新前的 a

## 多表 UPDATE

多表更新（JOIN 语法，MySQL 特有）
```sql
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;
```

子查询更新
> **注意**: 5.7 及之前 ERROR 1093，不能在 UPDATE 子查询中引用同一张表
需要包一层派生表绕过:
```sql
UPDATE users SET age = (SELECT avg_age FROM (SELECT AVG(age) AS avg_age FROM users) t)
WHERE age IS NULL;
```

8.0+: 部分场景已解除此限制

8.0+: WITH CTE 配合 UPDATE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;
```

## UPDATE 的锁行为分析（对引擎开发者关键）

### InnoDB 的锁类型层次

InnoDB 使用多粒度锁协议:
  表级锁:  意向锁（IS/IX），UPDATE 自动获取 IX 锁（不阻塞其他行的操作）
  行级锁:  Record Lock（锁定索引记录）
           Gap Lock（锁定索引记录之间的间隙，防止幻读）
           Next-Key Lock = Record Lock + Gap Lock（默认锁类型，左开右闭区间）

UPDATE 的加锁过程:
  (1) 根据 WHERE 条件定位需要更新的行
  (2) 对扫描到的每条索引记录加 X 锁（排他锁）
  (3) 在 REPEATABLE READ 隔离级别下，同时加 Gap Lock 防止幻读
  (4) 如果通过二级索引定位，还需要回表对聚集索引记录加锁

关键点: InnoDB 的锁是加在索引上的，不是加在行上的。
如果 WHERE 条件不走索引（全表扫描），会锁定所有扫描到的行（接近锁全表）。

### 不同 WHERE 条件的锁行为对比

场景 A: 主键精确匹配
```sql
UPDATE users SET age = 26 WHERE id = 1;
```

加锁: 仅对 id=1 的聚集索引记录加 Record Lock（无 Gap Lock）
并发影响: 最小，只阻塞同一行的写操作

场景 B: 唯一索引精确匹配
```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

加锁: 对 uk_username 索引记录加 Record Lock + 对聚集索引记录加 Record Lock
并发影响: 小，锁定两条索引记录

场景 C: 非唯一索引范围扫描
```sql
UPDATE users SET status = 0 WHERE age > 60;
```

加锁: 对 age > 60 范围内每条索引记录加 Next-Key Lock
       + 对对应的聚集索引记录加 Record Lock
并发影响: 大，锁定范围内所有行及间隙，阻塞该范围的 INSERT

场景 D: 无索引的 WHERE 条件
```sql
UPDATE users SET status = 0 WHERE bio LIKE '%inactive%';
```

加锁: 全表扫描，对每条记录加 Next-Key Lock（即使不满足条件的行也会被锁）
并发影响: 接近锁全表！这是 UPDATE 性能问题的最常见原因。
解决方案: 为 WHERE 条件创建合适的索引

### 多表 UPDATE 的执行计划差异

```sql
UPDATE users u JOIN orders o ON u.id = o.user_id SET u.status = 1 WHERE o.amount > 1000;
```

执行计划依赖优化器的 JOIN 顺序选择:
  方案 A: 先扫描 orders（驱动表），再通过 user_id 更新 users
  方案 B: 先扫描 users，再通过 JOIN 条件过滤
优化器选择不同方案会导致锁的范围和顺序不同，可能引起死锁。

最佳实践:
  (1) 用 EXPLAIN 检查多表 UPDATE 的执行计划
  (2) 确保 JOIN 条件和 WHERE 条件都有索引
  (3) 如果遇到死锁，考虑拆分为: 先 SELECT 获取 ID 列表，再单表 UPDATE

## UPDATE 的 MVCC 与 undo log

InnoDB 每次 UPDATE:
  (1) 将旧版本写入 undo log（用于事务回滚和 MVCC 快照读）
  (2) 在聚集索引的记录头中更新 trx_id（事务 ID）和 roll_pointer（指向 undo）
  (3) 如果更新了二级索引列: 标记旧索引记录为删除 + 插入新索引记录
      （二级索引不存在原地更新，总是 delete-mark + insert）

对引擎开发者的启示:
  UPDATE 在存储层通常实现为 "原地修改 + 版本链" 或 "删除旧版本 + 插入新版本"。
  InnoDB 对聚集索引采用原地修改（如果更新不改变行大小），对二级索引采用删除+插入。
  PostgreSQL 的做法完全不同: 每次 UPDATE 都是插入新元组（no in-place update），
  旧元组标记为 dead，由 VACUUM 清理。这导致 PG 的 UPDATE 比 MySQL 更重（HOT 优化例外）。

## 横向对比: UPDATE 的设计差异

MySQL vs PostgreSQL: SET 子句求值顺序
  MySQL:      从左到右顺序求值（SET a=1, b=a 中 b 得到新的 a 值）
  PostgreSQL: 同时求值（SET a=1, b=a 中 b 得到旧的 a 值）
  SQL 标准:   未明确规定，但多数引擎采用 PG 的同时求值语义
  对引擎开发者: 需要明确选择并在文档中说明，这是常见的迁移兼容性问题

MySQL vs PostgreSQL: UPDATE ... LIMIT
  MySQL:   支持 UPDATE ... ORDER BY ... LIMIT N（非标准但实用）
  PG:      不支持，需要用 WHERE id IN (SELECT id FROM t ... LIMIT N)
  Oracle:  不支持 LIMIT，用 WHERE ROWNUM <= N 或 FETCH FIRST N ROWS
  适用场景: 分批更新大表时避免长事务，MySQL 的语法最简洁

MySQL vs PostgreSQL: UPDATE ... FROM
  MySQL:   UPDATE t1 JOIN t2 ON ... SET ...（JOIN 语法）
  PG:      UPDATE t1 SET ... FROM t2 WHERE t1.id = t2.id（FROM 子句语法）
  Oracle:  UPDATE (SELECT ... FROM t1 JOIN t2 ...) SET ...（可更新视图语法）
  SQL 标准: 不包含多表 UPDATE，各引擎各自实现

ClickHouse: 异步 mutation vs RDBMS 同步 UPDATE
  ALTER TABLE t UPDATE col = val WHERE ...;   -- ClickHouse 语法（注意是 ALTER）
  ClickHouse 的 UPDATE 实际上是异步 mutation:
    (1) 提交 mutation 任务到队列，语句立即返回
    (2) 后台逐 part 重写数据（实际上是读旧 part → 过滤 → 写新 part）
    (3) 旧 part 在 mutation 完成后被删除
  这意味着:
    - UPDATE 不是即时生效的（有延迟，可能几秒到几分钟）
    - 没有行级锁概念（列式存储按 part 级别操作）
    - 不适合频繁的单行更新（OLTP 场景应选择 RDBMS）
  CHECK: SELECT * FROM system.mutations WHERE is_done = 0;

对引擎开发者的启示:
  OLTP 引擎: UPDATE 必须是同步的、行级锁定的、ACID 的
  OLAP 引擎: UPDATE 可以是异步的、批量的、最终一致的
  混合引擎: 需要在两者之间找到平衡（如 TiDB 的 TiKV 同步更新 + TiFlash 异步同步）

## UPDATE 性能优化和常见陷阱

陷阱 1: 无 WHERE 的 UPDATE（全表更新）
```sql
UPDATE users SET status = 0;
```

在大表上: 锁全表、生成大量 undo log、binlog event 过大、可能导致复制延迟

陷阱 2: 更新主键值
```sql
UPDATE users SET id = id + 1000000;
```

聚集索引重组: 每一行都要物理移动，所有二级索引都要更新（指向新的主键值）
性能: 比更新普通列慢 10-100 倍

陷阱 3: 长事务中的 UPDATE
BEGIN; UPDATE users SET age = 26 WHERE id = 1; ... 很久后 ... COMMIT;
锁持有时间 = 事务持续时间（不是 UPDATE 执行时间）
长事务导致: 锁等待链变长 → 死锁概率增加 → undo log 膨胀

最佳实践:
  (1) 大表分批更新: 用 WHERE id BETWEEN ... AND ... 分段 + 每段独立事务
  (2) 确保 WHERE 条件有索引: EXPLAIN UPDATE ... 检查执行计划
  (3) 避免在高峰期做全表 UPDATE: 使用 pt-online-schema-change 等工具
  (4) 监控锁等待: SELECT * FROM information_schema.INNODB_TRX;

## 版本演进

MySQL 5.6:  优化器改进，UPDATE 子查询性能提升
MySQL 5.7:  生成列（Generated Column）不能直接 UPDATE
MySQL 8.0:  CTE + UPDATE 支持；部分解除同表子查询限制
MySQL 8.0:  EXPLAIN ANALYZE 可用于分析 UPDATE 的实际执行（8.0.18+）
