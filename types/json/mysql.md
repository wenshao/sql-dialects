# MySQL: JSON 类型

> 参考资料:
> - [MySQL 8.0 Reference Manual - The JSON Data Type](https://dev.mysql.com/doc/refman/8.0/en/json.html)
> - [MySQL 8.0 Reference Manual - JSON Function Reference](https://dev.mysql.com/doc/refman/8.0/en/json-function-reference.html)
> - [WL#8132 - JSON datatype and binary storage format](https://dev.mysql.com/worklog/task/?id=8132)
> - [WL#8955 - Multi-Valued Indexes](https://dev.mysql.com/worklog/task/?id=8955)

## 基本语法

```sql
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    data JSON,
    meta JSON DEFAULT (JSON_OBJECT())    -- 8.0.13+ 表达式默认值
) ENGINE=InnoDB;
```

插入
```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (JSON_OBJECT('name', 'bob', 'age', 30));
```

读取: -> 返回 JSON 值(带引号)，->> 返回文本值(去引号)
```sql
SELECT data->'$.name'  FROM events;       -- '"alice"' (JSON string)
SELECT data->>'$.name' FROM events;       -- 'alice'   (SQL string, 5.7.13+)
SELECT data->'$.tags[0]' FROM events;     -- '"vip"'
```

## JSON 的内部存储格式（对引擎开发者）

### 二进制存储格式 vs 文本存储

MySQL 的 JSON 列以优化的二进制格式存储，不是存原始 JSON 文本。
二进制格式的设计目标:
  1. O(1) 键查找: 键按排序存储，使用二分查找定位
  2. 嵌套访问无需全解析: data->'$.a.b.c' 直接按偏移量定位
  3. 写入时验证: INSERT 时验证 JSON 合法性，避免存入非法 JSON

二进制格式结构（简化）:
  [type_byte] [element_count] [size] [key_offset_table] [value_offset_table] [key_data] [value_data]
小值内联: 整数、布尔等小值直接存在 value_offset_table 的槽位中
大值引用: 字符串、嵌套对象通过偏移量引用后续数据区

### 存储开销

二进制 JSON 通常比文本 JSON 大 10-20%（额外的元数据和对齐填充）
但查询时避免了反复解析的 CPU 开销
最大大小: 受 max_allowed_packet 限制（默认 64MB）

### 部分更新（Partial Update, 8.0+）

JSON_SET / JSON_REPLACE / JSON_REMOVE 在满足条件时只修改二进制中的局部:
  条件: 1. 更新后大小 <= 原值大小  2. 不改变 JSON 结构（不增删键）
部分更新优势: 减少 redo log 和 binlog 的写入量（只记录 diff）
如果条件不满足: 回退为全量重写（与重新 INSERT JSON 等效）

对引擎开发者的启示:
  二进制 JSON 格式的设计权衡: 写入时多花 CPU 做序列化，换取读取时 O(1) 访问
  PostgreSQL JSONB 也是二进制存储，但采用不同的内部结构（TOAST + varlen header）
  如果目标是高写入低读取（如日志场景），文本存储 + 懒解析可能更优

## JSON 索引的实现

### 虚拟生成列 + B-Tree 索引（5.7+）

JSON 列本身不能直接创建索引。变通方案:
```sql
ALTER TABLE events ADD COLUMN name_virt VARCHAR(64)
    GENERATED ALWAYS AS (data->>'$.name') VIRTUAL;
CREATE INDEX idx_name ON events (name_virt);
```

虚拟列不占存储（VIRTUAL），查询时实时从 JSON 计算
存储列（STORED）则物理存储，读取更快但写入多一次

### 函数索引（8.0.13+）

不需要显式创建虚拟列:
```sql
CREATE INDEX idx_age ON events ((CAST(data->>'$.age' AS UNSIGNED)));
```

内部: 仍然创建隐藏的虚拟列，但语法更简洁

### 多值索引（Multi-Valued Index, 8.0.17+）

索引 JSON 数组中的每个元素 -- 这是 MySQL JSON 索引的重大突破
```sql
CREATE TABLE products (
    id    BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    attrs JSON
) ENGINE=InnoDB;
CREATE INDEX idx_tags ON products ((CAST(attrs->'$.tags' AS CHAR(64) ARRAY)));
```

一行的 tags=["electronics","sale","new"] 在索引中生成 3 个条目

查询: 使用 MEMBER OF / JSON_CONTAINS / JSON_OVERLAPS 触发索引
```sql
SELECT * FROM products WHERE 'sale' MEMBER OF (attrs->'$.tags');
SELECT * FROM products WHERE JSON_CONTAINS(attrs->'$.tags', '"sale"');
SELECT * FROM products WHERE JSON_OVERLAPS(attrs->'$.tags', '["sale","new"]');
```

实现原理: InnoDB 扩展了 B-Tree 索引以支持一行多键（类似 GIN 倒排索引）
限制: 数组元素类型必须一致，不支持嵌套数组索引

## JSON_TABLE: 将 JSON 展开为关系表

```sql
SELECT jt.* FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age  INT         PATH '$.age'     DEFAULT '0' ON EMPTY,
    tag  VARCHAR(64) PATH '$.tags[0]' DEFAULT NULL ON ERROR
)) AS jt;
```

NESTED PATH: 展开嵌套数组
```sql
SELECT e.id, jt.tag FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    NESTED PATH '$.tags[*]' COLUMNS (
        tag VARCHAR(64) PATH '$'
    )
)) AS jt;
```

### 查询优化影响

JSON_TABLE 在优化器中作为 lateral derived table 处理:
  1. 每行数据都需要调用 JSON_TABLE 函数 -- 无法被优化器"推下去"
  2. 结果集大小 = 原表行数 * 数组元素数（笛卡尔展开）
  3. 无法利用索引加速 JSON_TABLE 内部的路径访问
性能建议: 大数据量下避免 JSON_TABLE，考虑预展开到关系表

## JSON 修改函数

JSON_SET:    设置（存在则更新，不存在则插入）
```sql
SELECT JSON_SET(data, '$.age', 26, '$.email', 'a@b.com') FROM events;
-- JSON_INSERT: 插入（存在则不变）
SELECT JSON_INSERT(data, '$.email', 'a@b.com') FROM events;
-- JSON_REPLACE: 替换（不存在则不变）
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
-- JSON_REMOVE: 删除键
SELECT JSON_REMOVE(data, '$.tags') FROM events;
-- JSON_MERGE_PATCH: RFC 7396 合并（后者覆盖前者）
SELECT JSON_MERGE_PATCH('{"a":1,"b":2}', '{"b":3,"c":4}');  -- {"a":1,"b":3,"c":4}
-- JSON_MERGE_PRESERVE: 合并保留（数组追加）
SELECT JSON_MERGE_PRESERVE('{"a":[1]}', '{"a":[2]}');       -- {"a":[1,2]}
```

JSON 聚合 (5.7.22+)
```sql
SELECT JSON_ARRAYAGG(data->>'$.name') FROM events;
SELECT JSON_OBJECTAGG(data->>'$.name', data->'$.age') FROM events;
```

## 横向对比: 各引擎的 JSON 实现（对引擎开发者）

### PostgreSQL: JSON vs JSONB

JSON:  存原始文本，保留格式/键序/重复键，写入快
JSONB: 二进制存储（类似 MySQL JSON），去重复键、不保留格式
       支持 GIN 索引（倒排索引）-- 比 MySQL 多值索引更通用
       支持 @>（包含）、?（键存在）等操作符
       JSONB 是 PG 社区推荐的默认选择
优势: GIN 索引无需预定义路径，索引整个 JSON 文档
MySQL 多值索引需要指定具体的 JSON 路径 -- 灵活性不如 GIN

### Snowflake: VARIANT

VARIANT 类型: 可存 JSON、Avro、Parquet 等半结构化数据
自动推断和缓存 schema（称为 "metadata caching"）
查询: v:name::STRING（类似 SQL 路径语法但用 : 分隔）
优势: 自动列式存储 JSON 的各字段 -- 分析查询性能极佳
劣势: 事务语义弱于 OLTP 数据库

### ClickHouse: Nested / Tuple / JSON (实验性)

传统方案: 预定义 Nested 类型（本质是并行数组）
```sql
  CREATE TABLE t (tags Nested(name String, value Float64))
```

新方案: JSON 类型（23.1+ 实验性）自动推断 schema 并按列存储
哲学: 分析引擎倾向于 schema-on-write（写入时确定结构），而非 schema-on-read

### Oracle: JSON 类型（21c+）

21c+ 原生 JSON 类型（之前存在 VARCHAR2/CLOB 中）
支持 JSON 二进制格式 (OSON)，类似 MySQL/JSONB
JSON Duality View (23c): 同一数据既可以关系表方式访问也可以 JSON 方式访问

对引擎开发者的启示:
  1. 二进制 JSON 是主流方向（MySQL JSON, PG JSONB, Oracle OSON）
  2. 索引策略: 通用倒排索引 (PG GIN) vs 指定路径索引 (MySQL 多值索引)
     GIN 更灵活但写入开销更大；指定路径更精准但需要预知查询模式
  3. 分析场景: Snowflake VARIANT 的自动列式存储是创新方向
  4. 长期趋势: JSON 和关系模型的融合（Oracle JSON Duality View 的方向）

## 版本演进与最佳实践

MySQL 5.7.8:  引入 JSON 类型和基本函数
MySQL 5.7.13: ->> 操作符（JSON_UNQUOTE + JSON_EXTRACT 简写）
MySQL 5.7.22: JSON_ARRAYAGG / JSON_OBJECTAGG
MySQL 8.0.4:  JSON_TABLE
MySQL 8.0.13: 函数索引（间接索引 JSON 路径）
MySQL 8.0.17: 多值索引，MEMBER OF 操作符
MySQL 8.0.21: JSON 部分更新优化

实践建议:
  1. JSON 列适合: schema 不固定的扩展属性、标签、配置项
  2. JSON 列不适合: 高频查询过滤条件（索引支持有限）、需要参与 JOIN 的字段
  3. 需要索引的 JSON 字段: 优先用虚拟生成列 + B-Tree，其次函数索引
  4. JSON 数组查询: 8.0.17+ 多值索引是首选方案
  5. 避免在 JSON 列上做复杂聚合 -- 解析开销随数据量线性增长
