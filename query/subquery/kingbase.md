# KingbaseES (人大金仓): 子查询 (Subqueries)

KingbaseES is PostgreSQL-compatible, inheriting PG subquery features.

> 参考资料:
> - [KingbaseES SQL Reference - Subqueries](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Server Programming Guide](https://help.kingbase.com.cn/v8/develop-guide/index.html)
> - [PostgreSQL Documentation - Subquery Expressions](https://www.postgresql.org/docs/current/functions-subquery.html)
> - ============================================================
> - 1. 标量子查询
> - ============================================================
> - 示例数据:
> - users(id, username, age, city)
> - orders(id, user_id, amount, status)

```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

## 标量子查询必须返回 0 或 1 行，否则运行时报错

KingbaseES 优化器可能将标量子查询转换为 JOIN（subquery flattening）

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
KingbaseES 国产化适配注意:
从 Oracle 迁移时，Oracle 的 NOT IN 行为一致，可直接替换为 NOT EXISTS。

## EXISTS / NOT EXISTS


```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

EXISTS 的优化:
KingbaseES 优化器将 EXISTS 子查询转换为 Semi Join。
Semi Join 只需要找到第一个匹配行即可停止（不需要遍历所有匹配）。
NOT EXISTS 转换为 Anti Join。

## 比较运算符 + ALL / ANY


```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```

## ANY 等价于 SOME（SQL 标准），KingbaseES 两者都支持

## FROM 子查询（派生表 / Derived Table）


```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;
```

## KingbaseES 要求派生表必须有别名（与 PostgreSQL 一致）

Oracle 迁移注意: Oracle 中某些派生表可以省略别名，KingbaseES 需要补上

## LATERAL 子查询: 相关子查询的进化


## LATERAL 允许 FROM 中的子查询引用同级表的列

```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;
```

## 等价于标量子查询，但可以返回多行多列

```sql
SELECT u.username, t.order_id, t.amount
FROM users u,
LATERAL (SELECT order_id, amount FROM orders
         WHERE user_id = u.id ORDER BY amount DESC LIMIT 3) t;
```

## KingbaseES 继承 PostgreSQL 的 LATERAL 语法，完全兼容

## CTE (WITH 子句): 子查询的替代方案


## 简单 CTE

```sql
WITH city_stats AS (
    SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
    FROM users GROUP BY city
)
SELECT * FROM city_stats WHERE cnt > 10;
```

CTE vs 子查询:
CTE 可读性更好，且可以被多次引用
KingbaseES 默认将 CTE 作为优化屏障（不内联），可通过提示控制
递归 CTE（KingbaseES 支持）

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.level + 1
    FROM employees e, org_tree t WHERE e.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY level;
```

## 数组子查询（PostgreSQL 兼容）


## ARRAY() 构造器: 将子查询结果转为数组（KingbaseES 继承 PG 语法）

```sql
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;
```

## ANY + ARRAY: 数组成员测试

```sql
SELECT * FROM users
WHERE id = ANY(ARRAY(SELECT user_id FROM orders WHERE amount > 100));
```

## 子查询优化: 提升 (Subquery Flattening)


KingbaseES 继承 PostgreSQL 优化器:
IN (subquery)      →  Semi Join
NOT IN (subquery)  →  Anti Join (注意 NULL 语义)
EXISTS (subquery)  →  Semi Join
标量子查询          →  Left Join (某些情况)
不能提升的场景:
(a) 含 LIMIT/OFFSET 的子查询
(b) 含聚合但无 GROUP BY 的子查询
(c) 含 UNION/INTERSECT 的子查询
(d) 含 VOLATILE 函数的子查询

```sql
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
```

## 横向对比: KingbaseES vs 其他国产数据库


## LATERAL 支持:

KingbaseES:  完全支持（继承 PostgreSQL 9.3+）
openGauss:   完全支持（继承 PostgreSQL）
DamengDB:    不直接支持 LATERAL（Oracle 兼容路线）
TDSQL:       MySQL 8.0.14+ LATERAL（分布式限制）
2. 子查询优化:
KingbaseES:  PG 优化器（pull_up_subqueries, Semi Join, Anti Join）
openGauss:   PG 优化器 + 自研增强
DamengDB:    Oracle 风格子查询展开（unnesting）
TDSQL:       MySQL Semi Join + 分布式路由
3. CTE 优化:
KingbaseES:  支持 CTE 内联提示（PostgreSQL 12+ 特性）
DamengDB:    CTE 可被优化器内联
TDSQL:       MySQL 8.0 CTE 不支持物化提示

## 对引擎开发者的启示


(1) KingbaseES 的 PostgreSQL 兼容性是核心优势:
继承了成熟的 PG 子查询优化器（Semi Join, Anti Join, Lateral Join）。
从 Oracle 迁移时需要注意语法的细微差异。
(2) 国产化替代中的子查询测试要点:
NOT IN 与 NOT EXISTS 的 NULL 语义一致性。
递归 CTE 在 KingbaseES 中的执行计划效率。
ARRAY() 子查询在业务中的使用场景验证。
(3) 子查询提升 (flattening/unnesting) 是优化器的核心能力:
将 IN/EXISTS 子查询转为 JOIN 通常带来数量级的性能提升。
KingbaseES 的 pull_up_subqueries() 继承自 PostgreSQL，成熟可靠。

## 版本演进

KingbaseES V7:  基本子查询, IN, EXISTS, ALL, ANY（PG 兼容）
KingbaseES V8:  LATERAL 子查询, 递归 CTE, 改进的子查询优化
KingbaseES V8R6: 增强的 CTE 内联优化, 改进的 Semi Join 策略
