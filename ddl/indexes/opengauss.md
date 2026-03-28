# openGauss/GaussDB: 索引

PostgreSQL compatible with openGauss extensions.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)


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
CREATE INDEX idx_btree ON users USING btree (age);      -- 默认
CREATE INDEX idx_hash ON users USING hash (username);    -- 等值查询
CREATE INDEX idx_gin ON documents USING gin (tags);      -- 数组、JSONB、全文
CREATE INDEX idx_gist ON places USING gist (location);   -- 几何、范围
```

## GIN 索引用于 JSONB

```sql
CREATE INDEX idx_data ON users USING gin (data jsonb_path_ops);
```

## 全文搜索索引

```sql
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));
```

## 本地分区索引（分区表上的索引）

```sql
CREATE INDEX idx_logs_date ON logs (log_date) LOCAL;
```

## 全局分区索引

```sql
CREATE INDEX idx_logs_message ON logs (message) GLOBAL;
```

列存表上的 Psort 索引（openGauss 特有）
CREATE INDEX idx_col ON col_table USING psort (col1);
删除索引

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
列存储表只支持 Psort 索引和 B-tree 索引
MOT 内存表有自己的索引类型
GaussDB 商业版支持 AI 自动索引推荐
分区表支持本地索引和全局索引
