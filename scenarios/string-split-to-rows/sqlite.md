# SQLite: 字符串拆分为行

> 参考资料:
> - [SQLite Documentation - Recursive CTE](https://www.sqlite.org/lang_with.html)
> - [SQLite Documentation - JSON Functions](https://www.sqlite.org/json1.html)

## 递归 CTE 方式（通用方案，所有版本）

将 'a,b,c,d' 拆分为 4 行:
```sql
WITH RECURSIVE split(value, rest) AS (
    SELECT '', 'a,b,c,d' || ','
    UNION ALL
    SELECT
        substr(rest, 1, instr(rest, ',') - 1),
        substr(rest, instr(rest, ',') + 1)
    FROM split WHERE rest != ''
)
SELECT value FROM split WHERE value != '';
```

输出: a, b, c, d

从表中拆分:
假设 users 表有 tags TEXT 列，值为 'vip,premium,new'
```sql
WITH RECURSIVE tag_split AS (
    SELECT id, '' AS tag, tags || ',' AS rest FROM users
    UNION ALL
    SELECT id,
        substr(rest, 1, instr(rest, ',') - 1),
        substr(rest, instr(rest, ',') + 1)
    FROM tag_split WHERE rest != ''
)
SELECT id, tag FROM tag_split WHERE tag != '';
```

## json_each 方式（3.9.0+，更简洁）

先将逗号分隔字符串转为 JSON 数组，再用 json_each 展开:
```sql
SELECT value FROM json_each('["a","b","c","d"]');
```

将逗号分隔字符串转为 JSON 数组:
```sql
SELECT value
FROM json_each('["' || replace('a,b,c,d', ',', '","') || '"]');
```

从表中拆分:
```sql
SELECT u.id, j.value AS tag
FROM users u, json_each('["' || replace(u.tags, ',', '","') || '"]') j;
```

## 为什么 SQLite 没有 SPLIT 函数

SQLite 没有内置的 STRING_SPLIT / SPLIT_PART 函数。
原因: 嵌入式定位，核心函数保持最少。
但通过递归 CTE 或 json_each 可以实现相同功能。

对比:
  MySQL:      无 SPLIT（用 SUBSTRING_INDEX 模拟）
  PostgreSQL: string_to_array() + unnest()（最简洁）
  ClickHouse: splitByChar() + arrayJoin()
  BigQuery:   SPLIT() + UNNEST()

## 对比与引擎开发者启示

SQLite 字符串拆分:
  递归 CTE → 通用但冗长
  json_each → 简洁但需要构造 JSON 数组
  无内置 SPLIT → 嵌入式极简设计的代价

对引擎开发者的启示:
  SPLIT + UNNEST/EXPLODE 是高频需求，值得内置。
  递归 CTE 可以替代 SPLIT，但性能和可读性都差。
  json_each 是一个聪明的替代方案（复用已有的 JSON 基础设施）。
