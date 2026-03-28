# SQLite: 执行计划

> 参考资料:
> - [SQLite Documentation - EXPLAIN QUERY PLAN](https://www.sqlite.org/eqp.html)
> - [SQLite Documentation - EXPLAIN](https://www.sqlite.org/lang_explain.html)
> - [SQLite Documentation - Query Planner](https://www.sqlite.org/queryplanner.html)

## EXPLAIN QUERY PLAN（推荐）

显示高层次的查询计划
```sql
EXPLAIN QUERY PLAN SELECT * FROM users WHERE username = 'alice';
```

输出示例：
QUERY PLAN
`--SEARCH users USING INDEX idx_users_username (username=?)

```sql
EXPLAIN QUERY PLAN SELECT * FROM users WHERE age > 25;
-- QUERY PLAN
-- `--SCAN users

EXPLAIN QUERY PLAN SELECT * FROM users WHERE id = 1;
```

QUERY PLAN
`--SEARCH users USING INTEGER PRIMARY KEY (rowid=?)

## 连接查询计划

```sql
EXPLAIN QUERY PLAN
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.age > 25;
```

输出示例：
QUERY PLAN
|--SCAN u
`--SEARCH o USING INDEX idx_orders_user_id (user_id=?)

## 子查询与 CTE

```sql
EXPLAIN QUERY PLAN
SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 1000);

EXPLAIN QUERY PLAN
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

## EXPLAIN（字节码级别）

显示 VDBE（Virtual Database Engine）字节码
```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

输出是 VDBE 操作码列表：
addr  opcode       p1    p2    p3    p4             p5  comment
----  -----------  ----  ----  ----  -------------  --  -------
0     Init         0     12    0                    0   Start
1     OpenRead     0     2     0     4              0   root=2 iDb=0; users
...

通常 EXPLAIN QUERY PLAN 更有用

## 关键计划操作

SCAN table              全表扫描
SEARCH table USING INDEX  索引查找
SEARCH table USING INTEGER PRIMARY KEY  主键查找
SEARCH table USING COVERING INDEX  覆盖索引（无需回表）
USE TEMP B-TREE FOR ORDER BY  文件排序
USE TEMP B-TREE FOR GROUP BY  分组排序
COMPOUND SUBQUERIES      复合子查询（UNION 等）
CO-ROUTINE               协程（用于子查询物化）
AUTOMATIC COVERING INDEX  自动创建的临时覆盖索引

## .eqp 命令（CLI 工具）

在 sqlite3 CLI 中：
.eqp on          每条查询自动显示执行计划
.eqp full        显示 EXPLAIN 和 EXPLAIN QUERY PLAN
.eqp off         关闭

## 统计信息与分析

更新统计信息
```sql
ANALYZE;
ANALYZE users;
```

查看统计信息
```sql
SELECT * FROM sqlite_stat1;
```

tbl    idx                 stat
users  idx_users_username  1000 1    (1000行，索引唯一)

sqlite_stat4（更详细的统计，如果编译时启用了 SQLITE_ENABLE_STAT4）
```sql
SELECT * FROM sqlite_stat4;
```

## 性能监控（3.31.0+）

启用查询性能监控
编译时需要 SQLITE_ENABLE_STMT_SCANSTATUS

## 查询优化器 Hint

SQLite 支持有限的 Hint

强制使用特定索引（3.30.0+）
```sql
SELECT * FROM users INDEXED BY idx_users_age WHERE age > 25;
```

禁止使用索引
```sql
SELECT * FROM users NOT INDEXED WHERE age > 25;
```

## 常用优化技巧

查看查询是否使用索引
```sql
EXPLAIN QUERY PLAN SELECT * FROM users WHERE age > 25;
```

如果显示 SCAN（全表扫描），考虑添加索引
```sql
CREATE INDEX IF NOT EXISTS idx_users_age ON users(age);
```

再次检查
```sql
EXPLAIN QUERY PLAN SELECT * FROM users WHERE age > 25;
```

现在应该显示 SEARCH ... USING INDEX

覆盖索引优化
```sql
CREATE INDEX idx_users_age_name ON users(age, username);
EXPLAIN QUERY PLAN SELECT username FROM users WHERE age > 25;
```

SEARCH users USING COVERING INDEX idx_users_age_name (age>?)

注意：EXPLAIN QUERY PLAN 是推荐的查询计划分析方式
注意：EXPLAIN 显示底层 VDBE 字节码，通常不需要
注意：SQLite 使用 Next Generation Query Planner（NGQP，3.8.0+）
注意：ANALYZE 收集统计信息帮助优化器做更好的决策
注意：INDEXED BY 可以强制使用特定索引，但通常不推荐
注意：SQLite 不支持 Hash Join，只有 Nested Loop
