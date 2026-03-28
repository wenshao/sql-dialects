# SQLite: JOIN 连接

> 参考资料:
> - [SQLite Documentation - SELECT (JOIN)](https://www.sqlite.org/lang_select.html)
> - [SQLite - Query Planner](https://www.sqlite.org/queryplanner.html)

## 支持的 JOIN 类型

INNER JOIN
```sql
SELECT u.username, o.amount
FROM users u INNER JOIN orders o ON u.id = o.user_id;
```

LEFT JOIN
```sql
SELECT u.username, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id;
```

CROSS JOIN
```sql
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;
```

自连接
```sql
SELECT e.username AS employee, m.username AS manager
FROM users e LEFT JOIN users m ON e.manager_id = m.id;
```

USING
```sql
SELECT * FROM users JOIN orders USING (user_id);
```

NATURAL JOIN（不推荐但支持）
```sql
SELECT * FROM users NATURAL JOIN orders;
```

多表 JOIN
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;
```

## 不支持的 JOIN 类型（设计分析）

SQLite 不支持:
  RIGHT JOIN → 用 LEFT JOIN 交换表的位置替代
  FULL OUTER JOIN → 用 LEFT JOIN UNION ALL 模拟（3.39.0+ 才支持!）

3.39.0+: 支持 RIGHT JOIN 和 FULL OUTER JOIN
为什么等了这么久（2022年）?
(a) SQLite 的查询计划器原来只支持"左表驱动"的嵌套循环
(b) RIGHT JOIN 需要"右表驱动"，FULL OUTER JOIN 需要双向驱动
(c) 修改查询计划器比添加语法复杂得多

## JOIN 优化（对引擎开发者）

SQLite 的 JOIN 实现是嵌套循环（Nested Loop Join）:
外层循环遍历左表 → 内层循环在右表中查找匹配行
没有 Hash Join 或 Sort Merge Join!

优化依赖索引:
确保 JOIN 列有索引:
```sql
CREATE INDEX idx_orders_user_id ON orders(user_id);
```

→ LEFT TABLE SCAN users → INDEX LOOKUP orders(user_id)
→ O(N * log M) 而非 O(N * M)

对比:
  MySQL:      Nested Loop + Hash Join（8.0.18+）
  PostgreSQL: Nested Loop + Hash Join + Merge Join
  ClickHouse: Hash Join（默认）+ Partial Merge Join
  BigQuery:   Broadcast Join + Shuffle Join

EXPLAIN QUERY PLAN 查看 JOIN 策略:
```sql
EXPLAIN QUERY PLAN SELECT u.*, o.* FROM users u JOIN orders o ON u.id = o.user_id;
```

## 对比与引擎开发者启示

SQLite JOIN 的设计:
  (1) 只有嵌套循环 → 简单但依赖索引
  (2) RIGHT/FULL JOIN → 3.39.0 才支持（2022年）
  (3) NATURAL JOIN → 支持但不推荐
  (4) 无 LATERAL JOIN → 不支持

对引擎开发者的启示:
  嵌套循环 + 索引覆盖了嵌入式场景的绝大多数 JOIN 需求。
  Hash Join 对大数据量 JOIN 很重要，但嵌入式通常数据量小。
  RIGHT JOIN / FULL OUTER JOIN 的实现比看起来复杂得多（查询计划器改动大）。
