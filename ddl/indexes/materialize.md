# Materialize: 索引

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


## Materialize 的索引用于加速查询物化视图和表

索引决定数据如何在内存中排列

## CREATE INDEX


## 在表上创建索引

```sql
CREATE INDEX idx_users_email ON users (email);
```

## 在物化视图上创建索引

```sql
CREATE INDEX idx_summary_user ON order_summary (user_id);
```

## 复合索引

```sql
CREATE INDEX idx_users_city_age ON users (city, age);
```

## IF NOT EXISTS

```sql
CREATE INDEX IF NOT EXISTS idx_users_name ON users (username);
```

## 默认索引（创建物化视图时自动创建的索引）

```sql
CREATE DEFAULT INDEX ON order_summary;
```

## IN CLUSTER（指定计算集群）

```sql
CREATE INDEX idx_orders_amount IN CLUSTER default ON orders (amount);
```

## 索引对查询的影响


## 没有索引：全表扫描

```sql
SELECT * FROM users WHERE email = 'alice@example.com';
```

## 有索引后：点查询（point lookup）加速

```sql
CREATE INDEX idx_email ON users (email);
SELECT * FROM users WHERE email = 'alice@example.com';  -- 使用索引
```

## 物化视图索引加速 SUBSCRIBE

```sql
CREATE INDEX idx_mv_key ON order_summary (user_id);
```

## 删除索引


```sql
DROP INDEX idx_users_email;
DROP INDEX IF EXISTS idx_users_email;
```

## 查看索引


```sql
SHOW INDEXES;
SHOW INDEXES FROM users;
SHOW INDEXES IN CLUSTER default;
```

注意：Materialize 索引存储在内存中
注意：索引主要用于加速 SELECT（点查询和范围查询）
注意：每个索引都会增加内存消耗
注意：物化视图的索引用于加速对视图的查询
注意：Materialize 不支持 UNIQUE INDEX
注意：不支持 GIN, GiST, BRIN 等高级索引类型
