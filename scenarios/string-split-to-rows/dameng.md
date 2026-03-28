# 达梦 (Dameng): 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [达梦数据库 SQL 参考手册](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)
> - 达梦兼容 Oracle 语法


## 示例数据

```sql
CREATE TABLE tags_csv (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES ('Alice', 'python,java,sql');
INSERT INTO tags_csv (name, tags) VALUES ('Bob',   'go,rust');
INSERT INTO tags_csv (name, tags) VALUES ('Carol', 'sql,python,javascript,typescript');
COMMIT;
```

## 方法 1: CONNECT BY LEVEL + REGEXP_SUBSTR（兼容 Oracle）

```sql
SELECT id, name,
       TRIM(REGEXP_SUBSTR(tags, '[^,]+', 1, LEVEL)) AS tag,
       LEVEL AS pos
FROM   tags_csv
CONNECT BY LEVEL <= REGEXP_COUNT(tags, ',') + 1
       AND PRIOR id = id
       AND PRIOR DBMS_RANDOM.VALUE IS NOT NULL
ORDER BY id, pos;
```

## 方法 2: 递归 CTE

```sql
WITH RECURSIVE split_cte (id, name, tag, remaining, pos) AS (
    SELECT id, name,
           SUBSTR(tags, 1, CASE WHEN INSTR(tags, ',') > 0
                               THEN INSTR(tags, ',') - 1
                               ELSE LENGTH(tags) END),
           CASE WHEN INSTR(tags, ',') > 0
                THEN SUBSTR(tags, INSTR(tags, ',') + 1)
                ELSE '' END,
           1
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           SUBSTR(remaining, 1, CASE WHEN INSTR(remaining, ',') > 0
                                     THEN INSTR(remaining, ',') - 1
                                     ELSE LENGTH(remaining) END),
           CASE WHEN INSTR(remaining, ',') > 0
                THEN SUBSTR(remaining, INSTR(remaining, ',') + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```
