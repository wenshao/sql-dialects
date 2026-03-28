# MariaDB: JSON 支持

与 MySQL 的最大差异: MariaDB 的 JSON 是 LONGTEXT 的别名

参考资料:
[1] MariaDB Knowledge Base - JSON Data Type
https://mariadb.com/kb/en/json-data-type/

## 1. JSON 类型的本质差异

```sql
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    data JSON                  -- 实际是 LONGTEXT + CHECK 约束
);
```

MariaDB: JSON 是 LONGTEXT 的别名, 插入时验证 JSON 合法性
MySQL: JSON 是独立的二进制存储类型 (优化的内部格式)

影响:
MariaDB: 每次读取 JSON 都需要文本解析 (无二进制索引查找)
MySQL: 二进制格式支持 O(1) 键查找
MariaDB: JSON 列可以参与字符集/排序 (因为是 TEXT)
MySQL: JSON 列使用 utf8mb4 二进制排序 (不可变)
这是 fork 后最大的存储层设计分歧之一

## 2. JSON 函数 (与 MySQL 兼容)

```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip"]}');
SELECT JSON_EXTRACT(data, '$.name') FROM events;
SELECT data->'$.name' FROM events;       -- -> 操作符
SELECT data->>'$.name' FROM events;      -- ->> 操作符 (去引号)
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_REMOVE(data, '$.tags') FROM events;
SELECT JSON_CONTAINS(data, '"vip"', '$.tags') FROM events;
SELECT JSON_ARRAY(1, 2, 3), JSON_OBJECT('a', 1, 'b', 2);
SELECT JSON_TABLE(data, '$' COLUMNS (name VARCHAR(64) PATH '$.name')) AS jt FROM events;
```


## 3. JSON 索引

虚拟生成列 + 索引 (同 MySQL 方式)
```sql
ALTER TABLE events ADD COLUMN name_idx VARCHAR(64)
    GENERATED ALWAYS AS (JSON_VALUE(data, '$.name')) VIRTUAL;
CREATE INDEX idx_name ON events (name_idx);
```


JSON_VALUE (10.2.7+): MariaDB 独有函数, 比 JSON_EXTRACT 更简洁
```sql
SELECT JSON_VALUE(data, '$.name') FROM events;
```

等价于 JSON_UNQUOTE(JSON_EXTRACT(data, '$.name'))
MySQL 8.0.21+ 也添加了 JSON_VALUE

## 4. 对引擎开发者的启示

MariaDB 选择 LONGTEXT 作为 JSON 的存储基础的原因:
1. 实现简单: 复用已有的 TEXT 存储和索引基础设施
2. 灵活性: 可以直接用字符串函数操作 JSON
3. 兼容性: 导出/导入时 JSON 就是普通文本
MySQL 选择二进制格式的原因:
1. 查询性能: O(1) 键查找, 无需解析
2. 部分更新: 二进制格式支持局部修改 (减少 I/O)
3. 验证效率: 写入时一次验证, 读取时无需再验证
权衡: 写入密集 → 文本更好; 读取密集 → 二进制更好
