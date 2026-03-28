# Vertica: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [Vertica Documentation - SPLIT_PART](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/String/SPLIT_PART.htm)
> - [Vertica Documentation - String Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/String/StringFunctions.htm)


## 示例数据

```sql
CREATE TABLE tags_csv (
    id   INT,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv VALUES (1, 'Alice', 'python,java,sql');
INSERT INTO tags_csv VALUES (2, 'Bob',   'go,rust');
INSERT INTO tags_csv VALUES (3, 'Carol', 'sql,python,javascript,typescript');
COMMIT;
```


## 方法 1: CROSS JOIN + SPLIT_PART（推荐）

```sql
WITH nums AS (
    SELECT ROW_NUMBER() OVER () AS n
    FROM   (SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
            UNION ALL SELECT 4 UNION ALL SELECT 5
            UNION ALL SELECT 6 UNION ALL SELECT 7
            UNION ALL SELECT 8 UNION ALL SELECT 9
            UNION ALL SELECT 10) t(x)
)
SELECT t.id, t.name, SPLIT_PART(t.tags, ',', n.n) AS tag
FROM   tags_csv t
JOIN   nums n ON n.n <= REGEXP_COUNT(t.tags, ',') + 1
ORDER BY t.id, n.n;
```


## 方法 2: MapItems / EXPLODE（Vertica flex tables）

如果数据存储在 Flex Table 中可用 MAPITEMS

## 方法 3: 递归 CTE

```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SPLIT_PART(tags, ',', 1)      AS tag,
           tags                           AS original,
           1                              AS pos
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
