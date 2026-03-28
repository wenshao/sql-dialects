# Spanner: 全文搜索

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## Setup: create tokenized columns and search index


Add a TOKENLIST column (stores tokens for search)
```sql
CREATE TABLE Articles (
    ArticleId   INT64 NOT NULL,
    Title       STRING(500),
    Content     STRING(MAX),
    TitleTokens TOKENLIST AS (TOKENIZE_FULLTEXT(Title)) HIDDEN,
    ContentTokens TOKENLIST AS (TOKENIZE_FULLTEXT(Content)) HIDDEN
) PRIMARY KEY (ArticleId);

```

Create search index
```sql
CREATE SEARCH INDEX idx_articles_search
    ON Articles (TitleTokens, ContentTokens);

```

## Basic search


SEARCH function
```sql
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database performance');

```

Search with AND (space = AND by default)
```sql
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database performance');

```

Search with OR
```sql
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database OR performance');

```

Search with NOT
```sql
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database -mysql');

```

Phrase search (exact phrase)
```sql
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, '"full text search"');

```

## Ranking


SCORE function for relevance ranking
```sql
SELECT ArticleId, Title,
    SCORE(ContentTokens, 'database') AS relevance
FROM Articles
WHERE SEARCH(ContentTokens, 'database')
ORDER BY relevance DESC;

```

## Search across multiple columns


```sql
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(TitleTokens, 'database') OR SEARCH(ContentTokens, 'database');

```

## Substring search (TOKENIZE_SUBSTRING)


```sql
CREATE TABLE Products (
    ProductId    INT64 NOT NULL,
    Name         STRING(255),
    NameSubstr   TOKENLIST AS (TOKENIZE_SUBSTRING(Name)) HIDDEN
) PRIMARY KEY (ProductId);

CREATE SEARCH INDEX idx_products_substr ON Products (NameSubstr);

```

Substring match (like ILIKE '%widget%')
```sql
SELECT ProductId, Name
FROM Products
WHERE SEARCH_SUBSTRING(NameSubstr, 'widget');

```

## Numeric and other tokenizers


TOKENIZE_NUMBER for numeric search
TOKENIZE_BOOL for boolean search
TOKENIZE_NGRAMS for n-gram tokenization

## Search index with STORING


```sql
CREATE SEARCH INDEX idx_search_with_data
    ON Articles (ContentTokens)
    STORING (Title, Content);

```

Note: Full-text search requires TOKENLIST columns and SEARCH indexes
Note: SEARCH() function uses search index for efficient lookup
Note: SCORE() function returns relevance score
Note: TOKENIZE_FULLTEXT for natural language, TOKENIZE_SUBSTRING for LIKE
Note: Unlike PostgreSQL, no tsvector/tsquery; uses TOKENLIST/SEARCH
Note: Full-text search is globally consistent
Note: Search indexes are managed separately from secondary indexes
