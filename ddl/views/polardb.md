# PolarDB: Views

> 参考资料:
> - [PolarDB for MySQL Documentation - CREATE VIEW](https://www.alibabacloud.com/help/en/polardb/polardb-for-mysql/create-view)
> - [PolarDB for PostgreSQL Documentation - CREATE VIEW](https://www.alibabacloud.com/help/en/polardb/polardb-for-postgresql/create-view)


## 基本视图（MySQL 兼容模式）

PolarDB for MySQL 完全兼容 MySQL 语法

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## CREATE OR REPLACE VIEW

```sql
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 指定算法

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
WITH CASCADED CHECK OPTION;
```

物化视图
PolarDB for MySQL 不支持原生物化视图
PolarDB for PostgreSQL 支持物化视图


## MySQL 模式替代方案：表 + EVENT

```sql
CREATE TABLE mv_order_summary (
    user_id     BIGINT PRIMARY KEY,
    order_count INT,
    total_amount DECIMAL(18,2)
) ENGINE=InnoDB;

CREATE EVENT refresh_mv
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    TRUNCATE TABLE mv_order_summary;
    INSERT INTO mv_order_summary
    SELECT user_id, COUNT(*), SUM(amount)
    FROM orders GROUP BY user_id;
END;
```

PostgreSQL 模式（PolarDB for PostgreSQL）:
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders GROUP BY user_id;
REFRESH MATERIALIZED VIEW mv_order_summary;

## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
```

限制：
PolarDB for MySQL 不支持物化视图（同 MySQL）
PolarDB for PostgreSQL 支持物化视图（同 PostgreSQL）
支持 WITH CHECK OPTION
视图功能取决于所选兼容模式（MySQL/PostgreSQL/Oracle）
