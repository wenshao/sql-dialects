# Hive: 字符串拆分为多行 (SPLIT + LATERAL VIEW EXPLODE)

> 参考资料:
> - [1] Apache Hive - LATERAL VIEW
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView
> - [2] Apache Hive - explode / posexplode
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF


## 1. SPLIT + LATERAL VIEW EXPLODE (标准方法)

这是 Hive 最经典的字符串拆分写法

```sql
SELECT t.id, t.name, tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag;

```

 执行流程:
### 1. SPLIT(tags, ',') → 将 'a,b,c' 转为 ARRAY['a','b','c']

### 2. EXPLODE(array) → 将数组展开为多行: 'a', 'b', 'c'

### 3. LATERAL VIEW → 将展开的行与原表关联


## 2. POSEXPLODE: 带位置信息 (0.13+)

```sql
SELECT t.id, t.name, pos, tag
FROM tags_csv t
LATERAL VIEW POSEXPLODE(SPLIT(t.tags, ',')) exploded AS pos, tag;
```

 pos 从 0 开始: (0, 'a'), (1, 'b'), (2, 'c')

## 3. LATERAL VIEW OUTER: 保留空值行

```sql
SELECT t.id, t.name, tag
FROM tags_csv t
LATERAL VIEW OUTER EXPLODE(SPLIT(t.tags, ',')) exploded AS tag;
```

 如果 tags 为 NULL 或空字符串，tag 输出 NULL 而不是跳过该行

## 4. 清理拆分结果

去除前后空格

```sql
SELECT t.id, TRIM(tag) AS tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag;

```

过滤空字符串

```sql
SELECT t.id, tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag
WHERE tag != '' AND tag IS NOT NULL;

```

正则分隔（支持多种分隔符）

```sql
SELECT t.id, tag FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, '[,;|]')) exploded AS tag;

```

## 5. 反向操作: 多行聚合为字符串

```sql
SELECT id, CONCAT_WS(',', COLLECT_LIST(tag)) AS tags
FROM tags_exploded
GROUP BY id;

```

## 6. 设计分析: LATERAL VIEW EXPLODE 的语义

 LATERAL VIEW EXPLODE 是 Hive 对 SQL 标准 UNNEST 的实现。
 两者等价:
 Hive:     FROM t LATERAL VIEW EXPLODE(t.arr) v AS elem
 SQL标准:  FROM t, UNNEST(t.arr) AS v(elem)
 PG:       FROM t, UNNEST(t.arr) AS elem
 BigQuery: FROM t, UNNEST(t.arr) AS elem

 Hive 的写法更冗长但语义更显式:
 LATERAL VIEW 明确表达了"生成虚拟表并与原表关联"

## 7. 跨引擎对比: 字符串拆分

 引擎          拆分函数                      展开方式
 MySQL(8.0+)   无 SPLIT (用 JSON_TABLE)      JSON_TABLE
 PostgreSQL    STRING_TO_ARRAY + UNNEST       UNNEST
 Hive          SPLIT + LATERAL VIEW EXPLODE   LATERAL VIEW
 Spark SQL     SPLIT + LATERAL VIEW EXPLODE   继承 Hive
 BigQuery      SPLIT + UNNEST                 UNNEST
 Trino         SPLIT + UNNEST                 UNNEST

## 8. 对引擎开发者的启示

### 1. SPLIT → ARRAY → EXPLODE 是直观的数据处理管道:

    字符串 → 数组 → 行，每一步的语义清晰
### 2. LATERAL VIEW OUTER 很重要: 保留无数据的行避免意外丢失

### 3. POSEXPLODE 的位置信息在 ETL 中有用: 保留原始顺序或用于去重

