# OceanBase: 视图

> 参考资料:
> - [OceanBase Documentation - CREATE VIEW](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000820042)
> - [OceanBase Documentation - Materialized View (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000820120)
> - [OceanBase Documentation - Views](https://en.oceanbase.com/docs/common-oceanbase-database-10000000001700706)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## 基本视图（MySQL 兼容模式）

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

CREATE OR REPLACE VIEW
```sql
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

指定算法（MySQL 模式）
```sql
CREATE
    ALGORITHM = MERGE
    SQL SECURITY DEFINER
VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

## 可更新视图 + WITH CHECK OPTION

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;

```

## 物化视图（Oracle 兼容模式, OceanBase 4.x+）

Oracle 模式下支持物化视图
```sql
CREATE MATERIALIZED VIEW mv_order_summary
REFRESH COMPLETE ON DEMAND
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

快速刷新（需要物化视图日志）
CREATE MATERIALIZED VIEW LOG ON orders WITH PRIMARY KEY, ROWID;

手动刷新
EXEC DBMS_MVIEW.REFRESH('mv_order_summary', 'C');

MySQL 模式替代方案：表 + 定时任务
```sql
CREATE TABLE mv_order_summary (
    user_id     BIGINT PRIMARY KEY,
    order_count INT,
    total_amount DECIMAL(18,2)
);

```

## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
```

Oracle 模式: DROP MATERIALIZED VIEW mv_order_summary;

**限制:**
物化视图仅在 Oracle 兼容模式下支持
MySQL 模式不支持物化视图
支持 WITH CHECK OPTION
OceanBase 兼容 MySQL 和 Oracle 两种模式
