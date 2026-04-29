# SQL 注入防御 (SQL Injection Defense)

一行 `' OR '1'='1` 让 1998 年的 Phrack #54 第一次把"SQL 注入"写进黑客词典；到 2026 年的今天，OWASP Top 10 的 A03 仍然是 Injection——这二十多年里只有一个真正有效的防御手段：**让参数永远不进入 SQL 文本**。本文从协议层、SQL 层、ORM 层、静态分析层四个维度，逐方言对比各引擎与框架的 SQL 注入防御机制。

## 核心论点：参数化查询是唯一正确的防御

业界对 SQL 注入防御曾长期存在三种"方案"：

1. **参数化查询（Parameterized Queries / Prepared Statements）**：参数与 SQL 模板分两条通道传输，服务端永远不会把参数解析为 SQL 语法。**这是唯一真正有效的方案**。
2. **转义函数（Escaping）**：在拼接前对参数做字符级转义（如 `mysql_real_escape_string`、`addslashes`）。**弱方案**：依赖字符集、转义规则正确性，历史上多次被绕过（GBK、宽字符、二阶注入等）。
3. **允许列表/黑名单（Allowlist / Blacklist）**：检测危险关键字（如 `UNION`、`--`、`'`）。**最弱方案**：对编码绕过、注释绕过、二阶注入完全无效，且会破坏合法输入（如包含 `'` 的人名）。

OWASP A03:2021、CWE-89、PCI DSS 4.0、ISO/IEC 27034 均明确将**参数化查询**列为首选防御。本文重点讨论各引擎如何在协议层、SQL 层、客户端 API 层提供参数化能力，以及在不可避免使用动态 SQL（如动态表名、动态列名）时的安全构造工具（如 PostgreSQL 的 `format(%I, %L)`）。

> 与本文密切相关的两篇文章：
> - `dynamic-sql.md`：动态 SQL 的语法机制（`EXECUTE IMMEDIATE`、`PREPARE/EXECUTE`），是注入风险的高发区
> - `server-side-prepared-statements.md`：协议层 Parse/Bind/Execute 的字节流细节，是参数化查询的底层实现

## OWASP Top 10 与行业标准定位

### OWASP A03:2021 - Injection

OWASP Top 10 自 2003 年首版起，**SQL 注入连续 22 年**位列前三：

| 年份 | OWASP 排名 | 类别名称 | 备注 |
|------|----------|---------|------|
| 2003 | A6 | Injection Flaws | 首次入榜 |
| 2004 | A6 | Injection Flaws | -- |
| 2007 | A2 | Injection Flaws | 上升至第 2 |
| 2010 | A1 | Injection | **登顶第 1**，连续 9 年 |
| 2013 | A1 | Injection | -- |
| 2017 | A1 | Injection | -- |
| 2021 | **A3** | Injection | 让位于 Broken Access Control，仍居前三 |

**OWASP A03:2021 关键数据**：33% 的应用包含某种形式的 Injection，CWE-89（SQL 注入）出现频次最高，CWE-89 的 CVSS 平均分 7.25（高危）。

**OWASP A03:2021 推荐防御措施**（按优先级）：

1. **使用安全的 API**：完全避免使用解释器，或使用提供参数化接口的 API
2. **正白名单输入校验**：但**不能作为唯一防御**（输入可能合法但语义恶意）
3. **转义特殊字符**：仅用于残留场景（如动态表名），且必须使用引擎提供的标准转义函数
4. **LIMIT 与 SQL 控制**：在查询中使用 `LIMIT` 等 SQL 控制以防止大规模数据泄露
5. **静态分析（SAST）+ 动态分析（DAST）**：CodeQL、Semgrep、Snyk Code、SonarQube 检测危险模式

### CWE 与其他标准

- **CWE-89**：Improper Neutralization of Special Elements used in an SQL Command - **SQL 注入主体定义**
- **CWE-564**：SQL Injection: Hibernate
- **CWE-943**：Improper Neutralization of Special Elements in Data Query Logic
- **PCI DSS 4.0 Requirement 6.2.4**：开发安全编码，明确要求防 Injection
- **NIST SP 800-53 SI-10**：信息输入校验
- **ISO/IEC 27034**：应用安全控制

## 支持矩阵（45+ 引擎与框架）

### 服务端预编译（真正的参数绑定）

服务端预编译 = 协议层 Parse/Bind/Execute，参数永远以独立通道送达，**这是最强的注入防御**。

| 引擎 | 协议层预编译 | 参数标记 | 二进制参数 | 强类型 | 参考版本 |
|------|:---:|------|:---:|:---:|------|
| PostgreSQL | 是 | `$1, $2` | 是 | 是 | 7.4+ |
| MySQL | 是 | `?` | 是 | 是 | 4.1+ |
| MariaDB | 是 | `?` | 是 | 是 | 5.1+ |
| SQL Server | 是 | `@param` | 是 | 是 | 7.0+ |
| Oracle | 是 | `:bind` | 是 | 是 | 早期 |
| DB2 | 是 | `?` | 是 | 是 | 早期 |
| SQLite | 是 (C API) | `?, :name, $name` | 是 | 弱 | 3.0+ |
| Snowflake | 是 (REST bindings) | `?` 或 `:name` | 是 | 是 | GA |
| BigQuery | 是 (queryParameters) | `?` 或 `@name` | 是 | 是 | GA |
| Redshift | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| ClickHouse | 部分 (参数化 SQL) | `{name:Type}` | 部分 | 是 | 22.3+ |
| DuckDB | 是 (C/Python API) | `?, $1` | 是 | 是 | 早期 |
| Trino | 是 (HTTP PREPARE) | `?` | -- | 部分 | 早期 |
| Presto | 是 (同 Trino) | `?` | -- | 部分 | 0.80+ |
| Spark SQL | 部分 (HiveServer2) | `?, :name` | 部分 | 部分 | 3.4+ |
| Hive | 部分 (HiveServer2) | `?` | -- | -- | 受限 |
| Flink SQL | 部分 (SQL Gateway) | `?` | -- | -- | 受限 |
| Databricks | 是 (Statement Execution API) | `:named_param` | 是 | 是 | 2024+ |
| Teradata | 是 (CLIv2 PCL) | `?` | 是 | 是 | 早期 |
| Greenplum | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| CockroachDB | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| TiDB | 是 (MySQL 协议) | `?` | 是 | 是 | 继承 MySQL |
| OceanBase | 是 (MySQL/Oracle 双协议) | `? 或 :bind` | 是 | 是 | 早期 |
| YugabyteDB (YSQL) | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| YugabyteDB (YCQL) | 是 (CQL 协议) | `?` | 是 | 是 | 继承 Cassandra |
| SingleStore | 是 (MySQL 协议) | `?` | 是 | 是 | 继承 MySQL |
| Vertica | 是 | `?` | 是 | 是 | 早期 |
| Impala | 是 (HiveServer2) | `?` | 部分 | 部分 | 早期 |
| StarRocks | 是 (MySQL 协议) | `?` | 是 | 是 | 继承 MySQL |
| Doris | 是 (MySQL 协议 + Arrow Flight SQL) | `?` | 是 | 是 | 继承 MySQL |
| MonetDB | 是 (MAPI) | `?` | 是 | 是 | 早期 |
| CrateDB | 是 (PG 协议) | `$1, ?` | 部分 | 部分 | 继承 PG |
| TimescaleDB | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| QuestDB | 是 (PG 协议) | `$1` | 部分 | 部分 | 6.x+ |
| Exasol | 是 | `?` | 是 | 是 | 早期 |
| SAP HANA | 是 | `?, :name` | 是 | 是 | 1.0+ |
| Informix | 是 | `?` | 是 | 是 | 早期 |
| Firebird | 是 | `?` | 是 | 是 | 早期 |
| H2 | 是 | `?` | 是 | 是 | 早期 |
| HSQLDB | 是 | `?` | 是 | 是 | 早期 |
| Derby | 是 | `?` | 是 | 是 | 早期 |
| Amazon Athena | 是 (HTTP) | `?` | -- | 部分 | 继承 Trino |
| Azure Synapse | 是 (TDS) | `@param` | 是 | 是 | 继承 SQL Server |
| Google Spanner | 是 (gRPC) | `@param` | 是 | 是 | GA |
| Materialize | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| RisingWave | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| InfluxDB IOx | 是 (Arrow Flight SQL) | `$1` | 是 | 是 | IOx+ |
| DatabendDB | 是 | `?` | 是 | 是 | GA |
| Yellowbrick | 是 (PG 协议) | `$1` | 是 | 是 | 继承 PG |
| Firebolt | 是 | `?` | 部分 | 部分 | GA |

> 统计：约 45+ 引擎提供原生服务端预编译能力，覆盖几乎所有主流数据库。**没有任何主流数据库不支持参数化查询**——使用拼接是程序员的选择，不是技术限制。

### 安全身份与字面量构造（用于动态 SQL）

当确实需要动态构造表名、列名时（如管理工具、多租户动态 DDL），引擎必须提供安全的"标识符引用"和"字面量引用"工具：

| 引擎 | 安全身份引用 | 安全字面量引用 | 动态 SQL 构造 | 备注 |
|------|------------|--------------|-------------|------|
| PostgreSQL | `quote_ident()` / `format(%I)` | `quote_literal()` / `quote_nullable()` / `format(%L)` | `format()` 9.1+ | 标杆实现 |
| MySQL | `QUOTE()` (字面量) | `QUOTE()` | 拼接为主 | 无 quote_ident |
| MariaDB | `QUOTE()` | `QUOTE()` | 拼接为主 | 同 MySQL |
| Oracle | `DBMS_ASSERT.SIMPLE_SQL_NAME` / `ENQUOTE_NAME` | `DBMS_ASSERT.ENQUOTE_LITERAL` | `EXECUTE IMMEDIATE USING` | DBMS_ASSERT 包 |
| SQL Server | `QUOTENAME()` | `STRING_ESCAPE()` (有限) | `sp_executesql @param` | QUOTENAME 1998+ |
| DB2 | -- | -- | `EXECUTE IMMEDIATE` + 字符串拼接 | 缺乏专用函数 |
| SQLite | -- | `quote()` | `?` 参数 | 仅字面量 |
| Snowflake | `IDENTIFIER('name')` | `?` 参数 | `EXECUTE IMMEDIATE` | IDENTIFIER 函数 |
| BigQuery | -- | -- | `@param` 仅字面量 | 表名不可参数化 |
| Redshift | -- | `quote_ident` (有限) | `EXECUTE` | 部分继承 PG |
| ClickHouse | -- | `quote()` | 参数化 SQL | 标识符无函数 |
| DuckDB | `quote_ident` (社区扩展) | `quote()` | `?` 参数 | 标准函数有限 |
| Trino/Presto | -- | -- | `PREPARE` + `?` | 标识符不可参数化 |
| Spark SQL | -- | -- | `?, :name` | 限于字面量 |
| Greenplum | `quote_ident` / `format(%I)` | `quote_literal` / `format(%L)` | `format()` | 继承 PG |
| CockroachDB | `quote_ident` | `quote_literal` | `format()` (受限) | 部分 PG 兼容 |
| YugabyteDB (YSQL) | `quote_ident` / `format(%I)` | `quote_literal` / `format(%L)` | `format()` | 继承 PG |
| TimescaleDB | `quote_ident` / `format(%I)` | `quote_literal` / `format(%L)` | `format()` | 继承 PG |
| Materialize | `quote_ident` | `quote_literal` | -- | 继承 PG |
| RisingWave | `quote_ident` | `quote_literal` | -- | 继承 PG |
| Vertica | `quote_ident` | `quote_literal` | -- | 部分 PG 兼容 |

> **关键发现**：PostgreSQL 的 `format(%I, %L)` 是业界最完整的安全动态 SQL 构造工具，被多个 PG 兼容引擎继承。SQL Server 的 `QUOTENAME()` 也是优秀实现，自 SQL Server 7.0 起即提供。

### 框架/驱动级参数化

| 框架/驱动 | 语言 | 参数化 API | 命名/位置 | 注入风险点 |
|---------|------|-----------|---------|-----------|
| JDBC PreparedStatement | Java | `setInt(1, x)` | 位置 `?` | 拼接 SQL 后再 prepare |
| JDBC NamedParameter (Spring) | Java | `:name` | 命名 | 内部转换为 `?` |
| ADO.NET SqlParameter | C# | `cmd.Parameters.Add` | 命名 `@name` | 字符串插值 |
| ADO.NET DbParameter | C# | `DbParameter` | 命名 | 同上 |
| psycopg2/3 | Python | `cur.execute(sql, params)` | `%s` 或 `%(name)s` | 元组拼接 |
| psycopg sql.SQL | Python | `sql.SQL().format(sql.Identifier())` | -- | 安全标识符 |
| asyncpg | Python | `conn.fetch(sql, *args)` | `$1` | 字符串拼接 |
| MySQLdb / mysqlclient | Python | `cur.execute(sql, params)` | `%s` | 拼接 |
| PyMySQL | Python | 同上 | `%s` | 拼接 |
| SQLAlchemy Core | Python | `text(":name")` + `bindparams` | 命名 | `text()` 直接拼接 |
| SQLAlchemy ORM | Python | Query API | -- | `text()` raw |
| Django ORM | Python | QuerySet API | -- | `extra()`, `RawSQL` |
| Django raw() | Python | `Model.objects.raw(sql, params)` | `%s` | 拼接 |
| Active Record (Rails) | Ruby | `where("col = ?", val)` | `?` 或 `:name` | `where("col = #{val}")` |
| Sequel (Ruby) | Ruby | `Sequel.lit(?, val)` | -- | -- |
| Hibernate (JPA) | Java | `setParameter(1, x)` 或 `:name` | 命名/位置 | `createNativeQuery` 拼接 |
| MyBatis | Java | `#{name}` (安全) vs `${name}` (拼接！) | 命名 | `${name}` 是注入入口 |
| jOOQ | Java | DSL `param()` | 类型安全 | `DSL.sql(raw)` |
| Sequelize | Node.js | `replacements` 或 `bind` | `:name` 或 `?` | `query()` 拼接 |
| TypeORM | Node.js | QueryBuilder | -- | `query()` raw |
| Knex.js | Node.js | `.where('col', val)` 或 `?` | 位置 | `raw()` 不安全 |
| Prisma | Node.js | 类型安全查询 | -- | `$queryRawUnsafe` |
| Drizzle ORM | Node.js | SQL template tag | -- | 类型安全 |
| Diesel | Rust | 类型安全 DSL | -- | 编译期检查 |
| sqlx | Rust | `sqlx::query!` 宏 | `?` 或 `$1` | 编译期校验 |
| GORM | Go | `Where("col = ?", val)` | `?` | `Raw(sql)` 拼接 |
| sqlx (Go) | Go | 命名/位置 | `?` 或 `:name` | -- |
| Doctrine ORM | PHP | `setParameter(1, x)` | 命名/位置 | `createNativeQuery` |
| PHP PDO | PHP | `bindParam`, `bindValue` | `?` 或 `:name` | `query()` 拼接 |
| PHP mysqli | PHP | `bind_param("si", $s, $i)` | 类型字符串 | `query()` 拼接 |
| Laravel Eloquent | PHP | Query Builder | -- | `DB::raw()` 拼接 |
| Ecto | Elixir | `from x in X, where: x.col == ^val` | 编译期 | `fragment` 类型化 |
| Slick | Scala | `sql"..."` 插值 | 编译期 | -- |
| ScalaSQL | Scala | 类型安全 | -- | -- |

> **关键观察**：几乎所有现代 ORM 默认使用参数化查询。**注入入口主要是"原始 SQL 逃生舱"**：`raw()`, `query()`, `text()`, `extra()`, `${}` 等。这些 API 必须搭配显式参数绑定使用。

### 静态分析与运行时检测工具

| 工具 | 类型 | 检测能力 | 误报率 | 适用语言 |
|------|------|---------|-------|---------|
| CodeQL (GitHub) | SAST | 数据流污染追踪 | 低 | Java, C#, Python, JS, Go, Ruby |
| Semgrep | SAST | 模式匹配 | 中 | 30+ 语言 |
| Snyk Code | SAST | AI + 规则 | 中 | 15+ 语言 |
| SonarQube | SAST | 规则匹配 | 中 | 主流语言 |
| Checkmarx | SAST | 商业 SAST | 中 | 主流语言 |
| Fortify | SAST | 商业 SAST | 中 | 主流语言 |
| Bandit | SAST | Python 专用 | 中 | Python |
| Brakeman | SAST | Rails 专用 | 低 | Ruby |
| FindBugs/SpotBugs | SAST | Java | 高 | Java |
| Veracode | SAST | 商业 | 中 | 主流语言 |
| OWASP ZAP | DAST | 黑盒注入测试 | -- | 任何 Web 应用 |
| Burp Suite | DAST | 商业 DAST | -- | 任何 Web 应用 |
| sqlmap | DAST | 自动化注入工具 | -- | 渗透测试 |
| RASP (Contrast) | RASP | 运行时拦截 | 极低 | Java, .NET, Node |
| ImmunIO | RASP | 运行时拦截 | 极低 | 多语言 |
| WAF (ModSecurity, AWS WAF) | 网络层 | 规则匹配 | 高 | 任何 |
| CloudFlare WAF | 网络层 | 商业 WAF | 中高 | 任何 |
| Database Activity Monitor (Imperva) | 数据库层 | 异常 SQL 检测 | 低 | 主流 DB |
| pg_stat_statements + 异常分析 | 数据库层 | 自定义 | -- | PostgreSQL |

## 各引擎参数化机制详解

### PostgreSQL：业界标杆

PostgreSQL 在 SQL 注入防御上有最完整的工具链：协议层 Extended Query、SQL 层 PREPARE、安全函数 `quote_ident/quote_literal`、`format()` 函数。

```sql
-- 1. 协议层（推荐）：JDBC/psycopg/libpq 自动使用
-- 客户端 API 看似 SQL 字符串，实际走 Parse/Bind/Execute 三段消息
PreparedStatement pst = conn.prepareStatement(
    "SELECT * FROM users WHERE email = $1 AND status = $2"
);
pst.setString(1, userEmail);  -- 永远不会被解析为 SQL
pst.setString(2, "active");

-- 2. SQL 层 PREPARE/EXECUTE
PREPARE find_user (text, text) AS
    SELECT * FROM users WHERE email = $1 AND status = $2;
EXECUTE find_user('alice@example.com', 'active');
DEALLOCATE find_user;

-- 3. PL/pgSQL 中：USING 子句必须使用
DO $$
DECLARE
    user_email text := 'alice@example.com';
    result record;
BEGIN
    -- 正确：USING 绑定参数
    EXECUTE 'SELECT * FROM users WHERE email = $1'
        INTO result
        USING user_email;
    -- 错误：字符串拼接
    -- EXECUTE 'SELECT * FROM users WHERE email = ''' || user_email || '''';
END $$;

-- 4. format() 函数：用于动态表名/列名（自 9.1）
DO $$
DECLARE
    tbl text := 'audit_2026_q1';
    col text := 'created_at';
BEGIN
    -- %I 自动添加双引号并转义内部双引号（quote_ident）
    -- %L 自动添加单引号并转义内部单引号（quote_literal）
    -- %s 直接插入（不安全，仅用于已验证内容）
    EXECUTE format(
        'CREATE INDEX ON %I (%I) WHERE %I > %L',
        tbl, col, col, '2026-01-01'::date
    );
END $$;

-- 5. quote_ident / quote_literal / quote_nullable
SELECT quote_ident('users');           -- "users"
SELECT quote_ident('weird"name');      -- "weird""name"
SELECT quote_literal('O''Brien');      -- 'O''Brien'
SELECT quote_literal(NULL);            -- 报错
SELECT quote_nullable(NULL);           -- NULL（字面量 NULL）
SELECT quote_nullable('alice');        -- 'alice'

-- 6. 危险写法（SQL 注入入口）
DO $$
DECLARE
    user_input text := $$'); DROP TABLE users; --$$;
BEGIN
    -- 错误：直接拼接，可被注入
    EXECUTE 'INSERT INTO log (msg) VALUES (''' || user_input || ''')';
    -- 注入后实际执行：
    -- INSERT INTO log (msg) VALUES (''); DROP TABLE users; --')
END $$;
```

PostgreSQL 的 `format()` 函数自 9.1 起提供了三个关键说明符：`%I`（identifier）、`%L`（literal）、`%s`（string）。**`%s` 应仅用于已通过白名单验证的固定值**。

### MySQL / MariaDB：协议层 + SQL 层

```sql
-- 1. 客户端 API（推荐）：JDBC/Python connector 走 COM_STMT_PREPARE
PreparedStatement pst = conn.prepareStatement(
    "SELECT * FROM users WHERE email = ? AND status = ?"
);
pst.setString(1, userEmail);
pst.setString(2, "active");

-- 2. SQL 层 PREPARE/EXECUTE（自 4.1）
PREPARE find_user FROM 'SELECT * FROM users WHERE email = ? AND status = ?';
SET @email = 'alice@example.com';
SET @status = 'active';
EXECUTE find_user USING @email, @status;
DEALLOCATE PREPARE find_user;

-- 3. QUOTE() 函数：仅用于字面量
SELECT QUOTE('O\'Brien');  -- 'O\'Brien'
SELECT QUOTE(NULL);        -- NULL（注意：返回字符串 'NULL'，不是 NULL 值）

-- 4. MySQL 没有 quote_ident！动态表名只能用反引号手动转义
-- 替代方案：在应用层做白名单校验
SET @tbl_name = 'orders_2026_q1';
-- 错误：直接拼接
SET @sql = CONCAT('SELECT * FROM ', @tbl_name);
-- 必须先白名单校验 @tbl_name，确保只包含 [a-zA-Z0-9_]
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 5. 历史漏洞：mysql_real_escape_string 在 GBK 字符集下被绕过
-- 0xBF 27 在 GBK 下是合法汉字，转义后变成 0xBF 5C 27 仍是合法汉字 + 单引号
-- 自 MySQL 5.0+ 推荐使用预编译语句替代转义
```

MySQL 自 4.1 引入服务端预编译协议，但生态中 PHP 的 `mysql_*` 系列函数（已废弃）长期使用 `mysql_real_escape_string` 拼接，导致历史上大量注入漏洞。

### SQL Server：sp_executesql 与 QUOTENAME

```sql
-- 1. 协议层 RPC：ADO.NET SqlParameter 走 TDS RPC
using var cmd = new SqlCommand(
    "SELECT * FROM Users WHERE Email = @email AND Status = @status",
    connection
);
cmd.Parameters.AddWithValue("@email", userEmail);
cmd.Parameters.AddWithValue("@status", "active");

-- 2. T-SQL：sp_executesql（推荐）
DECLARE @sql NVARCHAR(MAX);
DECLARE @email NVARCHAR(255) = 'alice@example.com';
SET @sql = N'SELECT * FROM Users WHERE Email = @email_param';
EXEC sp_executesql @sql,
    N'@email_param NVARCHAR(255)',
    @email_param = @email;

-- 3. EXEC()（不推荐，无参数化）
DECLARE @sql NVARCHAR(MAX);
SET @sql = 'SELECT * FROM Users WHERE Email = ''' + @email + '''';
EXEC(@sql);  -- 危险：拼接

-- 4. QUOTENAME（自 SQL Server 7.0/1998）：安全标识符引用
DECLARE @tbl SYSNAME = 'audit_2026_q1';
DECLARE @col SYSNAME = 'created_at';
DECLARE @sql NVARCHAR(MAX);
SET @sql = 'SELECT ' + QUOTENAME(@col) + ' FROM ' + QUOTENAME(@tbl);
EXEC sp_executesql @sql;
-- QUOTENAME('a]b') -> [a]]b]，正确转义右方括号

-- 5. 防止 sp_executesql 中的二阶注入
DECLARE @user_input NVARCHAR(100) = 'alice''; DROP TABLE Users; --';
DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM Users WHERE Name = @name';
EXEC sp_executesql @sql, N'@name NVARCHAR(100)', @name = @user_input;
-- 安全：参数与 SQL 模板分离，DROP TABLE 不会被执行

-- 6. STRING_ESCAPE（2016+，仅 JSON 转义，不能用于 SQL 字面量）
-- 注意：STRING_ESCAPE('text', 'json') 转义 JSON 特殊字符，不是 SQL 字符
```

SQL Server 的 `sp_executesql` 自 7.0（1998）起即支持参数化动态 SQL，是 T-SQL 防注入的核心工具。`QUOTENAME()` 提供了安全的标识符引用。

### Oracle：bind 变量与 DBMS_ASSERT

```sql
-- 1. PL/SQL 静态 SQL：自动使用 bind
DECLARE
    v_email VARCHAR2(255) := 'alice@example.com';
    v_user users%ROWTYPE;
BEGIN
    SELECT * INTO v_user FROM users WHERE email = v_email;  -- 自动 bind
END;

-- 2. EXECUTE IMMEDIATE USING：动态 SQL 必须使用
DECLARE
    v_email VARCHAR2(255) := 'alice@example.com';
    v_count NUMBER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE email = :1'
        INTO v_count
        USING v_email;
END;

-- 3. DBMS_SQL（动态 SQL 老式 API）
DECLARE
    v_cursor INTEGER := DBMS_SQL.OPEN_CURSOR;
    v_email VARCHAR2(255) := 'alice@example.com';
BEGIN
    DBMS_SQL.PARSE(v_cursor,
        'SELECT * FROM users WHERE email = :email',
        DBMS_SQL.NATIVE);
    DBMS_SQL.BIND_VARIABLE(v_cursor, ':email', v_email);
    -- ...
END;

-- 4. DBMS_ASSERT：标识符与字面量校验包
DECLARE
    v_tbl VARCHAR2(30);
    v_sql VARCHAR2(4000);
BEGIN
    -- SIMPLE_SQL_NAME：校验是否为合法 SQL 标识符
    v_tbl := DBMS_ASSERT.SIMPLE_SQL_NAME('audit_2026_q1');
    -- ENQUOTE_NAME：转义标识符并加双引号
    v_sql := 'SELECT * FROM ' || DBMS_ASSERT.ENQUOTE_NAME(v_tbl, FALSE);
    EXECUTE IMMEDIATE v_sql;

    -- ENQUOTE_LITERAL：转义字面量并加单引号
    DBMS_OUTPUT.PUT_LINE(DBMS_ASSERT.ENQUOTE_LITERAL('O''Brien'));
    -- 输出: 'O''Brien'

    -- 其他校验函数：
    -- QUALIFIED_SQL_NAME: schema.table 形式
    -- SCHEMA_NAME: 校验 schema 存在
    -- SQL_OBJECT_NAME: 校验对象存在
    -- NOOP: 占位符（不做校验）
END;

-- 5. 危险模式：字符串拼接到 EXECUTE IMMEDIATE
DECLARE
    v_input VARCHAR2(100) := q'[' OR '1'='1]';
BEGIN
    -- 错误：可被注入
    EXECUTE IMMEDIATE 'SELECT * FROM users WHERE email = ''' || v_input || '''';
END;
```

Oracle 的 `DBMS_ASSERT` 包是企业 PL/SQL 防注入的核心工具，提供五个关键函数。Oracle 自动 bind 是其性能与安全双赢的设计。

### SQLite：sqlite3_bind_*

```c
// SQLite 是嵌入式数据库，参数化通过 C API 实现
sqlite3_stmt *stmt;
const char *sql = "SELECT * FROM users WHERE email = ? AND status = ?";

// 1. 准备语句
sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);

// 2. 绑定参数
sqlite3_bind_text(stmt, 1, user_email, -1, SQLITE_TRANSIENT);
sqlite3_bind_text(stmt, 2, "active", -1, SQLITE_TRANSIENT);

// 3. 执行
while (sqlite3_step(stmt) == SQLITE_ROW) {
    // 处理行
}

// 4. 释放
sqlite3_finalize(stmt);

// 5. 命名参数
const char *sql2 = "SELECT * FROM users WHERE email = :email";
sqlite3_prepare_v2(db, sql2, -1, &stmt, NULL);
int idx = sqlite3_bind_parameter_index(stmt, ":email");
sqlite3_bind_text(stmt, idx, user_email, -1, SQLITE_TRANSIENT);
```

```sql
-- SQLite SQL 层 quote() 函数
SELECT quote('O''Brien');   -- 'O''Brien'
SELECT quote(NULL);          -- NULL
SELECT quote(123);            -- 123
SELECT quote(x'AB');           -- X'AB'
```

SQLite 没有 `quote_ident` 函数，动态标识符需在应用层校验后用双引号包围。

## 框架/驱动级安全实践

### Java JDBC PreparedStatement

```java
// 1. 正确：参数化查询（默认走 Parse/Bind/Execute 协议）
String sql = "SELECT * FROM users WHERE email = ? AND status = ?";
try (PreparedStatement pst = conn.prepareStatement(sql)) {
    pst.setString(1, userEmail);
    pst.setString(2, "active");
    try (ResultSet rs = pst.executeQuery()) {
        while (rs.next()) {
            // 处理行
        }
    }
}

// 2. 危险：客户端字符串拼接
String sql = "SELECT * FROM users WHERE email = '" + userEmail + "'";
Statement stmt = conn.createStatement();  // 错误！
ResultSet rs = stmt.executeQuery(sql);

// 3. 危险：拼接 SQL 后再 prepare（"伪参数化"）
String sql = "SELECT * FROM users WHERE email = '" + userEmail + "'";
PreparedStatement pst = conn.prepareStatement(sql);  // 仍然注入！
// PreparedStatement 不会撤销已经存在于 SQL 文本中的注入

// 4. IN 子句的处理（参数数量动态）
StringBuilder sb = new StringBuilder("SELECT * FROM users WHERE id IN (");
for (int i = 0; i < ids.size(); i++) {
    if (i > 0) sb.append(",");
    sb.append("?");
}
sb.append(")");
PreparedStatement pst = conn.prepareStatement(sb.toString());
for (int i = 0; i < ids.size(); i++) {
    pst.setInt(i + 1, ids.get(i));
}
// 或 PostgreSQL 特有：用 ANY 数组
PreparedStatement pst = conn.prepareStatement(
    "SELECT * FROM users WHERE id = ANY(?)"
);
pst.setArray(1, conn.createArrayOf("INTEGER", ids.toArray()));

// 5. 动态排序列：白名单校验后拼接
private static final Set<String> ALLOWED_SORT = Set.of("id", "email", "created_at");
public List<User> findUsers(String sortColumn) {
    if (!ALLOWED_SORT.contains(sortColumn)) {
        throw new IllegalArgumentException("Invalid sort column");
    }
    String sql = "SELECT * FROM users ORDER BY " + sortColumn;  // 安全
    // ...
}
```

### .NET ADO.NET SqlParameter

```csharp
// 1. 正确：参数化
using var cmd = new SqlCommand(
    "SELECT * FROM Users WHERE Email = @email AND Status = @status",
    connection
);
cmd.Parameters.Add("@email", SqlDbType.NVarChar, 255).Value = userEmail;
cmd.Parameters.Add("@status", SqlDbType.NVarChar, 20).Value = "active";

// 2. 推荐：显式指定类型，避免类型推断错误
cmd.Parameters.Add(new SqlParameter("@email", SqlDbType.NVarChar, 255)
{
    Value = userEmail
});

// 3. AddWithValue 的陷阱：类型推断可能导致索引失效
cmd.Parameters.AddWithValue("@email", userEmail);  // 推断为 NVARCHAR(N)
// 如果列是 VARCHAR，会发生隐式转换，索引失效

// 4. Dapper（轻量 ORM）
var users = connection.Query<User>(
    "SELECT * FROM Users WHERE Email = @Email",
    new { Email = userEmail }
);

// 5. 危险：字符串插值
var sql = $"SELECT * FROM Users WHERE Email = '{userEmail}'";  // 注入！
using var cmd = new SqlCommand(sql, connection);

// 6. Entity Framework Core：默认参数化
var users = context.Users
    .Where(u => u.Email == userEmail)  // 自动参数化
    .ToList();

// 7. EF Core FromSqlRaw 必须显式参数
var users = context.Users
    .FromSqlRaw("SELECT * FROM Users WHERE Email = {0}", userEmail)
    .ToList();
// 或
var users = context.Users
    .FromSqlInterpolated($"SELECT * FROM Users WHERE Email = {userEmail}")
    .ToList();
// FromSqlInterpolated 内部转换为参数化（不是字符串插值！）
```

### Python psycopg / SQLAlchemy

```python
# 1. psycopg2/3：正确的参数化
import psycopg
with psycopg.connect(...) as conn:
    with conn.cursor() as cur:
        # %s 是参数占位符（不是 Python format！）
        cur.execute(
            "SELECT * FROM users WHERE email = %s AND status = %s",
            (user_email, "active")
        )
        # 命名参数
        cur.execute(
            "SELECT * FROM users WHERE email = %(email)s",
            {"email": user_email}
        )

# 2. 危险：Python 字符串格式化
cur.execute(
    "SELECT * FROM users WHERE email = '%s'" % user_email  # 注入！
)
cur.execute(
    f"SELECT * FROM users WHERE email = '{user_email}'"  # 注入！
)

# 3. psycopg 的 sql 模块：安全标识符
from psycopg import sql
table = "audit_2026_q1"
column = "created_at"
query = sql.SQL("SELECT {col} FROM {tbl} WHERE {col} > %s").format(
    tbl=sql.Identifier(table),
    col=sql.Identifier(column)
)
cur.execute(query, ("2026-01-01",))

# 4. SQLAlchemy Core
from sqlalchemy import text, bindparam
stmt = text("SELECT * FROM users WHERE email = :email")
result = conn.execute(stmt, {"email": user_email})

# 5. SQLAlchemy ORM（自动参数化）
session.query(User).filter(User.email == user_email).all()

# 6. 危险：text() 拼接
stmt = text(f"SELECT * FROM users WHERE email = '{user_email}'")  # 注入！

# 7. 动态列名（必须白名单）
ALLOWED_COLUMNS = {"id", "email", "created_at"}
def get_users(sort_col: str):
    if sort_col not in ALLOWED_COLUMNS:
        raise ValueError(f"Invalid sort column: {sort_col}")
    return session.query(User).order_by(text(sort_col)).all()
```

### Ruby Active Record

```ruby
# 1. 正确：占位符
User.where("email = ?", user_email)
User.where("email = :email AND status = :status",
           email: user_email, status: "active")

# 2. 推荐：哈希语法（最安全）
User.where(email: user_email, status: "active")

# 3. 危险：字符串插值
User.where("email = '#{user_email}'")  # 注入！

# 4. 动态列：使用 sanitize_sql_array
sql = ActiveRecord::Base.sanitize_sql_array(["email = ?", user_email])

# 5. 原生 SQL 必须参数化
User.find_by_sql(["SELECT * FROM users WHERE email = ?", user_email])

# 6. Brakeman 静态分析自动检测以下危险模式：
# - User.where("email = '#{params[:email]}'")
# - find_by_sql("... #{params[:x]} ...")
# - update_all("name = '#{params[:name]}'")
```

### MyBatis：`#{}` vs `${}`

MyBatis 是 SQL 注入的"经典反例"——它的 `${}` 语法直接拼接，是大量企业 Java 应用的注入入口。

```xml
<!-- 1. 正确：#{} 自动参数化（生成 ?） -->
<select id="findByEmail" parameterType="String" resultType="User">
    SELECT * FROM users WHERE email = #{email}
</select>
<!-- 实际生成 SQL: SELECT * FROM users WHERE email = ? -->

<!-- 2. 危险：${} 字符串拼接（绝对禁用于用户输入！） -->
<select id="findByEmail" parameterType="String" resultType="User">
    SELECT * FROM users WHERE email = '${email}'  <!-- 注入！ -->
</select>

<!-- 3. ${} 唯一合法用途：动态表名/列名（必须白名单） -->
<select id="findFromTable" resultType="User">
    SELECT * FROM ${tableName}  <!-- 必须在 Java 层白名单校验 tableName -->
    WHERE email = #{email}
</select>

<!-- 4. ORDER BY 动态列（白名单 + ${}） -->
<select id="findUsers" resultType="User">
    SELECT * FROM users
    ORDER BY ${sortColumn} ${sortOrder}
    <!-- sortColumn 和 sortOrder 必须在 Java 层校验 -->
</select>
```

```java
// MyBatis 安全实践：所有 ${} 参数都必须白名单校验
public List<User> findUsers(String sortColumn, String sortOrder) {
    Set<String> allowedColumns = Set.of("id", "email", "created_at");
    Set<String> allowedOrders = Set.of("ASC", "DESC");
    if (!allowedColumns.contains(sortColumn)) {
        throw new IllegalArgumentException();
    }
    if (!allowedOrders.contains(sortOrder.toUpperCase())) {
        throw new IllegalArgumentException();
    }
    return mapper.findUsers(sortColumn, sortOrder.toUpperCase());
}
```

### Hibernate / JPA

```java
// 1. 正确：JPQL 参数化
TypedQuery<User> query = em.createQuery(
    "SELECT u FROM User u WHERE u.email = :email",
    User.class
);
query.setParameter("email", userEmail);

// 2. Native SQL 参数化
Query query = em.createNativeQuery(
    "SELECT * FROM users WHERE email = :email",
    User.class
);
query.setParameter("email", userEmail);

// 3. 危险：JPQL 字符串拼接
TypedQuery<User> query = em.createQuery(
    "SELECT u FROM User u WHERE u.email = '" + userEmail + "'",  // 注入！
    User.class
);
// 注意：JPQL 注入仍然存在，虽然 JPA 会做一些验证，但不能依赖

// 4. Criteria API（最安全）
CriteriaBuilder cb = em.getCriteriaBuilder();
CriteriaQuery<User> cq = cb.createQuery(User.class);
Root<User> root = cq.from(User.class);
cq.where(cb.equal(root.get("email"), userEmail));
List<User> results = em.createQuery(cq).getResultList();
```

### Go GORM / sqlx

```go
// 1. GORM：正确的参数化
db.Where("email = ?", userEmail).First(&user)
db.Where("email = ? AND status = ?", userEmail, "active").Find(&users)

// 2. GORM：命名参数
db.Where("email = @email AND status = @status",
    sql.Named("email", userEmail),
    sql.Named("status", "active"),
).Find(&users)

// 3. GORM：危险的 Raw SQL
db.Raw("SELECT * FROM users WHERE email = '" + userEmail + "'").Scan(&user)  // 注入！

// 4. GORM：正确的 Raw SQL
db.Raw("SELECT * FROM users WHERE email = ?", userEmail).Scan(&user)

// 5. database/sql 标准库
rows, err := db.Query("SELECT * FROM users WHERE email = $1", userEmail)
// PostgreSQL: $1 占位符
// MySQL: ? 占位符
// SQL Server: @p1 或 ? 占位符

// 6. sqlx 命名参数
rows, err := db.NamedQuery(
    "SELECT * FROM users WHERE email = :email",
    map[string]interface{}{"email": userEmail},
)
```

### Rust sqlx

```rust
// 1. sqlx::query! 宏（编译期校验！）
let users = sqlx::query!(
    "SELECT id, email FROM users WHERE email = $1",
    user_email
)
.fetch_all(&pool)
.await?;
// sqlx::query! 在编译期连接数据库验证 SQL 语法和类型

// 2. sqlx::query 函数（运行时）
let users = sqlx::query("SELECT * FROM users WHERE email = $1")
    .bind(user_email)
    .fetch_all(&pool)
    .await?;

// 3. Diesel（类型安全 ORM）
use diesel::prelude::*;
let users = users::table
    .filter(users::email.eq(user_email))
    .load::<User>(&conn)?;
// Diesel 在编译期保证 SQL 类型正确，无注入风险
```

## 常见 SQL 注入攻击模式

### 1. 经典字符串拼接（`$var`）

```sql
-- 应用代码（伪代码）
sql = "SELECT * FROM users WHERE name = '" + name + "' AND password = '" + pwd + "'"

-- 攻击 1: ' OR '1'='1
-- name = "admin' OR '1'='1' --"
-- 实际执行: SELECT * FROM users WHERE name = 'admin' OR '1'='1' -- AND password = '...'
-- 效果: 绕过密码校验

-- 攻击 2: 注释提前结束
-- name = "admin' --"
-- 实际执行: SELECT * FROM users WHERE name = 'admin' -- AND password = '...'
-- 效果: 仅按用户名查询

-- 攻击 3: 注释字符变体
-- MySQL: -- 注释（需后跟空格）, # 注释, /* */ 块注释
-- PostgreSQL: -- 注释
-- SQL Server: -- 注释
-- Oracle: -- 注释
```

### 2. UNION SELECT 数据泄露

```sql
-- 应用代码
sql = "SELECT id, name FROM products WHERE id = " + id

-- 攻击：UNION 拼接
-- id = "1 UNION SELECT username, password FROM users--"
-- 实际执行:
SELECT id, name FROM products WHERE id = 1
UNION SELECT username, password FROM users--

-- UNION 注入要点:
-- 1. 列数必须匹配（UNION SELECT NULL,NULL,NULL 探测列数）
-- 2. 类型必须兼容（NULL 是万能类型）
-- 3. 列顺序必须对应

-- 探测列数:
-- id = "1 ORDER BY 5--"  -- 列数小于 5 报错
-- id = "1 UNION SELECT 1,2,3,4,5--"

-- 提取数据库版本:
-- id = "1 UNION SELECT version(),NULL--"  -- PostgreSQL/MySQL
-- id = "1 UNION SELECT @@version,NULL--"  -- SQL Server
-- id = "1 UNION SELECT banner FROM v$version--"  -- Oracle

-- 列出所有表:
-- id = "1 UNION SELECT table_name,NULL FROM information_schema.tables--"
```

### 3. 时间盲注（Time-Based Blind SQLi）

```sql
-- 当应用不返回查询结果但执行了 SQL（如内部错误页面）时使用

-- MySQL 时间盲注
-- id = "1 AND IF(SUBSTRING((SELECT password FROM users WHERE id=1),1,1)='a', SLEEP(5), 0)--"
-- 如果第一个字符是 'a'，响应延迟 5 秒

-- PostgreSQL 时间盲注
-- id = "1 AND CASE WHEN (SELECT password FROM users WHERE id=1) LIKE 'a%' THEN pg_sleep(5) ELSE NULL END IS NOT NULL--"

-- SQL Server 时间盲注
-- id = "1; IF (SUBSTRING((SELECT password FROM users WHERE id=1),1,1)='a') WAITFOR DELAY '0:0:5'--"

-- Oracle 时间盲注
-- id = "1 AND CASE WHEN (SUBSTR((SELECT password FROM users WHERE id=1),1,1)='a') THEN dbms_pipe.receive_message('a',5) ELSE NULL END IS NOT NULL--"

-- 时间盲注效率极低（一字符一查询），但完全黑盒可用
-- sqlmap 自动化此类攻击
```

### 4. 布尔盲注（Boolean-Based Blind SQLi）

```sql
-- 应用根据查询是否返回结果显示不同页面
-- id = "1 AND (SELECT SUBSTRING(password,1,1) FROM users WHERE id=1)='a'"
-- 如果首字符是 'a'：返回正常页面
-- 否则：返回空白页面
```

### 5. 报错注入（Error-Based SQLi）

```sql
-- MySQL: extractvalue / updatexml
-- id = "1 AND extractvalue(1, concat(0x7e, (SELECT password FROM users WHERE id=1), 0x7e))"
-- 错误信息中包含密码

-- PostgreSQL: 整数转换报错
-- id = "1 AND CAST((SELECT password FROM users WHERE id=1) AS INTEGER)=1"
-- 错误信息: invalid input syntax for type integer: "actual_password"

-- SQL Server: 类型转换
-- id = "1 AND 1=convert(int, (SELECT password FROM users WHERE id=1))"
```

### 6. 二阶注入（Second-Order SQLi）

```sql
-- 攻击者先存储恶意输入，等到后续查询拼接时触发
-- 第 1 步（注册）: name = "admin' --"  （转义后入库）
-- 第 2 步（修改密码）:
-- sql = "UPDATE users SET password = '...' WHERE name = '" + storedName + "'"
-- 实际执行: UPDATE users SET password = '...' WHERE name = 'admin' --'
-- 效果: 修改了 admin 的密码

-- 防御: 所有 SQL 拼接点都必须参数化（包括内部数据来源）
```

### 7. 编码绕过

```sql
-- URL 编码: ' -> %27, -- -> --%20
-- 双重 URL 编码: ' -> %2527
-- HTML 实体: ' -> &#39;
-- Unicode: ' -> '
-- 十六进制: 'admin' -> 0x61646D696E

-- MySQL 历史漏洞 GBK 注入:
-- 0xBF 0x27 在 GBK 字符集下是合法汉字
-- mysql_real_escape_string 会变成 0xBF 0x5C 0x27
-- 但 0xBF 0x5C 在 GBK 下仍是合法汉字，0x27 (单引号) 逃逸

-- 防御: 使用预编译语句而非转义
```

### 8. 堆叠查询（Stacked Queries）

```sql
-- 部分数据库支持分号分隔多语句
-- id = "1; DROP TABLE users; --"

-- 引擎支持情况:
-- SQL Server: 支持（ExecuteReader 多语句）
-- PostgreSQL: 支持（多个语句）
-- MySQL: 默认禁用（需 multi_query_query 选项）
-- Oracle: 不支持（单语句）
-- SQLite: 不支持
```

## 标识符注入 vs 字面量注入

很多开发者只关注字面量注入（`WHERE col = 'value'`），但**标识符注入**（动态表名、列名）同样危险。

### 字面量注入：参数化即可解决

```sql
-- 正确：参数化
sql = "SELECT * FROM users WHERE email = ?"
pst.setString(1, userEmail);  -- 完美防御
```

### 标识符注入：必须白名单 + 安全引用

参数标记 `?` **不能用于标识符**（表名、列名、模式名）。这是 SQL 解析器的本质限制——标识符在解析阶段决定查询计划，不能延迟到执行时。

```sql
-- 错误：参数标记不能用于表名
PREPARE stmt FROM 'SELECT * FROM ?';   -- 语法错误（所有引擎）
PREPARE stmt FROM 'SELECT * FROM users ORDER BY ?';  -- 不会按列名排序，而是按字面量

-- 必须的两层防御：
-- 1. 白名单校验
ALLOWED_TABLES = {"users", "orders", "products"}
if table not in ALLOWED_TABLES:
    raise SecurityError()

-- 2. 安全标识符引用（即使白名单通过也加一层防御）
-- PostgreSQL: format(%I, table)
-- SQL Server: QUOTENAME(@table)
-- Oracle: DBMS_ASSERT.SIMPLE_SQL_NAME(p_table)
```

### 各引擎标识符引用规则

| 引擎 | 标识符分隔符 | 转义规则 | 大小写敏感 | 备注 |
|------|------------|---------|-----------|------|
| PostgreSQL | `"name"` | `""` 转义内部 `"` | 引用后区分大小写 | -- |
| MySQL | `` `name` `` 或 `"name"` (ANSI 模式) | 反引号转义 ``` `` ``` | -- | -- |
| MariaDB | 同 MySQL | -- | -- | -- |
| SQL Server | `[name]` 或 `"name"` | `]]` 转义 `]` | -- | -- |
| Oracle | `"NAME"` | `""` 转义 | 区分大小写 | 默认大写 |
| DB2 | `"name"` | `""` 转义 | -- | -- |
| SQLite | `[name]` 或 `"name"` 或 `` `name` `` | -- | -- | 多种风格兼容 |
| Snowflake | `"name"` | `""` 转义 | 区分大小写 | -- |
| BigQuery | `` `project.dataset.table` `` | 反引号 | -- | -- |
| ClickHouse | `` `name` `` 或 `"name"` | -- | -- | -- |

### 动态 ORDER BY/LIMIT 的安全模式

```python
# 错误：直接拼接
def list_users(sort_col, page_size):
    sql = f"SELECT * FROM users ORDER BY {sort_col} LIMIT {page_size}"
    # 注入: sort_col = "1; DROP TABLE users; --"

# 正确 1: 白名单校验
ALLOWED_SORT = {"id", "email", "created_at", "-id", "-email", "-created_at"}
def list_users(sort_col: str, page_size: int):
    if sort_col not in ALLOWED_SORT:
        raise ValueError("Invalid sort column")
    if not isinstance(page_size, int) or page_size > 1000:
        raise ValueError("Invalid page size")
    direction = "DESC" if sort_col.startswith("-") else "ASC"
    column = sort_col.lstrip("-")
    sql = f"SELECT * FROM users ORDER BY {column} {direction} LIMIT %s"
    cur.execute(sql, (page_size,))

# 正确 2: 映射表
SORT_MAPPING = {
    "name_asc": "email ASC",
    "name_desc": "email DESC",
    "newest": "created_at DESC",
    "oldest": "created_at ASC",
}
def list_users(sort_key: str):
    sort_clause = SORT_MAPPING.get(sort_key, "id ASC")
    sql = f"SELECT * FROM users ORDER BY {sort_clause}"
```

## ORM 安全模式

现代 ORM 在默认路径上是安全的，但都有"原始 SQL 逃生舱"（escape hatch）。**注入风险集中在逃生舱**。

### ORM 安全/危险 API 对照

| ORM | 安全 API（默认参数化） | 危险 API（必须显式绑定） |
|-----|---------------------|----------------------|
| Hibernate | `setParameter()` JPQL/HQL/Criteria | `createNativeQuery()` 拼接 |
| Active Record | `where(col: val)`, `where("col = ?", val)` | `where("col = #{val}")`, `find_by_sql` 拼接 |
| Sequelize | `.findAll({ where: {...} })`, `replacements` | `.query()` 拼接 |
| TypeORM | QueryBuilder, Repository | `.query()` 拼接 |
| Prisma | 类型安全 API | `$queryRawUnsafe`, `$executeRawUnsafe` |
| Django ORM | `.filter()`, `.exclude()` | `.extra()`, `RawSQL`, `raw()` 拼接 |
| SQLAlchemy ORM | Query 对象 | `text()` 拼接, `engine.execute()` |
| Doctrine | DQL `setParameter()` | `createNativeQuery()` 拼接 |
| GORM | `Where("col = ?", val)` | `Raw(sql)` 拼接 |
| MyBatis | `#{}` | `${}` |
| Diesel (Rust) | DSL 类型安全 | `sql_query()` 拼接 |
| sqlx (Rust) | `query!()` 宏（编译期校验） | `query()` 字符串 |
| Ecto (Elixir) | `from x in X, where:` 编译期 | `fragment` 拼接 |
| Slick (Scala) | `sql"..."` 插值（编译期） | `sqlu` 字符串 |

### Active Record 与 Brakeman

Ruby on Rails 的 Active Record 是 ORM 安全设计的范例之一，配合 Brakeman 静态分析工具几乎杜绝注入：

```ruby
# Brakeman 自动检测的危险模式：
# Confidence: High
User.where("name = '#{params[:name]}'")          # 字符串插值
User.find_by_sql("... #{params[:x]} ...")        # 字符串插值
User.where("name = ?" % params[:name])           # 格式化操作
exec_query("SELECT ... #{params[:x]}")           # 字符串插值

# Brakeman 不会误报的安全模式：
User.where(name: params[:name])                  # 哈希
User.where("name = ?", params[:name])            # 占位符
User.where("name = :name", name: params[:name])  # 命名占位符
```

### Django ORM 与 Bandit

```python
# Django QuerySet API 默认参数化
User.objects.filter(email=user_email)

# Bandit 检测的危险模式：
User.objects.raw("SELECT * FROM users WHERE email = '%s'" % email)  # B608
User.objects.extra(where=["email = '%s'" % email])                   # B608
cursor.execute("SELECT * FROM users WHERE email = '%s'" % email)    # B608

# 安全的 raw 用法：
User.objects.raw("SELECT * FROM users WHERE email = %s", [email])
User.objects.extra(where=["email = %s"], params=[email])
cursor.execute("SELECT * FROM users WHERE email = %s", [email])
```

### Prisma：类型安全与逃生舱

```typescript
// 1. 类型安全 API（默认参数化）
const user = await prisma.user.findUnique({
    where: { email: userEmail }
});

// 2. $queryRaw（模板字符串自动参数化）
const users = await prisma.$queryRaw`
    SELECT * FROM users WHERE email = ${userEmail}
`;
// Prisma 内部转换为参数化（不是字符串插值！）

// 3. $queryRawUnsafe（危险，必须显式参数）
const users = await prisma.$queryRawUnsafe(
    'SELECT * FROM users WHERE email = $1',
    userEmail
);

// 4. 危险：错误使用 Unsafe
const users = await prisma.$queryRawUnsafe(
    `SELECT * FROM users WHERE email = '${userEmail}'`  // 注入！
);
```

## 静态分析与运行时检测

### CodeQL（GitHub 集成）

CodeQL 通过数据流污染追踪检测 SQL 注入，是最精确的开源 SAST 工具之一。

```ql
// CodeQL 简化规则：检测 user input 流向 SQL 执行
import java
import semmle.code.java.dataflow.TaintTracking
import semmle.code.java.security.SqlInjection

class SqlInjectionFlow extends TaintTracking::Configuration {
    override predicate isSource(DataFlow::Node source) {
        source instanceof RemoteUserInput  // 用户输入
    }
    override predicate isSink(DataFlow::Node sink) {
        exists(MethodAccess ma |
            ma.getMethod().hasName(["executeQuery", "execute"])
            and sink.asExpr() = ma.getArgument(0)
        )
    }
}
```

### Semgrep（多语言模式匹配）

```yaml
# Semgrep 规则示例
rules:
  - id: python-sql-injection
    pattern-either:
      - pattern: |
          $CUR.execute("..." % $X)
      - pattern: |
          $CUR.execute(f"...{$X}...")
      - pattern: |
          $CUR.execute("..." + $X + "...")
    message: SQL injection via string formatting/concatenation
    languages: [python]
    severity: ERROR
```

### 运行时检测（RASP）

RASP（Runtime Application Self-Protection）在应用运行时拦截可疑 SQL 调用：

```
RASP 检测原理:
1. Hook JDBC/ADO.NET 等 SQL 执行 API
2. 在执行前分析 SQL 文本结构
3. 对比"原始查询"与"实际查询"的语法树差异
4. 如果用户输入改变了语法结构 → 注入

例如:
原始查询: SELECT * FROM users WHERE id = ?
用户输入: 1 OR 1=1
拼接结果: SELECT * FROM users WHERE id = 1 OR 1=1
RASP 检测: AST 中多了 OR 节点 → 拦截
```

### 数据库层异常检测

```sql
-- PostgreSQL: pg_stat_statements 监控异常 SQL
SELECT query, calls, mean_exec_time, rows
FROM pg_stat_statements
WHERE query LIKE '%UNION%'
   OR query LIKE '%pg_sleep%'
ORDER BY calls DESC
LIMIT 100;

-- SQL Server: 扩展事件监控
CREATE EVENT SESSION [SqlInjectionMonitor] ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    WHERE sql_text LIKE '%UNION%SELECT%'
       OR sql_text LIKE '%xp_cmdshell%'
       OR sql_text LIKE '%WAITFOR%DELAY%'
);

-- MySQL: 慢查询日志 + 异常长时间查询
-- log_queries_not_using_indexes = ON
-- long_query_time = 0.5  -- 异常 SLEEP() 注入会触发
```

## 客户端字符串拼接：永远的反模式

无论使用何种语言、何种数据库、何种 ORM，**客户端字符串拼接都是错误的**。这是参数化查询章节最重要的一条铁律。

### 为什么转义不够

```python
# 看似安全的转义
def escape(s):
    return s.replace("'", "''")

email = escape(user_input)
sql = f"SELECT * FROM users WHERE email = '{email}'"

# 失败场景 1: GBK 字符集（MySQL 历史漏洞）
# 0xBF 0x27 在 GBK 是合法汉字 + 单引号
# 转义后: 0xBF 0x5C 0x27 → 0xBF 0x5C 是合法汉字, 0x27 逃逸

# 失败场景 2: UTF-8 多字节误判
# 简单 replace 可能切断多字节字符

# 失败场景 3: 嵌套引用
# 用户输入: \' 或者 '''
# 不同 SQL 引擎对反斜杠的处理不同（PG 有 standard_conforming_strings）

# 失败场景 4: 类型注入
# 数字字段拼接：sql = f"id = {id}"
# 用户输入: "1; DROP TABLE users"
# 没有引号也能注入

# 唯一正确方案: 永远不拼接
sql = "SELECT * FROM users WHERE email = %s"
cur.execute(sql, (email,))
```

### 为什么允许列表（Allowlist）输入校验是辅助而非主要防御

```python
# 弱方案：黑名单
def is_safe(s):
    blacklist = ["UNION", "DROP", "INSERT", "--", "'"]
    return not any(b in s.upper() for b in blacklist)
# 失败：合法用户名 "Don't Stop" 被拒绝；编码绕过 "0x554E494F4E"

# 弱方案：正则白名单
def is_safe_email(s):
    return re.match(r"^[a-zA-Z0-9._@-]+$", s) is not None
# 缺点：只对特定字段类型有效；不能用于自由文本字段

# 正确：参数化 + 输入校验作为辅助
def find_user(email: str):
    if not re.match(r"^[a-zA-Z0-9._@-]+$", email):
        raise ValueError("Invalid email format")
    cur.execute("SELECT * FROM users WHERE email = %s", (email,))
    # 即使输入校验失败，参数化仍能阻止注入
```

输入校验的价值在于：
1. **业务层正确性**：拒绝无意义的格式（如非邮箱格式的邮箱字段）
2. **第二层防御**：纵深防御原则
3. **错误日志**：识别攻击尝试

但**不能替代参数化**。

## 关键发现

### 1. 参数化是唯一正确的防御，且所有主流引擎都支持

45+ 引擎/框架统计：**没有任何主流数据库不支持服务端预编译**。SQL 注入漏洞 100% 是程序员的选择问题，不是技术限制问题。

### 2. ORM 默认安全，但都有"原始 SQL 逃生舱"

每个 ORM 都有 `raw()`, `query()`, `text()`, `${}`, `Unsafe()` 这类逃生舱。**95% 的现代 SQL 注入漏洞集中在这些 API**。

### 3. 标识符不能参数化，必须白名单 + 安全引用

参数标记 `?` 只能绑定字面量。表名、列名、模式名必须：
- **白名单校验**（必需）
- **安全引用函数**（推荐，纵深防御）：PostgreSQL `format(%I)`、SQL Server `QUOTENAME()`、Oracle `DBMS_ASSERT.ENQUOTE_NAME`

### 4. PostgreSQL 的 `format(%I, %L)` 是业界标杆

自 PostgreSQL 9.1（2011）引入的 `format()` 函数提供了 `%I`（identifier）、`%L`（literal）、`%s`（string）三种安全说明符，是动态 SQL 构造的最佳实践。被 Greenplum、CockroachDB、YugabyteDB、TimescaleDB 等多个 PG 兼容引擎继承。

### 5. SQL Server 的 `sp_executesql` 自 7.0 起即提供完整参数化动态 SQL

SQL Server 7.0（1998）引入的 `sp_executesql` 是企业 T-SQL 防注入的核心工具，配合 `QUOTENAME()` 安全引用函数，提供了完整的动态 SQL 安全方案。

### 6. MyBatis `${}` 是企业 Java 应用的主要注入入口

`#{}` 安全（自动参数化），`${}` 直接拼接。**`${}` 仅在动态表名/列名场景使用，且必须配合 Java 层白名单**。代码审计中 MyBatis `${}` 是优先排查目标。

### 7. 转义函数（Escape）是历史遗留方案，不应作为主要防御

`mysql_real_escape_string`、`addslashes`、`PHP_QUOTE` 等历史上多次被绕过（GBK、宽字符、二阶注入）。OWASP 与 PostgreSQL 文档均明确说明：**转义只用于无法参数化的场景**（如已通过白名单的标识符二次保护）。

### 8. 输入校验是辅助而非主要防御

正则白名单、黑名单只能作为业务正确性校验和第二层防御。**核心防御必须是参数化**。

### 9. 静态分析（CodeQL/Semgrep）是 CI/CD 标配

GitHub Advanced Security（CodeQL）、Semgrep、Snyk Code、SonarQube 等 SAST 工具能在编码阶段检测大部分注入漏洞。**应集成到 CI 管道**。

### 10. 服务端预编译协议（Parse/Bind/Execute）是协议层的安全保证

PostgreSQL Extended Query、MySQL COM_STMT_PREPARE、SQL Server TDS RPC、Oracle OCI bind 等协议消息把"语句模板"和"参数值"分两条字节通道传输，**协议层物理隔离了 SQL 与参数**——参数永远不会被服务端 SQL 解析器看到。这是最强的注入防御层。

### 11. 二阶注入要求所有 SQL 拼接点都参数化

只在用户输入接收处参数化是不够的——内部数据来源（如数据库读出后再拼接）也必须参数化。**任何 SQL 拼接都是潜在的注入点**。

### 12. 堆叠查询能力差异显著

SQL Server 与 PostgreSQL 默认支持分号分隔多语句，是堆叠注入的高危引擎；MySQL 默认禁用；Oracle 与 SQLite 不支持。**多语句执行能力应在驱动级关闭**（如 MySQL 的 `multi_query` 选项）。

### 13. WAF 是网络层防御，不能替代代码层参数化

ModSecurity、AWS WAF、CloudFlare WAF 等基于规则匹配，对编码绕过、二阶注入、业务逻辑漏洞效果有限，**应作为纵深防御补充而非主要手段**。

## 参考资料

- OWASP Top 10:2021 A03 Injection: https://owasp.org/Top10/A03_2021-Injection/
- OWASP SQL Injection Prevention Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html
- CWE-89: Improper Neutralization of Special Elements used in an SQL Command: https://cwe.mitre.org/data/definitions/89.html
- PostgreSQL `format()` 文档: https://www.postgresql.org/docs/current/functions-string.html#FUNCTIONS-STRING-FORMAT
- PostgreSQL `quote_ident()` / `quote_literal()`: https://www.postgresql.org/docs/current/functions-string.html
- SQL Server `sp_executesql`: https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql
- SQL Server `QUOTENAME`: https://learn.microsoft.com/en-us/sql/t-sql/functions/quotename-transact-sql
- Oracle `DBMS_ASSERT`: https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_ASSERT.html
- MySQL Prepared Statements: https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html
- SQLite C API `sqlite3_prepare_v2`: https://www.sqlite.org/c3ref/prepare.html
- JDBC `PreparedStatement` (JSR 221): https://docs.oracle.com/javase/8/docs/api/java/sql/PreparedStatement.html
- ADO.NET `SqlParameter`: https://learn.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlparameter
- CodeQL SQL Injection: https://codeql.github.com/codeql-query-help/java/java-sql-injection/
- Semgrep Rules: https://semgrep.dev/explore
- Brakeman Ruby Analyzer: https://brakemanscanner.org/
- MyBatis `#{}` vs `${}`: https://mybatis.org/mybatis-3/sqlmap-xml.html
- PCI DSS 4.0 Requirement 6.2.4: https://www.pcisecuritystandards.org/
- NIST SP 800-53 SI-10: https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final
- Phrack #54: SQL injection (1998): http://phrack.org/issues/54/
- sqlmap: https://sqlmap.org/
