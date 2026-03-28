# Oracle: 数组/映射/结构体

> 参考资料:
> - [Oracle PL/SQL Language Reference - Collections and Records](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-collections-and-records.html)
> - [Oracle Database Object-Relational Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/23/adobj/)

## VARRAY: 固定大小数组

```sql
CREATE TYPE tag_array AS VARRAY(20) OF VARCHAR2(50);
/
CREATE TYPE score_array AS VARRAY(100) OF NUMBER;
/

CREATE TABLE users (
    id     NUMBER PRIMARY KEY,
    name   VARCHAR2(100) NOT NULL,
    tags   tag_array,
    scores score_array
);

INSERT INTO users VALUES (1, 'Alice', tag_array('admin', 'dev'), score_array(90, 85, 95));
```

## Nested Table: 可变大小集合

```sql
CREATE TYPE string_table AS TABLE OF VARCHAR2(100);
/

CREATE TABLE products (
    id       NUMBER PRIMARY KEY,
    name     VARCHAR2(100),
    keywords string_table
) NESTED TABLE keywords STORE AS keywords_nt;

INSERT INTO products VALUES (1, 'Laptop', string_table('computer', 'electronics'));
```

## 集合操作（Oracle 的独有能力）

TABLE(): 展开集合为行（等价于 UNNEST）
```sql
SELECT u.name, t.COLUMN_VALUE AS tag
FROM users u, TABLE(u.tags) t;
```

CARDINALITY: 集合大小
```sql
SELECT CARDINALITY(tags) FROM users;
```

MEMBER OF: 元素检查
```sql
SELECT * FROM users WHERE 'admin' MEMBER OF tags;
```

MULTISET 操作（仅 Nested Table）
```sql
SELECT string_table('a','b') MULTISET UNION string_table('b','c') FROM DUAL;
SELECT string_table('a','b','c') MULTISET INTERSECT string_table('b','c','d') FROM DUAL;
SELECT string_table('a','b','c') MULTISET EXCEPT string_table('b') FROM DUAL;
```

SET: 去重
```sql
SELECT SET(string_table('a','b','a','c')) FROM DUAL;
```

设计分析:
  Oracle 的集合类型系统是关系数据库中最完善的:
  VARRAY（固定大小）、Nested Table（可变大小）、MULTISET 操作。
  但这些类型需要预先定义 TYPE，使用较繁琐。

横向对比:
  Oracle:     VARRAY / Nested Table + TYPE 定义（最完整但最繁琐）
  PostgreSQL: ARRAY[] 类型（内置，无需 TYPE 定义，最易用）
  MySQL:      无数组类型（用 JSON 替代）
  BigQuery:   ARRAY<T>（内置，类似 PostgreSQL）
  ClickHouse: Array(T)（内置）

对引擎开发者的启示:
  内置 ARRAY 类型（如 PostgreSQL）比需要 TYPE 定义的方案（Oracle）用户体验好得多。
  UNNEST/TABLE() 是数组与关系模型的桥梁，必须支持。

## Object Type: 类似 STRUCT

```sql
CREATE TYPE address_type AS OBJECT (
    street VARCHAR2(200),
    city   VARCHAR2(100),
    state  VARCHAR2(50),
    zip    VARCHAR2(10)
);
/

CREATE TYPE contact_type AS OBJECT (
    email VARCHAR2(200),
    phone VARCHAR2(20)
);
/

CREATE TABLE customers (
    id        NUMBER PRIMARY KEY,
    name      VARCHAR2(100),
    home_addr address_type,
    contact   contact_type
);

INSERT INTO customers VALUES (
    1, 'Alice',
    address_type('123 Main St', 'Springfield', 'IL', '62701'),
    contact_type('alice@example.com', '555-0100')
);
```

访问对象字段
```sql
SELECT c.home_addr.city, c.contact.email FROM customers c;
```

更新对象字段
```sql
UPDATE customers c SET c.home_addr.city = 'Chicago' WHERE c.id = 1;
```

## 嵌套类型（对象数组）

```sql
CREATE TYPE address_array AS VARRAY(10) OF address_type;
/

CREATE TABLE orders (
    id        NUMBER PRIMARY KEY,
    addresses address_array
);
```

展开
```sql
SELECT o.id, a.* FROM orders o, TABLE(o.addresses) a;
```

## COLLECT: 聚合为集合（等价于 ARRAY_AGG，10g+）

```sql
SELECT department, COLLECT(name) AS members
FROM employees GROUP BY department;
```

CAST + MULTISET
```sql
SELECT CAST(MULTISET(
    SELECT name FROM employees WHERE department = 'IT'
) AS string_table) FROM DUAL;
```

横向对比:
  Oracle:     COLLECT（需要预定义集合类型）
  PostgreSQL: ARRAY_AGG（返回内置 ARRAY，无需定义类型，最易用）
  MySQL:      JSON_ARRAYAGG（返回 JSON 数组）
  BigQuery:   ARRAY_AGG

## PL/SQL 关联数组: 最接近 MAP 的实现

Oracle SQL 层面没有 MAP 类型!
PL/SQL 中可以使用关联数组（但不能作为表列）
```sql
DECLARE
    TYPE string_map IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(50);
    settings string_map;
BEGIN
    settings('theme') := 'dark';
    settings('lang')  := 'en';
    DBMS_OUTPUT.PUT_LINE(settings('theme'));
END;
/
```

MAP 的替代方案:
1. Object Type（编译时已知键）
2. JSON 对象（运行时动态键，21c+ 推荐）
3. 键值对表（传统关系方式）

## JSON 类型作为现代替代（21c+）

```sql
CREATE TABLE events (
    id   NUMBER PRIMARY KEY,
    data JSON
);

INSERT INTO events VALUES (1, '{"type": "click", "tags": ["mobile", "ios"]}');
```

JSON_TABLE 展开
```sql
SELECT jt.* FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    event_type VARCHAR2(50) PATH '$.type',
    NESTED PATH '$.tags[*]' COLUMNS (tag VARCHAR2(50) PATH '$')
)) jt;
```

## '' = NULL 对集合类型的影响

集合中的空字符串元素:
```sql
INSERT INTO users VALUES (2, 'Bob', tag_array('', 'dev'), score_array());
```

tags 中的 '' 被存储为 NULL
MEMBER OF 检查: '' MEMBER OF tags 等于 NULL MEMBER OF tags → NULL

## 对引擎开发者的总结

1. Oracle 的集合类型体系（VARRAY/Nested Table/Object Type）是最完整的，
   但需要预定义 TYPE，用户体验不如 PostgreSQL 的内置 ARRAY。
2. MULTISET 集合操作（UNION/INTERSECT/EXCEPT）是 Oracle 独有的高级特性。
3. SQL 层面无 MAP 类型是一个缺口，JSON 是现代的替代方案。
4. COLLECT/ARRAY_AGG 是将关系数据转为集合的关键函数。
5. TABLE()/UNNEST 是将集合展开为行的关键函数，是数组与关系模型的桥梁。
6. '' = NULL 影响集合中的空字符串元素和 MEMBER OF 检查。
