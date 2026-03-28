# Greenplum: 全文搜索

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


Greenplum 基于 PostgreSQL，支持完整的全文搜索功能

## tsvector / tsquery 基础


将文本转为 tsvector（分词向量）
```sql
SELECT to_tsvector('english', 'The quick brown fox jumps over the lazy dog');
```


将查询转为 tsquery
```sql
SELECT to_tsquery('english', 'quick & fox');
```


基本全文搜索
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');
```


## 全文搜索列和索引


添加 tsvector 列
```sql
ALTER TABLE articles ADD COLUMN search_vector TSVECTOR;
```


更新 tsvector 列
```sql
UPDATE articles SET search_vector =
    setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(content, '')), 'B');
```


创建 GIN 索引
```sql
CREATE INDEX idx_articles_search ON articles USING GIN (search_vector);
```


使用索引查询
```sql
SELECT * FROM articles
WHERE search_vector @@ to_tsquery('english', 'database & performance');
```


## 查询语法


AND
```sql
SELECT * FROM articles
WHERE search_vector @@ to_tsquery('english', 'database & performance');
```


OR
```sql
SELECT * FROM articles
WHERE search_vector @@ to_tsquery('english', 'database | performance');
```


NOT
```sql
SELECT * FROM articles
WHERE search_vector @@ to_tsquery('english', 'database & !mysql');
```


短语搜索
```sql
SELECT * FROM articles
WHERE search_vector @@ phraseto_tsquery('english', 'full text search');
```


前缀匹配
```sql
SELECT * FROM articles
WHERE search_vector @@ to_tsquery('english', 'data:*');
```


## 相关度排序


```sql
SELECT title, ts_rank(search_vector, query) AS rank
FROM articles, to_tsquery('english', 'database & performance') AS query
WHERE search_vector @@ query
ORDER BY rank DESC;
```


带权重的排序
```sql
SELECT title, ts_rank_cd(search_vector, query) AS rank
FROM articles, to_tsquery('english', 'database') AS query
WHERE search_vector @@ query
ORDER BY rank DESC;
```


## 高亮显示


```sql
SELECT ts_headline('english', content,
    to_tsquery('english', 'database'),
    'StartSel=<b>, StopSel=</b>, MaxFragments=3') AS highlight
FROM articles
WHERE search_vector @@ to_tsquery('english', 'database');
```


## 自动更新触发器


```sql
CREATE FUNCTION update_search_vector() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_search_vector
    BEFORE INSERT OR UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION update_search_vector();
```


注意：Greenplum 兼容 PostgreSQL 全文搜索语法
注意：GIN 索引加速全文搜索
注意：支持权重（A > B > C > D）
注意：支持多种语言分词（english, simple, german 等）
