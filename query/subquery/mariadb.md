# MariaDB: 子查询 (Subquery)

优化器在子查询去关联和物化策略上与 MySQL 有差异

参考资料:
[1] MariaDB Knowledge Base - Subqueries
https://mariadb.com/kb/en/subqueries/

## 1. 基本子查询

标量子查询
```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id) AS order_count
FROM users;
```


IN 子查询
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
```


EXISTS 子查询
```sql
SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```


派生表 (FROM 子查询)
```sql
SELECT ranked.* FROM (
    SELECT username, age, ROW_NUMBER() OVER (ORDER BY age) AS rn FROM users
) ranked WHERE ranked.rn <= 10;
```


## 2. MariaDB 子查询优化策略

MariaDB 10.0+ 引入了多项独立的子查询优化:
1. Semi-Join: IN/EXISTS 子查询转为 semi-join (10.0+)
2. Materialization: 子查询结果物化为临时表 (10.0+)
3. FirstMatch: 找到第一个匹配即停止扫描
4. LooseScan: 利用索引的松散扫描
5. DuplicateWeedout: 去重策略

关键差异 vs MySQL:
MariaDB 10.0 的 semi-join 策略基于 MySQL 5.6 但独立发展
MariaDB 对相关子查询的优化在某些场景下比 MySQL 更好
MySQL 8.0 引入的 anti-join 优化 MariaDB 后续也独立实现

## 3. 对引擎开发者: 子查询去关联

子查询去关联 (Decorrelation) 是优化器的核心能力:
关联子查询: 每行外表数据执行一次子查询 → O(n*m)
去关联后: 转为 JOIN → 可利用索引和 Hash Join → O(n+m)
MariaDB 与 MySQL 在去关联策略选择上已有分歧:
相同的查询可能一个选择 FirstMatch, 另一个选择 Materialization
这影响内存使用和 I/O 模式
