# DamengDB (达梦): 全文搜索

DamengDB has built-in full-text search using CONTEXT INDEX.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


## 创建全文索引

```sql
CREATE CONTEXT INDEX idx_ft_content ON articles (content) LEXER DEFAULT_LEXER;
```

## 多列全文索引

```sql
CREATE CONTEXT INDEX idx_ft_multi ON articles (title, content) LEXER DEFAULT_LEXER;
```

## 中文分词器

```sql
CREATE CONTEXT INDEX idx_ft_chinese ON articles (content) LEXER CHINESE_LEXER;
```

## 基本搜索（CONTAINS 函数）

```sql
SELECT * FROM articles
WHERE CONTAINS(content, 'database');
```

## 多关键词搜索（AND）

```sql
SELECT * FROM articles
WHERE CONTAINS(content, 'database AND performance');
```

## OR 搜索

```sql
SELECT * FROM articles
WHERE CONTAINS(content, 'database OR performance');
```

## NOT 搜索

```sql
SELECT * FROM articles
WHERE CONTAINS(content, 'database NOT mysql');
```

## 短语搜索

```sql
SELECT * FROM articles
WHERE CONTAINS(content, '"full text search"');
```

## 带相关度分数（SCORE 函数）

```sql
SELECT title, SCORE(1) AS relevance
FROM articles
WHERE CONTAINS(content, 'database', 1)
ORDER BY relevance DESC;
```

## 近似搜索（NEAR）

```sql
SELECT * FROM articles
WHERE CONTAINS(content, 'NEAR(database, performance, 5)');
```

## 通配符搜索

```sql
SELECT * FROM articles
WHERE CONTAINS(content, 'data%');
```

## 重建全文索引

```sql
ALTER INDEX idx_ft_content REBUILD;
```

## 删除全文索引

```sql
DROP INDEX idx_ft_content;
```

注意事项：
使用 CONTEXT INDEX 创建全文索引（类似 Oracle Text）
使用 CONTAINS 函数进行全文搜索（非 MATCH AGAINST）
支持中文分词（CHINESE_LEXER）
支持 NEAR 近似搜索
SCORE 函数返回相关度分数
