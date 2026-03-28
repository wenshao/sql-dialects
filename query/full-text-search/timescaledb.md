# TimescaleDB: 全文搜索

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)
> - TimescaleDB 继承 PostgreSQL 的全文搜索功能
> - 支持 tsvector/tsquery、GIN 索引
> - ============================================================
> - 基本全文搜索
> - ============================================================
> - to_tsvector + to_tsquery

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');
```

## plainto_tsquery（自动处理空格和标点）

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ plainto_tsquery('english', 'database performance');
```

## phraseto_tsquery（短语搜索）

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ phraseto_tsquery('english', 'database performance');
```

## websearch_to_tsquery（类似搜索引擎语法）

```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ websearch_to_tsquery('english', '"database performance" -slow');
```

## GIN 索引加速


## 在 tsvector 列上创建 GIN 索引

```sql
CREATE INDEX idx_articles_fts ON articles USING GIN (to_tsvector('english', content));
```

## 存储 tsvector 列加速查询

```sql
ALTER TABLE articles ADD COLUMN content_tsv TSVECTOR
    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;
CREATE INDEX idx_articles_tsv ON articles USING GIN (content_tsv);

SELECT * FROM articles WHERE content_tsv @@ to_tsquery('english', 'database');
```

## 相关度排序


## ts_rank

```sql
SELECT title, ts_rank(to_tsvector('english', content), to_tsquery('database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('database')
ORDER BY rank DESC;
```

## ts_rank_cd（覆盖密度排名）

```sql
SELECT title, ts_rank_cd(to_tsvector('english', content), to_tsquery('database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('database')
ORDER BY rank DESC;
```

## 高亮显示


```sql
SELECT title,
    ts_headline('english', content, to_tsquery('database'),
        'StartSel=<b>, StopSel=</b>, MaxWords=50') AS snippet
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('database');
```

## LIKE / 正则


```sql
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content ~* 'database\s+performance';
```

注意：完全兼容 PostgreSQL 的全文搜索功能
注意：GIN 索引可加速超级表的全文搜索
注意：支持多种语言的分词器
注意：tsvector + GIN 索引是推荐的全文搜索方案
