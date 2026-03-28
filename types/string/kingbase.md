# KingbaseES (人大金仓): 字符串类型

PostgreSQL compatible with Oracle-compatible extensions.

> 参考资料:
> - [KingbaseES SQL Reference - Data Types](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Oracle Compatibility Guide](https://help.kingbase.com.cn/v8/development/sql-plsql/oracle-compat.html)
> - [PostgreSQL Documentation - String Types](https://www.postgresql.org/docs/current/datatype-character.html)
> - ============================================================
> - 1. 字符串类型一览
> - ============================================================

```sql
CREATE TABLE string_examples (
    country_code  CHAR(2)           NOT NULL,    -- 'US', 'CN', 'JP'
    username      VARCHAR(64)       NOT NULL,
    email         VARCHAR(255)      NOT NULL,
    bio           TEXT,
    name2         VARCHAR2(128),                  -- Oracle 兼容
    cname         NVARCHAR2(128)                  -- Oracle 兼容国际字符
);
```

## 核心类型详解


2.1 CHAR(n) / CHARACTER(n)
定长字符串，n 为字符数（非字节数）
比较时按 PAD SPACE 语义: 'abc   ' = 'abc'
与 PostgreSQL 行为完全一致
2.2 VARCHAR(n) / CHARACTER VARYING(n)
变长字符串，n 为字符数
不自动填充空格
继承 PostgreSQL 的 TOAST 机制: 数据超过阈值自动压缩/溢出
2.3 TEXT
无显式长度限制的变长文本（实际受 TOAST 机制限制，最大约 1GB）
KingbaseES 继承 PostgreSQL 的 TEXT = 无限制 VARCHAR 的设计
推荐日常使用 TEXT，仅在需要显式长度约束时使用 VARCHAR(n)
2.4 VARCHAR2(n) — Oracle 兼容模式
KingbaseES 在 Oracle 兼容模式下支持 VARCHAR2 类型
功能与 VARCHAR 基本相同
Oracle 迁移场景下自动映射 Oracle 的 VARCHAR2 到 KingbaseES
需要在初始化数据库时选择 Oracle 兼容模式:
initdb -U system -D data_dir --enable-ci --case-insensitive=yes
2.5 NCHAR(n) / NVARCHAR2(n) — Oracle 兼容
NCHAR: 国际字符定长，使用国家字符集编码
NVARCHAR2: 国际字符变长，Oracle 兼容
适合存储多语言混合数据（中文、日文、韩文等）
2.6 CLOB — Oracle 兼容
大文本对象，Oracle 兼容模式支持
内部映射到 TEXT（复用 PostgreSQL TOAST 机制）
支持 Oracle 风格的 DBMS_LOB 包操作

## 二进制字符串类型


BYTEA: 变长二进制数据，PostgreSQL 原生类型
hex 格式输出: '\x48656C6C6F'
escape 格式: '\110\145\154\154\157'
最大约 1GB（受 TOAST 限制）
BLOB: 二进制大对象，Oracle 兼容模式支持
内部映射到 BYTEA
RAW(n): Oracle 兼容的定长二进制类型
n 为字节数，最大 32767

```sql
CREATE TABLE binary_examples (
    raw_data   BYTEA,                          -- 变长二进制
    file_data  BLOB                            -- Oracle 兼容大对象
);
```

## 字符集与编码


KingbaseES 在数据库级别设置字符集，不支持列级别字符集
创建数据库时指定:
CREATE DATABASE mydb ENCODING 'UTF8' LC_COLLATE='zh_CN.UTF-8' LC_CTYPE='zh_CN.UTF-8';
支持的编码:
UTF-8:     1-4 字节/字符（推荐，全 Unicode 支持）
GBK:       1-2 字节/字符（中文常用，与 GB2312 兼容）
GB18030:   1-4 字节/字符（中国国家标准）
EUC-JP:    日文编码
SQL_ASCII: 无编码转换（字节原样存储，不推荐）
KingbaseES 相比 PostgreSQL 的扩展:
1. 更完善的中文编码支持（GBK、GB18030）
2. 中文全文搜索优化（zhparser 插件）
3. 中文排序规则增强（zh_CN 相关 COLLATION）

## 排序规则（COLLATION）


继承 PostgreSQL 的 COLLATION 体系
支持 ICU collation 和操作系统 locale
中文排序示例

```sql
CREATE TABLE collation_demo (
    val_pinyin  VARCHAR(64) COLLATE "zh_CN.utf8",   -- 按拼音排序
    val_binary  VARCHAR(64) COLLATE "C"              -- 二进制排序（最快）
);
```

## 表达式级排序

```sql
SELECT * FROM collation_demo ORDER BY val_pinyin COLLATE "zh_CN.utf8";
```

中文排序的常见选择:
zh_CN.utf8:  按中文拼音排序
zh_TW.utf8:  按繁体中文笔画排序
"C":         二进制字节比较（最快，但不适合语言排序）

## KingbaseES 特有的字符串功能


6.1 中文全文搜索
使用 zhparser 扩展实现中文分词
CREATE EXTENSION zhparser;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese ADD MAPPING FOR ...;
6.2 Oracle 兼容的字符串函数
KingbaseES 额外支持 Oracle 风格的字符串函数:
SUBSTR(str, start, len)      -- Oracle 风格（PostgreSQL 用 SUBSTRING）
INSTR(str, substr)           -- Oracle 风格查找
LPAD / RPAD                  -- 填充
TRIM / LTRIM / RTRIM         -- 裁剪
INITCAP                      -- 首字母大写
REPLACE                      -- 替换
TRANSLATE                    -- 字符映射
6.3 长度函数的区别

```sql
SELECT LENGTH('你好世界');              -- 4（字符数，PostgreSQL 行为）
SELECT LENGTHB('你好世界');             -- 12（UTF-8 字节数: 4×3=12，Oracle 兼容）
SELECT OCTET_LENGTH('你好世界');        -- 12（字节数，PostgreSQL 标准）
```

## 与 PostgreSQL / Oracle 的横向对比


类型对比:
类型          PostgreSQL    KingbaseES     Oracle
CHAR(n)       支持          支持           支持
VARCHAR(n)    支持          支持           支持
TEXT          支持          支持           无（用 CLOB）
VARCHAR2(n)   无            支持（兼容）    支持
NVARCHAR2(n)  无            支持（兼容）    支持
CLOB          无（用 TEXT）  支持（兼容）    支持
NCHAR(n)      无            支持（兼容）    支持
BLOB          无（用 BYTEA） 支持（兼容）    支持
KingbaseES 的定位:
1. 以 PostgreSQL 内核为基础，同时提供 Oracle 兼容模式
2. 字符串类型在两种模式下均可用
3. Oracle 迁移场景使用 VARCHAR2/CLOB/NVARCHAR2
4. 新项目推荐使用 PostgreSQL 原生的 VARCHAR/TEXT

## 注意事项与最佳实践


## 字符串类型与 PostgreSQL 完全兼容，可无缝迁移

## Oracle 兼容模式下支持 VARCHAR2、CLOB、NVARCHAR2 等类型

## TEXT 类型无长度限制，日常使用推荐 TEXT

## 字符集在 CREATE DATABASE 时确定，之后不可更改

## 支持多种字符集（UTF-8、GBK、GB18030 等），推荐 UTF-8

## 中文全文搜索需安装 zhparser 扩展

## 不支持 MySQL 的 ENUM 和 SET 类型，使用 CHECK 约束替代

## LENGTHB 函数是 Oracle 兼容扩展，返回字节数（区别于 LENGTH 返回字符数）
