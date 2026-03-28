# DB2: 临时表与临时存储

> 参考资料:
> - [IBM Documentation - DECLARE GLOBAL TEMPORARY TABLE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-declare-global-temporary-table)
> - [IBM Documentation - CREATE GLOBAL TEMPORARY TABLE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-global-temporary-table)


## DECLARE GLOBAL TEMPORARY TABLE（会话级）


```sql
DECLARE GLOBAL TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200)
) ON COMMIT PRESERVE ROWS
  NOT LOGGED;
```

ON COMMIT 选项：
ON COMMIT DELETE ROWS      事务提交时清空
ON COMMIT PRESERVE ROWS    事务提交时保留
NOT LOGGED: 不记录日志（性能更好）

## 从查询创建


```sql
DECLARE GLOBAL TEMPORARY TABLE temp_orders AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) DEFINITION ONLY;  -- 只创建结构
```

## 包含数据

```sql
DECLARE GLOBAL TEMPORARY TABLE temp_stats AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) WITH DATA ON COMMIT PRESERVE ROWS NOT LOGGED;
```

## 使用声明的临时表


## 临时表在 SESSION schema 中

```sql
INSERT INTO SESSION.temp_users
SELECT id, username, email FROM users WHERE status = 1;

SELECT * FROM SESSION.temp_users;
```

## 显式释放

会话结束时自动释放

## CREATE GLOBAL TEMPORARY TABLE（已创建的临时表）


## 创建永久结构的临时表（DDL 层面存在）

```sql
CREATE GLOBAL TEMPORARY TABLE gtt_results (
    id BIGINT NOT NULL,
    value DECIMAL(10,2)
) ON COMMIT PRESERVE ROWS;
```

## 结构对所有会话可见，数据会话隔离

```sql
INSERT INTO gtt_results VALUES (1, 100.00);
```

## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u JOIN stats s ON u.id = s.user_id
WHERE s.total > 1000;
```

## 递归 CTE

```sql
WITH tree (id, name, parent_id, lvl) AS (
    SELECT id, name, parent_id, 1
    FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.lvl + 1
    FROM departments d JOIN tree t ON d.parent_id = t.id
)
SELECT * FROM tree;
```

注意：DECLARE GLOBAL TEMPORARY TABLE 创建会话级临时表
注意：临时表通过 SESSION schema 访问
注意：NOT LOGGED 选项提高性能但数据不可恢复
注意：CREATE GLOBAL TEMPORARY TABLE 创建永久结构的临时表
注意：DEFINITION ONLY 只创建结构不复制数据
