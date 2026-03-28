# PostgreSQL: 字符串拆分为行

> 参考资料:
> - [PostgreSQL Documentation - String Functions](https://www.postgresql.org/docs/current/functions-string.html)

## STRING_TO_ARRAY + UNNEST（推荐, 8.1+）

```sql
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM tags_csv;
```

设计分析: 两步组合
  STRING_TO_ARRAY: 字符串 → 数组（'a,b,c' → {a,b,c}）
  UNNEST: 数组 → 多行（{a,b,c} → 3行）
  PostgreSQL 的数组类型让这个操作自然且高效。

## regexp_split_to_table (8.3+)

```sql
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM tags_csv;
```

支持正则分隔符: regexp_split_to_table(tags, ',\s*')（逗号+可选空格）

## LATERAL + UNNEST + WITH ORDINALITY（保留序号, 9.3+/9.4+）

```sql
SELECT t.id, t.name, s.ordinality, s.tag
FROM tags_csv t,
     LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
            WITH ORDINALITY AS s(tag, ordinality);
```

WITH ORDINALITY 为每个展开的元素添加序号列（从 1 开始）
这在需要保留原始顺序时非常有用

## 递归 CTE（通用方法, 8.4+）

```sql
WITH RECURSIVE split AS (
    SELECT id, name,
           LEFT(tags, POSITION(',' IN tags || ',') - 1) AS tag,
           SUBSTRING(tags FROM POSITION(',' IN tags || ',') + 1) AS remaining
    FROM tags_csv
    UNION ALL
    SELECT id, name,
           LEFT(remaining, POSITION(',' IN remaining || ',') - 1),
           SUBSTRING(remaining FROM POSITION(',' IN remaining || ',') + 1)
    FROM split WHERE remaining <> ''
)
SELECT id, name, tag FROM split ORDER BY id;
```

## 横向对比与对引擎开发者的启示

### 拆分函数

  PostgreSQL: STRING_TO_ARRAY + UNNEST 或 regexp_split_to_table
  MySQL:      无内置拆分函数（需递归CTE, 8.0+）
  Oracle:     REGEXP_SUBSTR + CONNECT BY LEVEL
  SQL Server: STRING_SPLIT (2016+, 不保证顺序) 或 OPENJSON
  BigQuery:   SPLIT() + UNNEST()

### PostgreSQL 的优势

  (a) 数组是一等类型 → STRING_TO_ARRAY 自然
  (b) UNNEST 是通用的数组展开函数（不仅限于字符串拆分）
  (c) WITH ORDINALITY 保留顺序（SQL Server STRING_SPLIT 无此能力到 2022）

对引擎开发者:
  内置数组类型 + UNNEST 函数是字符串拆分的最优基础设施。
  不需要专门的 STRING_SPLIT 函数——组合已有原语更优雅。
  WITH ORDINALITY 对保留顺序至关重要（很多场景需要知道"第几个元素"）。
