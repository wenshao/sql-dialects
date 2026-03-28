# Snowflake: 复合类型 (VARIANT / ARRAY / OBJECT)

> 参考资料:
> - [1] Snowflake Documentation - Semi-structured Data Types
>   https://docs.snowflake.com/en/sql-reference/data-types-semistructured


## 1. 三种半结构化类型


VARIANT: 万能类型，可存储标量/数组/对象（最大 16MB）
ARRAY:   有序 VARIANT 元素集合
OBJECT:  键值对集合（键为字符串，值为 VARIANT）


```sql
CREATE TABLE users (
    id     NUMBER NOT NULL,
    name   VARCHAR(100) NOT NULL,
    tags   ARRAY,                              -- 动态类型数组
    scores ARRAY,
    attrs  OBJECT                              -- 键值对
);

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 VARIANT 的统一存储设计

 Snowflake 用 VARIANT 作为半结构化数据的统一容器:
   JSON 对象 → VARIANT（内部存储为 OBJECT）
   JSON 数组 → VARIANT（内部存储为 ARRAY）
   标量值    → VARIANT（内部存储为对应类型）

 对比:
   PostgreSQL: JSON + JSONB（两种独立类型，JSONB 是二进制优化版）
   MySQL:      JSON（单一类型，内部二进制存储）
   BigQuery:   STRUCT + ARRAY（强类型，必须预定义 Schema）
   Redshift:   SUPER（借鉴 Snowflake VARIANT 设计）
   Databricks: MAP/STRUCT/ARRAY（强类型）

 Snowflake VARIANT 的内部优化:
   虽然 VARIANT 是动态类型，但 Snowflake 自动推断子列类型
   (Sub-column Pruning)，为高频访问的路径创建独立物理子列。
   查询 data:name 时，引擎可能只读取 name 子列而非整个 VARIANT。

### 2.2 弱类型 vs 强类型嵌套

 Snowflake (VARIANT): Schema-on-Read，写入时不校验结构
 BigQuery (STRUCT):   Schema-on-Write，必须预定义每个字段的类型
 权衡: 灵活性 vs 类型安全性

## 3. ARRAY 操作


构造

```sql
INSERT INTO users SELECT 1, 'Alice',
    ARRAY_CONSTRUCT('admin', 'dev'), ARRAY_CONSTRUCT(90, 85, 95), NULL;

```

访问（从 0 开始）

```sql
SELECT tags[0]::VARCHAR FROM users;
SELECT GET(tags, 0) FROM users;

```

常用函数

```sql
SELECT ARRAY_SIZE(tags) FROM users;                           -- 长度
SELECT ARRAY_CONTAINS('admin'::VARIANT, tags) FROM users;     -- 包含
SELECT ARRAY_POSITION('admin'::VARIANT, tags) FROM users;     -- 位置
SELECT ARRAY_APPEND(tags, 'new') FROM users;                  -- 追加
SELECT ARRAY_PREPEND(tags, 'first') FROM users;               -- 前插
SELECT ARRAY_CAT(ARRAY_CONSTRUCT(1,2), ARRAY_CONSTRUCT(3,4)); -- 连接
SELECT ARRAY_COMPACT(ARRAY_CONSTRUCT(1, NULL, 2));            -- 移除NULL
SELECT ARRAY_DISTINCT(ARRAY_CONSTRUCT(1, 2, 2, 3));           -- 去重
SELECT ARRAY_INTERSECTION(ARRAY_CONSTRUCT(1,2,3), ARRAY_CONSTRUCT(2,3,4)); -- 交集
SELECT ARRAY_EXCEPT(ARRAY_CONSTRUCT(1,2,3), ARRAY_CONSTRUCT(2));           -- 差集
SELECT ARRAY_SLICE(ARRAY_CONSTRUCT(1,2,3,4,5), 1, 3);        -- 切片[1,3)
SELECT ARRAY_SORT(ARRAY_CONSTRUCT(3, 1, 2));                  -- 排序
SELECT ARRAY_TO_STRING(ARRAY_CONSTRUCT('a','b','c'), ', ');   -- 转字符串

```

## 4. FLATTEN: 展开数组为行


```sql
SELECT u.name, f.value::VARCHAR AS tag
FROM users u, LATERAL FLATTEN(input => u.tags) f;

```

OUTER FLATTEN（保留空数组的行）

```sql
SELECT u.name, f.value::VARCHAR AS tag
FROM users u, LATERAL FLATTEN(input => u.tags, outer => TRUE) f;

```

FLATTEN 输出列: SEQ, KEY, PATH, INDEX, VALUE, THIS

聚合回数组

```sql
SELECT department, ARRAY_AGG(name) WITHIN GROUP (ORDER BY name) AS members
FROM employees GROUP BY department;

```

## 5. OBJECT 操作


构造

```sql
SELECT OBJECT_CONSTRUCT('brand', 'Dell', 'ram', '16GB', 'cpu', 'i7');
SELECT OBJECT_CONSTRUCT_KEEP_NULL('a', 1, 'b', NULL);  -- 保留 NULL

```

访问

```sql
SELECT attrs:brand::VARCHAR FROM products;      -- 冒号语法
SELECT attrs['brand']::VARCHAR FROM products;   -- 方括号语法

```

修改

```sql
SELECT OBJECT_INSERT(attrs, 'color', 'black') FROM products;      -- 添加键
SELECT OBJECT_DELETE(attrs, 'cpu') FROM products;                   -- 删除键
SELECT OBJECT_PICK(attrs, 'brand', 'ram') FROM products;           -- 选择键

```

获取所有键

```sql
SELECT OBJECT_KEYS(attrs) FROM products;

```

FLATTEN OBJECT（展开为 KEY-VALUE 行）

```sql
SELECT p.name, f.key, f.value::VARCHAR
FROM products p, LATERAL FLATTEN(input => p.attrs) f;

```

聚合为对象

```sql
SELECT OBJECT_AGG(name, salary::VARIANT) FROM employees;

```

## 6. MAP 类型（结构化键值对，2023+）


```sql
CREATE TABLE configs (id NUMBER, settings MAP(VARCHAR, VARCHAR));

```

 MAP 是强类型的键值对（与 OBJECT 的区别: MAP 有明确的键/值类型）

## 7. 嵌套结构


ARRAY of OBJECT

```sql
SELECT p.name, f.value:product::VARCHAR AS product, f.value:price::FLOAT AS price
FROM products p, LATERAL FLATTEN(input => p.metadata) f;

```

递归展开

```sql
SELECT f.PATH, f.KEY, f.VALUE
FROM events, LATERAL FLATTEN(input => data, RECURSIVE => TRUE) f
WHERE TYPEOF(f.VALUE) NOT IN ('OBJECT', 'ARRAY');

```

## 横向对比: 复合类型能力

| 特性          | Snowflake       | BigQuery       | PostgreSQL  | MySQL |
|------|------|------|------|------|
| 数组类型      | ARRAY(VARIANT)  | ARRAY(typed)   | ARRAY       | 不支持 |
| 对象/结构体   | OBJECT/VARIANT  | STRUCT(typed)  | JSONB       | JSON |
| 类型灵活性    | Schema-on-Read  | Schema-on-Write| 动态        | 动态 |
| 路径访问      | : 冒号语法      | . 点号         | -> / ->>    | $.path |
| 展开为行      | FLATTEN         | UNNEST         | unnest      | JSON_TABLE |
| 数组函数      | 丰富(20+)       | 中等           | 中等        | 基本 |
| 聚合为数组    | ARRAY_AGG       | ARRAY_AGG      | array_agg   | 不支持 |
| 聚合为对象    | OBJECT_AGG      | 不支持         | 不支持      | 不支持 |
| 最大大小      | 16MB/值         | 无限制         | 1GB         | 1GB |

