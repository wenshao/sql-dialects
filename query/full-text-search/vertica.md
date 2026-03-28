# Vertica: 全文搜索

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


Vertica 支持通过 Text Index 实现全文搜索

## 文本索引（Text Index）


创建文本索引（需要 v_txtindex schema）
```sql
CREATE TEXT INDEX idx_articles_content ON articles (id, content)
    STEMMER NONE TOKENIZER NONE;
```


使用内置 Stemmer（词干提取）
```sql
CREATE TEXT INDEX idx_articles_search ON articles (id, content)
    STEMMER PUBLIC.StemmerLib TOKENIZER PUBLIC.StringTokenizer;
```


删除文本索引
```sql
DROP TEXT INDEX idx_articles_content;
```


## 使用 LIKE / ILIKE（基本搜索）


```sql
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content ILIKE '%database%';  -- 大小写不敏感
```


多关键词
```sql
SELECT * FROM articles
WHERE content ILIKE '%database%'
  AND content ILIKE '%performance%';
```


## 正则搜索（REGEXP_LIKE）


```sql
SELECT * FROM articles WHERE REGEXP_LIKE(content, 'database|performance', 'i');
```


词边界
```sql
SELECT * FROM articles WHERE REGEXP_LIKE(content, '\bdatabase\b', 'i');
```


## 使用 v_txtindex 搜索


查找包含关键词的文档
```sql
SELECT a.id, a.title, a.content
FROM articles a
JOIN v_txtindex.idx_articles_content idx ON a.id = idx.id
WHERE idx.word = 'database';
```


多关键词搜索（AND）
```sql
SELECT a.id, a.title
FROM articles a
WHERE a.id IN (SELECT id FROM v_txtindex.idx_articles_content WHERE word = 'database')
  AND a.id IN (SELECT id FROM v_txtindex.idx_articles_content WHERE word = 'performance');
```


## 相关度评分


简单 TF 评分
```sql
SELECT a.id, a.title, COUNT(*) AS relevance
FROM articles a
JOIN v_txtindex.idx_articles_content idx ON a.id = idx.id
WHERE idx.word IN ('database', 'performance')
GROUP BY a.id, a.title
ORDER BY relevance DESC;
```


CASE 加权评分
```sql
SELECT title,
    CASE WHEN title ILIKE '%database%' THEN 10 ELSE 0 END +
    CASE WHEN content ILIKE '%database%' THEN 5 ELSE 0 END AS score
FROM articles
WHERE title ILIKE '%database%' OR content ILIKE '%database%'
ORDER BY score DESC;
```


## 模式匹配（MATCH 子句，Vertica 特有）


事件模式匹配（用于时间序列分析）
```sql
SELECT * FROM (
    SELECT user_id, event_name, event_time,
        MATCH(event_name, 'login' AS a, 'purchase' AS b
              PATTERN 'a b'
              DEFINE a AS event_name = 'login',
                     b AS event_name = 'purchase') AS matched
    FROM events
) t WHERE matched = TRUE;
```


注意：Vertica 通过 Text Index 实现全文搜索
注意：支持 ILIKE（大小写不敏感 LIKE）
注意：REGEXP_LIKE 支持正则搜索
注意：Vertica 的 MATCH 子句用于事件模式匹配，不是传统全文搜索
注意：生产环境可考虑集成 Elasticsearch 作为全文搜索补充
