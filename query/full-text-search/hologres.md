# Hologres: 全文搜索（兼容 PostgreSQL 语法）

> 参考资料:
> - [Hologres SQL - SELECT](https://help.aliyun.com/zh/hologres/user-guide/select)
> - [Hologres Built-in Functions](https://help.aliyun.com/zh/hologres/user-guide/built-in-functions)


## LIKE 模糊搜索

```sql
SELECT * FROM articles
WHERE content LIKE '%database%';
```

## ILIKE（大小写不敏感）

```sql
SELECT * FROM articles
WHERE content ILIKE '%database%';
```

## POSITION（查找子字符串位置）

```sql
SELECT * FROM articles
WHERE POSITION('database' IN LOWER(content)) > 0;
```

## 正则表达式搜索（~ 运算符）

```sql
SELECT * FROM articles
WHERE content ~* 'database.*performance';
```

## 多关键词搜索

```sql
SELECT * FROM articles
WHERE content ~* '(database|performance|optimization)';

SELECT * FROM articles
WHERE content LIKE '%database%' AND content LIKE '%performance%';
```

## tsvector / tsquery（部分兼容 PostgreSQL 全文搜索）

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');
```

## 带排名

```sql
SELECT title,
    ts_rank(to_tsvector('english', content), to_tsquery('english', 'database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database')
ORDER BY rank DESC;
```

## GIN 索引加速

```sql
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));
```

注意：Hologres 部分兼容 PostgreSQL 全文搜索语法
注意：Hologres 的全文搜索功能可能不如原生 PostgreSQL 完整
注意：Hologres 行存表适合点查，列存表适合分析，全文搜索在行存表上性能更好
注意：如需高性能全文搜索，建议结合阿里云 OpenSearch 使用
