# KingbaseES (人大金仓): DELETE

PostgreSQL compatible syntax.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Oracle Compatibility Guide](https://help.kingbase.com.cn/v8/develop-guide/oracle-compat.html)
> - [KingbaseES PL/SQL Reference](https://help.kingbase.com.cn/v8/server-programming/pl-sql.html)


## 基本 DELETE（PostgreSQL 标准语法）


## 单行删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 多条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01'::date;
```

## 删除所有行

```sql
DELETE FROM users;
```

## 快速清空表

```sql
TRUNCATE TABLE users;
TRUNCATE TABLE users RESTART IDENTITY;    -- 同时重置序列
TRUNCATE TABLE users CASCADE;             -- 级联截断（同时截断所有外键引用表）
```

## USING 子句（PostgreSQL 风格多表删除）


## USING 关联删除

```sql
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;
```

## 多表 USING

```sql
DELETE FROM users
USING blacklist, spam_reports
WHERE users.email = blacklist.email
   OR users.email = spam_reports.email;
```

## USING + 额外条件

```sql
DELETE FROM users
USING orders
WHERE users.id = orders.user_id
  AND orders.amount < 0;
```

## 子查询与 EXISTS 删除


## IN 子查询

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## EXISTS 关联删除

```sql
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);
```

## NOT EXISTS（删除没有订单的用户）

```sql
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

## 标量子查询

```sql
DELETE FROM users WHERE age < (SELECT AVG(age) - 50 FROM users);
```

## RETURNING 子句


## 返回被删除的行

```sql
DELETE FROM users WHERE status = 0 RETURNING id, username;
```

## RETURNING 所有列

```sql
DELETE FROM users WHERE id = 42 RETURNING *;
```

## RETURNING 表达式

```sql
DELETE FROM users WHERE status = 0
RETURNING id, username, 'deleted' AS action;
```

## RETURNING 与 CTE 结合实现归档删除

```sql
WITH deleted AS (
    DELETE FROM users WHERE status = 0
    RETURNING id, username, email, age
)
INSERT INTO users_archive (id, username, email, age, archived_at)
SELECT id, username, email, age, now() FROM deleted;
```

## CTE (WITH) + DELETE


## CTE 定义删除目标

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

## 多层 CTE

```sql
WITH
    target_ids AS (
        SELECT user_id FROM orders
        GROUP BY user_id HAVING SUM(amount) < 100
    ),
    to_delete AS (
        SELECT id FROM users
        WHERE id IN (SELECT user_id FROM target_ids) AND status = 0
    )
DELETE FROM users WHERE id IN (SELECT id FROM to_delete);
```

## Oracle 兼容特性

人大金仓以 Oracle 兼容模式著称，DELETE 也支持 Oracle 风格:
Oracle 兼容: ROWNUM 分批删除（KingbaseES Oracle 模式）
DELETE FROM logs WHERE ROWNUM <= 10000 AND created_at < DATE '2023-01-01';
COMMIT;
重复执行直到影响行数为 0
Oracle 兼容: RETURNING INTO（在 ksql 或 PL/SQL 匿名块中使用）
DECLARE
v_id INTEGER;
v_name VARCHAR(50);
BEGIN
DELETE FROM users WHERE username = 'alice'
RETURNING id, username INTO v_id, v_name;
DBMS_OUTPUT.PUT_LINE('Deleted: ' || v_name);
END;
/
Oracle 兼容: BULK COLLECT INTO
DECLARE
TYPE id_array IS TABLE OF INTEGER;
v_ids id_array;
BEGIN
DELETE FROM users WHERE status = 0
RETURNING id BULK COLLECT INTO v_ids;
FOR i IN 1..v_ids.COUNT LOOP
DBMS_OUTPUT.PUT_LINE('Deleted id: ' || v_ids(i));
END LOOP;
END;
/
Oracle 兼容: %ROWCOUNT 获取影响行数
DECLARE
v_count INTEGER;
BEGIN
DELETE FROM users WHERE status = 0;
v_count := SQL%ROWCOUNT;
DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows');
COMMIT;
END;
/

## 批量删除策略


策略 1: 分批删除（避免长事务）
在 PL/SQL 或应用层循环:
LOOP
DELETE FROM logs WHERE created_at < '2023-01-01' LIMIT 10000;
EXIT WHEN NOT FOUND;
COMMIT;
END LOOP;
策略 2: TRUNCATE（清空整表）
最快，DDL 操作，不可回滚
策略 3: DROP TABLE + CREATE TABLE（完全重建）
比 DELETE + VACUUM 更快
策略 4: 分区表 DROP PARTITION
ALTER TABLE logs DETACH PARTITION p2020;
DROP TABLE logs_p2020;
这是批量删除最高效的方式: O(1) 操作，不产生 dead tuples
注意事项:
DELETE 产生 dead tuples，需要 VACUUM 回收空间
大量 DELETE 后建议执行: VACGARBAGE 或 VACUUM FULL users;
TRUNCATE 是事务性的（与 Oracle 不同，可以回滚）

## 横向对比: KingbaseES vs PostgreSQL vs Oracle DELETE

KingbaseES 与 PostgreSQL 的共同特性:
USING 子句多表删除、RETURNING 子句、CTE + DELETE
TRUNCATE 可回滚、MVCC 并发控制
KingbaseES 的 Oracle 兼容优势:
ROWNUM 分页、RETURNING INTO 变量、BULK COLLECT INTO
SQL%ROWCOUNT、DBMS_OUTPUT 包
在 Oracle 迁移场景下可以几乎不改代码
KingbaseES vs Oracle 差异:
KingbaseES 的 TRUNCATE 可以回滚（Oracle 不可以）
KingbaseES 没有 Oracle 的 FLASHBACK QUERY
KingbaseES 使用 MVCC（多版本并发控制），Oracle 使用 Undo + SCNs
