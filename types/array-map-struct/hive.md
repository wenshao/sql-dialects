# Hive: 复合类型 (ARRAY, MAP, STRUCT)

> 参考资料:
> - [1] Apache Hive - Complex Types
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types#LanguageManualTypes-ComplexTypes
> - [2] Apache Hive - LATERAL VIEW
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView


## 1. ARRAY 类型

```sql
CREATE TABLE users (
    id BIGINT, name STRING,
    tags ARRAY<STRING>, scores ARRAY<INT>
) STORED AS ORC;

INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin', 'dev'), ARRAY(90, 85, 95)),
    (2, 'Bob',   ARRAY('user'),         ARRAY(70, 80));

```

数组索引（从 0 开始，与 Java 一致）

```sql
SELECT tags[0], scores[2] FROM users;

```

数组函数

```sql
SELECT SIZE(tags) FROM users;                              -- 长度
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;           -- 包含检查
SELECT SORT_ARRAY(scores) FROM users;                      -- 排序
SELECT ARRAY_DISTINCT(ARRAY(1, 2, 2, 3));                  -- 去重 (2.2+)
SELECT ARRAY_UNION(ARRAY(1, 2), ARRAY(2, 3));              -- 合并 (2.2+)
SELECT ARRAY_INTERSECT(ARRAY(1, 2, 3), ARRAY(2, 3, 4));   -- 交集 (2.2+)
SELECT ARRAY_EXCEPT(ARRAY(1, 2, 3), ARRAY(2));             -- 差集 (2.2+)

```

EXPLODE: 展开数组为多行

```sql
SELECT u.name, tag FROM users u LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

POSEXPLODE: 带位置信息 (0.13+)

```sql
SELECT u.name, pos, tag FROM users u LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

```

OUTER: 保留空数组的行

```sql
SELECT u.name, tag FROM users u LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

```

COLLECT_LIST / COLLECT_SET: 行聚合为数组

```sql
SELECT department, COLLECT_LIST(name) AS members FROM employees GROUP BY department;
SELECT department, COLLECT_SET(name) AS unique_members FROM employees GROUP BY department;

```

 设计分析: ARRAY 是 Hive 的一等类型
 大多数 RDBMS（MySQL/SQL Server）没有原生 ARRAY 类型。
 PostgreSQL 有 ARRAY，BigQuery 有 ARRAY，都是分析友好的引擎。
 Hive 的 ARRAY 与 LATERAL VIEW EXPLODE 配合是处理嵌套数据的标准模式。

## 2. MAP 类型

```sql
CREATE TABLE products (
    id BIGINT, name STRING,
    attributes MAP<STRING, STRING>, metrics MAP<STRING, DOUBLE>
) STORED AS ORC;

INSERT INTO products VALUES (1, 'Laptop',
    MAP('brand', 'Dell', 'ram', '16GB'), MAP('price', 999.99, 'weight', 2.1));

```

Map 访问

```sql
SELECT attributes['brand'] FROM products;

```

Map 函数

```sql
SELECT MAP_KEYS(attributes) FROM products;      -- 所有键 → ARRAY
SELECT MAP_VALUES(attributes) FROM products;    -- 所有值 → ARRAY
SELECT SIZE(attributes) FROM products;          -- 键值对数量

```

Map 展开

```sql
SELECT p.name, k, v FROM products p
LATERAL VIEW EXPLODE(p.attributes) t AS k, v;

```

Map 构造

```sql
SELECT MAP('k1', 'v1', 'k2', 'v2');
SELECT STR_TO_MAP('a:1,b:2,c:3', ',', ':');    -- 字符串转 Map

```

## 3. STRUCT 类型

```sql
CREATE TABLE orders (
    id BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<city: STRING, state: STRING, zip: STRING>
) STORED AS ORC;

INSERT INTO orders VALUES (1,
    NAMED_STRUCT('name', 'Alice', 'email', 'alice@example.com'),
    NAMED_STRUCT('city', 'Springfield', 'state', 'IL', 'zip', '62701'));

```

访问 STRUCT 字段（点号语法）

```sql
SELECT customer.name, customer.email, address.city FROM orders;

```

STRUCT 构造

```sql
SELECT STRUCT('Alice', 30);                          -- 匿名
SELECT NAMED_STRUCT('name', 'Alice', 'age', 30);    -- 命名

```

## 4. 嵌套类型

ARRAY of STRUCT (最常见的嵌套模式)

```sql
CREATE TABLE events (
    id BIGINT,
    items ARRAY<STRUCT<product_id: BIGINT, name: STRING, qty: INT, price: DOUBLE>>
) STORED AS ORC;

SELECT e.id, item.name, item.price FROM events e
LATERAL VIEW EXPLODE(e.items) t AS item;

```

STRUCT 嵌套 STRUCT

```sql
CREATE TABLE profiles (
    id BIGINT,
    info STRUCT<personal: STRUCT<name: STRING, age: INT>,
                contact: STRUCT<email: STRING, phone: STRING>>
) STORED AS ORC;
SELECT info.personal.name, info.contact.email FROM profiles;

```

## 5. 跨引擎对比: 复合类型

 引擎          ARRAY    MAP       STRUCT    嵌套       展开
 MySQL         不支持   不支持    不支持    N/A        JSON_TABLE
 PostgreSQL    支持     不支持    不支持    支持       UNNEST
 Hive          支持     支持      支持      支持       LATERAL VIEW
 Spark SQL     支持     支持      支持      支持       继承 Hive
 BigQuery      支持     不支持    STRUCT    支持       UNNEST
 ClickHouse    支持     支持      Tuple     支持       arrayJoin
 Trino         支持     支持      ROW       支持       UNNEST

## 6. 已知限制

1. 复合类型不能作为分区列

2. COLLECT_LIST 大数据量可能 OOM（单个分组内存溢出）

3. ARRAY 索引从 0 开始（与字符串位置从 1 开始不一致）

4. MAP 的键不保证有序

5. TextFile 的复合类型序列化依赖分隔符配置（易出错）

6. ORC/Parquet 对复合类型支持最好


## 7. 对引擎开发者的启示

1. 复合类型是处理半结构化数据的关键:

    Hive 的 ARRAY/MAP/STRUCT 让 SQL 可以直接操作嵌套数据
2. LATERAL VIEW EXPLODE 是展开嵌套数据的标准模式:

    SQL 标准的 UNNEST 更简洁，但 Hive 的语法更显式
3. COLLECT_LIST/COLLECT_SET 是行→数组的逆操作:

    与 EXPLODE 配合形成了完整的嵌套数据处理闭环
4. NAMED_STRUCT 比匿名 STRUCT 更安全: 按名称而非位置匹配字段

