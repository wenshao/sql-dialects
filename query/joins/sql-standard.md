# SQL 标准: JOIN 连接

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - JOIN](https://modern-sql.com/feature/join)

## SQL-89 (SQL1)

仅支持隐式连接（逗号连接 + WHERE）
```sql
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;
```

## SQL-92 (SQL2)

引入显式 JOIN 语法

INNER JOIN
```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;
```

LEFT OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u
LEFT OUTER JOIN orders o ON u.id = o.user_id;
```

RIGHT OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u
RIGHT OUTER JOIN orders o ON u.id = o.user_id;
```

FULL OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;
```

CROSS JOIN
```sql
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;
```

USING（连接列同名时简写）
```sql
SELECT * FROM users JOIN orders USING (user_id);
```

NATURAL JOIN（自动匹配所有同名列）
```sql
SELECT * FROM users NATURAL JOIN orders;
```

自连接
```sql
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT OUTER JOIN users m ON e.manager_id = m.id;
```

## SQL:1999 (SQL3)

多表连接无新语法变化，但引入了递归查询（WITH RECURSIVE）

## SQL:2003

TABLESAMPLE（表抽样）
```sql
SELECT * FROM users TABLESAMPLE BERNOULLI (10);   -- 逐行抽样，约 10%
SELECT * FROM users TABLESAMPLE SYSTEM (10);       -- 按页/块抽样，约 10%
```

## SQL:2011

时态表连接（Temporal JOIN）
```sql
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
    AND o.order_date BETWEEN u.valid_from AND u.valid_to;
```

标准时态语法（FOR SYSTEM_TIME / FOR BUSINESS_TIME）
```sql
SELECT u.username, o.amount
FROM users FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-01' u
JOIN orders o ON u.id = o.user_id;
```

## SQL:2016

行模式匹配（MATCH_RECOGNIZE，可用于连接后的模式分析）
此特性主要用于 FROM 子句中的模式识别，非传统 JOIN

各标准版本 JOIN 特性总结：
SQL-89: 仅 FROM t1, t2 WHERE ... 隐式连接
SQL-92: INNER/LEFT/RIGHT/FULL JOIN, CROSS JOIN, USING, NATURAL JOIN
SQL:1999: 无新 JOIN 语法
SQL:2003: TABLESAMPLE, LATERAL
SQL:2011: 时态表 JOIN（FOR SYSTEM_TIME / FOR BUSINESS_TIME）
SQL:2016: MATCH_RECOGNIZE（行模式匹配）

LATERAL（SQL:2003 标准，子查询可以引用外部表的列）
```sql
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) AS latest ON TRUE;
```

