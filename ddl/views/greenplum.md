# Greenplum: Views

> 参考资料:
> - [Greenplum Documentation - CREATE VIEW](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-CREATE_VIEW.html)
> - [Greenplum Documentation - CREATE MATERIALIZED VIEW](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-CREATE_MATERIALIZED_VIEW.html)
> - [Greenplum Documentation - Updatable Views](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-ddl-ddl-view.html)


## 基本视图（兼容 PostgreSQL 语法）

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```


临时视图
```sql
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;
```


## 可更新视图 + WITH CHECK OPTION（Greenplum 7+）

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;
```


WITH LOCAL CHECK OPTION / WITH CASCADED CHECK OPTION
```sql
CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH CASCADED CHECK OPTION;
```


## 物化视图 (Greenplum 7+ / 6.x 部分支持)

```sql
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id
DISTRIBUTED BY (user_id);                    -- Greenplum 特有的分布键
```


手动刷新
```sql
REFRESH MATERIALIZED VIEW mv_order_summary;
```


并发刷新（不阻塞读取）
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary;
-- 需要 UNIQUE 索引
```


在物化视图上创建索引
```sql
CREATE INDEX idx_mv_user ON mv_order_summary (user_id);
```


不填充数据创建（稍后刷新）
```sql
CREATE MATERIALIZED VIEW mv_empty AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
WITH NO DATA;
```


## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;
```


限制：
物化视图不支持自动刷新（需要手动或定时任务）
物化视图需要指定 DISTRIBUTED BY
Greenplum 6.x 对物化视图支持有限
可更新视图需要 Greenplum 7+
