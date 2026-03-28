# PostgreSQL: 子查询

> 参考资料:
> - [PostgreSQL Documentation - Subquery Expressions](https://www.postgresql.org/docs/current/functions-subquery.html)
> - [PostgreSQL Source - subselect.c (子查询优化)](https://github.com/postgres/postgres/blob/master/src/backend/optimizer/plan/subselect.c)

## 标量子查询

```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

标量子查询必须返回 0 或 1 行，否则运行时报错
PostgreSQL 优化器可能将标量子查询转换为 JOIN（subquery flattening）

## WHERE 子查询

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```

NOT IN 的 NULL 陷阱:
  如果子查询返回任何 NULL，NOT IN 的结果为 UNKNOWN（空集）。
  因为: x NOT IN (1, NULL) = x<>1 AND x<>NULL = ? AND UNKNOWN = UNKNOWN
  解决: 使用 NOT EXISTS 替代 NOT IN

## EXISTS / NOT EXISTS

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

EXISTS 的优化:
  PostgreSQL 优化器将 EXISTS 子查询转换为 Semi Join。
  Semi Join 只需要找到第一个匹配行即可停止（不需要遍历所有匹配）。
  NOT EXISTS 转换为 Anti Join。

## 比较运算符 + ALL / ANY

```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```

## LATERAL 子查询 (9.3+): 相关子查询的进化

LATERAL 允许 FROM 中的子查询引用同级表的列
```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;
```

等价于标量子查询，但可以返回多行多列
```sql
SELECT u.username, t.order_id, t.amount
FROM users u,
LATERAL (SELECT order_id, amount FROM orders
         WHERE user_id = u.id ORDER BY amount DESC LIMIT 3) t;
```

## 数组子查询: PostgreSQL 独有

ARRAY() 构造器: 将子查询结果转为数组
```sql
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;
```

ANY + ARRAY: 数组成员测试
```sql
SELECT * FROM users
WHERE id = ANY(ARRAY(SELECT user_id FROM orders WHERE amount > 100));
```

设计分析:
  ARRAY() 子查询是 PostgreSQL 独有的语法。
  它将相关子查询的多行结果聚合为单个数组值。
  对比 MySQL/Oracle: 需要 GROUP_CONCAT / LISTAGG + 应用层解析。

## 行子查询比较

ROW 值比较（同时比较多列）
```sql
SELECT * FROM users
WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);
```

等价于:
```sql
SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM (SELECT city, MIN(age) AS min_age FROM users GROUP BY city) t
    WHERE t.city = u.city AND t.min_age = u.age
);
```

## 子查询优化: 提升 (Subquery Flattening)

PostgreSQL 优化器尝试将子查询"提升"为 JOIN:
  IN (subquery)  →  Semi Join
  NOT IN (subquery)  →  Anti Join (注意 NULL 语义)
  EXISTS (subquery)  →  Semi Join
  标量子查询  →  Left Join (某些情况)

不能提升的场景:
  (a) 含 LIMIT/OFFSET 的子查询
  (b) 含聚合但无 GROUP BY 的子查询
  (c) 含 UNION/INTERSECT 的子查询
  (d) 含 VOLATILE 函数的子查询

```sql
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
```

观察: 是否出现 Hash Semi Join（说明子查询被提升为 JOIN）

## 横向对比: 子查询差异

### LATERAL

  PostgreSQL: LATERAL (9.3+)
  MySQL:      LATERAL (8.0.14+)
  SQL Server: CROSS APPLY / OUTER APPLY (2005+, 等价)
  Oracle:     LATERAL (12c+)

### ARRAY 子查询

  PostgreSQL: ARRAY(SELECT ...) — 独有
  其他:       无等价语法（需要聚合函数）

### 子查询优化

  PostgreSQL: 自动提升 IN/EXISTS 为 Semi Join
  MySQL:      8.0+ 改进了子查询优化（之前很多子查询不优化）
  Oracle:     成熟的子查询展开（subquery unnesting）

### NOT IN 的 NULL 处理

  所有数据库: NOT IN + NULL 子查询 = 空集（SQL 标准行为）
  最佳实践: 总是用 NOT EXISTS 替代 NOT IN

## 对引擎开发者的启示

(1) 子查询提升 (flattening/unnesting) 是优化器的核心能力:
    将 IN/EXISTS 子查询转为 JOIN 通常带来数量级的性能提升。
    PostgreSQL 的 pull_up_subqueries() 是这一优化的入口。

(2) Semi Join 和 Anti Join 是第一类 JOIN 类型:
    IN/EXISTS 不应该作为"嵌套循环+子查询"执行，
    而应该有专门的 Semi/Anti Join 算子。

(3) ARRAY() 子查询展示了 PostgreSQL 类型系统的威力:
    子查询结果可以直接成为数组值，无需中间步骤。
    这在其他数据库中需要 STRING_AGG + 解析的低效方案。

## 版本演进

PostgreSQL 7.x:  基本子查询, IN, EXISTS, ALL, ANY
PostgreSQL 9.3:  LATERAL 子查询
PostgreSQL 12:   改进标量子查询优化（hash subplan caching）
PostgreSQL 14:   Memoize 节点（缓存相关子查询结果）
