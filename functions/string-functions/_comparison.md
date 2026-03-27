# 字符串函数 (String Functions) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 拼接 | CONCAT/\|\| 8.0 | \|\| | \|\| | \|\| | + / CONCAT | CONCAT/\|\| | \|\| | \|\|/CONCAT | \|\|/CONCAT |
| 长度 | LENGTH/CHAR_LENGTH | LENGTH/CHAR_LENGTH | LENGTH | LENGTH | LEN/DATALENGTH | LENGTH | CHAR_LENGTH | LENGTH | LENGTH |
| 大小写 | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER | UPPER/LOWER |
| 截取 | SUBSTRING | SUBSTRING | SUBSTR | SUBSTR | SUBSTRING | SUBSTRING | SUBSTRING | SUBSTRING | SUBSTRING |
| 查找 | LOCATE/INSTR | POSITION | INSTR | INSTR | CHARINDEX/PATINDEX | LOCATE/INSTR | POSITION | POSSTR/LOCATE | LOCATE |
| 替换 | REPLACE | REPLACE | REPLACE | REPLACE | REPLACE | REPLACE | REPLACE | REPLACE | REPLACE |
| 去空格 | TRIM | TRIM | TRIM | TRIM | TRIM/LTRIM/RTRIM | TRIM | TRIM | TRIM | TRIM |
| 填充 | LPAD/RPAD | LPAD/RPAD | ❌ | LPAD/RPAD | ❌ | LPAD/RPAD | LPAD/RPAD | LPAD/RPAD | LPAD/RPAD |
| 反转 | REVERSE | REVERSE | ❌ | REVERSE | REVERSE | REVERSE | REVERSE | REVERSE | ❌ |
| 正则匹配 | REGEXP | ~ / SIMILAR TO | GLOB | REGEXP_LIKE | ❌ | REGEXP | SIMILAR TO | REGEXP_LIKE | ❌ |
| 正则替换 | REGEXP_REPLACE 8.0+ | REGEXP_REPLACE | ❌ | REGEXP_REPLACE | ❌ | REGEXP_REPLACE | ❌ | REGEXP_REPLACE | REPLACE_REGEXPR |
| 正则提取 | REGEXP_SUBSTR 8.0+ | REGEXP_MATCH | ❌ | REGEXP_SUBSTR | ❌ | REGEXP_SUBSTR | ❌ | REGEXP_EXTRACT | SUBSTRING_REGEXPR |
| 分隔拆分 | SUBSTRING_INDEX | STRING_TO_ARRAY | ❌ | REGEXP_SUBSTR | STRING_SPLIT | SUBSTRING_INDEX | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 拼接 | CONCAT/\|\| | \|\|/CONCAT | CONCAT | CONCAT | concat/\|\| | CONCAT | \|\|/CONCAT | \|\| | CONCAT | \|\|/CONCAT | CONCAT | \|\|/CONCAT |
| 正则匹配 | REGEXP_CONTAINS | REGEXP/RLIKE | ✅ | RLIKE/REGEXP | match | REGEXP | REGEXP_LIKE | ~ | REGEXP | REGEXP | RLIKE | REGEXP |
| 正则替换 | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE | replaceRegexpAll | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE | REGEXP_REPLACE |
| 分隔拆分 | SPLIT | SPLIT | SPLIT | SPLIT | splitByString | SPLIT | SPLIT | STRING_TO_ARRAY | SPLIT | STRING_SPLIT | SPLIT | ❌ |
| FORMAT | FORMAT | TO_CHAR | ❌ | PRINTF | format | ❌ | FORMAT | ❌ | ❌ | FORMAT/PRINTF | FORMAT_STRING | ❌ |
| REPEAT | REPEAT | REPEAT | REPEAT | REPEAT | repeat | REPEAT | ❌ | REPEAT | REPEAT | REPEAT | REPEAT | ❌ |

## 关键差异

- **字符串拼接**：MySQL/PostgreSQL/SQLite 用 \|\|，SQL Server 用 +，CONCAT() 最通用
- **正则表达式**：语法差异大，SQL Server 不支持原生正则
- **SQL Server** 字符串函数名最不标准（LEN 而非 LENGTH, CHARINDEX 而非 POSITION）
- **ClickHouse** 函数使用 camelCase 命名（splitByString, replaceRegexpAll）
- **SQLite** 字符串函数最少，不支持 LPAD/RPAD/REVERSE/正则替换
- **Oracle** SUBSTR 是 1-based 索引，其他多数引擎也是 1-based
- **BigQuery** 使用 REGEXP_CONTAINS 而非 REGEXP_LIKE
