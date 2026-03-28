# Materialize: 约束

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)
> - Materialize 约束支持有限，兼容部分 PostgreSQL 语法
> - ============================================================
> - NOT NULL
> - ============================================================

```sql
CREATE TABLE users (
    id       INT NOT NULL,
    username TEXT NOT NULL,
    email    TEXT NOT NULL,
    age      INT                        -- 允许 NULL
);

ALTER TABLE users ALTER COLUMN age SET NOT NULL;
ALTER TABLE users ALTER COLUMN age DROP NOT NULL;
```

## DEFAULT


```sql
CREATE TABLE events (
    id         INT NOT NULL,
    event_type TEXT NOT NULL DEFAULT 'unknown',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE events ALTER COLUMN event_type SET DEFAULT 'info';
ALTER TABLE events ALTER COLUMN event_type DROP DEFAULT;
```

## UNIQUE（不强制执行）


## Materialize 支持 UNIQUE 语法但不强制执行

主要用于优化器生成更好的查询计划

```sql
CREATE TABLE products (
    id    INT NOT NULL,
    name  TEXT NOT NULL,
    UNIQUE (id)
);
```

## PRIMARY KEY（不强制执行）


## SOURCE 中的主键用于 CDC 语义

TABLE 中可以声明但不强制执行

## CHECK / FOREIGN KEY


## 不支持 CHECK 约束

不支持 FOREIGN KEY 约束

## 物化视图约束（通过查询逻辑保证）


## 通过 WHERE 过滤实现类似 CHECK 的效果

```sql
CREATE MATERIALIZED VIEW valid_users AS
SELECT * FROM users WHERE age > 0 AND age < 200;
```

## 通过 JOIN 实现类似外键的效果

```sql
CREATE MATERIALIZED VIEW enriched_orders AS
SELECT o.*, u.username
FROM orders o
JOIN users u ON o.user_id = u.id;    -- JOIN 隐式保证引用完整性
```

## SOURCE 约束


## 从 PostgreSQL CDC 导入时，SOURCE 保留原始表的约束语义

```sql
CREATE SOURCE pg_source
FROM POSTGRES CONNECTION pg_conn (PUBLICATION 'mz_source')
FOR TABLES (users, orders);
```

注意：Materialize 主要关注流式计算，约束支持有限
注意：NOT NULL 和 DEFAULT 是主要支持的约束
注意：UNIQUE 和 PRIMARY KEY 不强制执行
注意：数据完整性由上游数据源保证
