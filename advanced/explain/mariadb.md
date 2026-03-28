# MariaDB: 执行计划 (EXPLAIN)

与 MySQL EXPLAIN 格式相似, 优化器细节不同

参考资料:
[1] MariaDB Knowledge Base - EXPLAIN
https://mariadb.com/kb/en/explain/

## 1. 基本 EXPLAIN

```sql
EXPLAIN SELECT * FROM users WHERE age > 25;
EXPLAIN SELECT u.username, COUNT(o.id)
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;
```


## 2. EXPLAIN FORMAT=JSON (10.1+)

```sql
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE age > 25;
-- JSON 输出包含更多细节: 成本估算, 过滤比例, 使用的优化策略
```


## 3. ANALYZE (10.1+)

```sql
ANALYZE SELECT * FROM users WHERE age > 25;
```

等价于 EXPLAIN ANALYZE: 实际执行查询并显示真实时间和行数
**对比 MySQL 8.0.18+: EXPLAIN ANALYZE 语法**

MariaDB 的 ANALYZE 更早实现

## 4. 优化器追踪

```sql
SET optimizer_trace='enabled=on';
SELECT * FROM users WHERE age > 25 AND email LIKE '%@example.com';
SELECT * FROM INFORMATION_SCHEMA.OPTIMIZER_TRACE\G
```


## 5. MariaDB 独有优化器特性

表消除 (Table Elimination): EXPLAIN 中不出现被消除的表
条件下推 (Condition Pushdown): 对派生表的优化
Histogram 统计 (10.0+): ANALYZE TABLE t PERSISTENT FOR ALL
这些优化器特性使 MariaDB 的 EXPLAIN 输出可能与 MySQL 不同

## 6. 对引擎开发者的启示

EXPLAIN 的设计目标: 让用户理解优化器的决策
好的 EXPLAIN 应该展示:
1. 访问方法 (全表扫描/索引扫描/索引查找)
2. JOIN 策略 (Nested Loop/Hash Join/Sort Merge)
3. 成本估算 (行数估计, I/O 成本, CPU 成本)
4. 过滤比例 (filtered 列: 经过条件过滤后的行百分比)
MariaDB ANALYZE 的价值: 对比估计值和实际值, 帮助诊断统计信息不准确
