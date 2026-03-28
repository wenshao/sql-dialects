# TDSQL: Views

> 参考资料:
> - [TDSQL Documentation - CREATE VIEW](https://cloud.tencent.com/document/product/557/7714)
> - [TDSQL Documentation - SQL Reference](https://cloud.tencent.com/document/product/557)


## 基本视图（兼容 MySQL 语法）

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
WITH CHECK OPTION;
```

## 物化视图

TDSQL 不支持原生物化视图

## 替代方案：表 + 定时任务（与 MySQL 一致）

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

限制：
不支持物化视图
兼容 MySQL 的视图功能
支持 WITH CHECK OPTION
分布式场景下视图跨分片的限制与 MySQL 不同
