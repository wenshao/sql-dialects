# PolarDB: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [PolarDB 兼容 MySQL / PostgreSQL / Oracle 语法](https://help.aliyun.com/product/172538.html)
> - [PolarDB-X 分布式数据库](https://help.aliyun.com/document_detail/313263.html)


## 示例数据（MySQL 兼容模式）

```sql
CREATE TABLE tags_csv (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');
```

## 方法 1: JSON_TABLE（PolarDB MySQL 模式）

```sql
SELECT t.id, t.name, j.tag
FROM   tags_csv t,
       JSON_TABLE(
           CONCAT('["', REPLACE(t.tags, ',', '","'), '"]'),
           '$[*]' COLUMNS (tag VARCHAR(100) PATH '$')
       ) AS j;
```

## 方法 2: 递归 CTE

```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SUBSTRING_INDEX(tags, ',', 1)  AS tag,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTRING(tags, LOCATE(',', tags) + 1)
                ELSE '' END               AS remaining,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           SUBSTRING_INDEX(remaining, ',', 1),
           CASE WHEN LOCATE(',', remaining) > 0
                THEN SUBSTRING(remaining, LOCATE(',', remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```
