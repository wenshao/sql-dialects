# Materialize: Sequences & Auto-Increment

> 参考资料:
> - [Materialize Documentation - CREATE TABLE](https://materialize.com/docs/sql/create-table/)
> - [Materialize Documentation - SQL Functions](https://materialize.com/docs/sql/functions/)


## Materialize 不支持 CREATE SEQUENCE（截至当前版本）


## 替代方案


方法 1：使用源系统的 ID
Materialize 通常从 Kafka、PostgreSQL CDC 等源读取数据
数据已有主键/ID，不需要数据库生成
方法 2：使用 mz_now() 等内部函数
mz_now() 返回 Materialize 的逻辑时间戳
方法 3：使用 ROW_NUMBER() 窗口函数

```sql
CREATE MATERIALIZED VIEW users_ranked AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;
```

## 方法 4：使用源数据中的 UUID

大多数流式数据源会在消息中包含 UUID

## Materialize TABLE（支持 INSERT）

## Materialize 的 TABLE 支持手动插入数据

```sql
CREATE TABLE events (
    id         TEXT,                          -- 应用层生成 UUID
    event_type TEXT,
    event_data TEXT,
    created_at TIMESTAMP DEFAULT now()
);

INSERT INTO events (id, event_type, event_data)
VALUES ('7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b', 'click', '{"page": "home"}');
```

## 序列 vs 自增 权衡

Materialize 是流式物化视图引擎，设计理念不同于 OLTP：
1. 数据通常从外部源（Kafka CDC）流入，已有 ID
2. 表支持 INSERT 但不是主要数据入口
3. ROW_NUMBER() 可在物化视图中生成序号
4. UUID 应在应用层或上游系统生成
限制：
不支持 CREATE SEQUENCE
不支持 AUTO_INCREMENT / IDENTITY / SERIAL / BIGSERIAL
不支持 GENERATED AS IDENTITY
不支持内置 UUID 生成函数
