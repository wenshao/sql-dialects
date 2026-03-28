# KingbaseES (人大金仓): UPDATE

PostgreSQL compatible syntax.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Oracle Compatibility Guide](https://help.kingbase.com.cn/v8/develop-guide/oracle-compat.html)
> - [KingbaseES PL/SQL Reference](https://help.kingbase.com.cn/v8/server-programming/pl-sql.html)


## 基本 UPDATE


## 单列更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## 多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## 全表更新

```sql
UPDATE users SET status = 1;
```

## FROM 子句（PostgreSQL 风格多表更新）


## 使用 FROM 引用其他表

```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```

## FROM 多表

```sql
UPDATE users SET city = o.shipping_city
FROM orders o, addresses a
WHERE users.id = o.user_id AND users.id = a.user_id AND a.verified = true;
```

## 子查询更新


## 标量子查询

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

## 相关子查询

```sql
UPDATE users u SET total_orders = (
    SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id
);
```

## IN 子查询

```sql
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);
```

## CASE 表达式


## 条件更新

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

## CASE + 条件过滤

```sql
UPDATE users SET status = CASE
    WHEN age < 18 AND region = 'US' THEN 0
    WHEN age >= 65 THEN 2
    ELSE status   -- 不满足条件的保持不变
END
WHERE region IN ('US', 'EU');
```

## 自引用更新


## 全表自引用

```sql
UPDATE users SET age = age + 1;
```

## 条件自引用

```sql
UPDATE accounts SET balance = balance - 100
WHERE user_id = 42 AND balance >= 100;
```

## RETURNING 子句


## 返回更新后的行

```sql
UPDATE users SET age = 26 WHERE username = 'alice'
RETURNING id, username, age;
```

## RETURNING 表达式

```sql
UPDATE users SET age = age + 1
RETURNING id, username, age, age - 1 AS old_age;
```

## RETURNING 所有列

```sql
UPDATE users SET status = 1 WHERE id = 42 RETURNING *;
```

## CTE (WITH) + UPDATE


```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2 WHERE id IN (SELECT user_id FROM vip);
```

## 多层 CTE

```sql
WITH
    big_spenders AS (
        SELECT user_id, SUM(amount) AS total
        FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
    ),
    target AS (
        SELECT user_id FROM big_spenders WHERE total > 50000
    )
UPDATE users SET status = 3 WHERE id IN (SELECT user_id FROM target);
```

## Oracle 兼容 UPDATE 特性

人大金仓以 Oracle 兼容模式著称，UPDATE 支持 Oracle 风格:
Oracle 兼容: UPDATE ... SET (col1, col2) = (SELECT ...)
UPDATE users u
SET (u.email, u.status) = (
SELECT s.email, s.status FROM staging s WHERE s.id = u.id
)
WHERE EXISTS (SELECT 1 FROM staging s WHERE s.id = u.id);
Oracle 兼容: RETURNING INTO（在 ksql 或 PL/SQL 匿名块中使用）
DECLARE
v_age INTEGER;
v_status INTEGER;
BEGIN
UPDATE users SET age = 30 WHERE username = 'alice'
RETURNING age, status INTO v_age, v_status;
DBMS_OUTPUT.PUT_LINE('New age: ' || v_age);
END;
/
Oracle 兼容: BULK COLLECT INTO
DECLARE
TYPE id_array IS TABLE OF INTEGER;
v_ids id_array;
BEGIN
UPDATE users SET status = 1 WHERE age > 30
RETURNING id BULK COLLECT INTO v_ids;
FOR i IN 1..v_ids.COUNT LOOP
DBMS_OUTPUT.PUT_LINE('Updated id: ' || v_ids(i));
END LOOP;
COMMIT;
END;
/
Oracle 兼容: SQL%ROWCOUNT
DECLARE
v_count INTEGER;
BEGIN
UPDATE users SET status = 1 WHERE age > 30;
v_count := SQL%ROWCOUNT;
DBMS_OUTPUT.PUT_LINE('Updated ' || v_count || ' rows');
COMMIT;
END;
/
Oracle 兼容: UPDATE ... CURRENT OF（游标定位更新）
DECLARE
CURSOR user_cur IS SELECT * FROM users WHERE status = 0 FOR UPDATE;
BEGIN
FOR rec IN user_cur LOOP
UPDATE users SET status = 1 WHERE CURRENT OF user_cur;
END LOOP;
COMMIT;
END;
/

## 批量更新策略

大批量 UPDATE 的推荐做法:
(1) 分批更新（避免长事务锁表）:
在 PL/SQL 或应用层循环:
LOOP
UPDATE users SET status = 1
WHERE status = 0 AND id IN (SELECT id FROM users WHERE status = 0 LIMIT 5000);
EXIT WHEN NOT FOUND;
COMMIT;
END LOOP;
(2) 使用临时表:
CREATE TEMP TABLE update_targets AS
SELECT id, new_status FROM ...;
UPDATE users SET status = update_targets.new_status
FROM update_targets WHERE users.id = update_targets.id;
(3) INSERT INTO ... SELECT + DELETE + RENAME:
适合超大表的全表更新
将更新后的数据写入新表，然后交换表名

## 横向对比: KingbaseES vs PostgreSQL vs Oracle UPDATE

KingbaseES 与 PostgreSQL 的共同特性:
FROM 子句多表更新、RETURNING 子句、CTE + UPDATE
MVCC 并发控制（UPDATE 创建新版本，旧版本用于快照读）
TRUNCATE 可回滚
KingbaseES 的 Oracle 兼容优势:
SET (col1, col2) = (SELECT ...) 行级多列更新
RETURNING INTO 变量、BULK COLLECT INTO
SQL%ROWCOUNT、CURRENT OF 游标更新
在 Oracle 迁移场景下可以几乎不改代码
KingbaseES vs Oracle 差异:
KingbaseES 的 UPDATE 使用 MVCC（多版本），Oracle 使用 Undo + SCNs
KingbaseES 的列级更新只写修改的列，Oracle 写整行
KingbaseES 没有 Oracle 的 /*+ PARALLEL */ 提示（使用不同语法）
