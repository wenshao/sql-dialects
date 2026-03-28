# TDSQL: 子查询 (Subqueries)

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation - SQL Statements](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation - Distributed Queries](https://cloud.tencent.com/document/product/557)
> - [MySQL 8.0 Reference - Subqueries](https://dev.mysql.com/doc/refman/8.0/en/subqueries.html)
> - ============================================================
> - 1. 标量子查询
> - ============================================================
> - 示例数据:
> - users(id, username, age, city, shardkey)
> - orders(id, user_id, amount, shardkey)

```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

## 标量子查询必须返回 0 或 1 行，否则运行时报错

TDSQL 注意: 如果 orders 和 users 的 shardkey 不同，此处触发跨分片查询

```sql
SELECT username,
    (SELECT SUM(amount) FROM orders WHERE user_id = users.id) AS total_amount
FROM users
WHERE city = 'Beijing';
```

## WHERE 子查询 (IN / NOT IN)


```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```

NOT IN 的 NULL 陷阱:
如果子查询返回任何 NULL，NOT IN 的结果为 UNKNOWN（空集）。
因为: x NOT IN (1, NULL) = x<>1 AND x<>NULL = ? AND UNKNOWN = UNKNOWN
解决: 使用 NOT EXISTS 替代 NOT IN
TDSQL 分布式优化:
当子查询中包含 shardkey 条件时，TDSQL 可以将 IN 子查询下推到对应分片。
例如: WHERE user_id IN (SELECT user_id FROM orders WHERE shardkey = 'value')

## EXISTS / NOT EXISTS


```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

EXISTS 在分布式环境下的优化:
TDSQL 优化器尽可能将 EXISTS 转为 Semi Join 并下推到分片。
如果关联条件涉及 shardkey，可以避免跨分片扫描。

## 比较运算符 + ALL / ANY / SOME


```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```

## FROM 子查询（派生表 / Derived Table）


```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;
```

## MySQL 8.0+ / TDSQL: 派生表支持 LATERAL（8.0.14+ 兼容）

但 TDSQL 分布式模式下 LATERAL 可能触发全表跨分片扫描，谨慎使用

```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;
```

## 子查询与分布式执行


TDSQL 架构:
TDSQL 通过 shardkey 将数据分布到多个物理分片（Set）。
子查询的性能取决于是否能在分片内完成。
跨分片子查询:
当子查询引用的表与外表的 shardkey 不同时，需要在协调节点汇总。
示例: users 按 id 分片，orders 按 user_id 分片:
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
如果 id = user_id 则 shardkey 一致可下推；否则需要跨分片。
优化建议:
(a) 尽量让子查询中的关联列与 shardkey 一致
(b) 用 JOIN 替代 IN 子查询，给优化器更多选择
(c) 对大结果集的子查询使用临时表 + 索引
用临时表优化复杂子查询:

```sql
CREATE TEMPORARY TABLE tmp_active_users AS
    SELECT DISTINCT user_id FROM orders WHERE amount > 100;
CREATE INDEX idx_tmp ON tmp_active_users (user_id);

SELECT u.* FROM users u
INNER JOIN tmp_active_users t ON u.id = t.user_id;

DROP TEMPORARY TABLE tmp_active_users;
```

## 子查询优化: MySQL 8.0 优化器改进


MySQL 8.0 子查询优化策略（TDSQL 继承）:
IN (subquery)       → Semi Join (FirstMatch, LooseScan, Materialization, Duplicate Weedout)
EXISTS (subquery)   → Semi Join
标量子查询           → 缓存优化（Subquery Cache）
派生表              → 合并到外层查询（Derived Merge, 8.0 派生条件下推）
EXPLAIN 查看子查询执行计划:

```sql
EXPLAIN SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
```

## 横向对比: TDSQL vs 其他数据库


## 子查询语法:

TDSQL:      MySQL 兼容（IN, EXISTS, ALL, ANY, 派生表）
PostgreSQL: 扩展支持 LATERAL, ARRAY(SELECT ...)
Oracle:     支持层级子查询, WITH 子句递归
SQL Server: CROSS APPLY / OUTER APPLY（等价于 LATERAL）
2. 分布式子查询:
TDSQL:      shardkey 路由优化，跨分片需协调
PolarDB-X:  类似分片路由优化
CockroachDB: DistSQL 分布式执行计划
TiDB:       子查询下推 + Hash Join
3. NOT IN 的 NULL 处理:
所有数据库: NOT IN + NULL 子查询 = 空集（SQL 标准行为）
最佳实践: 总是用 NOT EXISTS 替代 NOT IN

## 对引擎开发者的启示


(1) 分布式环境下的子查询优化是核心挑战:
TDSQL 的 shardkey 路由决定子查询是否需要跨分片执行。
理想的分布式子查询: 在分片内完成 Semi Join，避免数据汇总。
(2) MySQL 8.0 的子查询优化器已经大幅改进:
Semi Join 的多种策略（Materialization, FirstMatch, LooseScan）
允许优化器根据数据分布选择最优方案。
TDSQL 在此基础上增加了分布式路由优化。
(3) 跨分片子查询的替代方案:
使用 JOIN + shardkey 条件替代 IN 子查询。
使用临时表物化子查询结果再关联。
使用 UNION ALL 分别查询各分片再合并。

## 版本演进

MySQL 5.6:  子查询优化引入（Semi Join, Materialization）
MySQL 5.7:  派生表合并（Derived Merge）
MySQL 8.0:  LATERAL 派生表 (8.0.14), 通用表表达式 (CTE), 窗口函数
MySQL 8.0:  派生条件下推（Derived Condition Pushdown）
TDSQL:      在 MySQL 基础上增加 shardkey 路由优化和分布式执行
