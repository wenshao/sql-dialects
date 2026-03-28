# SQL 标准演进全览

ISO/IEC 9075 SQL 标准从 1986 年至今经历了 9 个主要版本。本目录按版本详细分析每个标准引入的特性、各引擎的实现差异、以及对引擎开发者的实现建议。

## 版本演进时间线

| 版本 | 年份 | 核心新增 | 详细页面 |
|------|------|---------|---------|
| SQL-86/89 | 1986/1989 | 基础 DDL/DML、约束（PK/FK/CHECK） | [sql-86-89.md](sql-86-89.md) |
| SQL-92 | 1992 | JOIN 语法、CASE WHEN、子查询、VARCHAR/DECIMAL/TIMESTAMP | [sql-92.md](sql-92.md) |
| SQL:1999 | 1999 | 递归 CTE、BOOLEAN、ARRAY、LATERAL、ROLE、触发器 | [sql-1999.md](sql-1999.md) |
| SQL:2003 | 2003 | **窗口函数**、MERGE、IDENTITY、SEQUENCE、FILTER、BIGINT | [sql-2003.md](sql-2003.md) |
| SQL:2006 | 2006 | XML 增强（XQuery 集成） | [sql-2006.md](sql-2006.md) |
| SQL:2008 | 2008 | FETCH FIRST 分页、TRUNCATE、MERGE 增强 | [sql-2008.md](sql-2008.md) |
| SQL:2011 | 2011 | **时态表**（System-Versioned）、PERIOD | [sql-2011.md](sql-2011.md) |
| SQL:2016 | 2016 | **JSON 支持**、LISTAGG、MATCH_RECOGNIZE | [sql-2016.md](sql-2016.md) |
| SQL:2023 | 2023 | ANY_VALUE、GREATEST/LEAST、**图查询 SQL/PGQ** | [sql-2023.md](sql-2023.md) |

## 各引擎标准合规度矩阵

下表标注各引擎对每个标准版本核心特性的支持程度：

### 核心语法特性

| 特性 | 标准版本 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite | BigQuery | Snowflake | ClickHouse |
|------|---------|-------|-----------|--------|-----------|--------|---------|-----------|-----------|
| JOIN 语法 | SQL-92 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CASE WHEN | SQL-92 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 递归 CTE | SQL:1999 | ✅ 8.0+ | ✅ 8.4+ | ✅ 11gR2+ | ✅ 2005+ | ✅ 3.8+ | ✅ | ✅ | ⚠️ 有限 |
| BOOLEAN | SQL:1999 | ⚠️ TINYINT(1) | ✅ | ❌→✅ 23ai | ⚠️ BIT | ⚠️ INTEGER | ✅ BOOL | ✅ | ✅ Bool |
| LATERAL | SQL:1999 | ✅ 8.0.14+ | ✅ 9.3+ | ✅ 12c+ | ✅ APPLY 2005+ | ❌ | ❌ | ✅ | ❌ |
| 窗口函数 | SQL:2003 | ✅ 8.0+ | ✅ 8.4+ | ✅ 8i+ | ✅ 2005+ | ✅ 3.25+ | ✅ | ✅ | ✅ |
| MERGE | SQL:2003 | ❌ | ✅ 15+ | ✅ 9i+ | ✅ 2008+ | ❌ | ✅ | ✅ | ❌ |
| IDENTITY | SQL:2003 | ❌ | ✅ 10+ | ✅ 12c+ | ✅ | ❌ | ❌ | ✅ | ❌ |
| SEQUENCE | SQL:2003 | ❌ | ✅ | ✅ | ✅ 2012+ | ❌ | ❌ | ✅ | ❌ |
| FILTER | SQL:2003 | ❌ | ✅ 9.4+ | ❌ | ❌ | ✅ 3.30+ | ❌ | ❌ | ⚠️ -If |
| TRUNCATE | SQL:2008 | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| FETCH FIRST | SQL:2008 | ❌ LIMIT | ✅ 8.4+ | ✅ 12c+ | ✅ 2012+ | ❌ LIMIT | ❌ LIMIT | ✅ | ❌ LIMIT |
| 时态表 | SQL:2011 | ❌ | ❌ | ⚠️ Flashback | ✅ 2016+ | ❌ | ❌ | ❌ | ❌ |
| JSON_VALUE | SQL:2016 | ✅ 8.0+ | ✅ 17+ | ✅ 12c+ | ✅ 2016+ | ❌ | ✅ | ✅ | ❌ |
| JSON_TABLE | SQL:2016 | ✅ 8.0+ | ✅ 17+ | ✅ 12c+ | ⚠️ OPENJSON | ❌ | ❌ UNNEST | ✅ FLATTEN | ❌ |
| LISTAGG | SQL:2016 | ❌ GROUP_CONCAT | ⚠️ STRING_AGG | ✅ 11gR2+ | ⚠️ STRING_AGG | ❌ | ⚠️ STRING_AGG | ✅ | ❌ |
| MATCH_RECOGNIZE | SQL:2016 | ❌ | ❌ | ✅ 12c+ | ❌ | ❌ | ✅ | ✅ | ❌ |
| ANY_VALUE | SQL:2023 | ✅ 5.7+ | ✅ 16+ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| GREATEST/LEAST | SQL:2023 | ✅ | ✅ | ✅ | ✅ 2022+ | ❌ | ✅ | ✅ | ✅ |

## 对引擎开发者：标准特性实现优先级

### P0: 必须实现（用户默认期望）

来自 SQL-92 和 SQL:2003 的核心特性：

| 特性 | 标准 | 理由 |
|------|------|------|
| SELECT/INSERT/UPDATE/DELETE | SQL-86 | 基础 |
| JOIN (INNER/LEFT/RIGHT/CROSS) | SQL-92 | 所有查询的基础 |
| CASE WHEN / COALESCE / NULLIF | SQL-92 | 条件逻辑 |
| 子查询 (IN/EXISTS/ALL/ANY) | SQL-92 | 复杂查询必需 |
| GROUP BY / HAVING / ORDER BY | SQL-86 | 聚合分析基础 |
| 窗口函数 (ROW_NUMBER/RANK/LAG/LEAD/SUM OVER) | SQL:2003 | 现代 SQL 分水岭 |
| CTE (WITH 子句) | SQL:1999 | 复杂查询可读性 |
| CAST 类型转换 | SQL-92 | 类型系统基础 |

### P1: 应该实现（用户常用）

| 特性 | 标准 | 理由 |
|------|------|------|
| 递归 CTE (WITH RECURSIVE) | SQL:1999 | 层级查询、序列生成 |
| MERGE INTO | SQL:2003 | UPSERT 标准方案 |
| FETCH FIRST N ROWS ONLY | SQL:2008 | 标准分页（但 LIMIT 更流行） |
| IDENTITY / SEQUENCE | SQL:2003 | 自增主键标准化 |
| JSON_VALUE / JSON_QUERY | SQL:2016 | 半结构化数据 |
| BOOLEAN 类型 | SQL:1999 | 类型系统完整性 |
| TRUNCATE TABLE | SQL:2008 | 快速清空表 |

### P2: 差异化特性（竞争优势）

| 特性 | 标准 | 理由 |
|------|------|------|
| JSON_TABLE | SQL:2016 | JSON 关系化的标准方案 |
| FILTER 子句 | SQL:2003 | 条件聚合的优雅语法 |
| MATCH_RECOGNIZE | SQL:2016 | 复杂事件处理 |
| 时态表 | SQL:2011 | 审计和合规 |
| LISTAGG | SQL:2016 | 字符串聚合标准化 |
| 图查询 SQL/PGQ | SQL:2023 | 图分析新方向 |

## 标准 vs 现实：最大的偏离

| 偏离 | 说明 | 影响 |
|------|------|------|
| MySQL `utf8` ≠ UTF-8 | MySQL 的 utf8 只有 3 字节，不符合 Unicode 标准 | 数据截断风险 |
| Oracle `'' = NULL` | SQL 标准明确 '' 是空字符串不是 NULL | 迁移噩梦 |
| MySQL 无 MERGE | SQL:2003 定义的 MERGE 至今不支持 | 用 ON DUPLICATE KEY UPDATE 替代 |
| MySQL CHECK 不执行 | 5.7 解析但不执行 CHECK 约束 | 数据完整性风险 |
| LIMIT vs FETCH FIRST | LIMIT 不在标准中但更流行 | 可移植性问题 |
| GROUP_CONCAT vs LISTAGG | 各引擎用不同名字实现字符串聚合 | SQL 不可移植 |
| `||` 运算符 | 标准定义为字符串拼接，MySQL 用作逻辑 OR | 迁移陷阱 |

## 参考资源

- [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
- [Modern SQL by Markus Winand](https://modern-sql.com/) — 最佳的 SQL 标准演进参考
- [jOOQ SQL Feature Comparison](https://www.jooq.org/diff) — 各引擎标准合规度对比
- [Wikipedia: SQL Standardization History](https://en.wikipedia.org/wiki/SQL#Standardization_history)
