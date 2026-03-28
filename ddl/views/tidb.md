# TiDB: 视图

> 参考资料:
> - [TiDB Documentation - CREATE VIEW](https://docs.pingcap.com/tidb/stable/sql-statement-create-view)
> - [TiDB Documentation - Views](https://docs.pingcap.com/tidb/stable/views)
> - [TiDB Documentation - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 基本视图（兼容 MySQL）

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

指定算法
```sql
CREATE
    ALGORITHM = MERGE
    SQL SECURITY DEFINER
VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

## 可更新视图 + WITH CHECK OPTION（TiDB 5.0+）

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CASCADED CHECK OPTION;

```

## 物化视图

TiDB 不支持物化视图
## 替代方案 1：使用 TiFlash 列式副本（分析加速）

ALTER TABLE orders SET TIFLASH REPLICA 1;
TiFlash 自动同步 TiKV 数据，提供 OLAP 加速

替代方案 2：使用 TiDB + TiCDC + 下游系统
通过 CDC 将数据变更推送到 ClickHouse/Kafka 等

替代方案 3：表 + 定时任务
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

**限制:**
不支持物化视图
兼容 MySQL 的视图功能
支持 WITH CHECK OPTION（5.0+）
ALGORITHM 被接受但不一定严格执行
TiFlash 是分析场景的替代方案（不是物化视图但提供类似效果）
