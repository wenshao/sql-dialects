# MySQL: 执行计划

> 参考资料:
> - [MySQL 8.0 Reference Manual - EXPLAIN Statement](https://dev.mysql.com/doc/refman/8.0/en/explain.html)
> - [MySQL 8.0 Reference Manual - Understanding the Query Execution Plan](https://dev.mysql.com/doc/refman/8.0/en/execution-plan-information.html)
> - [MySQL 8.0 Reference Manual - EXPLAIN ANALYZE](https://dev.mysql.com/doc/refman/8.0/en/explain.html#explain-analyze)

## EXPLAIN 基本用法

基本 EXPLAIN
```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

等价写法
```sql
DESCRIBE SELECT * FROM users WHERE username = 'alice';
DESC SELECT * FROM users WHERE username = 'alice';
```

EXPLAIN 输出列含义：
id            子查询编号
select_type   查询类型（SIMPLE, PRIMARY, SUBQUERY, DERIVED, UNION）
table         表名
partitions    匹配的分区
type          访问方式（system > const > eq_ref > ref > range > index > ALL）
possible_keys 可能用到的索引
key           实际使用的索引
key_len       使用的索引长度
ref           与索引比较的列
rows          预估扫描行数
filtered      按条件过滤后的百分比
Extra         额外信息

## EXPLAIN 输出格式（5.6+）

传统表格格式
```sql
EXPLAIN FORMAT=TRADITIONAL SELECT * FROM users WHERE age > 25;
```

JSON 格式（5.6+，包含成本信息）
```sql
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE age > 25;
```

树形格式（8.0.16+）
```sql
EXPLAIN FORMAT=TREE SELECT * FROM users WHERE age > 25;
```

## EXPLAIN ANALYZE（8.0.18+）

实际执行查询并收集运行时统计信息
```sql
EXPLAIN ANALYZE SELECT u.*, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.age > 25
GROUP BY u.id;
```

输出包含：
actual time: 实际耗时（毫秒）
rows: 实际返回行数
loops: 循环次数

注意：EXPLAIN ANALYZE 会实际执行查询

## EXPLAIN 用于 DML 语句（5.6.3+）

```sql
EXPLAIN INSERT INTO users (username, email) VALUES ('test', 'test@example.com');
EXPLAIN UPDATE users SET age = 30 WHERE username = 'alice';
EXPLAIN DELETE FROM users WHERE age < 18;
```

## EXPLAIN 用于连接查询

```sql
EXPLAIN SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE o.amount > 100
ORDER BY o.created_at DESC;
```

## EXPLAIN 用于子查询

```sql
EXPLAIN SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 1000);
```

## 查看优化器选择（8.0+）

查看优化器跟踪
```sql
SET optimizer_trace = 'enabled=on';
SELECT * FROM users WHERE age > 25 AND status = 1;
SELECT * FROM information_schema.OPTIMIZER_TRACE\G
```

关闭跟踪
```sql
SET optimizer_trace = 'enabled=off';
```

## PROFILE（已废弃，8.0 仍可用）

```sql
SET profiling = 1;
SELECT * FROM users WHERE age > 25;
SHOW PROFILES;
SHOW PROFILE FOR QUERY 1;
SHOW PROFILE CPU, BLOCK IO FOR QUERY 1;
```

## Performance Schema 替代 PROFILE（5.6+）

启用语句检测
```sql
UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'statement/%';

UPDATE performance_schema.setup_consumers
SET ENABLED = 'YES'
WHERE NAME LIKE 'events_statements%';
```

查看最近的查询性能
```sql
SELECT EVENT_ID, SQL_TEXT, TIMER_WAIT/1000000000 AS time_ms,
       ROWS_EXAMINED, ROWS_SENT
FROM performance_schema.events_statements_history
ORDER BY EVENT_ID DESC LIMIT 10;
```

## 关键优化指标

type 列（从好到差）：
system    表只有一行
const     通过主键/唯一索引匹配一行
eq_ref    连接使用主键/唯一索引
ref       使用非唯一索引
range     索引范围扫描
index     索引全扫描
ALL       全表扫描（通常需要优化）

Extra 列关键信息：
Using index         覆盖索引（好）
Using where         服务器层过滤
Using temporary     使用临时表（可能需要优化）
Using filesort      额外排序（可能需要优化）
Using index condition  索引条件下推（5.6+ ICP）

注意：EXPLAIN 不会实际执行查询，EXPLAIN ANALYZE 会
注意：JSON 格式提供最详细的成本估算信息
注意：TREE 格式（8.0.16+）展示迭代器执行模型
注意：PROFILE 已废弃，推荐使用 Performance Schema
注意：优化器跟踪可以了解为什么选择了特定的执行计划
