# Oracle: JOIN 连接

> 参考资料:
> - [Oracle SQL Language Reference - Joins](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Joins.html)
> - [Oracle SQL Language Reference - SELECT](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html)

## 标准 JOIN 语法（9i+ 完整支持 SQL 标准）

INNER JOIN
```sql
SELECT u.username, o.amount
FROM users u INNER JOIN orders o ON u.id = o.user_id;
```

LEFT / RIGHT / FULL OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;
```

CROSS JOIN
```sql
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;
```

NATURAL JOIN / USING
```sql
SELECT * FROM users NATURAL JOIN orders;
SELECT * FROM users JOIN orders USING (user_id);
```

## Oracle 传统 JOIN 语法（(+) 外连接，Oracle 独有）

传统内连接（逗号分隔 + WHERE）
```sql
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;
```

(+) 外连接: 放在"可能为 NULL 的一侧"
LEFT JOIN:
```sql
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id(+);
```

RIGHT JOIN:
```sql
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id(+) = o.user_id;
```

设计分析: (+) 语法的问题
  1. 无法表达 FULL OUTER JOIN（两边都加 (+) 是非法的）
  2. (+) 不能与 OR 和 IN 组合使用
  3. 可读性差，容易忘记加 (+) 导致变成内连接
  4. 只有 Oracle 支持这种语法（可移植性为零）

横向对比:
  Oracle:  (+) 传统语法（所有版本）+ SQL 标准 JOIN (9i+)
  MySQL:   只有 SQL 标准 JOIN（无传统语法）
  PostgreSQL: 只有 SQL 标准 JOIN
  SQL Server:  *= 和 =* 已废弃（2005+），只有标准 JOIN

对引擎开发者的启示:
  不要发明非标准的 JOIN 语法。SQL 标准的 INNER/LEFT/RIGHT/FULL/CROSS
  已经完整覆盖所有 JOIN 类型，且语义清晰。
  如果要兼容 Oracle 旧代码，可以将 (+) 作为方言支持，但不应推荐使用。

## LATERAL / CROSS APPLY / OUTER APPLY（12c+）

LATERAL: 允许子查询引用外部表的列
```sql
SELECT u.username, latest.amount
FROM users u
CROSS JOIN LATERAL (
    SELECT amount FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) latest;
```

CROSS APPLY（同 LATERAL，SQL Server 兼容语法）
```sql
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT amount FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) latest;
```

OUTER APPLY（允许右侧无匹配行时返回 NULL）
```sql
SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT amount FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) latest;
```

设计分析:
  LATERAL 是 SQL:2003 标准特性，允许在 FROM 子句中引用前面的表。
  这打破了 SQL 的"FROM 子句中表相互独立"的传统假设。
  核心价值: "每组取 Top-N" 等问题可以用 LATERAL 优雅解决。

横向对比:
  Oracle 12c+:   LATERAL / CROSS APPLY / OUTER APPLY（全部支持）
  PostgreSQL 9.3+: LATERAL（SQL 标准）
  SQL Server:    CROSS APPLY / OUTER APPLY（2005+，最早支持）
  MySQL 8.0.14+: LATERAL（SQL 标准）

## '' = NULL 对 JOIN 的影响

使用空字符串作为 JOIN 条件时:
```sql
SELECT * FROM t1 JOIN t2 ON t1.code = t2.code;
```

如果 t1.code = '' 和 t2.code = ''，Oracle 中它们不会匹配!
因为 '' = NULL，而 NULL = NULL 的结果是 UNKNOWN（不满足 JOIN 条件）

其他数据库中，'' = '' 是 TRUE，这两行会正常匹配。
这是 Oracle 迁移中的重大兼容性问题。

## 自连接与层次查询

自连接
```sql
SELECT e.username AS employee, m.username AS manager
FROM users e LEFT JOIN users m ON e.manager_id = m.id;
```

Oracle 传统层次查询（CONNECT BY，所有版本）比自连接更强大:
```sql
SELECT LPAD(' ', 2 * (LEVEL - 1)) || username AS name, LEVEL
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id
ORDER SIBLINGS BY username;
```

## 优化器 Hint 控制 JOIN 算法

Oracle 提供丰富的 Hint 控制 JOIN 执行算法:
```sql
SELECT /*+ USE_HASH(u o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /*+ USE_NL(u o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /*+ USE_MERGE(u o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```

JOIN 算法对比:
  USE_HASH:  哈希连接（适合大表 × 大表，等值连接）
  USE_NL:    嵌套循环（适合小表驱动大表，索引查找）
  USE_MERGE: 排序合并（适合已排序数据或不等值连接）

对引擎开发者的启示:
  优化器至少需要实现 Hash Join 和 Nested Loop Join。
  Hint 系统让专家用户可以覆盖优化器决策，是生产环境必备功能。
  但 Hint 不应该是常态——好的优化器应该自己做出正确选择。

## 对引擎开发者的总结

1. (+) 语法是历史遗留，新引擎不应模仿，标准 JOIN 语法已足够。
2. LATERAL/APPLY 是现代 SQL 的重要特性，对 Top-N-per-group 等场景价值大。
3. '' = NULL 导致空字符串 JOIN 条件失败，这是 Oracle 独有的陷阱。
4. 优化器 Hint 是生产环境的安全网，但好的 CBO 应该减少 Hint 的使用。
