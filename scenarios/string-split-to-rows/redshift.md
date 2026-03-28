# Redshift: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [Amazon Redshift - SPLIT_PART](https://docs.aws.amazon.com/redshift/latest/dg/r_SPLIT_PART.html)
> - [Amazon Redshift - Recursive CTE](https://docs.aws.amazon.com/redshift/latest/dg/r_WITH_clause.html)


## 示例数据

```sql
CREATE TABLE tags_csv (
    id   INT IDENTITY(1,1),
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');
```


## 方法 1: 数字表 + SPLIT_PART（推荐）

利用系统表生成数字序列
```sql
SELECT t.id, t.name,
       SPLIT_PART(t.tags, ',', n.n) AS tag
FROM   tags_csv t
JOIN   (SELECT ROW_NUMBER() OVER () AS n FROM stl_scan LIMIT 10) n
  ON   n.n <= REGEXP_COUNT(t.tags, ',') + 1
WHERE  SPLIT_PART(t.tags, ',', n.n) <> ''
ORDER BY t.id, n.n;
```


## 方法 2: 递归 CTE（Redshift 有限支持）

```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SPLIT_PART(tags, ',', 1) AS tag,
           tags AS original,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           SPLIT_PART(original, ',', pos + 1),
           original,
           pos + 1
    FROM   split_cte
    WHERE  SPLIT_PART(original, ',', pos + 1) <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```
