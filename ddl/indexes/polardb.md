# PolarDB: 索引

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 普通索引

```sql
CREATE INDEX idx_age ON users (age);
```

## 唯一索引

```sql
CREATE UNIQUE INDEX uk_email ON users (email);
```

## 复合索引

```sql
CREATE INDEX idx_city_age ON users (city, age);
```

## 前缀索引

```sql
CREATE INDEX idx_email_prefix ON users (email(20));
```

## 全文索引

```sql
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
```

## 降序索引

```sql
CREATE INDEX idx_age_desc ON users (age DESC);
```

## 函数索引（表达式索引）

```sql
CREATE INDEX idx_upper_name ON users ((UPPER(username)));
CREATE INDEX idx_json_name ON users ((CAST(data->>'$.name' AS CHAR(64))));
```

## 不可见索引

```sql
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER TABLE users ALTER INDEX idx_age VISIBLE;
```

## 全局二级索引（GSI，PolarDB-X 特有）

分布式环境下，在非分区键上创建全局索引

```sql
CREATE GLOBAL INDEX idx_global_email ON users (email)
    PARTITION BY HASH(email) PARTITIONS 4;
```

## 带覆盖列的全局索引（减少回表查询）

```sql
CREATE GLOBAL INDEX idx_global_username ON users (username)
    COVERING (email, age)
    PARTITION BY HASH(username) PARTITIONS 4;
```

## 聚簇全局索引（Clustered GSI）

```sql
CREATE CLUSTERED INDEX idx_clustered_user ON orders (user_id)
    PARTITION BY HASH(user_id) PARTITIONS 8;
```

## 删除索引

```sql
DROP INDEX idx_age ON users;
DROP INDEX IF EXISTS idx_age ON users;
```

## 删除全局索引

```sql
DROP INDEX idx_global_email ON users;
```

## 查看索引

```sql
SHOW INDEX FROM users;
SHOW GLOBAL INDEX FROM users;
```

## USING 指定索引类型

```sql
CREATE INDEX idx_age ON users (age) USING BTREE;
```

注意事项：
本地索引只在各自分片内有效
全局索引跨所有分片，可以加速非分区键查询
全局索引的维护开销较大（每次 DML 都需要维护）
HASH 索引仅在 MEMORY 引擎上支持
全局唯一索引可以保证分布式环境下的唯一性
