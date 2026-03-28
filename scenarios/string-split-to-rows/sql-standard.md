# SQL 标准: 字符串拆分为多行

> 参考资料:
> - ISO/IEC 9075 SQL Standard
> - SQL:2003 引入了递归 CTE (WITH RECURSIVE)
> - SQL:2016 引入了 JSON 函数

## 注意: SQL 标准中没有内置的字符串拆分函数

各数据库的实现方式各异

## 方法 1: 递归 CTE（SQL:2003 标准）

这是最通用的跨数据库方法
```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           CASE WHEN POSITION(',' IN tags) > 0
                THEN SUBSTRING(tags FROM 1 FOR POSITION(',' IN tags) - 1)
                ELSE tags END                    AS tag,
           CASE WHEN POSITION(',' IN tags) > 0
                THEN SUBSTRING(tags FROM POSITION(',' IN tags) + 1)
                ELSE '' END                      AS remaining,
           1                                     AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           CASE WHEN POSITION(',' IN remaining) > 0
                THEN SUBSTRING(remaining FROM 1 FOR POSITION(',' IN remaining) - 1)
                ELSE remaining END,
           CASE WHEN POSITION(',' IN remaining) > 0
                THEN SUBSTRING(remaining FROM POSITION(',' IN remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```

## 各数据库的首选方法对照

PostgreSQL:   UNNEST(STRING_TO_ARRAY(col, ','))
MySQL 8.0+:   JSON_TABLE 或递归 CTE
SQL Server:   STRING_SPLIT(col, ',')
Oracle:       CONNECT BY LEVEL + REGEXP_SUBSTR
BigQuery:     UNNEST(SPLIT(col, ','))
Snowflake:    SPLIT_TO_TABLE(col, ',')
ClickHouse:   arrayJoin(splitByChar(',', col))
Hive/Spark:   LATERAL VIEW explode(split(col, ','))
DuckDB:       UNNEST(STRING_SPLIT(col, ','))
Trino:        CROSS JOIN UNNEST(split(col, ','))
SQLite:       json_each + REPLACE 或递归 CTE
DB2:          XMLTABLE 或递归 CTE
Teradata:     STRTOK_SPLIT_TO_TABLE
