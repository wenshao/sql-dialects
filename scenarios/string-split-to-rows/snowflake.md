# Snowflake: 字符串拆分为行

> 参考资料:
> - [1] Snowflake SQL Reference - SPLIT_TO_TABLE
>   https://docs.snowflake.com/en/sql-reference/functions/split_to_table
> - [2] Snowflake SQL Reference - FLATTEN
>   https://docs.snowflake.com/en/sql-reference/functions/flatten


## 示例数据

```sql
CREATE OR REPLACE TEMPORARY TABLE tags_csv (
    id NUMBER AUTOINCREMENT, name VARCHAR(100), tags VARCHAR(500));
INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

```

## 1. SPLIT_TO_TABLE（推荐，最简洁）


```sql
SELECT t.id, t.name, s.VALUE AS tag, s.INDEX AS pos
FROM tags_csv t, LATERAL SPLIT_TO_TABLE(t.tags, ',') s;

```

 SPLIT_TO_TABLE 是 Snowflake 专用表函数:
   输入: 字符串 + 分隔符
   输出: SEQ, INDEX, VALUE 列
   LATERAL: 每行调用一次表函数

## 2. STRTOK_SPLIT_TO_TABLE（等价方案）


```sql
SELECT t.id, t.name, s.VALUE AS tag, s.INDEX AS pos
FROM tags_csv t, LATERAL STRTOK_SPLIT_TO_TABLE(t.tags, ',') s;

```

## 3. FLATTEN + SPLIT（通用方案）


```sql
SELECT t.id, t.name, f.VALUE::VARCHAR AS tag, f.INDEX AS pos
FROM tags_csv t, LATERAL FLATTEN(INPUT => SPLIT(t.tags, ',')) f;

```

 SPLIT 返回 ARRAY → FLATTEN 展开为行
 这是 SPLIT_TO_TABLE 的底层实现原理

## 4. 语法设计分析（对 SQL 引擎开发者）


 对比各引擎的字符串拆分方案:
   Snowflake:  SPLIT_TO_TABLE / FLATTEN(SPLIT()) — 最简洁
   PostgreSQL: unnest(string_to_array('a,b,c', ','))
   MySQL:      无原生方案（需要递归 CTE 或 JSON_TABLE 变通）
   BigQuery:   UNNEST(SPLIT('a,b,c', ','))
   Oracle:     CONNECT BY + REGEXP_SUBSTR（最繁琐）
   SQL Server: STRING_SPLIT('a,b,c', ',')（2016+）

 对引擎开发者的启示:
   字符串拆分是高频需求，专用表函数（SPLIT_TO_TABLE / STRING_SPLIT）
   比通用方案（递归 CTE）性能好得多，且语法更清晰。
   MySQL 至今缺少原生方案是一个重大缺陷。

## 5. 递归 CTE 方式（通用但较慢）


```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SPLIT_PART(tags, ',', 1) AS tag,
           SUBSTR(tags, LEN(SPLIT_PART(tags, ',', 1)) + 2) AS remaining,
           1 AS pos
    FROM tags_csv
    UNION ALL
    SELECT id, name,
           SPLIT_PART(remaining, ',', 1),
           SUBSTR(remaining, LEN(SPLIT_PART(remaining, ',', 1)) + 2),
           pos + 1
    FROM split_cte WHERE remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;

```

## 横向对比: 字符串拆分方案

| 方案          | Snowflake          | PostgreSQL         | MySQL |
|------|------|------|------|
| 推荐方案      | SPLIT_TO_TABLE     | unnest(string_to)  | 递归CTE |
| 通用方案      | FLATTEN(SPLIT())   | regexp_split_to_t  | JSON_TABLE |
| 表函数        | SPLIT_TO_TABLE     | 无                 | 无 |
| 递归CTE       | 支持               | 支持               | 8.0+ |
| 性能          | 最优(原生表函数)   | 优(内置函数)       | 差(递归) |

