# SQL Server: JOIN 连接

> 参考资料:
> - [SQL Server T-SQL - FROM clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql)
> - [SQL Server - Using APPLY](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql#using-apply)

## 标准 JOIN 语法

```sql
SELECT u.username, o.amount FROM users u
INNER JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

SELECT u.username, r.role_name FROM users u
CROSS JOIN roles r;
```

自连接
```sql
SELECT e.username AS employee, m.username AS manager
FROM users e LEFT JOIN users m ON e.manager_id = m.id;
```

SQL Server 不支持 USING 子句（必须使用 ON）
横向对比: PostgreSQL/MySQL/Oracle 都支持 JOIN ... USING (column_name)

SQL Server 不支持 NATURAL JOIN
横向对比: PostgreSQL/MySQL 支持 NATURAL JOIN（隐式匹配同名列）

## CROSS APPLY / OUTER APPLY: SQL Server 最重要的 JOIN 创新

CROSS APPLY = 内连接版本的 LATERAL JOIN
OUTER APPLY = 左连接版本的 LATERAL JOIN
SQL Server 2005 引入，比 SQL 标准的 LATERAL（SQL:2003）实现更早被广泛使用。

获取每个用户的最新一笔订单:
```sql
SELECT u.username, latest.amount, latest.order_date
FROM users u
CROSS APPLY (
    SELECT TOP 1 amount, order_date
    FROM orders WHERE user_id = u.id
    ORDER BY order_date DESC
) latest;
```

OUTER APPLY: 用户没有订单时也显示（类似 LEFT JOIN）
```sql
SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY order_date DESC
) latest;
```

设计分析（对引擎开发者）:
  CROSS APPLY 的核心语义: 右侧子查询可以引用左侧表的列。
  这是普通 JOIN 做不到的——普通 JOIN 的两侧是独立求值的。

  执行模型:
  对左表的每一行，执行一次右侧子查询（类似嵌套循环 JOIN）。
  优化器可能将其转换为其他 JOIN 策略，但语义上是"逐行关联"。

  APPLY 的典型应用场景:
  (1) 分组 Top-N（每组取前 N 条）——比窗口函数更高效
  (2) 表值函数调用（将函数结果与表 JOIN）
  (3) OPENJSON/STRING_SPLIT 等拆分函数
  (4) 替代复杂的相关子查询

横向对比:
  PostgreSQL: 9.3+ LATERAL JOIN（语义等价，语法不同）
```sql
              SELECT * FROM t, LATERAL (SELECT ... WHERE ... = t.id) sub
```

  MySQL:      8.0.14+ LATERAL JOIN
  Oracle:     12c+ LATERAL, CROSS APPLY/OUTER APPLY
  标准 SQL:   SQL:2003 定义了 LATERAL

对引擎开发者的启示:
  APPLY/LATERAL 是 SQL 中最强大的子查询关联机制。
  它统一了相关子查询和 JOIN 的语义——任何相关子查询都可以改写为 APPLY。
  引擎的查询优化器必须能够识别 APPLY 模式并选择最优执行策略:
  - 小右表: 嵌套循环（Nested Loop with Apply）
  - 可去关联化: 转换为 Hash Join 或 Merge Join
  SQL Server 的优化器在 APPLY 去关联化方面非常成熟。

## APPLY + 表值函数（T-SQL 特色组合）

内联表值函数（ITVF）是 T-SQL 中的"参数化视图":
```sql
CREATE FUNCTION dbo.GetTopOrders(@user_id BIGINT, @n INT)
RETURNS TABLE AS RETURN (
    SELECT TOP (@n) id, amount, order_date
    FROM orders WHERE user_id = @user_id
    ORDER BY amount DESC
);
GO
```

CROSS APPLY 调用 ITVF:
```sql
SELECT u.username, o.amount, o.order_date
FROM users u
CROSS APPLY dbo.GetTopOrders(u.id, 3) o;
```

设计分析: APPLY + ITVF 是 SQL Server 中替代存储过程循环的最佳模式。
优化器可以将 ITVF 内联到查询计划中（与存储过程不同）。

## WITH (NOLOCK) 提示: SQL Server 的锁提示文化

SQL Server 独有的表级锁提示:
```sql
SELECT u.username, o.amount
FROM users u WITH (NOLOCK)
JOIN orders o WITH (NOLOCK) ON u.id = o.user_id;
```

NOLOCK = READ UNCOMMITTED 隔离级别（只针对单个表）
这是 SQL Server 生态中最广泛使用（也是最危险）的优化手段。

NOLOCK 的风险:
  (1) 脏读: 读到其他事务未提交的数据（可能被回滚）
  (2) 不可重复读: 同一查询中读到不一致的数据
  (3) 幻读: 新插入或删除的行在扫描中部分出现
  (4) 页分裂期间可能读到重复行或跳过行

为什么 NOLOCK 如此流行（对引擎开发者的重要启示）:
  SQL Server 默认使用 READ COMMITTED 隔离级别，且读操作获取共享锁。
  共享锁与写操作的排他锁冲突——读写互斥。
  长时间的报表查询会阻塞 DML，DBA 的"权宜之计"是加 NOLOCK。

  PostgreSQL 不需要 NOLOCK 因为它使用 MVCC——读不阻塞写，写不阻塞读。
  SQL Server 2005+ 可以启用 READ_COMMITTED_SNAPSHOT 获得类似行为:
```sql
  ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;
```

  但这需要额外的 tempdb 空间存储行版本。

## JOIN 提示: 强制选择 JOIN 算法

SQL Server 允许在 JOIN 关键字前指定算法:
```sql
SELECT u.username, o.amount FROM users u
INNER LOOP JOIN orders o ON u.id = o.user_id;   -- 强制嵌套循环

SELECT u.username, o.amount FROM users u
INNER HASH JOIN orders o ON u.id = o.user_id;   -- 强制 Hash Join

SELECT u.username, o.amount FROM users u
INNER MERGE JOIN orders o ON u.id = o.user_id;  -- 强制 Merge Join

-- 横向对比:
--   PostgreSQL: SET enable_hashjoin = off 等 GUC 参数（间接控制）
--   MySQL:      8.0+ JOIN_ORDER 提示, HASH_JOIN 提示
--   Oracle:     USE_NL / USE_HASH / USE_MERGE 提示
--
-- 对引擎开发者的启示:
--   JOIN 算法提示在生产环境中应该很少使用——它们绕过了优化器。
--   但作为调试和应急手段，它们是必要的。
--   SQL Server 的语法（在 JOIN 关键字前指定）比 Oracle 的注释提示更直观。
```

## 旧式 JOIN 语法（已废弃，但仍常见）

SQL Server 2012 起 *= 和 =* 外连接语法已删除:
SELECT * FROM a, b WHERE a.id *= b.id   -- 旧式左连接，不再支持
必须使用 ANSI JOIN 语法（LEFT/RIGHT/FULL OUTER JOIN）
