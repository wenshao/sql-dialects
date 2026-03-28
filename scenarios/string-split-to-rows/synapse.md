# Synapse: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [Azure Synapse Analytics - STRING_SPLIT](https://learn.microsoft.com/en-us/sql/t-sql/functions/string-split-transact-sql)
> - [Azure Synapse Analytics - OPENJSON](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-json-files)


## 示例数据

```sql
CREATE TABLE tags_csv (
    id   INT IDENTITY(1,1),
    name NVARCHAR(100),
    tags NVARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    (N'Alice', N'python,java,sql'),
    (N'Bob',   N'go,rust'),
    (N'Carol', N'sql,python,javascript,typescript');
```


## 方法 1: STRING_SPLIT（推荐，与 SQL Server 语法相同）

```sql
SELECT t.id, t.name, s.value AS tag
FROM   tags_csv t
CROSS APPLY STRING_SPLIT(t.tags, ',') s;
```


## 方法 2: OPENJSON

```sql
SELECT t.id, t.name, j.[value] AS tag, j.[key] AS pos
FROM   tags_csv t
CROSS APPLY OPENJSON('["' + REPLACE(t.tags, ',', '","') + '"]') j;
```


## 方法 3: 递归 CTE

```sql
WITH split_cte AS (
    SELECT id, name,
           LEFT(tags, CHARINDEX(',', tags + ',') - 1) AS tag,
           STUFF(tags, 1, CHARINDEX(',', tags + ','), '') AS remaining,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           LEFT(remaining, CHARINDEX(',', remaining + ',') - 1),
           STUFF(remaining, 1, CHARINDEX(',', remaining + ','), ''),
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```
