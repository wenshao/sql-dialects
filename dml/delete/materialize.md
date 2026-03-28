# Materialize: DELETE

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


Materialize 的 TABLE 支持 DELETE
SOURCE 和 MATERIALIZED VIEW 不支持 DELETE
基本删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 条件删除

```sql
DELETE FROM users WHERE age < 18;
```

## 删除所有行

```sql
DELETE FROM users;
```

## IN 子查询

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## EXISTS 子查询

```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = users.email);
```

## 注意：物化视图自动反映删除


## 删除 TABLE 数据后，依赖的 MATERIALIZED VIEW 自动更新

```sql
DELETE FROM users WHERE status = 'inactive';
```

## DROP 操作（DDL 删除）


## 删除表

```sql
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS users CASCADE;        -- 同时删除依赖对象
```

## 删除物化视图

```sql
DROP MATERIALIZED VIEW IF EXISTS order_summary;
```

## 删除 SOURCE

```sql
DROP SOURCE IF EXISTS kafka_orders CASCADE;
```

## 删除连接

```sql
DROP CONNECTION IF EXISTS kafka_conn;
```

## 不支持的操作


不能删除 SOURCE 中的数据
DELETE FROM kafka_orders WHERE ...;  -- 错误
不能删除 MATERIALIZED VIEW 中的数据
DELETE FROM order_summary WHERE ...;  -- 错误
TRUNCATE 也不支持
注意：只有 TABLE 支持 DELETE
注意：DELETE 会触发依赖物化视图的增量更新
注意：兼容 PostgreSQL 的 DELETE 语法
注意：不支持 USING 子句（多表删除）
注意：不支持 RETURNING 子句
