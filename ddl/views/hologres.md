# Hologres: Views

> 参考资料:
> - [Hologres Documentation - CREATE VIEW](https://www.alibabacloud.com/help/en/hologres/developer-reference/create-view)
> - [Hologres Documentation - SQL Reference](https://www.alibabacloud.com/help/en/hologres/developer-reference/overview-16)
> - ============================================
> - 基本视图（兼容 PostgreSQL 语法）
> - ============================================

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

## IF NOT EXISTS

```sql
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 物化视图

Hologres 不支持标准的 MATERIALIZED VIEW

替代方案：
1. 使用内部表 + 定时任务（DataWorks 调度）
2. 使用 Hologres 的实时物化能力（内部预计算）
3. 创建汇总表，通过 INSERT OVERWRITE 刷新

```sql
CREATE TABLE mv_order_summary (
    user_id     BIGINT,
    order_count BIGINT,
    total_amount DECIMAL(18,2),
    PRIMARY KEY (user_id)
);

INSERT INTO mv_order_summary
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id
ON CONFLICT (user_id) DO UPDATE SET
    order_count = EXCLUDED.order_count,
    total_amount = EXCLUDED.total_amount;
```

## 可更新视图

Hologres 视图不可更新


## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
```

限制：
不支持物化视图语法
不支持 WITH CHECK OPTION
不支持可更新视图
视图主要用于简化查询逻辑
实际预计算通过内部表 + 调度实现
