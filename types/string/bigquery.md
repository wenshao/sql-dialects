# BigQuery: 字符串类型

> 参考资料:
> - [1] BigQuery SQL Reference - STRING Type
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#string_type
> - [2] BigQuery SQL Reference - BYTES Type
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#bytes_type


## 1. STRING: 唯一的字符串类型


BigQuery 只有 STRING 类型，没有 VARCHAR/CHAR/TEXT/CLOB 区分:

```sql
CREATE TABLE users (
    id       INT64 NOT NULL,
    username STRING NOT NULL,
    bio      STRING,            -- 无长度限制
    country  STRING             -- 也用于短字符串
);

```

 特点:
   (a) 保证 UTF-8 编码（插入无效 UTF-8 会报错）
   (b) 无长度限制（但受行大小限制: 最大 100 MB/行）
   (c) 无 VARCHAR(n) 的截断行为
   (d) 列式压缩自动优化（重复值字典编码，短值紧凑存储）

 为什么只有一种字符串类型?
 与 INT64 相同的设计理念: 简化用户体验。
 Capacitor 列式格式会自动选择最优编码。
 不需要用户决定 VARCHAR vs TEXT vs CLOB。

## 2. BYTES: 二进制数据类型


BYTES 是原始字节序列，不做 UTF-8 验证:

```sql
CREATE TABLE files (
    id   INT64,
    name STRING,
    hash BYTES     -- 二进制哈希值
);
```

 插入: INSERT INTO files VALUES (1, 'test', B'\xDE\xAD\xBE\xEF');
 或: INSERT INTO files VALUES (1, 'test', FROM_BASE64('3q2+7w=='));

 STRING vs BYTES:
   STRING: UTF-8 文本，字符级操作（LENGTH 返回字符数）
   BYTES: 原始字节，字节级操作（BYTE_LENGTH 返回字节数）

## 3. 排序规则（Collation）


BigQuery 默认区分大小写，可以通过 COLLATE 修改:

```sql
SELECT * FROM users WHERE COLLATE(username, 'und:ci') = 'alice';
```

'und:ci' = Unicode Default, Case Insensitive

建表时指定默认排序规则:

```sql
CREATE TABLE users (
    username STRING COLLATE 'und:ci'  -- 大小写不敏感
);

```

 对比:
   MySQL: 排序规则绑定到字符集（utf8mb4_unicode_ci）
   PostgreSQL: 排序规则绑定到列或数据库（ICU 12+）
   SQLite: COLLATE NOCASE（仅 ASCII）
   ClickHouse: 无内置排序规则（用 lower() 手动处理）

## 4. 字符串作为半结构化数据容器


 BigQuery 中 STRING 经常用于存储:
   JSON: STRING 列 + JSON_EXTRACT 函数（或用 JSON 类型）
   CSV: STRING 列 + SPLIT 函数
   URL: STRING 列 + NET.HOST / REGEXP_EXTRACT
   UUID: STRING 列 + GENERATE_UUID()（BigQuery 无专用 UUID 类型）

 SEARCH INDEX 可以在 STRING 列上创建全文搜索索引:
 CREATE SEARCH INDEX idx ON docs (content);
 SELECT * FROM docs WHERE SEARCH(content, 'keyword');

## 5. 对比与引擎开发者启示

BigQuery 字符串设计:
(1) 只有 STRING → 最简化
(2) 保证 UTF-8 → 比 ClickHouse（字节序列）更安全
(3) 自动压缩 → 不需要用户选择类型
(4) STRING 作为万能容器 → UUID/JSON/URL 都用 STRING

对引擎开发者的启示:
现代云数仓趋向于单一字符串类型（STRING），因为:
- 列压缩消除了 VARCHAR(n) 的存储优势
- 用户不需要为字符串长度做决策
- 简化了类型系统和迁移复杂度
但应该保证 UTF-8 编码（BigQuery）还是允许任意字节（ClickHouse），
取决于目标场景: 分析（保证 UTF-8）vs 日志处理（允许任意字节）。

