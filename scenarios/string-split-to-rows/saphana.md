# SAP HANA: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [SAP HANA SQL Reference - SERIES_GENERATE_INTEGER](https://help.sap.com/docs/HANA_CLOUD/c1d3f60099654ecfb3fe36ac93c121bb/f6e0dd0e15814b2f9f47b228fcd20e60.html)
> - [SAP HANA SQL Reference - String Functions](https://help.sap.com/docs/HANA_CLOUD/c1d3f60099654ecfb3fe36ac93c121bb/20a24d4b75191014b1e3a10c85cc1df1.html)


## 示例数据

```sql
CREATE TABLE tags_csv (
    id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name NVARCHAR(100),
    tags NVARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES ('Alice', 'python,java,sql');
INSERT INTO tags_csv (name, tags) VALUES ('Bob',   'go,rust');
INSERT INTO tags_csv (name, tags) VALUES ('Carol', 'sql,python,javascript,typescript');
```

## 方法 1: SERIES_GENERATE_INTEGER + SUBSTRING（推荐）

```sql
SELECT t.id, t.name,
       SUBSTRING_REGEXPR('([^,]+)' IN t.tags OCCURRENCE s.ELEMENT_NUMBER) AS tag,
       s.ELEMENT_NUMBER AS pos
FROM   tags_csv t,
       SERIES_GENERATE_INTEGER(1, 1, OCCURRENCES_REGEXPR(',' IN t.tags) + 1) s
ORDER BY t.id, pos;
```

## 方法 2: 递归 CTE

```sql
WITH split_cte AS (
    SELECT id, name,
           CASE WHEN LOCATE(',', tags) > 0
                THEN LEFT(tags, LOCATE(',', tags) - 1)
                ELSE tags END              AS tag,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTRING(tags, LOCATE(',', tags) + 1)
                ELSE '' END                AS remaining,
           1                               AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           CASE WHEN LOCATE(',', remaining) > 0
                THEN LEFT(remaining, LOCATE(',', remaining) - 1)
                ELSE remaining END,
           CASE WHEN LOCATE(',', remaining) > 0
                THEN SUBSTRING(remaining, LOCATE(',', remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```
