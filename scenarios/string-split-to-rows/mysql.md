# MySQL: 字符串拆分为行

> 参考资料:
> - [MySQL 8.0 Reference Manual - String Functions](https://dev.mysql.com/doc/refman/8.0/en/string-functions.html)
> - [MySQL 8.0 Reference Manual - JSON_TABLE](https://dev.mysql.com/doc/refman/8.0/en/json-table-functions.html)
> - [MySQL 8.0 Reference Manual - Recursive CTE](https://dev.mysql.com/doc/refman/8.0/en/with.html)

## 示例数据

```sql
CREATE TABLE tags_csv (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');
```

## 方法 1: JSON_TABLE（推荐, MySQL 8.0.4+）

将逗号分隔字符串转为 JSON 数组再展开

## 

```sql
SELECT t.id, t.name, j.tag
FROM   tags_csv t,
       JSON_TABLE(
           CONCAT('["', REPLACE(t.tags, ',', '","'), '"]'),
           '$[*]' COLUMNS (tag VARCHAR(100) PATH '$')
       ) AS j;
```

## 方法 2: 递归 CTE（MySQL 8.0+）

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

## 方法 3: 数字辅助表 + SUBSTRING_INDEX（MySQL 5.x 兼容）

先建数字表
```sql
CREATE TABLE numbers (n INT PRIMARY KEY);
INSERT INTO numbers VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);

SELECT t.id, t.name,
       SUBSTRING_INDEX(SUBSTRING_INDEX(t.tags, ',', n.n), ',', -1) AS tag
FROM   tags_csv t
JOIN   numbers n
  ON   n.n <= 1 + LENGTH(t.tags) - LENGTH(REPLACE(t.tags, ',', ''))
ORDER BY t.id, n.n;
```
