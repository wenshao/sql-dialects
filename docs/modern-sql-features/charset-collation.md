# 字符集与排序规则

字符集决定能存什么字符，排序规则决定字符怎么比较和排序。这两个看似基础的概念，在实践中导致了无数的数据丢失、乱码和性能问题。

## 核心概念

```
字符集 (Character Set / Encoding):
  - 字符到字节的映射规则
  - 决定能存储哪些字符
  - 例: UTF-8, Latin1, GB18030

排序规则 (Collation):
  - 字符的比较和排序规则
  - 决定 'a' 和 'A' 是否相等
  - 决定 'cafe' 和 'cafe' 的排序顺序
  - 例: utf8mb4_general_ci, en_US.UTF-8

关系: 一个字符集可以有多种排序规则
      一种排序规则只属于一个字符集
```

## MySQL utf8 vs utf8mb4: 最经典的教训

### 问题根源

```sql
-- MySQL 的 "utf8" 不是真正的 UTF-8!
-- MySQL utf8: 最多 3 字节/字符 (只覆盖 BMP: U+0000 ~ U+FFFF)
-- MySQL utf8mb4: 最多 4 字节/字符 (完整 UTF-8)

-- 被截断的字符:
-- Emoji: 😀 (U+1F600) = 4 字节 -> utf8 存不了!
-- 部分 CJK: 𠮷 (U+20BB7) = 4 字节 -> utf8 存不了!
-- 音乐符号: 𝄞 (U+1D11E) = 4 字节 -> utf8 存不了!

-- 实际后果:
CREATE TABLE messages (content VARCHAR(255)) CHARSET=utf8;
INSERT INTO messages VALUES ('Hello 😀');
-- MySQL 5.x: 静默截断为 'Hello '，数据丢失!
-- MySQL 5.x STRICT: 报错
-- MySQL 8.0: 默认字符集改为 utf8mb4，此问题不再出现
```

### 为什么 MySQL 犯了这个错误

```
历史原因:
1. MySQL 4.1 (2004年) 引入 utf8 支持时，Unicode 标准中
   绝大多数常用字符都在 BMP 范围内 (3字节够用)
2. 3字节设计使得 CHAR(n) 列可以预分配 3*n 字节 (而非 4*n)
3. InnoDB 索引键最大 767 字节，3字节的 utf8 可以索引 255 字符
   4字节的 utf8mb4 只能索引 191 字符

教训:
  - 不要为了短期优化牺牲正确性
  - 不要给标准编码起非标准的名字
  - MySQL 用了近 20 年才将默认编码改为 utf8mb4 (8.0, 2018年)
```

### 迁移方案

```sql
-- 方案 1: ALTER TABLE (会锁表，大表慎用)
ALTER TABLE messages CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 方案 2: pt-online-schema-change (在线迁移)
-- pt-online-schema-change --alter "CONVERT TO CHARACTER SET utf8mb4" D=db,t=messages

-- 方案 3: 逐列修改 (更可控)
ALTER TABLE messages MODIFY content VARCHAR(255) CHARACTER SET utf8mb4;

-- 注意索引长度限制:
-- utf8 的 VARCHAR(255) 索引: 255*3 = 765 字节 (< 767, 可以)
-- utf8mb4 的 VARCHAR(255) 索引: 255*4 = 1020 字节 (> 767, 需要前缀索引)
-- MySQL 5.7+ innodb_large_prefix=ON (默认) 可以支持 3072 字节索引键

-- 检查当前字符集:
SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_SET_NAME, COLLATION_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'mydb' AND CHARACTER_SET_NAME = 'utf8';
```

## PostgreSQL ICU 排序规则

### 传统 libc 排序规则的问题

```sql
-- PostgreSQL 传统上使用操作系统的 libc 提供排序规则
-- 问题: 不同操作系统、不同版本的 libc 排序结果不同!

-- glibc 2.28 (2018) 更新了排序规则:
-- 升级前: 'a' < 'B' < 'c'
-- 升级后: 'a' < 'b' < 'c' (修正了大小写混合排序)

-- 后果: 操作系统升级后，索引顺序可能不一致
-- 需要 REINDEX 所有使用文本排序的索引!
```

### ICU 排序规则 (PostgreSQL 12+)

```sql
-- ICU (International Components for Unicode) 提供跨平台一致的排序
-- PostgreSQL 12 开始支持 ICU 排序规则

-- 创建使用 ICU 的数据库
CREATE DATABASE mydb
    LOCALE_PROVIDER = icu
    ICU_LOCALE = 'und-u-ks-level2'  -- Unicode 默认, 大小写不敏感
    TEMPLATE = template0;

-- 创建 ICU 排序规则
CREATE COLLATION chinese_ci (
    provider = icu,
    locale = 'zh-u-ks-level1',     -- 中文拼音排序, 不区分大小写
    deterministic = false           -- 允许 'a' = 'A'
);

-- 使用 ICU 排序规则
SELECT * FROM users ORDER BY name COLLATE "zh-Hans-CN-u-co-pinyin";

-- ICU 特性: 自然数字排序
CREATE COLLATION natural_sort (
    provider = icu,
    locale = 'en-u-kn-true'  -- kn=true: 数字按数值排序
);
-- 'item2' < 'item10' (而非字典序的 'item10' < 'item2')

-- PostgreSQL 15+: 数据库级别的 ICU 排序规则
-- PostgreSQL 16+: 内置 C.UTF-8 排序规则 (无需操作系统支持)
```

## SQL Server 字符集与排序规则

### VARCHAR vs NVARCHAR

```sql
-- SQL Server 有两套字符串类型:
-- VARCHAR: 非 Unicode, 使用代码页 (Code Page)
-- NVARCHAR: Unicode, 使用 UCS-2/UTF-16

-- VARCHAR 的陷阱:
CREATE TABLE t (name VARCHAR(100));  -- 默认使用数据库的代码页
INSERT INTO t VALUES ('中文');       -- 如果代码页不支持中文: 乱码!
INSERT INTO t VALUES (N'中文');      -- N 前缀无用，列不是 NVARCHAR

-- 正确做法:
CREATE TABLE t (name NVARCHAR(100));  -- Unicode, 安全
INSERT INTO t VALUES (N'中文');        -- 正确

-- 存储开销:
-- VARCHAR: 每字符 1 字节 (Latin), 2 字节 (中文/日文, 取决于代码页)
-- NVARCHAR: 每字符 2 字节 (BMP), 4 字节 (supplementary)
-- 实践: 始终使用 NVARCHAR，除非确定只存 ASCII
```

### UTF-8 排序规则 (SQL Server 2019+)

```sql
-- SQL Server 2019 引入 UTF-8 排序规则
-- 让 VARCHAR 也能存 Unicode!

-- 使用 UTF-8 排序规则
CREATE TABLE t (
    name VARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8
);
INSERT INTO t VALUES ('中文');  -- 合法! VARCHAR + UTF-8
INSERT INTO t VALUES ('😀');   -- 合法!

-- 好处: VARCHAR + UTF-8 比 NVARCHAR 节省空间 (对于以 ASCII 为主的数据)
-- ASCII 字符: 1 字节 (VARCHAR UTF-8) vs 2 字节 (NVARCHAR)
-- 中文字符: 3 字节 (VARCHAR UTF-8) vs 2 字节 (NVARCHAR)

-- 排序规则命名规则:
-- Latin1_General : 语言/区域
-- 100            : 版本
-- CI             : Case Insensitive (大小写不敏感)
-- AS             : Accent Sensitive (重音敏感)
-- SC             : Supplementary Characters (支持补充字符)
-- UTF8           : 使用 UTF-8 编码
```

## Oracle 字符集

### AL32UTF8 与 NLS 设置

```sql
-- Oracle 推荐的字符集: AL32UTF8 (= UTF-8)
-- 创建数据库时指定:
CREATE DATABASE mydb CHARACTER SET AL32UTF8;

-- Oracle 的双字符集设计:
-- 数据库字符集: VARCHAR2, CHAR, CLOB 使用
-- 国家字符集: NVARCHAR2, NCHAR, NCLOB 使用 (通常 AL16UTF16)

-- NLS_SORT: 控制排序规则
ALTER SESSION SET NLS_SORT = 'BINARY';            -- 二进制排序 (最快)
ALTER SESSION SET NLS_SORT = 'BINARY_CI';          -- 二进制排序, 大小写不敏感
ALTER SESSION SET NLS_SORT = 'SCHINESE_PINYIN_M';  -- 中文拼音排序

-- NLS_COMP: 控制比较规则
ALTER SESSION SET NLS_COMP = 'LINGUISTIC';  -- 使用 NLS_SORT 指定的规则
ALTER SESSION SET NLS_COMP = 'BINARY';      -- 二进制比较 (默认)

-- 两者必须配合使用:
ALTER SESSION SET NLS_SORT = 'BINARY_CI';
ALTER SESSION SET NLS_COMP = 'LINGUISTIC';
-- 之后 WHERE name = 'john' 可以匹配 'John', 'JOHN'

-- 陷阱: NLS 设置是 session 级别，不同 session 可能行为不同!
-- 建议: 在应用连接池初始化时统一设置
```

## 大小写敏感性

### 各引擎默认行为

```sql
-- 大小写敏感 (Case Sensitive, CS):
-- PostgreSQL: 默认 CS
SELECT 'abc' = 'ABC';  -- FALSE

-- Oracle: 默认 CS (BINARY 比较)
SELECT CASE WHEN 'abc' = 'ABC' THEN 1 ELSE 0 END FROM dual;  -- 0

-- 大小写不敏感 (Case Insensitive, CI):
-- MySQL: 默认 CI (utf8mb4_0900_ai_ci)
SELECT 'abc' = 'ABC';  -- 1 (TRUE)

-- SQL Server: 默认 CI (取决于安装时选择的排序规则)
SELECT CASE WHEN 'abc' = 'ABC' THEN 1 ELSE 0 END;  -- 通常 1
```

### 大小写不敏感的实现方式

```sql
-- 方案 1: CI 排序规则 (最优)
-- MySQL: 列定义时指定
ALTER TABLE users MODIFY name VARCHAR(100) COLLATE utf8mb4_unicode_ci;
-- 查询和索引都自动 CI

-- PostgreSQL: 使用 citext 扩展
CREATE EXTENSION citext;
CREATE TABLE users (name CITEXT);
SELECT * FROM users WHERE name = 'John';  -- 匹配 'john', 'JOHN' 等

-- 方案 2: 函数索引 (PostgreSQL)
CREATE INDEX idx_name_lower ON users (LOWER(name));
SELECT * FROM users WHERE LOWER(name) = LOWER('John');
-- 索引可用，但查询需要一致使用 LOWER()

-- 方案 3: 运行时转换 (性能最差)
SELECT * FROM users WHERE UPPER(name) = UPPER('John');
-- 如果没有函数索引，每行都要调用 UPPER()，导致全表扫描
```

### 索引与排序规则的关系

```sql
-- 索引按照列的排序规则存储
-- 如果查询使用不同的排序规则，索引无法使用!

-- MySQL 示例:
CREATE TABLE t (name VARCHAR(100) COLLATE utf8mb4_bin);
CREATE INDEX idx_name ON t(name);

SELECT * FROM t WHERE name = 'John';  -- 使用索引 (utf8mb4_bin)
SELECT * FROM t WHERE name COLLATE utf8mb4_general_ci = 'John';
-- 不使用索引! 排序规则不匹配

-- PostgreSQL 示例:
CREATE TABLE t (name TEXT);
CREATE INDEX idx_name ON t(name);  -- 使用默认排序规则

SELECT * FROM t WHERE name = 'John';  -- 使用索引
SELECT * FROM t WHERE name COLLATE "en_US" = 'John';
-- 可能不使用索引 (取决于排序规则是否兼容)
```

## 排序规则对 SQL 操作的影响

### JOIN 的排序规则

```sql
-- 两表 JOIN 时，如果列的排序规则不同，需要决定用哪个

-- MySQL: 使用 "排序规则优先级" 规则
-- utf8mb4_general_ci 与 utf8mb4_bin JOIN:
SELECT * FROM a JOIN b ON a.name = b.name;
-- 如果排序规则不兼容: ERROR 1267 (HY000): Illegal mix of collations

-- 解决方案:
SELECT * FROM a JOIN b ON a.name COLLATE utf8mb4_unicode_ci = b.name COLLATE utf8mb4_unicode_ci;

-- PostgreSQL: 如果排序规则不同，报错
-- 解决方案: 显式指定 COLLATE
SELECT * FROM a JOIN b ON a.name COLLATE "en_US" = b.name COLLATE "en_US";
```

### GROUP BY 与 DISTINCT 的排序规则

```sql
-- GROUP BY 按排序规则分组
-- CI 排序规则下: 'abc' 和 'ABC' 归为同一组

-- MySQL (CI 排序规则):
SELECT name, COUNT(*) FROM users GROUP BY name;
-- 'John' 和 'john' 和 'JOHN' 归为一组

-- PostgreSQL (CS 默认):
SELECT name, COUNT(*) FROM users GROUP BY name;
-- 'John' 和 'john' 和 'JOHN' 是不同的组

-- DISTINCT 同理:
-- CI: SELECT DISTINCT name -> 'John', 'john' 只保留一个
-- CS: SELECT DISTINCT name -> 'John', 'john' 分别保留
```

### LIKE 与排序规则

```sql
-- LIKE 的大小写敏感性取决于排序规则

-- MySQL (CI):
SELECT * FROM t WHERE name LIKE 'j%';
-- 匹配: 'John', 'john', 'JONES' (CI 下 'j' 匹配 'J')

-- PostgreSQL (CS):
SELECT * FROM t WHERE name LIKE 'j%';
-- 只匹配: 'john' (CS 下 'j' 不匹配 'J')

-- PostgreSQL CI LIKE:
SELECT * FROM t WHERE name ILIKE 'j%';  -- ILIKE = CI 版的 LIKE
-- 匹配: 'John', 'john', 'JONES'
```

## 多语言排序的挑战

### 中文排序

```sql
-- 中文有多种排序方式: 拼音、笔画、部首、Unicode码点

-- MySQL:
-- utf8mb4_unicode_ci: 按 Unicode 码点 (不符合中文习惯)
-- utf8mb4_zh_0900_as_cs: 按拼音排序 (MySQL 8.0+)
SELECT * FROM users ORDER BY name COLLATE utf8mb4_zh_0900_as_cs;

-- PostgreSQL (ICU):
SELECT * FROM users ORDER BY name COLLATE "zh-Hans-CN-u-co-pinyin";

-- Oracle:
ALTER SESSION SET NLS_SORT = 'SCHINESE_PINYIN_M';
SELECT * FROM users ORDER BY name;

-- 问题: 多音字
-- '长' 可以读 'chang' 或 'zhang'
-- 数据库无法根据上下文判断正确读音
-- 实际应用中通常需要额外的拼音字段
```

### 重音与变音符号

```sql
-- 重音敏感 (Accent Sensitive, AS) vs 不敏感 (AI)
-- 'cafe' vs 'cafe' (带重音的 e)

-- MySQL:
-- utf8mb4_0900_ai_ci: Accent Insensitive, Case Insensitive
-- utf8mb4_0900_as_cs: Accent Sensitive, Case Sensitive

-- 德语排序:
-- 'a' < 'ae' (标准排序)
-- 但在电话簿中: 'ae' 等同于 'a' (Umlaut 折叠)

-- SQL Server 的命名约定清晰地表达了这些选项:
-- Latin1_General_CI_AS: Case Insensitive, Accent Sensitive
-- Latin1_General_CI_AI: Case Insensitive, Accent Insensitive
-- Latin1_General_CS_AS: Case Sensitive, Accent Sensitive
```

## 对引擎开发者的建议

### 推荐架构

```
1. 内部编码: 统一使用 UTF-8
   - 所有字符串在引擎内部以 UTF-8 存储和处理
   - 输入/输出时转换客户端编码
   - 避免 MySQL 的 utf8/utf8mb4 双轨制

2. 排序规则库: 集成 ICU
   - 不依赖操作系统的 libc
   - 跨平台一致的排序结果
   - 丰富的语言和区域支持
   - 代价: 增加约 25MB 的库依赖

3. 排序规则层级:
   数据库 -> Schema -> 表 -> 列 -> 表达式
   每一级可以覆盖上一级的设置
   列级排序规则存储在元数据中

4. COLLATE 子句:
   支持在表达式级别临时改变排序规则
   SELECT * FROM t WHERE name COLLATE xxx = 'value'
   ORDER BY name COLLATE yyy
```

### 关键实现决策

```
1. 二进制排序是否作为默认?
   - 二进制排序: 最快，但不符合自然语言习惯
   - 语言排序: 符合用户预期，但性能开销大
   - 建议: 提供两种默认模板

2. 索引中的排序规则:
   - 索引必须记录使用的排序规则
   - 排序规则变更 = 索引重建
   - 排序规则版本变更检测 (ICU 版本升级)

3. 哈希的排序规则:
   - CI 排序规则下: hash('abc') 必须等于 hash('ABC')
   - 实现: hash 前先做排序规则的 weight 转换
   - 影响: Hash Join, Hash Aggregate, Hash 分区

4. 比较的性能优化:
   - 对 BINARY 排序规则使用 memcmp (最快)
   - 对 CI 排序规则可以预计算 case-folded 版本
   - 对复杂语言排序规则使用 ICU 的 sort key
```

### 排序规则命名规范建议

```
推荐格式: {charset}_{language}_{sensitivity}_{version}

示例:
  utf8_en_ci_v1     -- UTF-8, 英语, 大小写不敏感, 版本1
  utf8_zh_pinyin_v1 -- UTF-8, 中文拼音, 版本1
  utf8_binary       -- UTF-8, 二进制比较
  utf8_unicode_ci   -- UTF-8, Unicode 默认, CI

好处:
  - 从名字可以知道行为
  - 版本号允许未来更新排序规则而不破坏兼容性
  - 与 MySQL 的命名风格类似，迁移友好
```

## 参考资料

- Unicode Consortium: [Unicode Collation Algorithm (UCA)](https://unicode.org/reports/tr10/)
- ICU Project: [Collation Concepts](https://unicode-org.github.io/icu/userguide/collation/concepts.html)
- MySQL: [Character Sets and Collations](https://dev.mysql.com/doc/refman/8.0/en/charset.html)
- PostgreSQL: [Collation Support](https://www.postgresql.org/docs/current/collation.html)
- SQL Server: [Collation and Unicode Support](https://learn.microsoft.com/en-us/sql/relational-databases/collations/collation-and-unicode-support)
- Oracle: [Linguistic Sorting and Matching](https://docs.oracle.com/en/database/oracle/oracle-database/19/nlspg/linguistic-sorting-and-matching.html)
