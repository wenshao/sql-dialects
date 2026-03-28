# KingbaseES (人大金仓): 索引

PostgreSQL compatible syntax.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)


## 普通索引（B-tree，默认）

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

## 降序索引

```sql
CREATE INDEX idx_age_desc ON users (age DESC);
```

## 表达式索引

```sql
CREATE INDEX idx_lower_email ON users (LOWER(email));
CREATE INDEX idx_year ON events (EXTRACT(YEAR FROM created_at));
```

## 部分索引（只索引满足条件的行）

```sql
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;
```

## 并发创建（不锁表）

```sql
CREATE INDEX CONCURRENTLY idx_age ON users (age);
```

## 包含列索引（Index-Only Scan 友好）

```sql
CREATE INDEX idx_username_incl ON users (username) INCLUDE (email, age);
```

## 不同索引类型

```sql
CREATE INDEX idx_btree ON users USING btree (age);
CREATE INDEX idx_hash ON users USING hash (username);
CREATE INDEX idx_gin ON documents USING gin (tags);
CREATE INDEX idx_gist ON places USING gist (location);
```

## GIN 索引用于 JSONB

```sql
CREATE INDEX idx_data ON users USING gin (data jsonb_path_ops);
```

## 全文搜索索引

```sql
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));
```

## 删除索引

```sql
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;
DROP INDEX CONCURRENTLY idx_age;
```

## 重建索引

```sql
REINDEX INDEX idx_age;
```

## 查看索引

```sql
SELECT * FROM pg_indexes WHERE tablename = 'users';
```

注意事项：
索引语法与 PostgreSQL 完全兼容
支持 B-tree、Hash、GIN、GiST 等索引类型
支持并发创建和删除索引
支持部分索引和表达式索引
分区表上的索引自动在各分区上创建
