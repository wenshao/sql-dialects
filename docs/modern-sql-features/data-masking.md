# 数据遮罩与脱敏 (Data Masking and Redaction)

一张包含 1 亿条身份证号、手机号、信用卡号的用户表，既要让开发和分析人员能看到其中的业务数据，又不能让他们看到真实的敏感字段——数据遮罩（Data Masking）是现代数据库在合规时代的核心安全能力。

## 为什么数据遮罩至关重要

全球主要隐私合规法规对敏感数据处理有明确要求：

- **GDPR (欧盟通用数据保护条例, 2018)**：要求对个人可识别信息（PII）实施"假名化"（pseudonymisation）和"匿名化"（anonymisation）。数据遮罩是实现 Article 32 "数据处理安全"的关键技术之一。
- **HIPAA (美国健康保险流通与责任法案, 1996)**：Safe Harbor 方法要求移除 18 类标识符，Privacy Rule 要求"最少必要"原则。医疗数据在开发/测试环境中必须脱敏。
- **PCI-DSS (支付卡行业数据安全标准, 3.2.1/4.0)**：Requirement 3.4 明确要求"使 PAN（主账号）在任何地方存储时都不可读"，最少要求只显示前 6 位和后 4 位（`123456******7890`）。
- **CCPA/CPRA (加州消费者隐私法)**、**PIPL (中国个人信息保护法, 2021)**、**LGPD (巴西)** 等也有类似要求。

数据遮罩主要解决三类场景：
1. **生产查询受控暴露**：DBA/分析师需要访问数据，但不应看到明文 PII
2. **开发/测试环境数据**：从生产导出数据用于测试时，必须脱敏
3. **第三方数据共享**：合作伙伴、监管报送需要"看得到结构，看不到隐私"

## 没有 SQL 标准：纯粹的厂商实现

与 `TABLESAMPLE`（SQL:2003）、`MERGE`（SQL:2003）、`GROUPING SETS`（SQL:1999）等特性不同，**数据遮罩没有 ISO/ANSI SQL 标准语法**。原因有三：

1. **合规驱动**：这是 2010 年后才由 GDPR/HIPAA 等法规催生的需求，SQL 核心标准已稳定
2. **实现深度差异**：策略引擎、元数据治理、权限模型差异巨大，难以抽象统一语法
3. **厂商差异化**：每家数据库将此作为企业版卖点，没有动力统一

因此各厂商各自为政，语法五花八门：
- SQL Server: `MASKED WITH (FUNCTION = '...')`
- Snowflake/Redshift: `CREATE MASKING POLICY ... CASE WHEN`
- Oracle: `DBMS_REDACT.ADD_POLICY(...)` PL/SQL API
- BigQuery: 通过 Data Catalog 的 Policy Tags 实现
- Databricks: `MASK` 函数 + Unity Catalog

## 支持矩阵（综合）

### 静态遮罩 (SDM) vs 动态遮罩 (DDM) 基础支持

| 引擎 | 动态遮罩 DDM | 静态遮罩 SDM | 条件遮罩 | 版本/首次支持 |
|------|-------------|-------------|---------|--------------|
| PostgreSQL | 扩展 (pg_anonymizer) | 扩展 | 扩展 | -- (核心未支持) |
| MySQL | 企业版函数 | 企业版函数 | 企业版 | 5.7.24 (EE only, 2018) |
| MariaDB | MaxScale 过滤器 | -- | MaxScale | MaxScale 2.1+ |
| SQLite | -- | -- | -- | 不支持 |
| Oracle | 是 (DBMS_REDACT) | 选件 (DMP) | 是 | 12.1 (2013) |
| SQL Server | 是 (MASKED WITH) | -- | 有限 | 2016+ |
| DB2 | 是 (CREATE MASK) | -- | 是 | 10.5+ (2013) |
| Snowflake | 是 (MASKING POLICY) | -- | 是 (CASE) | GA 2020 |
| BigQuery | 是 (Policy Tags) | -- | 是 | GA 2022-07 |
| Redshift | 是 (MASKING POLICY) | -- | 是 | GA 2024-04 |
| DuckDB | -- | -- | -- | 不支持 |
| ClickHouse | -- (视图模拟) | -- | -- | 不支持 |
| Trino | -- | -- | -- | 不支持（Ranger 插件） |
| Presto | -- | -- | -- | 不支持（Ranger 插件） |
| Spark SQL | -- | -- | -- | 不支持（Ranger 插件） |
| Hive | -- (Ranger) | -- | Ranger | Ranger 2.0+ |
| Flink SQL | -- | -- | -- | 不支持 |
| Databricks | 是 (MASK 函数) | -- | 是 | 2022 (Unity Catalog) |
| Teradata | 是 (视图 + Row/Column Security) | -- | 是 | 14.10+ |
| Greenplum | -- | -- | -- | 不支持（可用 pg_anonymizer） |
| CockroachDB | -- | -- | -- | 不支持 |
| TiDB | -- | -- | -- | 不支持（应用层） |
| OceanBase | 企业版 | -- | 企业版 | 4.x (EE) |
| YugabyteDB | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | -- | 不支持（角色 + 视图） |
| Vertica | 视图 + 访问策略 | -- | `CREATE ACCESS POLICY` | 9.0+ |
| Impala | -- (Ranger) | -- | Ranger | Ranger 2.0+ |
| StarRocks | -- | -- | -- | 不支持（视图模拟） |
| Doris | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | 扩展 (pg_anonymizer) | -- | 扩展 | 继承 PG |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | 不支持（视图） |
| SAP HANA | 是 (MASKED WITH) | 选件 | 是 | SPS11 (2015) |
| Informix | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | LF Tags | Lake Formation 标签级 |
| Azure Synapse | 是 (MASKED WITH) | -- | 是 | 继承 SQL Server |
| Google Spanner | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| DatabendDB | 是 (MASKING POLICY) | -- | 是 | v1.1+ (2023) |
| Yellowbrick | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |

> 统计：约 13 个引擎提供原生动态遮罩能力，其余依赖视图 + RLS/ACL 模拟、外部网关（MaxScale/Ranger）或完全不支持。企业版与社区版在此能力上差异巨大。

### 内置遮罩函数支持

| 引擎 | 默认遮罩 | 邮箱遮罩 | 部分遮罩 | 随机化 | 自定义函数 |
|------|---------|---------|---------|--------|-----------|
| SQL Server | `default()` | `email()` | `partial(p,'mask',s)` | `random(l,h)` | -- |
| Oracle | `FULL` redaction | `REGEXP` 模式 | `PARTIAL(..)` | `RANDOM` | 是（PL/SQL） |
| Snowflake | -- | SQL 表达式 | SQL 表达式 | SQL 表达式 | 是（SQL UDF） |
| BigQuery | `SHA256` / `DEFAULT_MASKING_VALUE` | `EMAIL_MASK` | 是 | `HASH` | 是（Routine） |
| Redshift | -- | SQL 表达式 | SQL 表达式 | SQL 表达式 | 是（SQL UDF） |
| Databricks | -- | SQL 表达式 | SQL 表达式 | SQL 表达式 | 是（UDF） |
| MySQL (EE) | `mask_inner()` / `mask_outer()` | -- | `mask_inner` | `gen_rnd_*` | 有限 |
| DB2 | 任意 SQL 表达式 | SQL 表达式 | SQL 表达式 | SQL 表达式 | 是 |
| SAP HANA | `*****` 固定 | -- | 是 | -- | 是（hdbsysvar）|

### 策略 / 角色模型对比

| 引擎 | 策略对象 | 绑定方式 | 解除遮罩的权限 |
|------|---------|---------|---------------|
| SQL Server | 列级属性 | `ALTER COLUMN ADD MASKED WITH` | `UNMASK` 权限 |
| Oracle | `DBMS_REDACT.POLICY` | PL/SQL 注册，逐列 | `EXEMPT REDACTION POLICY` 系统权限 |
| Snowflake | `MASKING POLICY` 对象 | `ALTER TABLE ... SET MASKING POLICY` | `APPLY MASKING POLICY` / 策略条件 |
| Redshift | `MASKING POLICY` 对象 | `ATTACH MASKING POLICY ON ... TO ROLE` | 策略条件 |
| BigQuery | Data Catalog **Policy Tag** | 打标到列 | `Fine-Grained Reader` IAM 角色 |
| Databricks | `MASK` 表属性（函数引用） | `ALTER TABLE ... SET MASK` | Unity Catalog 权限 |
| DB2 | `COLUMN MASK` 对象 | `CREATE MASK ... FOR COLUMN` | `EXEMPT FROM ROW ACCESS` |
| SAP HANA | 列级属性 | `ALTER TABLE ... MASKED WITH` | `UNMASKED` object privilege |
| MariaDB | MaxScale `masking` 过滤器 | 代理层配置 JSON | 账号白名单 |

## 各引擎深入

### SQL Server：Dynamic Data Masking (2016+)

SQL Server 2016 引入原生动态数据遮罩，是最早将此作为标准功能的商业数据库之一。语法非常简洁：

```sql
-- 创建表时声明遮罩
CREATE TABLE Membership (
    MemberID       INT IDENTITY PRIMARY KEY,
    FirstName      VARCHAR(100) MASKED WITH (FUNCTION = 'partial(1,"XXXXXXX",0)') NOT NULL,
    LastName       VARCHAR(100) NOT NULL,
    Phone          VARCHAR(12)  MASKED WITH (FUNCTION = 'default()') NULL,
    Email          VARCHAR(100) MASKED WITH (FUNCTION = 'email()') NULL,
    Salary         MONEY        MASKED WITH (FUNCTION = 'random(1000, 9999)') NOT NULL,
    CreditCardNo   CHAR(16)     MASKED WITH (FUNCTION = 'partial(6, "XXXXXX", 4)') NULL
);

-- 对已有列添加遮罩
ALTER TABLE Membership
    ALTER COLUMN LastName ADD MASKED WITH (FUNCTION = 'default()');

-- 解除遮罩
ALTER TABLE Membership
    ALTER COLUMN LastName DROP MASKED;

-- 授予解除遮罩的权限
GRANT UNMASK TO AnalystUser;

-- 撤销
REVOKE UNMASK FROM AnalystUser;

-- SQL Server 2022+ 支持列级 UNMASK 权限
GRANT UNMASK ON Membership(Email) TO AnalystUser;
```

**四种内置遮罩函数**：

| 函数 | 作用 | 示例输入 | 示例输出 |
|------|------|---------|---------|
| `default()` | 按类型返回默认值 | 字符串/日期/数字 | `XXXX` / `1900-01-01` / `0` |
| `email()` | 保留首字母和域名后缀 | `john@contoso.com` | `jXXX@XXXX.com` |
| `partial(prefix, pad, suffix)` | 保留前 `prefix` 和后 `suffix` 字符 | `1234567890`, `partial(2,"***",2)` | `12***90` |
| `random(low, high)` | 返回随机数（仅数值类型） | `35000` | `3278` |

**安全警告**：DDM 是"表示层遮罩"，不是加密。有 `SELECT` 权限的用户可以通过以下方式推断真值：
```sql
-- 二分查找反推真实工资
SELECT MemberID FROM Membership WHERE Salary > 50000;
-- 对遮罩过的 Salary 列，上面谓词仍然用真实值执行！
```

Microsoft 官方文档明确提醒："DDM is intended to limit exposure of sensitive data by preventing users who should not have access to the data from viewing it. However, DDM is not designed to prevent database users from connecting directly to the database and running exhaustive queries that expose pieces of the sensitive data."

### Oracle：Data Redaction (12.1+, 2013)

Oracle 使用 `DBMS_REDACT` PL/SQL 包定义策略，这是比 SQL Server 更早推出的原生方案。

```sql
-- 添加完整遮罩策略
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema      => 'HR',
    object_name        => 'EMPLOYEES',
    column_name        => 'SALARY',
    policy_name        => 'redact_salary',
    function_type      => DBMS_REDACT.FULL,
    expression         => 'SYS_CONTEXT(''USERENV'', ''SESSION_USER'') != ''HR_MANAGER'''
  );
END;
/

-- 部分遮罩：信用卡只显示后 4 位
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema      => 'SALES',
    object_name        => 'PAYMENTS',
    column_name        => 'CARD_NO',
    policy_name        => 'redact_card',
    function_type      => DBMS_REDACT.PARTIAL,
    function_parameters => 'VVVVFVVVVFVVVVFVVVV,VVVV-VVVV-VVVV-VVVV,*,1,12',
    expression         => '1=1'  -- 对所有用户生效
  );
END;
/

-- 正则表达式遮罩：邮箱用户名部分
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema        => 'HR',
    object_name          => 'EMPLOYEES',
    column_name          => 'EMAIL',
    policy_name          => 'redact_email',
    function_type        => DBMS_REDACT.REGEXP,
    regexp_pattern       => '(.+)@(.+\..+)',
    regexp_replace_string=> '****@\2',
    regexp_position      => 1,
    regexp_occurrence    => 0,
    regexp_match_parameter => 'i',
    expression           => '1=1'
  );
END;
/

-- 随机化
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema => 'HR', object_name => 'EMPLOYEES',
    column_name   => 'SALARY', policy_name => 'redact_sal_rand',
    function_type => DBMS_REDACT.RANDOM,
    expression    => 'SYS_CONTEXT(''USERENV'', ''SESSION_USER'') = ''TESTER'''
  );
END;
/

-- 免除策略（UNMASK 等价）
GRANT EXEMPT REDACTION POLICY TO hr_manager;

-- 查看所有策略
SELECT object_name, column_name, policy_name, function_type
  FROM redaction_columns;
```

**Data Redaction vs Data Masking Pack（Oracle 两种能力）**：

| 对比维度 | Data Redaction | Data Masking Pack |
|---------|----------------|-------------------|
| 引入版本 | 12.1 (2013) | 11g R2（独立 Option） |
| 许可 | 包含在企业版（EE + Advanced Security Option） | **单独的付费选件** |
| 类型 | 动态（DDM，查询时） | 静态（SDM，导出/克隆时） |
| 数据是否真改 | 不改，底层数据不变 | **真实修改**数据（通常在 Enterprise Manager 克隆的副本上） |
| 主要场景 | 生产环境查询访问控制 | 测试/开发环境准备脱敏副本 |
| 性能影响 | 查询时开销（小） | 一次性导出开销（大） |
| 实现 | `DBMS_REDACT` PL/SQL 包 | Enterprise Manager Cloud Control / EMCLI |

许多团队会组合使用：生产用 Data Redaction 控制日常访问，每月/每周用 Data Masking Pack 导出脱敏副本到测试环境。

### PostgreSQL：核心不支持，Dalibo 的 PostgreSQL Anonymizer

PostgreSQL 核心从未内置动态数据遮罩。官方推荐的方案是 Dalibo 开源的 **PostgreSQL Anonymizer** (`anon`) 扩展，它综合了静态、动态、假名化、泛化等多种能力。

```sql
-- 安装扩展（需要 superuser）
CREATE EXTENSION anon CASCADE;
SELECT anon.init();

-- 通过 SECURITY LABEL 声明遮罩策略
SECURITY LABEL FOR anon ON COLUMN customer.first_name
    IS 'MASKED WITH FUNCTION anon.fake_first_name()';

SECURITY LABEL FOR anon ON COLUMN customer.last_name
    IS 'MASKED WITH FUNCTION anon.fake_last_name()';

SECURITY LABEL FOR anon ON COLUMN customer.email
    IS 'MASKED WITH FUNCTION anon.partial_email(email)';

SECURITY LABEL FOR anon ON COLUMN customer.ssn
    IS 'MASKED WITH VALUE NULL';

-- 声明某个角色在读表时应用遮罩
SECURITY LABEL FOR anon ON ROLE analyst IS 'MASKED';

-- 启动动态遮罩（基于 session_user）
SELECT anon.start_dynamic_masking();

-- analyst 登录后看到的是 fake 数据；dba 登录看到真实数据

-- 静态遮罩（永久修改数据）
SELECT anon.anonymize_database();   -- 应用所有策略，不可逆

-- 内置函数族（节选）
SELECT anon.fake_first_name();       -- "Olivia"
SELECT anon.fake_email();            -- "jsmith@foo.test"
SELECT anon.partial('1234567890',2,'*****',2);  -- "12*****90"
SELECT anon.hash('sensitive_string');           -- SHA-256
SELECT anon.noise(42.0, 0.1);        -- 42 +/- 10%
SELECT anon.generalize_daterange('2020-03-15', 'decade');  -- '2020-01-01', '2030-01-01'
```

**无扩展时的常见变通**（很多团队部署在受限环境用不了扩展）：

```sql
-- 方案 1：视图 + REVOKE + ROLE（纯标准 SQL）
REVOKE ALL ON customer FROM PUBLIC;
GRANT SELECT ON customer TO admin;

CREATE VIEW customer_masked AS
SELECT
    id,
    left(first_name, 1) || '***' AS first_name,
    regexp_replace(email, '(^.).*(@.+)$', '\1***\2') AS email,
    CASE
        WHEN current_user = 'admin' THEN ssn
        ELSE regexp_replace(ssn, '\d{3}-\d{2}', 'XXX-XX')
    END AS ssn,
    created_at
FROM customer;

GRANT SELECT ON customer_masked TO analyst;

-- 方案 2：行级安全 (RLS) + 条件遮罩
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY orders_self_only
    ON orders FOR SELECT
    USING (customer_id = current_setting('app.current_user_id')::bigint);

-- 方案 3：应用层使用 PG 代理（如 PgPool, Pgbouncer + SQL 改写）
```

### Snowflake：MASKING POLICY (GA 2020)

Snowflake 将遮罩策略建模为独立的 schema 级对象，通过 `CASE WHEN` 表达式实现条件遮罩，是目前最优雅的 DDM 设计之一。

```sql
-- 创建遮罩策略（独立对象）
CREATE OR REPLACE MASKING POLICY email_mask AS
    (val STRING) RETURNS STRING ->
        CASE
            WHEN CURRENT_ROLE() IN ('ADMIN', 'COMPLIANCE_OFFICER') THEN val
            WHEN CURRENT_ROLE() = 'ANALYST' THEN
                REGEXP_REPLACE(val, '(^.)[^@]*(@.*)', '\\1***\\2')
            ELSE '*********'
        END;

CREATE OR REPLACE MASKING POLICY ssn_mask AS
    (val STRING) RETURNS STRING ->
        CASE
            WHEN CURRENT_ROLE() = 'ADMIN' THEN val
            WHEN IS_ROLE_IN_SESSION('HR_READ') THEN
                CONCAT('XXX-XX-', RIGHT(val, 4))
            ELSE 'XXX-XX-XXXX'
        END;

-- 附加策略到列
ALTER TABLE customers MODIFY COLUMN email
    SET MASKING POLICY email_mask;

ALTER TABLE customers MODIFY COLUMN ssn
    SET MASKING POLICY ssn_mask;

-- 多列复用同一策略
ALTER TABLE orders MODIFY COLUMN customer_email
    SET MASKING POLICY email_mask;

-- 解除策略
ALTER TABLE customers MODIFY COLUMN email UNSET MASKING POLICY;

-- 查看策略定义
SHOW MASKING POLICIES;
SELECT GET_DDL('MASKING_POLICY', 'email_mask');

-- 查看策略绑定
SELECT * FROM TABLE(
    INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'email_mask')
);

-- Tag-Based Masking（Snowflake 独有）：给列打 Tag，对 Tag 统一应用策略
CREATE TAG pii_email;

ALTER TAG pii_email SET MASKING POLICY email_mask;

ALTER TABLE customers
    MODIFY COLUMN email SET TAG pii_email = 'CUSTOMER_EMAIL';

-- 任何打了 pii_email Tag 的列都自动遮罩，便于全域治理
```

**条件表达式可用的上下文函数**：
- `CURRENT_ROLE()`：当前会话角色
- `CURRENT_USER()`：当前用户
- `IS_ROLE_IN_SESSION('ROLE_NAME')`：角色层级检查
- `INVOKER_SHARE()`：是否通过 Secure Data Sharing 访问
- `SYSTEM$GET_TAG('tag_name', ...)`：Tag 值

### BigQuery：Policy Tags + Data Catalog (GA 2022)

BigQuery 的设计哲学最独特——**遮罩完全外置于 SQL**，通过 GCP Data Catalog 的 Policy Tags 实现。

```sql
-- 1. 在 Data Catalog 创建 Taxonomy 和 Policy Tag（通常用控制台或 gcloud）
-- gcloud data-catalog taxonomies create ...
-- gcloud data-catalog taxonomies policy-tags create ...

-- 2. 对 Policy Tag 配置 Data Policy（选择遮罩规则）
-- 可选规则：SHA256, Always null, Default masking value, Email mask,
--           Date year mask, Last four characters, First four characters

-- 3. 将 Policy Tag 附加到列（通过 BigQuery DDL）
ALTER TABLE `proj.ds.customers`
    ALTER COLUMN ssn SET OPTIONS (
        policy_tags = "projects/P/locations/us/taxonomies/T/policyTags/PT_SSN"
    );

ALTER TABLE `proj.ds.customers`
    ALTER COLUMN email SET OPTIONS (
        policy_tags = "projects/P/locations/us/taxonomies/T/policyTags/PT_EMAIL"
    );

-- 4. 通过 IAM 授予 Fine-Grained Reader 角色才能看到真值
-- 否则读到的是遮罩后的值（或拒绝读取，视策略配置）

-- 查询时用户透明：
SELECT name, email, ssn FROM `proj.ds.customers`;
-- 无 Fine-Grained Reader：email 看到 'XXX@example.com'，ssn 看到 'XXX-XX-1234'
-- 有 Fine-Grained Reader：真值
```

**Data Policy 支持的规则**（2024）：
- `SHA256`：单向哈希（可用于 JOIN 保持一致性）
- `Always null`：永远返回 NULL
- `Default masking value`：按类型返回默认值
- `Email mask`：邮箱遮罩
- `Date year mask`：只保留年份
- `Last four characters` / `First four characters`：保留首/末 4 位
- `Hash (SHA256)` with salt：加盐哈希

**优势**：与 Google 数据治理生态深度集成，同一 Policy Tag 可跨 BigQuery、Dataplex、Dataproc 使用。
**劣势**：策略不在 SQL 中可见，依赖 GCP 外部元数据服务；自定义逻辑能力弱于 Snowflake 的 `CASE WHEN`。

### Redshift：Dynamic Data Masking (GA 2024)

Amazon Redshift 是大型云数仓中最晚加入 DDM 的，2024 年 4 月正式 GA。语法与 Snowflake 类似：

```sql
-- 创建策略（支持输入输出不同类型转换）
CREATE MASKING POLICY mask_credit_card
    WITH (credit_card VARCHAR(16))
    USING (
        'XXXX-XXXX-XXXX-' || SUBSTRING(credit_card, 13, 4)
    );

-- 基于角色的条件（Redshift 通过 ATTACH 时用不同策略实现分角色）
CREATE MASKING POLICY mask_ssn_full USING ('XXX-XX-XXXX');
CREATE MASKING POLICY mask_ssn_last4
    WITH (ssn VARCHAR)
    USING ('XXX-XX-' || SUBSTRING(ssn, 8, 4));

-- 附加到列（按角色附加不同优先级）
ATTACH MASKING POLICY mask_credit_card
    ON customers(credit_card_number)
    TO ROLE analyst PRIORITY 10;

ATTACH MASKING POLICY mask_ssn_full
    ON customers(ssn)
    TO PUBLIC PRIORITY 0;

ATTACH MASKING POLICY mask_ssn_last4
    ON customers(ssn)
    TO ROLE hr_reader PRIORITY 20;
-- hr_reader 优先级更高，看到末 4 位；其他用户看到全 X

-- 查看策略
SELECT * FROM SVV_MASKING_POLICY;
SELECT * FROM SVV_ATTACHED_MASKING_POLICY;

-- 分离策略
DETACH MASKING POLICY mask_credit_card ON customers(credit_card_number) FROM ROLE analyst;
DROP MASKING POLICY mask_credit_card;
```

**关键设计**：通过 `PRIORITY` 数值解决多角色用户的策略冲突——同一用户属于多个角色时，最高优先级的策略生效。

### Databricks：Column Mask 函数 (Unity Catalog, 2022)

Databricks 用 Unity Catalog 提供 Column-level Masking，将遮罩逻辑注册为 SQL UDF，然后绑定到列：

```sql
-- 创建遮罩函数（Unity Catalog SQL UDF）
CREATE FUNCTION catalog.schema.mask_ssn(ssn STRING)
RETURNS STRING
RETURN
    CASE
        WHEN is_member('hr_admin') THEN ssn
        WHEN is_member('hr_reader') THEN CONCAT('XXX-XX-', SUBSTR(ssn, -4))
        ELSE 'XXX-XX-XXXX'
    END;

CREATE FUNCTION catalog.schema.mask_email(email STRING)
RETURNS STRING
RETURN
    CASE
        WHEN is_account_group_member('data-privacy-officers') THEN email
        ELSE REGEXP_REPLACE(email, '(^.).+(@.+)$', '$1***$2')
    END;

-- 绑定到列（列遮罩）
ALTER TABLE customers
    ALTER COLUMN ssn SET MASK catalog.schema.mask_ssn;

ALTER TABLE customers
    ALTER COLUMN email SET MASK catalog.schema.mask_email;

-- 移除绑定
ALTER TABLE customers ALTER COLUMN ssn DROP MASK;

-- 行过滤（Row Filter）配合使用
CREATE FUNCTION catalog.schema.region_filter(region STRING)
RETURNS BOOLEAN
RETURN region = current_user() OR is_member('global_admin');

ALTER TABLE orders SET ROW FILTER catalog.schema.region_filter ON (region);
```

**优势**：UDF 是完全可编程的 SQL 逻辑，比声明式的 `partial()` 更灵活，可跨 Databricks 工作区共享。

### MySQL：企业版专属 (5.7.24+, 2018)

MySQL 的数据遮罩能力**仅在企业版（Enterprise Edition）**中提供，以 `data_masking` 组件/插件形式发布。MySQL Community Edition 和 Percona Server、MariaDB 都不包含。

```sql
-- Enterprise Edition: 安装组件
INSTALL COMPONENT 'file://component_masking';

-- 字符串遮罩
SELECT mask_inner('0123456789', 2, 2);        -- '01XXXXXX89'
SELECT mask_outer('0123456789', 2, 2);        -- 'XX345678XX'
SELECT mask_pan('5123456789012345');          -- 'XXXXXXXXXXXX2345'
SELECT mask_pan_relaxed('5123456789012345');  -- '512345XXXXXX2345'
SELECT mask_ssn('909636922');                 -- 'XXX-XX-6922'

-- 随机生成
SELECT gen_rnd_email();                       -- 'yx.umhx@example.com'
SELECT gen_rnd_pan();                         -- '6821485921053467'
SELECT gen_rnd_ssn();                         -- '912-15-3446'
SELECT gen_rnd_us_phone();                    -- '1-555-903-7638'
SELECT gen_range(1000, 9999);                 -- 3872

-- 通常与视图和权限组合使用
CREATE VIEW customers_masked AS
SELECT
    id,
    name,
    mask_pan(credit_card) AS credit_card,
    mask_inner(email, 1, LENGTH(SUBSTRING_INDEX(email, '@', -1))+1) AS email
FROM customers;

GRANT SELECT ON customers_masked TO 'analyst'@'%';
REVOKE SELECT ON customers FROM 'analyst'@'%';
```

社区版唯一的选项是**自己写函数 + 视图**或使用 ProxySQL / MaxScale 等代理层。

### MariaDB：MaxScale Masking Filter

MariaDB 本身无内置遮罩，但其配套的 **MaxScale 代理**提供 `masking` 过滤器，在 SQL 流量经过代理时透明改写结果：

```ini
# /etc/maxscale.cnf
[MyMaskingFilter]
type=filter
module=masking
rules=/etc/maxscale/masking_rules.json

[ReadWriteService]
type=service
...
filters=MyMaskingFilter
```

```json
{
    "rules": [
        {
            "replace": {
                "column": "ssn",
                "table": "customers"
            },
            "with": {
                "fill": "X"
            },
            "applies_to": ["'analyst'@'%'"]
        },
        {
            "obfuscate": {
                "column": "email",
                "table": "customers"
            },
            "applies_to": ["'analyst'@'%'"]
        }
    ]
}
```

**注意**：MaxScale 的 masking 可能被 `SELECT CONCAT(ssn, '')` 等表达式绕过（代理只识别字段名），仅适合低风险脱敏。

### DB2：Column Mask (10.5+)

IBM DB2 提供了功能完整的列遮罩，语法独立于 SQL Server：

```sql
-- 创建掩码
CREATE MASK ssn_mask ON employees
    FOR COLUMN ssn
    RETURN
        CASE
            WHEN VERIFY_ROLE_FOR_USER(SESSION_USER, 'HR_MANAGER') = 1
                THEN ssn
            WHEN VERIFY_ROLE_FOR_USER(SESSION_USER, 'ANALYST') = 1
                THEN 'XXX-XX-' || SUBSTR(ssn, 8, 4)
            ELSE 'XXX-XX-XXXX'
        END
    ENABLE;

-- 激活表级掩码（所有该表上的掩码生效）
ALTER TABLE employees ACTIVATE COLUMN ACCESS CONTROL;

-- 停用
ALTER TABLE employees DEACTIVATE COLUMN ACCESS CONTROL;

DROP MASK ssn_mask;
```

DB2 的行级安全（Row Permission）与列遮罩配合使用，形成完整的 RCAC（Row and Column Access Control）。

### SAP HANA：Data Masking (SPS11+, 2015)

SAP HANA 是较早提供 DDM 的列式引擎：

```sql
-- 创建表时声明
CREATE TABLE customers (
    id      INTEGER,
    name    NVARCHAR(100),
    email   NVARCHAR(100) MASKED WITH ('*****'),
    ssn     NVARCHAR(11)  MASKED WITH (SUBSTR(ssn, 1, 3) || '-XX-XXXX')
);

-- 修改
ALTER TABLE customers ALTER (email NVARCHAR(100) MASKED WITH ('xxx@xxx.com'));

-- 关闭
ALTER TABLE customers ALTER (email NVARCHAR(100) NOT MASKED);

-- 授予"看真值"的权限
GRANT UNMASKED ON customers TO hr_role;
```

HANA 还提供**静态**的 Data Anonymization Services（SPS03+），用于创建 K-匿名、L-多样性等差分隐私副本。

### Teradata：视图 + Row/Column Security

Teradata 本身不提供 SQL 级别的 `MASK` DDL，而是通过 Row Level Security 和视图组合实现：

```sql
-- 基于用户角色的视图
REPLACE VIEW customers_masked AS
SELECT
    id,
    name,
    CASE WHEN ROLE = 'HR_FULL' THEN ssn
         ELSE 'XXX-XX-' || SUBSTR(ssn, 8, 4)
    END AS ssn,
    CASE WHEN ROLE = 'HR_FULL' THEN email
         ELSE REGEXP_REPLACE(email, '.+@', 'XXXX@')
    END AS email
FROM customers;

GRANT SELECT ON customers_masked TO analyst;
```

### Vertica：Access Policies (9.0+)

Vertica 提供 `CREATE ACCESS POLICY` 实现列级条件遮罩：

```sql
CREATE ACCESS POLICY ON customers
    FOR COLUMN ssn
    CASE
        WHEN ENABLED_ROLE('hr_manager') THEN ssn
        WHEN ENABLED_ROLE('analyst')   THEN 'XXX-XX-' || SUBSTR(ssn, 8, 4)
        ELSE NULL
    END
    ENABLE;

-- 行级
CREATE ACCESS POLICY ON orders
    FOR ROWS
    WHERE region = CURRENT_USER() OR ENABLED_ROLE('global')
    ENABLE;
```

### DatabendDB：MASKING POLICY (v1.1+)

新兴云数仓 Databend 紧跟 Snowflake 风格，提供 `MASKING POLICY`：

```sql
CREATE MASKING POLICY email_mask AS
    (val STRING) RETURNS STRING ->
        CASE
            WHEN CURRENT_ROLE() = 'admin' THEN val
            ELSE REGEXP_REPLACE(val, '(^.).+(@.+)$', '\1***\2')
        END
    COMMENT = 'Mask email except admin';

ALTER TABLE customers MODIFY COLUMN email
    SET MASKING POLICY email_mask;
```

### Ranger 插件（Hive / Spark / Trino / Presto / Impala）

Hadoop 生态系通过 **Apache Ranger** 统一管理列级遮罩。Ranger 2.0+ 支持：

```
Ranger 策略 JSON（节选）：
"dataMaskPolicyItems": [
    {
        "accesses": [{"type": "select", "isAllowed": true}],
        "roles": ["analyst"],
        "dataMaskInfo": {
            "dataMaskType": "MASK_SHOW_LAST_4"
            // 或 MASK, MASK_SHOW_FIRST_4, MASK_HASH, MASK_NULL,
            //    MASK_NONE, MASK_DATE_SHOW_YEAR, CUSTOM
        }
    }
]
```

Ranger 在查询规划阶段改写 SQL，将 `SELECT ssn FROM t` 改写为 `SELECT CONCAT('XXX-XX-', SUBSTRING(ssn, 8, 4)) AS ssn FROM t`，对用户透明。

## 内置遮罩函数深度对比

### SQL Server 四大函数详解

```sql
-- default() —— 按类型返回固定值
-- 字符型：XXXX (4 个 X)
-- 数值型：0
-- 日期型：1900-01-01 00:00:00.0000000
-- 二进制：0x00
ALTER TABLE t ALTER COLUMN name    ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE t ALTER COLUMN salary  ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE t ALTER COLUMN hiredat ADD MASKED WITH (FUNCTION = 'default()');

-- email() —— 保留首字母和 .com 等后缀
-- 'john.smith@acme.com' → 'jXXX@XXXX.com'
-- 'a@b.co'              → 'aXXX@XXXX.com'  (永远返回 .com 后缀，不保留真实后缀)
ALTER TABLE t ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');

-- partial(prefix_count, padding_string, suffix_count)
-- '123456789', partial(1,"XXX",2) → '1XXX89'
-- 'ABCDEFG',   partial(2,"###",0) → 'AB###'
ALTER TABLE t ALTER COLUMN card ADD MASKED WITH (FUNCTION = 'partial(6,"******",4)');

-- random(low, high) —— 仅数值型，每次查询返回不同随机值
-- 每行独立随机，同一行每次查询也可能不同
ALTER TABLE t ALTER COLUMN salary ADD MASKED WITH (FUNCTION = 'random(1000, 9999)');
```

### 等价函数的各引擎对比

```sql
-- 信用卡部分遮罩：'5123456789012345' → '512345XXXXXX2345'

-- SQL Server
MASKED WITH (FUNCTION = 'partial(6,"XXXXXX",4)')

-- Oracle
DBMS_REDACT.PARTIAL, function_parameters => 'VVVVVVVVVVVVVVVV,VVVVVVXXXXXXVVVV,X,7,12'

-- Snowflake
CREATE MASKING POLICY cc_mask AS (v STRING) RETURNS STRING ->
    SUBSTRING(v, 1, 6) || 'XXXXXX' || SUBSTRING(v, 13, 4);

-- BigQuery Data Policy: "First four characters" 预设规则（内置，无 SQL 表达式）

-- Redshift
CREATE MASKING POLICY cc_mask WITH (v VARCHAR)
    USING (LEFT(v, 6) || 'XXXXXX' || RIGHT(v, 4));

-- Databricks
CREATE FUNCTION mask_cc(v STRING) RETURNS STRING
    RETURN CONCAT(SUBSTR(v, 1, 6), 'XXXXXX', SUBSTR(v, -4));

-- MySQL Enterprise
SELECT mask_pan_relaxed('5123456789012345');   -- 内置等价

-- PostgreSQL anon
SELECT anon.partial('5123456789012345', 6, 'XXXXXX', 4);

-- DB2
CREATE MASK cc_mask ON t FOR COLUMN cc RETURN
    SUBSTR(cc, 1, 6) || 'XXXXXX' || SUBSTR(cc, 13, 4) ENABLE;
```

## 静态 vs 动态遮罩：设计权衡

### 静态数据遮罩 (SDM)

特点：**数据在存储时已被永久修改**，通常用于生成测试/开发环境副本。

```
原库 (prod)              遮罩脚本/工具             目标库 (test)
─────────                ─────────────            ─────────────
ssn: 123-45-6789  ─────>  Oracle DMP / pg_anon ──> ssn: 999-99-9999
name: John Doe             (一次性作业)            name: Alex Smith
```

**优点**：
- 副本可任意使用，下游查询无性能损失
- 即使测试环境被黑，泄露的也是假数据
- 引用一致性可保持（同样的输入哈希到同样的输出）

**缺点**：
- 需要存储/计算双倍资源
- 数据更新不同步，过时问题
- 不可逆（副本中看不到真值）

### 动态数据遮罩 (DDM)

特点：**数据在存储时不变**，查询时根据用户身份即时应用遮罩。

```
Table (storage)           Query Engine              User
─────────────             ─────────────            ──────
ssn: 123-45-6789  ────>  DDM Filter        ────>  分析师看到 XXX-XX-6789
                          (基于角色)                DBA 看到 123-45-6789
```

**优点**：
- 零存储开销，一份数据多种视图
- 授权实时生效，改策略即改可见性
- 数据保持最新

**缺点**：
- 查询时 CPU 开销（小）
- **不防推断攻击**：WHERE、JOIN、聚合仍用真值，有经验的攻击者可通过二分查找等手段反推
- 策略错误会影响生产查询

### 何时选择哪种

| 场景 | 推荐 | 理由 |
|------|------|------|
| 开发/测试环境 | SDM | 数据可带出安全区，必须彻底脱敏 |
| 分析师访问生产 | DDM | 需要保持数据一致和新鲜 |
| 数据科学建模 | SDM + 差分隐私 | 要保留统计特性同时防重标识 |
| 监管报送 | SDM 或 DDM + 聚合 | 按要求选择 |
| 第三方数据共享 | SDM | 数据离开企业边界 |
| DBA 日常维护 | DDM + 临时 UNMASK | 按需解遮罩 |

## 遮罩的局限性：推断攻击

动态遮罩**不是加密**，是表示层的过滤器。攻击者在有 `SELECT` 权限时可以绕过：

```sql
-- 假设 salary 列被 MASKED WITH (FUNCTION = 'default()')
-- 用户只能看到 0，但 WHERE 用真值执行

-- 攻击 1：二分查找 CEO 工资
SELECT COUNT(*) FROM employees WHERE position='CEO' AND salary > 500000;  -- 1
SELECT COUNT(*) FROM employees WHERE position='CEO' AND salary > 700000;  -- 1
SELECT COUNT(*) FROM employees WHERE position='CEO' AND salary > 900000;  -- 0
-- 攻击者推断 CEO 工资在 700k - 900k 之间，继续缩小范围

-- 攻击 2：通过 JOIN 推断
SELECT COUNT(*) FROM employees e JOIN ssn_list s ON e.ssn = s.ssn
WHERE s.is_vip = TRUE;
-- 即使 ssn 被遮罩，JOIN 仍以真值匹配

-- 攻击 3：通过 CASE 表达式暴露
SELECT CASE WHEN ssn LIKE '123%' THEN 1 ELSE 0 END FROM employees;
-- 结果 0/1 暴露 ssn 前缀
```

**缓解措施**：
1. **限制查询能力**：只给 `SELECT` 在遮罩视图上，不给基表
2. **审计日志**：记录所有对遮罩列的查询
3. **查询水印**：对过滤谓词做异常检测
4. **不可查询的加密列**（Always Encrypted）：代价是 JOIN 无法用真值
5. **差分隐私查询**：加噪声，但只适合聚合场景

Microsoft 在 SQL Server DDM 文档中明确指出："DDM should not be used alone as a substitute for proper security controls such as encryption, access control, and auditing."

## 列级 vs 行级遮罩

### 列级遮罩

大多数引擎支持，按列定义策略：所有行的该列按规则遮罩。

### 行级遮罩（通过 RLS 实现）

没有单独的 "row masking" 概念，通常用 Row Level Security (RLS) 实现：只返回满足条件的行，等价于"不该看见的行不返回"。

```sql
-- PostgreSQL
CREATE POLICY orders_region
    ON orders FOR SELECT
    USING (region = current_setting('app.user_region'));

-- SQL Server
CREATE SECURITY POLICY orders_filter
    ADD FILTER PREDICATE dbo.fn_securitypredicate(region) ON dbo.orders;

-- Snowflake
CREATE ROW ACCESS POLICY orders_region_policy AS
    (region STRING) RETURNS BOOLEAN ->
        region = CURRENT_REGION()
        OR CURRENT_ROLE() = 'GLOBAL_ADMIN';

ALTER TABLE orders ADD ROW ACCESS POLICY orders_region_policy ON (region);

-- Databricks
CREATE FUNCTION region_filter(r STRING) RETURNS BOOLEAN
    RETURN r = current_user() OR is_member('global');
ALTER TABLE orders SET ROW FILTER region_filter ON (region);
```

**组合使用**：列遮罩隐藏敏感列的值，行遮罩隐藏敏感的行，两者正交互补。

## 策略管理最佳实践

### 1. 集中策略库

将所有遮罩策略定义在一个专用 schema（如 `security_policies`），便于审计：

```sql
-- Snowflake 示例
CREATE SCHEMA security_policies;
CREATE MASKING POLICY security_policies.email_mask AS ...;
CREATE MASKING POLICY security_policies.ssn_mask AS ...;
CREATE MASKING POLICY security_policies.phone_mask AS ...;

-- 所有其他 schema 的表引用这里的策略
ALTER TABLE sales.customers MODIFY COLUMN email
    SET MASKING POLICY security_policies.email_mask;
```

### 2. 基于 Tag 的自动化治理

Snowflake 的 Tag-Based Masking 可以一次扫描整个账户，给所有名为 `*email*`、`*ssn*` 的列打 tag 并自动遮罩：

```sql
ALTER TAG pii SET MASKING POLICY security_policies.generic_pii_mask;

-- 扫描匹配列并打标（脚本生成 DDL）
ALTER TABLE customers MODIFY COLUMN email SET TAG pii = 'EMAIL';
ALTER TABLE users    MODIFY COLUMN email SET TAG pii = 'EMAIL';
...
```

### 3. 策略测试

在生产应用前先用测试角色验证：

```sql
-- Snowflake
USE ROLE test_analyst;
SELECT email FROM customers LIMIT 1;  -- 应看到遮罩值

USE ROLE admin;
SELECT email FROM customers LIMIT 1;  -- 应看到真值
```

### 4. 审计解遮罩

```sql
-- SQL Server
SELECT * FROM sys.database_permissions
WHERE type = 'UNMK';

-- Snowflake
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.MASKING_POLICIES;
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
WHERE POLICY_KIND = 'MASKING_POLICY';

-- Oracle
SELECT * FROM REDACTION_POLICIES;
SELECT * FROM REDACTION_COLUMNS;
```

## 对引擎开发者的实现建议

### 1. 策略对象抽象

推荐设计模式（Snowflake/Redshift 风格）：

```
MaskingPolicy {
    name: string
    input_type: DataType
    return_type: DataType
    expression: SqlExpr        // 可引用 CURRENT_USER, CURRENT_ROLE 等
    created_by: user_id
    created_at: timestamp
}

ColumnPolicyBinding {
    table_id: oid
    column_id: oid
    policy_id: oid
    priority: int              // 角色冲突时选择
    attached_to_role: role_id  // 可选，按角色绑定
}
```

与直接把 SQL 嵌入 DDL（SQL Server 风格）比，策略对象化的优势：
- 策略可复用，一个对象附加到多个列
- 更新策略只需改一处
- 便于审计和血缘追踪

### 2. 查询重写时机

在逻辑计划（Logical Plan）阶段重写，而非解析阶段：

```
原查询: SELECT email, name FROM customers

解析后 LogicalPlan:
    Project [email, name]
      Scan customers

策略重写后:
    Project [mask_email_fn(email) AS email, name]
      Scan customers

再经过优化器：常量折叠、谓词下推 ...
```

关键点：
- 重写必须在绑定到具体列之后（需知道列的策略）
- 重写必须在优化之前（让优化器看到真实表达式）
- 对 `SELECT *` 展开后的每列逐一检查策略

### 3. 上下文变量传递

用户身份、角色列表、当前标签在整个查询生命周期内不变，应作为**编译时常量**注入：

```
compile_time_context {
    current_user: string
    current_role: string
    session_roles: string[]
    client_ip: string
    application_name: string
}
```

策略表达式 `CURRENT_ROLE() = 'ADMIN'` 在编译期即可求值为 `TRUE/FALSE`：
- 当值为 `TRUE`：直接优化掉 CASE 分支，返回原列
- 当值为 `FALSE`：优化为遮罩分支

对于 `IS_ROLE_IN_SESSION()` 等多值函数，至少可在会话开始时展开为集合常量。

### 4. 推断攻击的缓解（可选）

如果引擎愿意承担性能代价，可实现：

```
LimitExposureOptimizer {
    // 检测"行级别"的过滤 + 聚合模式
    // 如 SELECT COUNT(*) FROM t WHERE masked_col > X

    // 策略 1: 拒绝未使用聚合的查询
    if query.filters.references(masked_column) && !query.has_groupby {
        error("Queries filtering on masked columns must aggregate")
    }

    // 策略 2: 注入最小 k-匿名约束
    if result_rows < k_threshold {
        return null  // 返回空，不泄露精确信息
    }

    // 策略 3: 加噪声（差分隐私）
    return result + laplace_noise(sensitivity, epsilon)
}
```

现实中很少数据库原生实现这些——主要留给应用层或专用分析平台。

### 5. 与列裁剪、谓词下推的交互

- **列裁剪**：若 SELECT 不涉及被遮罩列，可完全跳过策略求值
- **谓词下推**：对被遮罩列的谓词**仍用真值**，这是"不防推断"的根源。如需防范，需要阻止下推 + 拒绝查询
- **表达式下推到存储**：遮罩函数通常是标量函数，可被下推到存储层（列存向量化执行）
- **物化视图**：对遮罩列的结果不应物化缓存，否则缓存中保留了遮罩后的值，后续无法为不同用户展示不同结果

### 6. 策略级联与继承

视图、CTE 继承基表策略的语义选择：

```sql
CREATE VIEW v AS SELECT email, name FROM customers;
-- customers.email 有遮罩策略

-- 方案 A: 视图继承基表策略（Snowflake/Redshift 默认）
SELECT * FROM v;  -- email 仍被遮罩

-- 方案 B: 视图定义者可"漂白"（SQL Server 部分情况）
-- 需要视图定义者拥有 UNMASK 权限
```

推荐默认方案 A：策略穿透视图/CTE 一直生效。

### 7. 性能基准与测试

测试要点：
- **正确性**：不同角色访问同一行，返回不同值
- **性能**：带策略 vs 不带策略的查询延迟差异应 < 10% 对简单谓词
- **谓词攻击**：故意构造二分查找攻击，验证审计是否告警
- **并发一致性**：角色权限变更后，运行中的事务的语义
- **优化器交互**：列裁剪、谓词下推后策略是否仍生效
- **边界值**：NULL 输入、空串、超长串、特殊字符

## 总结对比矩阵

### 核心能力总览

| 能力 | SQL Server | Oracle | Snowflake | BigQuery | Redshift | Databricks | DB2 | SAP HANA | PostgreSQL |
|------|-----------|--------|-----------|----------|----------|-----------|-----|----------|-----------|
| 原生 DDM | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 扩展 |
| 策略对象化 | -- | 是 | 是 | 是 | 是 | 是(UDF) | 是 | -- | -- |
| 条件遮罩 | 有限 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 扩展 |
| 内置函数库 | 4 种 | 4 类 | -- | 预设规则 | -- | -- | -- | 固定 | 丰富 |
| 自定义函数 | -- | PL/SQL | SQL | Routine | SQL UDF | SQL UDF | 是 | 是 | 是 |
| Tag 治理 | -- | -- | 是 | 是 | -- | 是 | -- | -- | -- |
| 行级安全 | 是 | VPD | 是 | -- | 是 | 是 | 是 | 是 | RLS |
| 静态遮罩工具 | -- | DMP | -- | -- | -- | -- | -- | 选件 | anon |
| 解遮罩权限 | UNMASK | EXEMPT | APPLY | IAM | 策略条件 | UC权限 | EXEMPT | UNMASKED | 扩展 |

### 引擎选型建议

| 场景 | 推荐引擎 | 理由 |
|------|---------|------|
| 合规要求高的 OLTP | SQL Server / Oracle | 成熟、内置、文档完善 |
| 云数仓 + 多团队共享 | Snowflake | 策略对象化 + Tag 自动化治理 |
| GCP 生态 | BigQuery | 与 IAM、Data Catalog 无缝集成 |
| AWS 生态 | Redshift | 2024 新推出，与 IAM 集成 |
| Lakehouse | Databricks | UDF 灵活，与 ML/Notebook 贯通 |
| 开源 OLTP | PostgreSQL + pg_anonymizer | 社区活跃，功能丰富 |
| Hadoop 生态 | Ranger + Hive/Spark | 统一策略中心，多引擎支持 |
| 测试环境脱敏 | Oracle DMP / PG anon 静态 | 一次性导出，彻底脱敏 |
| 第三方共享 | SDM + Secure Share | 防推断攻击，物理隔离 |

## 关键发现

1. **没有 SQL 标准**：数据遮罩是 2013 年后才成熟的能力，SQL 标准未覆盖，导致各厂商语法完全不兼容。企业多引擎环境下的策略迁移痛苦。

2. **SQL Server 最早规范化 (2016)**，语法最简，但函数库只有 4 种且无法自定义；Snowflake (2020)、Redshift (2024) 后来居上，用策略对象 + CASE 表达式获得更强表达力。

3. **Oracle Data Redaction (2013)** 是商业数据库中最早的原生 DDM，PL/SQL API 式配置在现代 SQL 视角下略显笨重，但功能完备（PARTIAL、REGEXP、RANDOM 都支持）。

4. **BigQuery 走外置路线**：策略在 Data Catalog 而非 SQL 中，受益于 GCP 治理生态，代价是策略逻辑可编程性弱。

5. **MySQL 社区版长期无支持**：数据遮罩仅在 Enterprise Edition 中（2018 起），这是 MySQL 在 PII 合规场景下的显著短板，许多企业因此选择 PostgreSQL + pg_anonymizer。

6. **PostgreSQL 核心至今无内置**：依赖 Dalibo 的 anon 扩展。扩展质量很高（静态/动态/假名化/泛化都支持），但在云托管环境（RDS）中可能不可用。

7. **DDM 不防推断攻击**：所有厂商都在文档中明确提醒——WHERE/JOIN 仍用真值执行，攻击者可通过二分查找、JOIN 匹配等方式反推真实值。DDM 是"降低意外泄露风险"，不是"对抗恶意攻击"。

8. **静态 vs 动态的定位不同**：动态用于日常生产查询的访问控制；静态用于生成完全脱敏的副本，供开发、测试、第三方使用。Oracle 对两者分别提供独立产品（Redaction vs Masking Pack）是最清晰的划分。

9. **Lakehouse/OLAP 生态进展最慢**：Trino、Spark、Flink、ClickHouse 都没有原生遮罩，主要依赖 Apache Ranger 等外部插件。新兴引擎（Databricks、Snowflake、Databend）的治理设计明显更先进。

10. **Tag-Based Masking 是治理的未来**：Snowflake 首创，BigQuery（Policy Tags）、Databricks（Unity Catalog Tags）跟进。对 PII 列打 Tag 后自动应用策略，避免了每张表逐列配置的维护负担——这是大规模数据治理的关键能力。

## 参考资料

- SQL Server: [Dynamic Data Masking](https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking)
- Oracle: [Using Oracle Data Redaction](https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/using-oracle-data-redaction.html)
- Oracle: [Data Masking and Subsetting Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/mshome.html)
- Snowflake: [Column-level Security Masking Policies](https://docs.snowflake.com/en/user-guide/security-column-ddm-intro)
- BigQuery: [Introduction to Column Data Masking](https://cloud.google.com/bigquery/docs/column-data-masking-intro)
- Amazon Redshift: [Dynamic Data Masking](https://docs.aws.amazon.com/redshift/latest/dg/t_ddm.html) (2024)
- Databricks: [Column Mask Functions](https://docs.databricks.com/en/tables/column-mask.html)
- IBM DB2: [Column Masks](https://www.ibm.com/docs/en/db2/11.5?topic=security-column-masks)
- SAP HANA: [Data Masking](https://help.sap.com/docs/SAP_HANA_PLATFORM/b3ee5778bc2e4a089d3299b82ec762a7/2a1cfe983e574f29bd3e4a64707f7b88.html)
- PostgreSQL Anonymizer: [Dalibo anon Documentation](https://postgresql-anonymizer.readthedocs.io/)
- MySQL Enterprise: [Data Masking and De-Identification](https://dev.mysql.com/doc/refman/8.0/en/data-masking.html)
- MariaDB MaxScale: [Masking Filter](https://mariadb.com/kb/en/mariadb-maxscale-24-maskingfilter/)
- Apache Ranger: [Dynamic Row Filter and Column Masking](https://ranger.apache.org/)
- GDPR: [Article 32 - Security of processing](https://gdpr-info.eu/art-32-gdpr/)
- HIPAA: [De-identification Methods](https://www.hhs.gov/hipaa/for-professionals/privacy/special-topics/de-identification/)
- PCI-DSS v4.0: [Requirement 3.4](https://www.pcisecuritystandards.org/)
