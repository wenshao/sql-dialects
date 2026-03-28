# MariaDB: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [MariaDB Knowledge Base - SUBSTRING_INDEX](https://mariadb.com/kb/en/substring_index/)
> - [MariaDB Knowledge Base - Recursive CTE](https://mariadb.com/kb/en/recursive-common-table-expressions-overview/)
> - [MariaDB Knowledge Base - Sequence Engine](https://mariadb.com/kb/en/sequence-storage-engine/)


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


## 方法 1: seq 序列引擎（MariaDB 特色，推荐）

```sql
SELECT t.id, t.name,
       SUBSTRING_INDEX(SUBSTRING_INDEX(t.tags, ',', s.seq), ',', -1) AS tag
FROM   tags_csv t
JOIN   seq_1_to_100 s
  ON   s.seq <= 1 + LENGTH(t.tags) - LENGTH(REPLACE(t.tags, ',', ''));
```


## 方法 2: 递归 CTE（MariaDB 10.2.2+）

```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SUBSTRING_INDEX(tags, ',', 1)     AS tag,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTRING(tags, LOCATE(',', tags) + 1)
                ELSE '' END                  AS remaining,
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


## 方法 3: JSON_TABLE（MariaDB 10.6+）

```sql
SELECT t.id, t.name, j.tag
FROM   tags_csv t,
       JSON_TABLE(
           CONCAT('["', REPLACE(t.tags, ',', '","'), '"]'),
           '$[*]' COLUMNS (tag VARCHAR(100) PATH '$')
       ) AS j;
```
