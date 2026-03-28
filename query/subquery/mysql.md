# MySQL: 子查询

> 参考资料:
> - [MySQL 8.0 Reference Manual - Subqueries](https://dev.mysql.com/doc/refman/8.0/en/subqueries.html)
> - [MySQL 8.0 Reference Manual - Subquery Optimization](https://dev.mysql.com/doc/refman/8.0/en/subquery-optimization.html)
> - [MySQL 8.0 Reference Manual - Derived Tables](https://dev.mysql.com/doc/refman/8.0/en/derived-tables.html)
> - [MySQL 8.0 Reference Manual - Optimizing Subqueries with Semijoin](https://dev.mysql.com/doc/refman/8.0/en/semijoins.html)

## 基本语法

标量子查询（返回单个值）
```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

WHERE IN 子查询
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```

EXISTS / NOT EXISTS
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

比较运算符 + 子查询
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```

FROM 子查询（派生表，必须有别名）
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;
```

## MySQL 5.x 子查询的性能噩梦（历史教训）

### 5.5 及之前的 IN 子查询问题

查询: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

期望的执行方式（先执行子查询，得到 ID 列表）:
  (1) 执行子查询: SELECT user_id FROM orders WHERE amount > 100 → 得到 {1, 5, 12}
  (2) 改写为: SELECT * FROM users WHERE id IN (1, 5, 12)
  (3) 利用主键索引查找 3 行 → 瞬间完成

MySQL 5.5 的实际执行方式（灾难）:
  优化器将 IN 子查询改写为 EXISTS 关联子查询:
```sql
  SELECT * FROM users WHERE EXISTS (
      SELECT 1 FROM orders WHERE amount > 100 AND user_id = users.id
```

  );
  对 users 表每一行: 重新执行内部查询（关联子查询）
  如果 users 有 100 万行: 执行 100 万次子查询
  即使 orders 子查询本身很快，100 万次重复执行也会极慢

这个问题在 MySQL 社区被称为 "subquery materialization bug"
是 MySQL 5.x 时代最著名的性能陷阱
用户被迫手动将 IN 子查询改写为 JOIN:
```sql
SELECT u.* FROM users u JOIN orders o ON u.id = o.user_id WHERE o.amount > 100;
-- 或使用派生表:
SELECT u.* FROM users u JOIN (SELECT DISTINCT user_id FROM orders WHERE amount > 100) o
ON u.id = o.user_id;
```

### 根本原因: 优化器缺乏子查询优化策略

MySQL 5.5 的优化器对子查询只有一种策略: 转为关联子查询
没有:
  (1) 子查询物化（Subquery Materialization）: 先执行子查询存储结果
  (2) 半连接（Semijoin）: 将 IN/EXISTS 转为 JOIN
  (3) 子查询展开（Subquery Unnesting）: 将子查询提升为 JOIN
这些策略在 PostgreSQL 和 Oracle 中早已存在

## Semijoin 优化（5.6+）的工作原理

### 什么是 Semijoin

Semijoin: "半连接"，外表的每一行最多匹配内表一次
语义: IN / EXISTS 子查询的本质是 semijoin（只关心"是否存在匹配"，不关心匹配几次）

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
```

等价语义: 对每个 user，只要 orders 中存在匹配的 user_id 就返回
不等价于 INNER JOIN: INNER JOIN 会因为一个 user 有多个 order 而返回多行

### MySQL 5.6+ 的 Semijoin 策略

优化器可以选择以下策略（按场景自动选择）:

策略 A: Table Pullout（表拉出）
  条件: 子查询中的表可以通过唯一索引确定唯一性
  做法: 将子查询中的表直接提升到外部查询的 JOIN 中
  EXPLAIN: 子查询消失，变成普通 JOIN
  示例: WHERE id IN (SELECT pk FROM t) → JOIN t ON id = t.pk

策略 B: Duplicate Weedout（重复消除）
  做法: 将子查询转为 JOIN，用临时表对结果去重
  EXPLAIN: Extra: Start/End temporary
  适用: 无法使用 FirstMatch 或 LooseScan 时的通用 fallback

策略 C: FirstMatch（首次匹配）
  做法: 类似关联子查询（Nested Loop），但找到第一条匹配就停止
  EXPLAIN: Extra: FirstMatch(outer_table)
  适用: 外表较小、有索引支持时

策略 D: LooseScan（松散扫描）
  做法: 对内表索引进行去重扫描（跳过重复的 key）
  EXPLAIN: Extra: LooseScan
  适用: 内表的 JOIN 列有索引且重复值多

策略 E: Materialization（物化）
  做法: 先将子查询结果物化为临时表，再与外表 JOIN
  EXPLAIN: MATERIALIZED
  适用: 子查询不引用外部列（非关联子查询）

### Anti-join 优化（8.0.17+）

NOT IN / NOT EXISTS 子查询在 8.0.17+ 可以被优化为 anti-join:
```sql
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM orders);
```

优化器可以将其转为:
  users LEFT JOIN orders ON id = user_id WHERE user_id IS NULL
EXPLAIN 中表现为: type=ref, Extra: Not exists

注意 NOT IN 的 NULL 陷阱:
  如果子查询结果包含 NULL，NOT IN 返回空集!（SQL 标准行为）
  SELECT * FROM users WHERE id NOT IN (1, 2, NULL); → 返回空集
  原因: id NOT IN (..., NULL) → id != NULL → UNKNOWN → 不返回
  解决: 用 NOT EXISTS 代替 NOT IN（NOT EXISTS 不受 NULL 影响）
  或: WHERE id NOT IN (SELECT user_id FROM orders WHERE user_id IS NOT NULL)

## LATERAL 派生表（8.0.14+）

### 传统派生表的限制

派生表不能引用外部 FROM 子句中的列:
```sql
SELECT * FROM users u, (SELECT * FROM orders WHERE user_id = u.id) o;
```

ERROR: Unknown column 'u.id' in 'where clause'
派生表在语义上是独立的子查询（先执行子查询，再与外部 JOIN）

### LATERAL 打破独立性

LATERAL 允许派生表引用前面 FROM 子句中的列:
```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;
```

等价于关联子查询: SELECT u.username, (SELECT SUM(amount) FROM orders WHERE user_id = u.id)
但 LATERAL 可以返回多行（关联子查询在 SELECT 中只能返回标量）

### LATERAL 解决的问题

问题 1: "每组取 Top-N"（关联子查询只能返回标量）
```sql
SELECT u.username, latest.amount, latest.created_at
FROM users u
JOIN LATERAL (
    SELECT amount, created_at FROM orders
    WHERE user_id = u.id ORDER BY created_at DESC LIMIT 3
) latest ON TRUE;
```

等价方案: 窗口函数（见 window-functions/mysql.sql 第 4.2 节）
LATERAL 更直观且可能更高效（利用 LIMIT 提前终止）

问题 2: 参数化视图（派生表引用外部列）
计算每个用户的订单统计（多个聚合值）
```sql
SELECT u.username, stats.cnt, stats.total, stats.avg_amount
FROM users u
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt, SUM(amount) AS total, AVG(amount) AS avg_amount
    FROM orders WHERE user_id = u.id
) stats ON TRUE;
```

如果用标量子查询: 需要 3 个独立的子查询（SELECT 中的每个值一个）
LATERAL: 一个子查询返回多列

## 横向对比: 各引擎的子查询优化策略

### MySQL 的演进路径

5.5:   几乎不优化子查询（IN 转 EXISTS 关联子查询，性能灾难）
5.6:   引入 Semijoin 优化（Table Pullout, FirstMatch, LooseScan, Materialization）
5.7:   优化器改进，更多场景触发 semijoin
8.0:   子查询物化改进、派生表 merge、anti-join 优化
8.0.14: LATERAL 派生表
教训: 子查询优化是优化器最复杂的部分之一，需要持续迭代

### PostgreSQL 的子查询优化

PG 从很早就有成熟的子查询优化:
  (1) Subquery Flattening（子查询展开）: 将子查询提升为 JOIN
  (2) Subquery Materialization: 物化非关联子查询
  (3) Semijoin/Anti-join: EXISTS/NOT EXISTS 转 JOIN
  (4) LATERAL: 9.3+ 支持（比 MySQL 早 5 年）
PG 几乎不存在 MySQL 5.x 那样的子查询性能问题

### Oracle 的子查询优化

Oracle 的 CBO（Cost-Based Optimizer）是业界标杆:
  (1) Subquery Unnesting（子查询展开）: 自动将子查询转为 JOIN
  (2) Filter 操作: 对关联子查询缓存结果（相同外部值不重新执行）
  (3) Star Transformation: 维度表子查询优化（数据仓库场景）
  (4) /*+ UNNEST */ / /*+ NO_UNNEST */ hint: 手动控制展开行为
Oracle 的 Filter 缓存是独特的优化: 如果外部列的不同值很少，
缓存可以避免大量重复执行（MySQL 和 PG 都没有类似机制）

### SQL Server 的子查询优化

  (1) Subquery -> Apply（CROSS APPLY / OUTER APPLY）
  (2) Semijoin / Anti-semijoin
  (3) 独特优化: 对关联子查询使用 Lazy Spool（缓存中间结果）
  SQL Server 2016+: Adaptive Join（运行时根据数据量选择 NLJ 或 Hash Join）

### 分析型引擎的子查询处理

ClickHouse:
  IN 子查询: 物化为 Set（哈希集合），用于 IN 过滤
  JOIN 子查询: 物化为 Hash Table
  不支持关联子查询（需要改写为 JOIN）
  设计哲学: 分析查询应尽量用 JOIN 而非子查询

Spark SQL:
  高度优化的子查询展开（Subquery Unnesting）
  关联子查询自动改写为 Left Semi Join / Left Anti Join
  LATERAL: Spark 3.0+ 支持

## 对引擎开发者: 子查询优化的实现路线

### 最低要求（MVP）

  (1) 非关联子查询物化: IN (SELECT ...) 先执行子查询存储结果
      没有这个优化，IN 子查询会退化为逐行关联子查询（MySQL 5.5 的教训）
  (2) EXISTS 短路求值: 找到第一条匹配就返回 true

### 推荐实现

  (3) Semijoin 转换: IN/EXISTS → 半连接 JOIN
      这是子查询性能提升最大的优化（通常提升 10-100 倍）
  (4) Anti-join 转换: NOT IN/NOT EXISTS → 反连接
  (5) 标量子查询缓存: 对相同输入值的关联子查询缓存结果

### 高级优化

  (6) 子查询展开（Unnesting）: 将子查询提升为外部 JOIN
      需要处理: 语义等价性验证（去重、NULL 语义等）
  (7) LATERAL 支持: 允许派生表引用外部列
      实现: 在优化器中支持关联的派生表（Correlated Derived Table）
  (8) 谓词下推到子查询: 将外部 WHERE 条件推入子查询减少计算量

### NOT IN 的 NULL 语义是陷阱

实现 NOT IN 时必须正确处理 NULL:
  SQL 标准: NOT IN (..., NULL) → 全部返回 UNKNOWN → 空结果集
  这是反直觉的，但必须正确实现
  推荐: 在文档中提醒用户使用 NOT EXISTS 代替 NOT IN
  或: 提供编译器 warning（如果子查询列可能为 NULL）

## 子查询 vs JOIN vs CTE 的选择指南

IN 子查询 vs JOIN:
  语义: IN 是半连接（不产生重复行），JOIN 可能产生重复行
  性能: 5.6+ 两者通常等价（优化器自动转换）
  可读性: IN 更直观（"找出在订单表中存在的用户"）

EXISTS vs IN:
  EXISTS: 对关联子查询更高效（短路求值），不受 NULL 影响
  IN:     对非关联子查询更直观，但 NOT IN 有 NULL 陷阱

CTE vs 子查询:
  CTE: 可读性好（命名查询），可被多次引用
  子查询: MySQL 8.0.14+ 优化同样好（单次引用的 CTE 被内联）
> **注意**: MySQL 不支持 NOT MATERIALIZED hint，多次引用的 CTE 总是物化

LATERAL vs 关联子查询:
  LATERAL: 可以返回多行多列（SELECT 中的关联子查询只能返回标量）
  关联子查询: 更广泛支持（5.0+），LATERAL 需要 8.0.14+

## 版本演进

MySQL 5.5:   子查询性能差（IN 转 EXISTS 关联子查询）
MySQL 5.6:   Semijoin 优化引入（Table Pullout, FirstMatch, LooseScan, Materialization）
MySQL 5.7:   优化器改进: 更多 semijoin 策略, 派生表条件下推
MySQL 8.0:   Subquery to derived table 转换改进
MySQL 8.0.14: LATERAL 派生表支持
MySQL 8.0.17: Anti-join 优化（NOT IN/NOT EXISTS → anti-join）
MySQL 8.0.21: 派生表条件下推进一步增强
