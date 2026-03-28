# openGauss/GaussDB: 全文搜索

PostgreSQL compatible tsvector/tsquery approach.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)
> - 基本搜索：tsvector + tsquery

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');
```

运算符
&: AND
|: OR
!: NOT
<->: 相邻（短语搜索）

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'full <-> text <-> search');
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

## 存储 tsvector 列

```sql
ALTER TABLE articles ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(content,''))) STORED;
CREATE INDEX idx_search ON articles USING gin (search_vector);
```

## plainto_tsquery（自动处理空格为 AND）

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ plainto_tsquery('english', 'database performance');
```

## 高亮显示

```sql
SELECT ts_headline('english', content, to_tsquery('english', 'database'),
    'StartSel=<b>, StopSel=</b>, MaxFragments=3')
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database');
```

注意事项：
全文搜索语法与 PostgreSQL 兼容
使用 GIN 索引加速全文搜索
中文支持需要安装额外的分词扩展（如 zhparser）
openGauss 内置支持简单的中文分词配置
