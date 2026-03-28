# Oracle: 字符串拆分为行

> 参考资料:
> - [Oracle SQL Language Reference - REGEXP_SUBSTR](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/REGEXP_SUBSTR.html)

## 准备数据

```sql
CREATE TABLE tags_csv (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(100),
    tags VARCHAR2(500)
);
INSERT INTO tags_csv (name, tags) VALUES ('Alice', 'python,java,sql');
INSERT INTO tags_csv (name, tags) VALUES ('Bob',   'go,rust');
INSERT INTO tags_csv (name, tags) VALUES ('Carol', 'sql,python,javascript,typescript');
COMMIT;
```

## CONNECT BY + REGEXP_SUBSTR（推荐，10g+）

```sql
SELECT id, name,
       TRIM(REGEXP_SUBSTR(tags, '[^,]+', 1, LEVEL)) AS tag,
       LEVEL AS pos
FROM tags_csv
CONNECT BY LEVEL <= REGEXP_COUNT(tags, ',') + 1
       AND PRIOR id = id
       AND PRIOR SYS_GUID() IS NOT NULL
ORDER BY id, pos;
```

设计分析:
  CONNECT BY LEVEL 生成序列 + REGEXP_SUBSTR 提取第 N 个元素。
  PRIOR SYS_GUID() IS NOT NULL 防止行间交叉产生（每行独立递归）。
  这是 Oracle 最经典的字符串拆分技巧，但语法不直观。

## XMLTABLE（10g+，利用 XML 解析）

```sql
SELECT t.id, t.name, x.tag
FROM tags_csv t,
     XMLTABLE(
         'for $s in ora:tokenize($str, ",") return $s'
         PASSING t.tags AS "str"
         COLUMNS tag VARCHAR2(100) PATH '.'
     ) x;
```

## JSON_TABLE（12c+，利用 JSON 解析）

```sql
SELECT t.id, t.name, j.tag
FROM tags_csv t,
     JSON_TABLE(
         '["' || REPLACE(t.tags, ',', '","') || '"]',
         '$[*]' COLUMNS (tag VARCHAR2(100) PATH '$')
     ) j;
```

技巧: 将 CSV 转为 JSON 数组再用 JSON_TABLE 展开

## 递归 CTE（11g R2+）

```sql
WITH split_cte (id, name, tag, remaining, pos) AS (
    SELECT id, name,
           REGEXP_SUBSTR(tags, '[^,]+', 1, 1),
           SUBSTR(tags, INSTR(tags || ',', ',') + 1),
           1
    FROM tags_csv
    UNION ALL
    SELECT id, name,
           REGEXP_SUBSTR(remaining, '[^,]+', 1, 1),
           SUBSTR(remaining, INSTR(remaining || ',', ',') + 1),
           pos + 1
    FROM split_cte
    WHERE remaining IS NOT NULL
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
```

'' = NULL 在递归中的影响:
WHERE remaining IS NOT NULL 同时处理了 NULL 和空字符串
因为 '' = NULL，空的 remaining 自然终止递归

## 横向对比: 字符串拆分方案

Oracle:     CONNECT BY + REGEXP_SUBSTR（独有技巧）
PostgreSQL: string_to_table('a,b,c', ',') (14+) 或 unnest(string_to_array(...))
MySQL:      JSON_TABLE + 递归 CTE
SQL Server: STRING_SPLIT('a,b,c', ',')（2016+，最简单但不保证顺序）

对引擎开发者的启示:
  内置 STRING_SPLIT/STRING_TO_TABLE 函数是用户最常请求的功能之一。
  应返回元素值 + 序号（顺序信息很重要）。
  Oracle 缺乏这样的内置函数，需要复杂的技巧替代。

## 对引擎开发者的总结

1. Oracle 缺乏原生的字符串拆分函数，需要 CONNECT BY 等技巧替代。
2. CONNECT BY + REGEXP_SUBSTR 是经典方案但语法不直观。
3. JSON_TABLE 方法巧妙地将 CSV 转为 JSON 数组再展开。
4. 新引擎应提供内置的 STRING_SPLIT 或 UNNEST 函数。
5. '' = NULL 在递归终止条件中意外地"帮了忙"（空串自动终止）。
