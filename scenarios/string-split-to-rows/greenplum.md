# Greenplum: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [Greenplum Documentation - String Functions](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-function-summary.html)
> - [Greenplum Documentation - UNNEST](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-SELECT.html)


## 示例数据

```sql
CREATE TABLE tags_csv (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');
```


## 方法 1: UNNEST + STRING_TO_ARRAY（推荐，兼容 PostgreSQL）

```sql
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;
```


## 方法 2: regexp_split_to_table

```sql
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;
```


## 方法 3: 递归 CTE（Greenplum 6.x+）

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
