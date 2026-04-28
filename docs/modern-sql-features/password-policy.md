# 密码策略 (Password Policy)

一个未启用密码策略的数据库账户，等于把企业最敏感的数据交给一组永不过期、可以反复尝试的字符串保管——这是 PCI-DSS、HIPAA、SOX、ISO 27001 审计员第一眼会盯住的位置。本文横向对比 47 款主流数据库/分析引擎对密码策略的内置支持，覆盖六个维度：复杂度、过期、历史、失败锁定、首次登录强制改密、密码校验函数。配合本仓库的 `auth-methods.md`（认证协议）与 `roles-grants-permissions.md`（授权与角色），就能完整描绘"账户身份层"的合规模型。

## 为什么密码策略是合规第一题

截至 2026 年，所有主流合规框架都把"密码强度策略"列为强制项：

1. **PCI-DSS v4.0**（2025 年 3 月强制生效）——8.3.6 要求最少 12 字符（先前 8 字符）+ 数字 + 字母；8.3.7 要求 12 个月内不得重复历史 4 次密码；8.3.4 要求失败 10 次后锁定 30 分钟以上；8.3.9 要求每 90 天轮换或动态分析。
2. **HIPAA Security Rule §164.308(a)(5)(ii)(D)**——明确要求"密码管理程序"，包括过期、复杂度、变更、历史。
3. **SOX § 404 (内部控制)**——审计师以 NIST SP 800-53 IA-5 (Authenticator Management) 为参考实现，要求最少 8-14 字符、有限重复、最少历史。
4. **NIST SP 800-63B**（数字身份指南）——AAL2/AAL3 等级要求"至少 8 字符 + 黑名单检查"，但反对强制周期性轮换（除非凭证泄露）。这与 PCI-DSS、SOX 在 2024 年仍然要求的"90 天必须改密码"形成有趣的张力。
5. **ISO/IEC 27001:2022 Annex A 9.4.3**——"密码管理系统"必须支持复杂度、历史、失败计数。
6. **GDPR Article 32**——"采取适当的技术措施"被监管机关解读为包括密码策略。
7. **中国《数据安全法》第 27 条 / 等保 2.0 三级**——明确要求密码复杂度、过期、历史、失败锁定。
8. **CIS Benchmarks**——为 PostgreSQL/MySQL/Oracle/SQL Server/MongoDB 提供详细加固清单，把密码策略放在前 5 项。

合规要求与 NIST SP 800-63B 之间的张力点：周期性强制轮换是否仍有意义？2017 年以来 NIST 已不再推荐"基于时间"的强制轮换（理由：导致用户用 `Password1!`/`Password2!` 这种递增模式，反而降低安全），主张"事件驱动"轮换（仅在凭证泄露时强制改密）。但 PCI-DSS 4.0、HIPAA、ISO 27001 仍在 2026 年要求 90 天周期。结果是数据库厂商必须**同时**提供"周期轮换"和"基于事件的密码哈希作废"两套机制。

## 没有 SQL 标准

密码策略不在 ISO/IEC 9075（SQL）覆盖范围内。SQL 标准只规定了 `CREATE USER ... IDENTIFIED BY ...` 的最小语法（SQL:1999 § 12.x），密码长度、复杂度、过期、历史、锁定全部留给厂商自行扩展。结果就是：每个引擎的语法、参数名、参数粒度、参数默认值都不同，迁移与统一审计变得困难。本文存在的核心理由就是把这种碎片化整理成可对照表。

行业可参考的事实标准：

| 规范 | 说明 |
|------|------|
| **NIST SP 800-63B** (Digital Identity Guidelines) | 反对强制周期轮换，主张黑名单 + MFA |
| **NIST SP 800-53 IA-5** | 联邦系统的"Authenticator Management" |
| **PCI-DSS v4.0 § 8.3** | 支付卡数据系统的密码要求（强制） |
| **CIS PostgreSQL Benchmark v15+** | PostgreSQL `passwordcheck`/`credcheck` 配置参考 |
| **CIS MySQL Benchmark 8.0** | `validate_password` 必须 STRONG，长度 ≥ 14 |
| **CIS Oracle 19c Benchmark** | DEFAULT profile 必须替换为加固版 |
| **OWASP ASVS V2.1** | 密码与凭据管理的应用层要求 |

## 支持矩阵（47 引擎总览）

### 矩阵一：密码复杂度策略 (Complexity)

| 引擎 | 内置复杂度 | 长度要求 | 字符种类要求 | 黑名单/字典 | 用户名相关性 | 引入版本 |
|------|-----------|----------|-------------|------------|-------------|----------|
| Oracle | 是 (PROFILE + verify_function) | 是 | 是 | `ora12c_strong_verify_function` | 是 | 8i (1999) |
| SQL Server | 是 (`CHECK_POLICY`) | 委托 Windows | 委托 Windows | -- | 是 | 2005 |
| MySQL | 是 (`validate_password` 组件) | 是 | 是 | `dictionary_file` | -- | 5.6 (插件), 8.0 (组件) |
| MariaDB | 是 (`simple_password_check`/`cracklib_password_check`) | 是 | 是 | cracklib 字典 | -- | 10.1.2 |
| PostgreSQL | 扩展 (`passwordcheck`/`credcheck`) | 配置 | 配置 | 字典 | 配置 | 8.4 (2009) |
| DB2 | 是 (`PASSWORD ATTRIBUTES`) | 是 | 是 | -- | -- | 9.7+ |
| SAP HANA | 是 (`PASSWORD POLICY`) | 是 | 是 | 黑名单表 | 是 | 1.0 SPS 04 |
| Snowflake | 是 (固定规则) | 是 (≥ 8) | 是 | -- | -- | GA |
| CockroachDB | 是 (`server.user_login.min_password_length`) | 是 | -- | -- | -- | v22.1 |
| Teradata | 是 (DBC.SysSecDefaults) | 是 | 是 | -- | 是 | V2R5 |
| Vertica | 是 (PROFILE) | 是 | 是 | -- | -- | 9.0+ |
| Greenplum | 继承 PG (`gp_passwordcheck`) | 是 | 是 | -- | -- | 5.x+ |
| YugabyteDB | 继承 PG (`passwordcheck` 扩展) | 配置 | 配置 | -- | -- | 2.x+ |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| TiDB | 是 (`validate_password` 类 MySQL) | 是 | 是 | 字典 | -- | 6.5+ |
| OceanBase | 是 (类 MySQL/Oracle 双模式) | 是 | 是 | -- | -- | 3.x+ |
| SingleStore | -- (依赖 SAML/LDAP) | -- | -- | -- | -- | -- |
| Doris | 是 (`validate_password_policy` 类 MySQL, 1.2+) | 是 | 是 | -- | -- | 1.2+ |
| StarRocks | 是 (`validate_password_policy`, 3.1+) | 是 | 是 | -- | -- | 3.1+ |
| Exasol | 是 (`PASSWORD_SECURITY_POLICY`) | 是 | 是 | -- | -- | 6.x+ |
| MongoDB | -- (依赖 SCRAM 强度) | -- | -- | -- | -- | -- |
| Redis | -- | -- | -- | -- | -- | -- |
| Informix | 是 (`PAM` 模块) | PAM 提供 | PAM 提供 | PAM 提供 | -- | 11.x+ |
| Firebird | -- (3.x SRP 不内置策略) | -- | -- | -- | -- | -- |
| ClickHouse | 部分 (用户配置 RBAC，但无内置复杂度检查) | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | -- | -- | -- |
| Trino | 配置文件 (file authenticator) | -- | -- | -- | -- | -- |
| Presto | 配置文件 | -- | -- | -- | -- | -- |
| Spark SQL | -- (依赖外部 IdP) | -- | -- | -- | -- | -- |
| Hive | -- (依赖 Hadoop SASL/Kerberos) | -- | -- | -- | -- | -- |
| Impala | -- (依赖 LDAP/Kerberos) | -- | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- | -- | -- |
| BigQuery | -- (无密码) | -- | -- | -- | -- | -- |
| Redshift | 是 (`password_check_*` GUC) | 是 | 是 | -- | -- | GA |
| Snowflake | 是 (`PASSWORD POLICY` 对象, 2022+) | 是 | 是 | 黑名单 | -- | 2022 |
| Athena | -- (无密码) | -- | -- | -- | -- | -- |
| Azure Synapse | 是 (继承 SQL Server) | 是 | 是 | -- | -- | GA |
| Google Spanner | -- (无密码) | -- | -- | -- | -- | -- |
| Databricks | 委托 IdP | -- | -- | -- | -- | -- |
| Materialize | 继承 PG | 扩展 | 扩展 | 扩展 | 扩展 | -- |
| RisingWave | 继承 PG | 扩展 | 扩展 | 扩展 | 扩展 | -- |
| Yellowbrick | 继承 PG | 扩展 | 扩展 | 扩展 | 扩展 | GA |
| Firebolt | -- (无密码) | -- | -- | -- | -- | -- |
| QuestDB | -- (Enterprise 集成 LDAP/OIDC) | -- | -- | -- | -- | -- |
| InfluxDB | -- (Token only) | -- | -- | -- | -- | -- |
| Databend | -- (Token + 简单密码) | -- | -- | -- | -- | -- |
| CrateDB | -- (依赖 JWT/简单密码) | -- | -- | -- | -- | -- |

> 统计：47 个引擎中，约 18 个有内置复杂度策略；其余通过外部认证（LDAP/SAML/OIDC）或扩展插件提供。

### 矩阵二：密码过期 (Expiration)

| 引擎 | 内置过期 | 默认过期天数 | 宽限期 | 用户级覆盖 | 引入版本 |
|------|---------|-------------|--------|-----------|----------|
| Oracle | 是 (`PASSWORD_LIFE_TIME`) | 180 (DEFAULT profile, 11g+) | 是 (`PASSWORD_GRACE_TIME`, 默认 7) | 通过 PROFILE | 8i (1999) |
| SQL Server | 是 (`CHECK_EXPIRATION`) | 委托 Windows policy | -- | 是 (`MUST_CHANGE`) | 2005 |
| MySQL | 是 (`PASSWORD EXPIRE INTERVAL`) | 默认 0 (不过期, 8.0) | -- | 是 | 5.6.6 |
| MariaDB | 是 (`PASSWORD EXPIRE INTERVAL`) | 默认 0 | -- | 是 | 10.4 |
| PostgreSQL | 是 (`VALID UNTIL`) | 默认无限 | -- | 是 | 7.x+ |
| DB2 | 是 (`PASSWORD ATTRIBUTES PASSWORD VALID DAYS`) | -- | -- | 是 | 9.7+ |
| SAP HANA | 是 (`MAXIMUM_PASSWORD_LIFETIME`) | 182 | 是 | 是 | 1.0 |
| Snowflake | 是 (`DAYS_TO_EXPIRY`, `PASSWORD POLICY`) | -- | -- | 是 | 2022 |
| CockroachDB | 是 (`VALID UNTIL`, 继承 PG) | 默认无限 | -- | 是 | v22.1 |
| Teradata | 是 (`PASSWORD EXPIRE`) | 90 (默认) | -- | 是 | V2R5 |
| Vertica | 是 (`PROFILE PASSWORD_LIFE_TIME`) | -- | 是 (`PASSWORD_GRACE_TIME`) | 是 | 9.0+ |
| Greenplum | 继承 PG (`VALID UNTIL`) | 默认无限 | -- | 是 | 5.x+ |
| YugabyteDB | 继承 PG | 默认无限 | -- | 是 | 2.x+ |
| TiDB | 是 (`PASSWORD EXPIRE`) | 默认 0 | -- | 是 | 6.5+ |
| OceanBase | 是 (类 MySQL) | 默认 0 | -- | 是 | 3.x+ |
| Doris | 是 (`PASSWORD EXPIRE`, 兼容 MySQL) | 默认 0 | -- | 是 | 1.2+ |
| StarRocks | 是 (`PASSWORD EXPIRE`, 兼容 MySQL) | 默认 0 | -- | 是 | 3.0+ |
| Exasol | 是 (`PASSWORD_EXPIRY_POLICY`) | -- | 是 | 是 | 6.x+ |
| Redshift | 是 (`PASSWORD VALID UNTIL`) | 默认无限 | -- | 是 | GA |
| Azure Synapse | 是 (继承 SQL Server) | 委托 | -- | 是 | GA |
| 其他云引擎 | -- (依赖 IAM token 寿命) | -- | -- | -- | -- |

### 矩阵三：密码历史 (Password History / Reuse)

| 引擎 | 历史保留数 | 重用时间间隔 | 最大重用次数 | 引入版本 |
|------|-----------|-------------|-------------|----------|
| Oracle | `PASSWORD_REUSE_MAX` | `PASSWORD_REUSE_TIME` (天) | 是 | 8i |
| SQL Server | 委托 Windows policy | 委托 Windows policy | 委托 Windows policy | 2005 |
| MySQL | `password_history` (8.0.16) | `password_reuse_interval` (天, 8.0.16) | 是 | 8.0.16 (2019) |
| MariaDB | -- (无内置) | -- | -- | -- |
| PostgreSQL | 扩展 (`credcheck.password_reuse_history`) | 扩展 | 是 | 扩展 |
| DB2 | `NUM_DB_BACKUPS` (实际为 `pwd_min_change_count`) | 是 | -- | 9.7+ |
| SAP HANA | `MINIMAL_PASSWORD_LENGTH` 等 + `LAST_USED_PASSWORDS` | 是 | -- | 1.0 |
| Snowflake | `HISTORY` 字段 (PASSWORD POLICY) | -- | -- | 2022 |
| Teradata | `PasswordReuse` (默认 5) | -- | 是 | V2R5 |
| Vertica | `PROFILE PASSWORD_REUSE_MAX` | `PASSWORD_REUSE_TIME` | 是 | 9.0+ |
| TiDB | 是 (`password_history`) | 是 (`password_reuse_interval`) | 是 | 6.5+ |
| Doris | 是 (`password_history`) | 是 | 是 | 1.2+ |
| StarRocks | 是 (`password_history`) | 是 | 是 | 3.0+ |
| Exasol | 是 | 是 | 是 | 6.x+ |
| Redshift | 是 | 是 | -- | GA |
| 其他 | -- | -- | -- | -- |

### 矩阵四：失败登录锁定 (Failed Login Lockout)

| 引擎 | 失败计数 | 锁定时间 | 自动解锁 | 解锁语法 | 引入版本 |
|------|---------|---------|---------|---------|----------|
| Oracle | `FAILED_LOGIN_ATTEMPTS` | `PASSWORD_LOCK_TIME` (天) | 是 (按时间) | `ALTER USER … ACCOUNT UNLOCK` | 8i (1999) |
| SQL Server | 委托 Windows policy | 委托 | 委托 | `ALTER LOGIN … UNLOCK` | 2005 |
| MySQL | `FAILED_LOGIN_ATTEMPTS` | `PASSWORD_LOCK_TIME` (天 / `UNBOUNDED`) | 是 | `ALTER USER … ACCOUNT UNLOCK` | 8.0.19 |
| MariaDB | -- (无内置) | -- | -- | -- | -- |
| PostgreSQL | 扩展 (`auth_delay` 仅延迟，不锁定) | 扩展 | 扩展 | 扩展 | 扩展 |
| DB2 | `RESETCOUNT` | -- | -- | -- | 9.7+ |
| SAP HANA | `MAX_FAILED_USER_LOGIN` | 是 | 是 | -- | 1.0 |
| Snowflake | `MAX_RETRIES` (PASSWORD POLICY) | `MINS_TO_UNLOCK` | 是 | `ALTER USER … SET DISABLED=FALSE` | 2022 |
| CockroachDB | -- (依赖外部) | -- | -- | -- | -- |
| Teradata | `MaxLogonAttempts` | `LockedUserExpire` | 是 | `MODIFY USER … RELEASE PASSWORD LOCK` | V2R5 |
| Vertica | `PROFILE FAILED_LOGIN_ATTEMPTS` | `PASSWORD_LOCK_TIME` | 是 | -- | 9.0+ |
| TiDB | `FAILED_LOGIN_ATTEMPTS` | `PASSWORD_LOCK_TIME` | 是 | 同 MySQL | 6.5+ |
| OceanBase | `FAILED_LOGIN_ATTEMPTS` | `PASSWORD_LOCK_TIME` | 是 | 同 Oracle | 3.x+ |
| Doris | 同 MySQL | 同 MySQL | 是 | -- | 1.2+ |
| StarRocks | 同 MySQL | 同 MySQL | 是 | -- | 3.0+ |
| Exasol | 是 | 是 | 是 | -- | 6.x+ |
| Redshift | -- | -- | -- | -- | -- |
| 其他 | -- | -- | -- | -- | -- |

### 矩阵五：首次登录强制改密 (Force Password Change)

| 引擎 | 强制改密语法 | 引入版本 | 备注 |
|------|-------------|----------|------|
| Oracle | `PASSWORD EXPIRE` (DDL 子句) | 8i | 创建用户时密码已过期，登录后必须改 |
| SQL Server | `MUST_CHANGE` | 2005 | `CREATE LOGIN … MUST_CHANGE` |
| MySQL | `PASSWORD EXPIRE` 子句 | 5.6.6 | 8.0.18 加入 `PASSWORD EXPIRE` 关键字简化 |
| MariaDB | `PASSWORD EXPIRE` | 10.4 | 兼容 MySQL |
| PostgreSQL | `VALID UNTIL 'NOW'` (变通方法) | -- | 无原生关键字，须设置过去时间 |
| DB2 | `PASSWORD EXPIRE` | -- | -- |
| SAP HANA | `FORCE FIRST PASSWORD CHANGE` (创建时) | -- | -- |
| Snowflake | `MUST_CHANGE_PASSWORD` (USER 属性) | -- | `ALTER USER alice SET MUST_CHANGE_PASSWORD = TRUE` |
| Teradata | `PASSWORD EXPIRE` | -- | -- |
| Vertica | `PASSWORD EXPIRE` | 9.0+ | -- |
| TiDB | 同 MySQL | 6.5+ | -- |
| Doris | 同 MySQL | 1.2+ | -- |
| StarRocks | 同 MySQL | 3.0+ | -- |
| Exasol | 是 | 6.x+ | -- |
| 其他 | -- | -- | -- |

### 矩阵六：密码校验函数 (Password Verify Function)

| 引擎 | 函数语法 | 引入版本 | 备注 |
|------|---------|----------|------|
| Oracle | `PASSWORD_VERIFY_FUNCTION` (PROFILE) | 8i (1999) | PL/SQL 函数自定义校验 |
| MySQL | `validate_password` 组件 (插件式) | 5.6.6 (插件), 8.0 (组件) | 不可写自定义函数 |
| MariaDB | `simple_password_check`/`cracklib_password_check` 插件 | 10.1.2 | 类似 MySQL |
| PostgreSQL | `passwordcheck` 钩子或 `credcheck` 扩展 | 8.4 (2009) | 扩展点 |
| DB2 | -- | -- | 仅参数化 |
| SAP HANA | `PASSWORD POLICY` + 自定义黑名单 | 1.0 | -- |
| Snowflake | `PASSWORD POLICY` 对象 | 2022 | 不可写自定义函数 |
| Teradata | `PASSWORD CHECK` (函数化) | V2R5 | 较简单 |
| Vertica | -- | -- | 仅参数化 |
| TiDB | `validate_password` (兼容 MySQL) | 6.5+ | -- |
| Exasol | -- | -- | 仅参数化 |
| 其他 | -- | -- | -- |

> 关键事实：仅 Oracle 与 PostgreSQL（通过 `passwordcheck` 钩子）支持开发者**编写任意 PL/SQL 或 C 函数**作为密码校验逻辑；其余引擎只允许在固定参数集内调整。

## 各引擎深入解析

### Oracle：PROFILE + PASSWORD_VERIFY_FUNCTION 的鼻祖（8i, 1999）

Oracle 8i (1999) 引入 `PROFILE` 概念，把"密码策略"作为可命名的对象与用户解绑，是数据库行业最早的完整实现。一个 PROFILE 包含资源限制（CPU、连接数）和密码策略两组参数。

```sql
-- 查看默认 profile 的密码策略参数
SELECT resource_name, limit
FROM dba_profiles
WHERE profile = 'DEFAULT' AND resource_type = 'PASSWORD';

-- 11g 之后 DEFAULT profile 的关键密码参数：
-- FAILED_LOGIN_ATTEMPTS         10
-- PASSWORD_LIFE_TIME           180
-- PASSWORD_REUSE_TIME       UNLIMITED
-- PASSWORD_REUSE_MAX        UNLIMITED
-- PASSWORD_VERIFY_FUNCTION     NULL
-- PASSWORD_LOCK_TIME             1
-- PASSWORD_GRACE_TIME            7
-- INACTIVE_ACCOUNT_TIME    UNLIMITED  (12c+)
```

#### 创建一个加固的 PROFILE

```sql
CREATE PROFILE app_profile LIMIT
    -- 失败登录锁定
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1                  -- 失败后锁定 1 天

    -- 过期与宽限期
    PASSWORD_LIFE_TIME 90                 -- 密码 90 天后过期
    PASSWORD_GRACE_TIME 7                 -- 过期后给 7 天宽限期

    -- 历史
    PASSWORD_REUSE_TIME 365               -- 密码不能在 365 天内重复
    PASSWORD_REUSE_MAX 5                  -- 最少 5 次后才能重复

    -- 复杂度（自定义 PL/SQL 函数）
    PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function

    -- 12c+ 闲置账户
    INACTIVE_ACCOUNT_TIME 90;             -- 闲置 90 天后锁定

-- 把 profile 绑给用户
CREATE USER alice IDENTIFIED BY "Strong#Passw0rd!" PROFILE app_profile;
ALTER USER bob PROFILE app_profile;
```

#### Oracle 自带的密码校验函数

Oracle 在 `$ORACLE_HOME/rdbms/admin/utlpwdmg.sql` 中提供四个内置校验函数：

| 函数 | 复杂度等级 | 引入版本 | 默认要求 |
|------|-----------|---------|---------|
| `verify_function` | 旧（基本） | 9i | 长度 4，包含字母+数字 |
| `verify_function_11G` | 11g 标准 | 11g | 长度 8，字母+数字+不重复用户名 |
| `ora12c_verify_function` | 12c 标准 | 12c | 长度 8，复杂度 |
| `ora12c_strong_verify_function` | 12c 强 | 12c | 长度 9，含大小写、数字、特殊字符，且不在常见弱密码列表 |
| `ora12c_stig_verify_function` | DoD STIG (Secure Tech Implementation Guide) | 12c | 长度 15，类别 ≥ 4，复杂度 STIG |

#### 自定义校验函数

```sql
CREATE OR REPLACE FUNCTION my_pwd_verify(
    username      VARCHAR2,
    new_password  VARCHAR2,
    old_password  VARCHAR2
) RETURN BOOLEAN AS
BEGIN
    -- 长度
    IF LENGTH(new_password) < 14 THEN
        raise_application_error(-20001, '密码必须至少 14 字符');
    END IF;

    -- 不能包含用户名
    IF UPPER(new_password) LIKE '%' || UPPER(username) || '%' THEN
        raise_application_error(-20002, '密码不能包含用户名');
    END IF;

    -- 必须包含大写、小写、数字、特殊字符
    IF NOT REGEXP_LIKE(new_password, '[A-Z]') THEN
        raise_application_error(-20003, '密码必须包含大写字母');
    END IF;
    IF NOT REGEXP_LIKE(new_password, '[a-z]') THEN
        raise_application_error(-20004, '密码必须包含小写字母');
    END IF;
    IF NOT REGEXP_LIKE(new_password, '[0-9]') THEN
        raise_application_error(-20005, '密码必须包含数字');
    END IF;
    IF NOT REGEXP_LIKE(new_password, '[^A-Za-z0-9]') THEN
        raise_application_error(-20006, '密码必须包含特殊字符');
    END IF;

    -- 与旧密码差异 ≥ 4 字符（汉明距离）
    IF UTL_RAW.LENGTH(UTL_RAW.BIT_XOR(
            UTL_RAW.CAST_TO_RAW(old_password),
            UTL_RAW.CAST_TO_RAW(new_password)
        )) < 4 THEN
        raise_application_error(-20007, '与旧密码相似度过高');
    END IF;

    RETURN TRUE;
END;
/

ALTER PROFILE app_profile LIMIT PASSWORD_VERIFY_FUNCTION my_pwd_verify;
```

#### 解锁 / 重置

```sql
-- 手动解锁
ALTER USER alice ACCOUNT UNLOCK;

-- 强制密码过期，下次登录必须改
ALTER USER alice PASSWORD EXPIRE;

-- 查询锁定状态
SELECT username, account_status, lock_date, expiry_date
FROM dba_users
WHERE username = 'ALICE';
```

#### Oracle DEFAULT profile 的演进

| Oracle 版本 | DEFAULT profile 的关键变化 |
|------------|-------------------------|
| 8i (1999) | 引入 PROFILE，DEFAULT 全部 UNLIMITED |
| 9i | 加入 `verify_function` 模板 |
| 10g | 默认仍非常松 (`FAILED_LOGIN_ATTEMPTS=10`, 其他 UNLIMITED) |
| 11g | DEFAULT.PASSWORD_LIFE_TIME 由 UNLIMITED → 180；FAILED_LOGIN_ATTEMPTS=10；引入 verify_function_11G |
| 12c | INACTIVE_ACCOUNT_TIME=UNLIMITED；引入 ora12c_strong_verify_function/ora12c_stig_verify_function |
| 18c+ | 收紧 sec_case_sensitive_logon=true (12.2 起) |
| 19c+ | 推荐使用 `ora12c_strong_verify_function` |
| 21c | 默认 `sec_max_failed_login_attempts = 3` (监听器层) |

> 注意：Oracle 12c 引入"密码版本"概念。`PASSWORD_VERSIONS` 字段 (`DBA_USERS`) 可能同时包含 `10G,11G,12C` 三种哈希。`SEC_CASE_SENSITIVE_LOGON=true` 后旧 10g 哈希不再使用，但仍存在 → 升级时需要逐个 `ALTER USER … IDENTIFIED BY values 'new'` 或重置密码强制重生成 12c verifier。

### SQL Server：CHECK_POLICY 委托 Windows（2005）

SQL Server 2005 引入 `CHECK_POLICY` 与 `CHECK_EXPIRATION` 子句。其设计哲学独特：**不重复实现密码策略，而是调用 Windows API `NetValidatePasswordPolicy()`，把决策权委托给 Windows 域 / 本地组策略**。

```sql
-- 创建一个走 Windows 策略的 SQL Login
CREATE LOGIN alice
    WITH PASSWORD = 'Strong#Passw0rd!',
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = ON,
         MUST_CHANGE;

-- 修改现有 login
ALTER LOGIN alice WITH CHECK_POLICY = ON, CHECK_EXPIRATION = ON;

-- 解锁账户（如被锁定）
ALTER LOGIN alice WITH PASSWORD = 'New#Pass!' UNLOCK;

-- 强制改密（保留密码，但要求下次登录改）
ALTER LOGIN alice WITH PASSWORD = 'Temp#Pass!' MUST_CHANGE,
                  CHECK_EXPIRATION = ON;
```

#### Windows 密码策略来源

| 平台 | 策略来源 |
|------|---------|
| 工作组 | 本地"安全策略"(secpol.msc) → 账户策略 |
| 域成员 | 域控的"默认域策略 GPO" 或 OU 级 GPO |
| Linux SQL Server (2017+) | mssql-conf 配置文件 (无 Windows policy 时使用内置默认) |

Windows 密码策略包括：
- 强制密码历史（默认 24 次）
- 密码最长使用期限（默认 42 天）
- 密码最短使用期限（默认 1 天）
- 密码最短长度（默认 8 字符；2022+ 推荐 14）
- 密码必须符合复杂性要求（开/关）
- 用可还原的加密存储密码（一般关）
- 账户锁定阈值（默认 0=不锁定，2022+ 默认 10）
- 账户锁定持续时间
- 重置账户锁定计数器

#### CHECK_POLICY=OFF 的副作用

```sql
-- CHECK_POLICY=OFF 同时关闭历史、复杂度、最短/最长
ALTER LOGIN service_account WITH CHECK_POLICY = OFF;
-- 服务账户常这样配置以避免被自动过期/锁定打扰
-- 但安全审计会标红
```

> 重要细节：在 Linux 上的 SQL Server (2017+) 没有 `NetValidatePasswordPolicy()` API，`CHECK_POLICY=ON` 退化为基础检查（长度 ≥ 8、含 3 类字符、不能包含用户名）。这是迁移到 Linux 时容易踩的坑。

#### Azure SQL / Synapse 上的 CHECK_POLICY

Azure SQL Database 内置策略不可改：长度 8-128，必须含 3 类字符（大写、小写、数字、特殊）。无 Windows 域可委托。Azure SQL Managed Instance 行为类似传统 SQL Server。Microsoft 官方推荐使用 Entra ID 认证替代 SQL Login，避免管理 SQL Login 的密码策略。

### MySQL：validate_password 组件化（5.6 → 8.0）

#### 演进历史

| 版本 | 变化 |
|------|------|
| 5.5 之前 | 无任何密码策略 |
| 5.6.6 (2012) | 引入 `validate_password` **插件**，支持长度、字符种类 |
| 5.7.1 | 加入 `password_history`、`password_reuse_interval` 起步 |
| 8.0.0 | `validate_password` 重构为 **组件** (Component)，旧插件标记弃用 |
| 8.0.16 (2019) | `password_history`、`password_reuse_interval` 作为系统变量 GA |
| 8.0.19 (2020) | `FAILED_LOGIN_ATTEMPTS`、`PASSWORD_LOCK_TIME` 子句 |
| 8.0.27 | `authentication_policy` 与多因子认证 |
| 8.0.28 | 双密码 (`RETAIN CURRENT PASSWORD`)，平滑轮换 |

#### 安装与配置 validate_password 组件

```sql
-- 8.0+ 推荐用组件
INSTALL COMPONENT 'file://component_validate_password';

-- 查看可调参数
SHOW VARIABLES LIKE 'validate_password.%';
-- validate_password.policy           MEDIUM   (LOW/MEDIUM/STRONG)
-- validate_password.length           8
-- validate_password.mixed_case_count 1
-- validate_password.number_count     1
-- validate_password.special_char_count 1
-- validate_password.dictionary_file
-- validate_password.check_user_name  ON

-- 配置 STRONG 策略
SET GLOBAL validate_password.policy = 'STRONG';
SET GLOBAL validate_password.length = 14;
SET GLOBAL validate_password.mixed_case_count = 2;
SET GLOBAL validate_password.number_count = 2;
SET GLOBAL validate_password.special_char_count = 2;
SET GLOBAL validate_password.dictionary_file = '/etc/mysql/wordlist.txt';
```

`validate_password.policy` 三档语义：

| 级别 | 长度 | 字符种类 | 字典 |
|------|------|---------|------|
| LOW | 8 | 不检查 | -- |
| MEDIUM (默认) | 8 | 大写+小写+数字+特殊 各 1 | -- |
| STRONG | 8 | 大写+小写+数字+特殊 各 1 | 检查 dictionary_file |

#### 用户级策略子句（8.0.19+）

```sql
CREATE USER 'alice'@'%'
    IDENTIFIED BY 'Strong#Passw0rd!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    PASSWORD HISTORY 5
    PASSWORD REUSE INTERVAL 180 DAY
    PASSWORD REQUIRE CURRENT
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;          -- 锁定 1 天，UNBOUNDED 永久锁定

-- 修改现有用户
ALTER USER 'bob'@'%'
    PASSWORD EXPIRE                  -- 立即过期，下次登录必须改
    PASSWORD HISTORY DEFAULT          -- 使用全局 password_history 设置
    FAILED_LOGIN_ATTEMPTS 3;

-- 解锁
ALTER USER 'alice'@'%' ACCOUNT UNLOCK;

-- 双密码（平滑轮换）8.0.14+
ALTER USER 'service'@'%' IDENTIFIED BY 'NewPass#1' RETAIN CURRENT PASSWORD;
-- 此时旧密码与新密码都可登录
-- 应用更新配置后：
ALTER USER 'service'@'%' DISCARD OLD PASSWORD;
```

#### 全局变量

```ini
[mysqld]
# 全局历史与重用
password_history = 6
password_reuse_interval = 365         # days

# 全局过期
default_password_lifetime = 90         # days; 0 = 永不过期

# 全局失败锁定（覆盖默认无）
# 通过 CREATE USER 子句逐用户设置；无全局参数
```

#### MUST_CHANGE 的演进

8.0.18 (2019) 引入了简化的 `PASSWORD EXPIRE` 子句作为 `MUST_CHANGE` 关键字的等价：

```sql
-- 8.0.18 之前：通过 INTERVAL 0 模拟
ALTER USER 'alice'@'%' PASSWORD EXPIRE INTERVAL 0 DAY;

-- 8.0.18+：明确语义
ALTER USER 'alice'@'%' PASSWORD EXPIRE;
```

登录后会看到 ER_MUST_CHANGE_PASSWORD (1820) 错误，必须执行 `ALTER USER USER() IDENTIFIED BY '…'` 后才能执行其他语句。

#### 5.6/5.7 老语法对比

```sql
-- 5.6 插件方式（已弃用，但仍在 5.7 默认）
INSTALL PLUGIN validate_password SONAME 'validate_password.so';
SET GLOBAL validate_password_policy = STRONG;   -- 注意 _ 而非 .

-- 5.7 用户级密码过期
ALTER USER 'alice'@'%' PASSWORD EXPIRE;
ALTER USER 'alice'@'%' PASSWORD EXPIRE NEVER;
ALTER USER 'alice'@'%' PASSWORD EXPIRE INTERVAL 90 DAY;
```

迁移建议：8.0.4+ 后在新部署上**只**启用组件，禁用插件；老库升级到 8.0 时需要 `UNINSTALL PLUGIN validate_password` → `INSTALL COMPONENT`。

### MariaDB：simple_password_check / cracklib_password_check（10.1.2+）

MariaDB 与 MySQL 在密码策略上分道扬镳。它没有跟随 `validate_password` 组件，而是提供两个独立插件：

```sql
-- 简单检查
INSTALL SONAME 'simple_password_check';
SET GLOBAL simple_password_check_minimal_length = 14;
SET GLOBAL simple_password_check_digits = 2;
SET GLOBAL simple_password_check_letters_same_case = 2;
SET GLOBAL simple_password_check_other_characters = 2;

-- 字典检查（需要安装 cracklib）
INSTALL SONAME 'cracklib_password_check';
SET GLOBAL cracklib_password_check_dictionary = '/usr/share/cracklib/pw_dict';
```

历史保留与重用间隔在 MariaDB 没有直接 GA 的等价物（10.4 加入了 `password_reuse_check` 插件，但功能受限；10.5+ 仍未提供 password_history 数）。失败锁定也无原生支持，社区一般通过 `pam_tally2` (PAM 模块) 在 OS 层处理。

```sql
-- MariaDB 10.4+ 用户级过期
CREATE USER 'alice'@'%' IDENTIFIED BY 'Pass!'
    PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'alice'@'%' PASSWORD EXPIRE;
```

### PostgreSQL：刻意保持极简，全靠扩展（8.4+）

PostgreSQL 核心团队的设计哲学是"密码策略不属于数据库内核"，因此官方不内置任何长度、过期、历史、锁定能力。社区通过 contrib 与第三方扩展提供能力。

#### 内核仅有的两个工具

```sql
-- 密码"过期日期"（无周期）
ALTER USER alice VALID UNTIL '2026-12-31';

-- "立即过期"（变通）
ALTER USER alice VALID UNTIL 'now';

-- 永不过期
ALTER USER alice VALID UNTIL 'infinity';
```

`pg_hba.conf` 没有失败锁定参数；`auth_delay` contrib 在认证失败时仅引入随机延迟，并不会自动锁定账户。要实现真正的锁定，需要应用层 / fail2ban / pgaudit 后处理。

#### passwordcheck contrib 模块（8.4, 2009）

`passwordcheck` 是 PostgreSQL contrib 包附带的样例钩子：

```sql
-- 在 postgresql.conf 中加载
shared_preload_libraries = 'passwordcheck'

-- 然后重启 PostgreSQL
```

`passwordcheck` 的 C 实现非常简单：长度 ≥ 8、不与用户名相等、必须包含字母与非字母字符。**它不可配置**，不接受任何 GUC 参数。要更复杂的策略只能 fork 这个 contrib。许多发行版（Debian、CentOS）内置了魔改版，但仍非常基础。

#### credcheck 扩展（社区项目，非 contrib）

[credcheck](https://github.com/MigOpsRepos/credcheck) 是 MigOps 维护的开源扩展，把密码策略的"参数化"补到 PostgreSQL：

```sql
-- 安装
CREATE EXTENSION credcheck;

-- 配置（通过 GUC）
ALTER SYSTEM SET credcheck.username_min_length = 4;
ALTER SYSTEM SET credcheck.username_min_special = 0;
ALTER SYSTEM SET credcheck.username_contain_password = 'off';
ALTER SYSTEM SET credcheck.password_min_length = 14;
ALTER SYSTEM SET credcheck.password_min_special = 2;
ALTER SYSTEM SET credcheck.password_min_upper = 2;
ALTER SYSTEM SET credcheck.password_min_lower = 2;
ALTER SYSTEM SET credcheck.password_min_digit = 2;
ALTER SYSTEM SET credcheck.password_min_repeat = 3;       -- 同一字符最多连续 3 次
ALTER SYSTEM SET credcheck.password_contain_username = 'off';
ALTER SYSTEM SET credcheck.password_valid_until = '90 days';

-- 历史与锁定（credcheck 1.x+）
ALTER SYSTEM SET credcheck.password_reuse_history = 5;
ALTER SYSTEM SET credcheck.password_reuse_interval = 365;
ALTER SYSTEM SET credcheck.max_auth_failure = 5;
ALTER SYSTEM SET credcheck.reset_superuser = 'off';
SELECT pg_reload_conf();
```

#### check_password / pg_password 等其他扩展

EnterpriseDB Advanced Server 提供 `EDB_PASSWORD_VERIFY_FUNCTION`（仿 Oracle PROFILE 语法）；Citus、Yugabyte、Greenplum、TimescaleDB 通常推荐 `passwordcheck` 或 `credcheck`，少数云供应商（AWS RDS for Postgres）禁用 `shared_preload_libraries` 加载第三方扩展，需要走 RDS 提供的 `rds.force_ssl` + IAM 等替代方案。

#### Greenplum gp_passwordcheck

Greenplum 6+ 自带 `gp_passwordcheck` 钩子（替代 contrib），可配置：

```sql
gp_passwordcheck.minimum_password_length = 14
gp_passwordcheck.special_chars_required = 1
gp_passwordcheck.numbers_required = 1
gp_passwordcheck.uppercase_required = 1
gp_passwordcheck.lowercase_required = 1
```

#### 为什么 PostgreSQL 至今不内置？

- **设计哲学**：核心团队认为"密码策略属于身份提供者，不属于数据库内核"。
- **替代路径**：推荐外部 LDAP / Kerberos / SCRAM 通道，由 IdP 强制策略。
- **MFA 替代轮换**：NIST SP 800-63B 的趋势让 PG 不愿"为合规而合规"地加上 90 天过期。
- **风险**：如果合规审计要求"内置密码策略"（如 PCI-DSS 4.0 8.3.5），PG 用户必须通过 `credcheck` 或 EDB 满足，否则直接失分。

### CockroachDB：v22.1 起逐步引入

CockroachDB v22.1 (2022) 加入最少长度参数：

```sql
SET CLUSTER SETTING server.user_login.min_password_length = 14;
SET CLUSTER SETTING server.user_login.password_hashes.default_cost = 10;

-- v22.2+ SCRAM-SHA-256 哈希
SET CLUSTER SETTING server.user_login.password_encryption = 'scram-sha-256';
```

CRDB 仍依赖外部 IdP（OIDC / GSSAPI / LDAP）做完整策略，原因与 PG 类似（云原生设计倾向"无密码"）。

### MariaDB（PASSWORD ATTRIBUTES）— 简单策略

DB2 在 9.7 起引入 `PASSWORD ATTRIBUTES` 配置：

```sql
UPDATE DBMCFG USING PASSWORD_LIFE_TIME 90;     -- DB2 LUW 实际为 dbm cfg
db2 update dbm cfg using PASSWORD_LIFE_TIME 90
db2 update db cfg using NUM_DB_BACKUPS 5
```

DB2 的密码策略在数据库管理器配置中（`db2 get dbm cfg`），关键参数：

```
PASSWORD VALID DAYS              = 60
PASSWORD MIN LENGTH               = 8
NUM_DB_BACKUPS (实际为历史)         = 5
PASSWORD LOCK TIME (锁定时间)        = 30
FAILED_ATTEMPTS (失败次数)            = 5
```

DB2 z/OS 用 RACF / ACF2 / TopSecret 做密码策略，而非数据库内置。

### SAP HANA：PASSWORD POLICY 数据字典

SAP HANA 把密码策略放在系统视图，通过 `ALTER SYSTEM` 修改：

```sql
-- 完整策略一览
SELECT * FROM SYS.M_PASSWORD_POLICY;

-- 修改策略
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'minimal_password_length') = '14';
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'last_used_passwords') = '5';
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'password_lock_time') = '60';
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'maximum_invalid_connect_attempts') = '5';
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'maximum_password_lifetime') = '90';
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'force_first_password_change') = 'true';
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('password policy', 'password_layout') = 'A1a!';   -- 复杂度模板
```

`password_layout` 是 SAP HANA 独有的"模板字符串"机制：`A1a!` 表示至少 1 大写、1 小写、1 数字、1 特殊字符。

### Snowflake：PASSWORD POLICY 对象（2022+）

Snowflake 早期只有简单的"长度 ≥ 8"内建检查；2022 年正式引入 `PASSWORD POLICY` 对象，把策略对象化。

```sql
CREATE PASSWORD POLICY enterprise_pp
    PASSWORD_MIN_LENGTH = 14
    PASSWORD_MAX_LENGTH = 128
    PASSWORD_MIN_UPPER_CASE_CHARS = 2
    PASSWORD_MIN_LOWER_CASE_CHARS = 2
    PASSWORD_MIN_NUMERIC_CHARS = 2
    PASSWORD_MIN_SPECIAL_CHARS = 2
    PASSWORD_MIN_AGE_DAYS = 1                  -- 至少 1 天后才能再次改
    PASSWORD_MAX_AGE_DAYS = 90                 -- 90 天过期
    PASSWORD_MAX_RETRIES = 5                    -- 失败 5 次后锁定
    PASSWORD_LOCKOUT_TIME_MINS = 15             -- 锁定 15 分钟
    PASSWORD_HISTORY = 5                        -- 历史 5 个
    COMMENT = '企业级密码策略 - PCI-DSS 4.0';

-- 应用到账号或用户
ALTER ACCOUNT SET PASSWORD POLICY enterprise_pp;
ALTER USER alice SET PASSWORD POLICY enterprise_pp;

-- 强制下次登录改密
ALTER USER alice SET MUST_CHANGE_PASSWORD = TRUE;

-- 解锁（实际为禁用 → 启用）
ALTER USER alice SET DISABLED = FALSE;
```

Snowflake 自 2024 年 11 月起强制企业账户启用 MFA；2025 年开始新租户默认禁用纯密码登录，密码策略仅用于"最后的回退路径"。

### Teradata（V2R5 起）

Teradata 把密码策略放在 `DBC.SysSecDefaults` 系统表：

```sql
-- 查看当前默认
SELECT * FROM DBC.SysSecDefaults;

-- 修改全局策略
UPDATE DBC.SysSecDefaults SET
    ExpirePassword = 90,
    PasswordMinChar = 14,
    PasswordDigits = 'r',          -- r=required
    PasswordSpecChar = 'r',
    PasswordRestrictWords = 'y',
    MaxLogonAttempts = 5,
    LockedUserExpire = 30,         -- 30 分钟解锁
    PasswordReuse = 5;
```

Teradata 16.20+ 标配 LDAP/Kerberos，17.20+ 加入 OIDC。本地数据库账户的密码策略仍在 `DBC.SysSecDefaults`。

### Vertica（PROFILE 仿 Oracle）

```sql
CREATE PROFILE app_profile LIMIT
    PASSWORD_LIFE_TIME 90
    PASSWORD_GRACE_TIME 7
    PASSWORD_REUSE_TIME 365
    PASSWORD_REUSE_MAX 5
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1
    PASSWORD_MIN_LENGTH 14
    PASSWORD_MAX_LENGTH 128
    PASSWORD_MIN_LETTERS 2
    PASSWORD_MIN_UPPERCASE_LETTERS 2
    PASSWORD_MIN_LOWERCASE_LETTERS 2
    PASSWORD_MIN_DIGITS 2
    PASSWORD_MIN_SYMBOLS 2;

ALTER USER alice PROFILE app_profile;
```

Vertica 的 PROFILE 借鉴 Oracle，但比 Oracle 更细致：直接在 PROFILE 上声明长度与字符种类。

### TiDB / OceanBase / Doris / StarRocks（兼容 MySQL）

兼容 MySQL 协议的国产/分布式 NewSQL 引擎几乎逐字复制了 MySQL 的密码策略语法：

```sql
-- TiDB 6.5+ / Doris 1.2+ / StarRocks 3.0+
CREATE USER 'alice'@'%'
    IDENTIFIED BY 'Strong#Pass!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    PASSWORD HISTORY 5
    PASSWORD REUSE INTERVAL 180 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
```

OceanBase 双模式：
- MySQL 模式：上面的语法
- Oracle 模式：`CREATE PROFILE`、`PASSWORD_VERIFY_FUNCTION` 完全仿 Oracle

### Exasol（PASSWORD_SECURITY_POLICY）

```sql
ALTER SYSTEM SET PASSWORD_SECURITY_POLICY =
    'MIN_LENGTH=14:MIN_LOWER_CASE=2:MIN_UPPER_CASE=2:MIN_NUMERIC=2:'
    || 'MIN_SPECIAL=2:MIN_PASSWORD_AGE=1:PASSWORD_EXPIRY=90:'
    || 'REUSABLE_AFTER=365:HISTORY_LENGTH=5';

ALTER SYSTEM SET PASSWORD_LOGIN_FAILURE_LIMIT = 5;
ALTER SYSTEM SET PASSWORD_LOGIN_LOCK_TIME = 30;     -- 分钟
```

### Redshift

Redshift 通过若干 GUC 参数控制：

```sql
-- 集群级参数组
password_check_complex = on
password_check_min_length = 14
password_check_min_lower = 2
password_check_min_upper = 2
password_check_min_numbers = 2
password_check_min_special = 2

-- 用户级过期
ALTER USER alice PASSWORD VALID UNTIL '2026-12-31';
```

Redshift 推荐 IAM Auth 替代密码策略；`GetClusterCredentials` 动态生成 15 分钟 token，是更现代的路径。

### ClickHouse、Trino、Presto 等分析引擎

| 引擎 | 现状 |
|------|------|
| ClickHouse | RBAC 完整，但无内置密码策略；通过 `<ldap>` `<kerberos>` 委托外部 |
| Trino / Presto | `file authenticator` 仅做哈希校验，无策略；推荐 LDAP/OAuth2 |
| Spark SQL | 委托外部（Hive Metastore + Kerberos / LDAP） |
| Hive / Impala | 委托 Hadoop SASL/Kerberos；Apache Ranger 提供策略 |
| Flink SQL | 计算引擎，无内置认证 |

> 关键洞察：分析引擎普遍采用"密码策略 = 别人家的事"路线。这与它们"无状态计算 + 外部 metastore"的架构一致。生产部署里靠 Apache Ranger / Privacera / Immuta 做集中策略管理。

### 嵌入式与轻量数据库

| 引擎 | 现状 |
|------|------|
| SQLite | 无用户系统，密码策略不适用 |
| DuckDB | 嵌入式，无远程认证 |
| H2 / HSQLDB / Derby | 内置简单密码哈希，无策略 |
| Firebird 3.0+ | SRP-256 挑战-响应，无策略；4.x 加入 X.509 |

## Oracle PROFILE 深度剖析

PROFILE 是 Oracle 自 8i 以来"密码策略"的核心抽象，至 23c 仍然保持架构。值得展开。

### DEFAULT profile 在 19c 的具体值

```sql
-- 在 19c 上跑
SELECT resource_name, limit
FROM dba_profiles
WHERE profile = 'DEFAULT' AND resource_type = 'PASSWORD'
ORDER BY resource_name;

/*
RESOURCE_NAME                    LIMIT
-------------------------------- ----------
COMPOSITE_LIMIT                  UNLIMITED
CONNECT_TIME                     UNLIMITED
CPU_PER_CALL                     UNLIMITED
CPU_PER_SESSION                  UNLIMITED
FAILED_LOGIN_ATTEMPTS            10
IDLE_TIME                        UNLIMITED
INACTIVE_ACCOUNT_TIME            UNLIMITED
LOGICAL_READS_PER_CALL           UNLIMITED
LOGICAL_READS_PER_SESSION        UNLIMITED
PASSWORD_GRACE_TIME              7
PASSWORD_LIFE_TIME               180
PASSWORD_LOCK_TIME               1
PASSWORD_REUSE_MAX               UNLIMITED
PASSWORD_REUSE_TIME              UNLIMITED
PASSWORD_VERIFY_FUNCTION         NULL
PRIVATE_SGA                      UNLIMITED
SESSIONS_PER_USER                UNLIMITED
*/
```

### CIS Oracle 19c Benchmark 推荐配置

```sql
-- 1) 失败登录次数：CIS 推荐 ≤ 5 (满足 PCI-DSS 4.0)
ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS 5;

-- 2) 锁定时间：CIS 推荐 ≥ 1 天，PCI-DSS 推荐 ≥ 30 分钟
ALTER PROFILE DEFAULT LIMIT PASSWORD_LOCK_TIME 1;

-- 3) 密码生命周期：CIS 推荐 90 天 (PCI-DSS 4.0 也允许动态分析替代)
ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME 90;

-- 4) 历史
ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME 365;
ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_MAX 5;

-- 5) 校验函数
ALTER PROFILE DEFAULT LIMIT
    PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function;

-- 6) 闲置账户（12c+）
ALTER PROFILE DEFAULT LIMIT INACTIVE_ACCOUNT_TIME 90;

-- 7) 宽限期
ALTER PROFILE DEFAULT LIMIT PASSWORD_GRACE_TIME 7;
```

### 为某类账户创建专用 profile

```sql
-- 服务账户：不过期，但锁定严格
CREATE PROFILE service_profile LIMIT
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME UNLIMITED          -- 必须人工解锁
    PASSWORD_LIFE_TIME UNLIMITED
    PASSWORD_REUSE_MAX 99
    PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function;

-- 高权限 (DBA) 账户：最严格
CREATE PROFILE dba_profile LIMIT
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME 1
    PASSWORD_LIFE_TIME 60
    PASSWORD_GRACE_TIME 3
    PASSWORD_REUSE_TIME 730                  -- 2 年
    PASSWORD_REUSE_MAX 10
    PASSWORD_VERIFY_FUNCTION ora12c_stig_verify_function;   -- DoD 级
```

### 查看用户的 profile

```sql
SELECT username, profile, account_status, expiry_date, lock_date
FROM dba_users
WHERE username NOT LIKE 'SYS%';
```

### 锁定 / 解锁 / 过期管理

```sql
-- 锁定
ALTER USER alice ACCOUNT LOCK;

-- 解锁
ALTER USER alice ACCOUNT UNLOCK;

-- 强制过期
ALTER USER alice PASSWORD EXPIRE;

-- 查看锁定状态原因
SELECT username, account_status, lock_date, expiry_date
FROM dba_users WHERE username = 'ALICE';
/*
ACCOUNT_STATUS 可能取值：
  OPEN
  LOCKED
  EXPIRED
  EXPIRED & LOCKED
  EXPIRED(GRACE)
  LOCKED(TIMED)
  EXPIRED & LOCKED(TIMED)
*/
```

### Pluggable Database (PDB) 中的 PROFILE

12c+ 的 multi-tenant 架构里，CDB 与每个 PDB 各自独立维护 profile：

```sql
-- 切换到 PDB
ALTER SESSION SET CONTAINER = pdb1;

-- 在 PDB 中创建 profile（仅本 PDB 生效）
CREATE PROFILE pdb_profile LIMIT
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LIFE_TIME 90;

-- 公共用户 (C##) 必须在 CDB 创建公共 profile
ALTER SESSION SET CONTAINER = CDB$ROOT;
CREATE PROFILE c##common_profile LIMIT
    FAILED_LOGIN_ATTEMPTS 5
    CONTAINER = ALL;
```

## MySQL validate_password 完整配置

### 组件 vs 插件的关键差异

| 维度 | 插件 (5.6/5.7) | 组件 (8.0+) |
|------|---------------|-------------|
| 加载方式 | `INSTALL PLUGIN ... SONAME` | `INSTALL COMPONENT 'file://...'` |
| 系统变量名 | `validate_password_xxx` | `validate_password.xxx` |
| 卸载 | `UNINSTALL PLUGIN` | `UNINSTALL COMPONENT` |
| 注册位置 | `mysql.plugin` | `mysql.component` |
| 功能 | 相同 | 相同 |

8.0+ 推荐组件方式，未来版本可能完全移除插件路径。

### 完整参数表（组件方式）

| 参数 | 默认值 | 取值范围 | 说明 |
|------|-------|---------|------|
| `validate_password.policy` | MEDIUM | LOW/MEDIUM/STRONG | 总开关 |
| `validate_password.length` | 8 | 0-2147483647 | 最少长度（不会被覆盖到 4 以下） |
| `validate_password.mixed_case_count` | 1 | 0-? | MEDIUM/STRONG 时大写+小写各 N 个 |
| `validate_password.number_count` | 1 | 0-? | MEDIUM/STRONG 时数字 N 个 |
| `validate_password.special_char_count` | 1 | 0-? | MEDIUM/STRONG 时特殊字符 N 个 |
| `validate_password.dictionary_file` | (空) | 路径 | STRONG 时启用，每行一个禁用词 |
| `validate_password.check_user_name` | ON | ON/OFF | 不允许密码包含用户名 |
| `validate_password.changed_characters_percentage` | 0 | 0-100 | 改密时新旧密码差异百分比 (8.0.25+) |

### 实际配置示例（PCI-DSS 4.0 合规）

```sql
INSTALL COMPONENT 'file://component_validate_password';

SET PERSIST validate_password.policy = 'STRONG';
SET PERSIST validate_password.length = 14;
SET PERSIST validate_password.mixed_case_count = 2;
SET PERSIST validate_password.number_count = 2;
SET PERSIST validate_password.special_char_count = 2;
SET PERSIST validate_password.dictionary_file = '/etc/mysql/wordlist.txt';
SET PERSIST validate_password.check_user_name = ON;
SET PERSIST validate_password.changed_characters_percentage = 30;

-- 全局历史与重用
SET PERSIST password_history = 5;
SET PERSIST password_reuse_interval = 365;
SET PERSIST default_password_lifetime = 90;
SET PERSIST require_secure_transport = ON;       -- 强制 TLS
```

`SET PERSIST` 在 8.0+ 把变量持久化到 `mysqld-auto.cnf`，重启后保留。

### 字典文件示例

```text
# /etc/mysql/wordlist.txt
123456
password
qwerty
admin
welcome
letmein
mycompany
internalapp
```

`validate_password` 仅做"密码不能包含字典中的整词或子串（取决于实现）"的检查；要更智能的语义匹配（如 Levenshtein 距离），需要自己写组件。

### 测试策略生效

```sql
-- 用 VALIDATE_PASSWORD_STRENGTH() 函数估测密码
SELECT VALIDATE_PASSWORD_STRENGTH('Password123!');
-- 返回 0-100 整数
-- 0  = 太短
-- 25 = 弱
-- 50 = 中
-- 75 = 强
-- 100 = 极强
```

### 与 MUST_CHANGE 的交互

8.0.18+ 的 `PASSWORD EXPIRE` 让账户立即标记为 must_change：

```sql
ALTER USER 'alice'@'%' PASSWORD EXPIRE;
```

下次登录时 MySQL 返回 ER_MUST_CHANGE_PASSWORD (1820)，应用必须先发送 `ALTER USER USER() IDENTIFIED BY '...'`，否则其他语句一律拒绝。这与 SQL Server 的 `MUST_CHANGE` 语义完全一致，是 PCI-DSS 8.3.6（"账户初次创建必须强制改密"）的关键机制。

### 双密码与平滑轮换（8.0.14+）

```sql
-- 旧密码：'old_pass'
ALTER USER 'service'@'%' IDENTIFIED BY 'new_pass' RETAIN CURRENT PASSWORD;
-- 此时旧、新密码都可登录

-- 应用配置滚动更新完成后
ALTER USER 'service'@'%' DISCARD OLD PASSWORD;
```

这避免了"改密 → 重启所有应用"的窗口期，对 24/7 系统至关重要。Snowflake、Oracle 21c、PostgreSQL 16+ 都引入了类似机制（PG 用 PASSWORD 与 ENCRYPTED PASSWORD 两个字段实现）。

## 密码策略与外部 IdP 的协同

### 三种主流分工模型

| 模型 | 谁存策略 | 谁强制 | 适用场景 |
|------|---------|--------|---------|
| 数据库内置 | 数据库 | 数据库 | 隔离环境、合规审计要求"数据库本地策略" |
| 委托 OS / Windows | 操作系统 | 数据库验证密码时调 OS API | SQL Server 默认；Linux 下 PAM |
| 委托外部 IdP | LDAP / Kerberos / OIDC | IdP | 现代企业架构 |

### LDAP 密码策略示例（OpenLDAP ppolicy 覆写）

```ldif
# 默认密码策略 entry
dn: cn=default,ou=policies,dc=example,dc=com
objectClass: pwdPolicy
objectClass: top
cn: default
pwdAttribute: userPassword
pwdMaxAge: 7776000             # 90 days
pwdMinLength: 14
pwdInHistory: 5
pwdLockout: TRUE
pwdMaxFailure: 5
pwdLockoutDuration: 1800       # 30 minutes
pwdMustChange: TRUE
pwdExpireWarning: 604800       # 7 days
pwdMinAge: 86400               # 1 day
pwdAllowUserChange: TRUE
pwdSafeModify: TRUE
```

数据库（PostgreSQL/MySQL/Oracle）通过 LDAP `simple bind` 让 LDAP 服务器执行策略检查；账户被锁定时返回 LDAP_INVALID_CREDENTIALS + ppolicy 控制响应。

### Kerberos AS-REQ 时的 KDC policy

KDC 在签发 TGT 时检查：
- 密码已过期？返回 KRB_AP_ERR_PASSWORD_EXPIRED → 客户端被引导到 kpasswd 改密
- 失败计数超限？返回 KRB_AP_ERR_REPEAT
- 账户被锁？拒绝

数据库（PG/Oracle/SQL Server with Kerberos）只看 KDC 的最终签发结果，不直接检查策略。

## 密码哈希与策略的关系

### 哈希算法本身不是策略，但会被策略 implicitly 影响

合规框架（NIST SP 800-131A）禁止用 MD5、SHA-1 做认证。这与"密码策略"是两件事，但常常被一起讨论：

| 引擎 | 默认哈希算法 | 是否合规 |
|------|------------|---------|
| PostgreSQL 14+ | SCRAM-SHA-256, 4096 iterations | 是 |
| MySQL 8.0+ | caching_sha2_password (SHA-256, 5000 iterations) | 是 |
| Oracle 12c+ | PBKDF2-SHA-512, 4096 iterations | 是 |
| SQL Server 2012+ | PBKDF2-SHA-512 | 是 |
| MariaDB 10.4+ ed25519 | 公钥签名 | 是 |
| MongoDB 4.0+ | SCRAM-SHA-256 | 是 |
| Redis 7+ | SCRAM-SHA-256 | 是 |
| Firebird 3+ | SRP-256 | 是 |
| MySQL 5.7 mysql_native_password | SHA1 双轮 | 否 (NIST 禁用) |
| Oracle 10g | DES + SHA1 | 否 |
| PostgreSQL md5 | md5(pwd + user) | 否 |

升级哈希算法是密码策略实施的"前置条件"：哈希弱时，再严的策略也只是延缓而非消除暴破。

### Pepper 与外部秘钥

NIST 推荐"在哈希基础上加一个全局秘钥（Pepper）"提升安全：

```python
# 伪代码
stored = hmac_sha256(global_pepper, scram_sha256(password, salt))
```

但主流数据库都没实现 Pepper 机制；如果有，只是商业版（如 Oracle TDE 集成 HSM 派生 Pepper）。

## 设计争议与权衡

### 1. 周期性轮换的攻防价值

NIST SP 800-63B 在 2017 年明确反对周期性轮换。论据：
- 实证研究：用户在被强制改密时倾向用 `Pass1!` → `Pass2!` → `Pass3!` 这种最小变化。
- 攻击者通常拿到密码哈希后**当场**爆破或字典攻击，不会等 90 天。
- 真正有用的是"事件驱动"：检测到泄露立即重置。

但是 PCI-DSS 4.0、HIPAA、ISO 27001、GDPR 实施细则都要求 90 天周期。结果就是企业 DBA 必须**两手都抓**：让数据库支持周期轮换（合规需要），同时部署"暗网监控 + 立即重置"的事件驱动机制。

### 2. 密码黑名单 vs 字典攻击

`validate_password.dictionary_file` 与 `passwordcheck` 都允许加载词表，但实际执行的是"密码不能等于/包含字典中的词"。这与"密码哈希被拿到后能否快速暴破字典"是两个问题。前者拒绝弱密码，后者考验哈希算法的迭代次数。两者同时做才有效。

参考词表：
- `rockyou.txt`（1400 万条，2009 年泄露）
- `SecLists/Passwords/Common-Credentials/10-million-password-list-top-1000000.txt`
- `HaveIBeenPwned NTLM hashes`（按使用频次排序）

### 3. 用户名相关性检查的副作用

`validate_password.check_user_name = ON` 拒绝包含用户名的密码。这看似合理但在某些场景产生问题：
- 长用户名（`alice.smith.engineering@corp.com`）触发误判
- 自动生成密码（如 `gen_random_uuid()::text`）偶然包含用户名子串

实际部署常关闭这项，转而依赖更强的字符种类检查。

### 4. 密码历史的隐私问题

`PASSWORD HISTORY 5` 要求服务端存储最近 5 次密码哈希。这意味着：
- 一旦数据库被入侵，攻击者拿到 5 倍数量的哈希用于关联爆破。
- 用户可能在 5 个不同系统都使用过同一密码，泄露 1 处波及所有。

缓解：保证每个历史哈希的 salt 独立 + iteration 高 + 严格访问 `mysql.password_history` 表。

### 5. 失败锁定的 DoS 风险

```
攻击者只要在登录页面尝试 5 次错误密码，就能锁定任何账户，造成拒绝服务。
```

缓解：
- 锁定**用户名 + 客户端 IP** 而非仅用户名（PG `auth_delay` 走这个思路，但不锁，仅延迟）。
- 锁定时间随失败次数指数递增（Snowflake/SQL Server 默认线性递增）。
- 给"已知良好的客户端 IP"白名单（fail2ban allowlist）。

### 6. 闲置账户清理（12c+ 的 INACTIVE_ACCOUNT_TIME）

合规审计经常发现"3 年没登录的账户仍 active"。Oracle 12c 引入 `INACTIVE_ACCOUNT_TIME`：

```sql
ALTER PROFILE DEFAULT LIMIT INACTIVE_ACCOUNT_TIME 90;
-- 90 天没有登录的账户会被自动锁定
```

PostgreSQL/MySQL 没有此特性；CIS Benchmarks 推荐通过定期审计 `pg_stat_activity` / `INFORMATION_SCHEMA.PROCESSLIST` 历史 + cron 脚本手动锁定。

## 引擎开发者实现建议

### 1. 把策略对象化

不要把"长度 ≥ 14"当作硬编码常量。设计成命名对象（PROFILE / PASSWORD POLICY），允许：
- 不同账户类型适用不同策略（DBA、应用、服务账户）
- 集中查询当前生效策略（`SELECT * FROM SYS.PASSWORD_POLICIES`）
- 审计 ALTER PROFILE 事件

### 2. 提供"评分函数"

`VALIDATE_PASSWORD_STRENGTH()`（MySQL）让客户端能在用户输入时即时反馈强度。这是 UX 最大的改进点，避免用户提交后才被拒。

### 3. 哈希迁移与策略升级解耦

策略升级（"长度从 8 变 14"）不应导致旧密码失效；应：
- 已存在的密码继续可用直到下次修改
- 仅在"创建用户" / "改密" 时检查策略
- 提供"策略合规报告"列出哪些用户密码不符合

### 4. 失败锁定的事件钩子

锁定/解锁时发出事件（系统视图 + 审计日志），让监控系统能主动报警：
```
事件类型 = ACCOUNT_LOCKED
原因     = FAILED_LOGIN_ATTEMPTS_EXCEEDED
用户     = alice
来源 IP  = 203.0.113.5
计数     = 5
锁定到   = 2026-04-28 12:30:00
```

### 5. 与 LDAP / Kerberos 的明确分工

把"本地策略"与"委托给 IdP" 做成可独立开关的配置：
- 本地账户走本地策略
- LDAP 同步用户走 LDAP ppolicy
- Kerberos 用户走 KDC policy

不要让"启用 LDAP 后本地策略全部失效"——服务账户、紧急账户仍需要本地策略保护。

### 6. 双密码 / 平滑轮换

主流模式：
```
ALTER USER alice IDENTIFIED BY 'new' RETAIN CURRENT PASSWORD;  -- MySQL
ALTER USER alice WITH NEW_PASSWORD 'new', GRACE 7 DAYS;        -- 假想标准
```

把"密码轮换不停机"作为一等公民，不让 DBA 必须靠"应用层灰度"过渡。

### 7. 密码强度的语义检查

NIST 推荐的"语义检查"包括：
- 是否在 HaveIBeenPwned 数据库中（k-Anonymity API）
- 是否是字典中的常见词
- 是否是键盘相邻序列（`qwerty`、`asdf`）
- 是否是日期格式（`19900101`、`Jan2026`）
- 是否是用户邮箱前缀

这些都是简单参数化检查覆盖不到的。Oracle 的 `PASSWORD_VERIFY_FUNCTION` PL/SQL 是目前最灵活的扩展点；其他引擎应考虑暴露类似钩子。

### 8. 测试要点

- **边界**：长度 = 阈值-1 / 阈值 / 阈值+1 都应被正确拒绝/接受
- **字符集**：UTF-8 多字节、emoji、控制字符、零宽字符
- **大小写**：用户名 / 密码大小写敏感性是否一致（Oracle 12.2+ 默认敏感）
- **历史竞态**：高并发改密时历史不能出现"穿越"（A 改成 X，B 同时改成 X 都通过）
- **锁定恢复**：自动解锁的时间精度与时区影响
- **MUST_CHANGE**：登录后第一条非改密语句必须被拒绝
- **双密码**：同时持有两个密码时，新旧密码登录都成功；DISCARD 后旧密码失败

## 关键发现

1. **没有 SQL 标准，但事实标准已收敛在六个维度**。复杂度、过期、历史、失败锁定、首次改密、校验函数——47 个引擎里有 18 个完整覆盖这六个维度，其余靠外部 IdP 补齐。引擎选型时把这六项作为必检栏。

2. **Oracle PROFILE 是 25 年前的设计，仍是行业标杆**。1999 年 8i 引入的 `PROFILE + PASSWORD_VERIFY_FUNCTION` 至今没有被超越——把策略对象化、用 PL/SQL 函数实现任意校验逻辑、与用户解绑这三点的组合，没有任何后来者完全复制。

3. **SQL Server 选择"委托 Windows"是产品策略而非技术限制**。`CHECK_POLICY=ON` 通过 `NetValidatePasswordPolicy()` 调 OS API。优势：与企业域策略统一；劣势：Linux 上的 SQL Server (2017+) 无 Windows API，退化为基础检查，迁移时是常被忽略的坑。

4. **MySQL 的 validate_password 经历了"插件 → 组件"的架构升级**。5.6 (2012) 插件 → 8.0 (2018) 组件。8.0.16 (2019) 加入 `password_history`/`password_reuse_interval`；8.0.18 (2019) 简化 `PASSWORD EXPIRE` 关键字；8.0.19 (2020) 引入 `FAILED_LOGIN_ATTEMPTS`。MySQL 8.0 后是迄今最完整的开源密码策略实现。

5. **PostgreSQL 至今坚持"密码策略不属于内核"**。`passwordcheck` (8.4, 2009) 仅是 contrib 样例，不可配置；真正可用的策略来自第三方 `credcheck` 扩展。RDS / Cloud SQL 等 PaaS 限制扩展加载，PG 用户在合规审计时常需要切换到 EnterpriseDB 或叠加 LDAP。

6. **MySQL 兼容生态（TiDB、OceanBase、Doris、StarRocks、Databend）继承了 MySQL 8.0 的策略接口**。语法层几乎逐字一致；分布式实现的关键差异在历史保存的一致性（多副本下 `password_history` 表如何同步）与失败计数的全局聚合（多 PD/FE 节点如何统一计数）。

7. **云原生引擎（BigQuery、Athena、Spanner、Firebolt）没有"密码策略"概念**。它们没有密码字段，全部走 IAM/OAuth/服务账户密钥；策略由云身份系统（Google IAM Recommender、AWS IAM Access Analyzer）提供。这是"密码策略"在 2026 年的终态形式。

8. **Snowflake 在 2022 年才补齐 `PASSWORD POLICY` 对象**。这反映了云数据库的优先级：密码策略不如 MFA/SSO 重要。Snowflake 2024 年起强制 MFA，2025 年新租户禁用纯密码，密码策略成为"最后兜底"。

9. **NIST 与 PCI-DSS 在周期轮换上的分歧持续存在**。NIST 2017 年起反对周期性轮换，PCI-DSS 4.0 (2025) 仍要求 90 天。结果：所有引擎都同时支持"周期轮换"和"事件驱动重置"，让 DBA 自行平衡合规与可用性。

10. **失败锁定是 DoS 攻击向量**。攻击者用错误密码几次就能锁住任何账户。SQL Server / Oracle / MySQL 都仅按用户名计数，无法区分"善意输错"和"恶意尝试"。Snowflake 和 PG `auth_delay` 用"延迟"而非"锁定"作为缓解，是更现代的做法。

11. **双密码 / 平滑轮换是生产环境的硬需求**。MySQL 8.0.14 `RETAIN CURRENT PASSWORD`、Snowflake `RSA_PUBLIC_KEY_2`、PostgreSQL 16 的双密码字段，都是为"24/7 应用改密不停机"设计。这是 2020 年代密码策略的关键演进点。

12. **密码哈希算法升级与策略升级正交但相关**。NIST SP 800-131A 禁用 MD5/SHA1 后，PostgreSQL 10 切到 SCRAM-SHA-256、MySQL 8.0 切到 caching_sha2_password、Oracle 12c 切到 PBKDF2-SHA-512。哈希弱时再严的策略也只是延缓，必须把哈希升级作为策略实施的前置条件。

13. **审计日志必须把策略事件纳入**。账户锁定、密码过期、改密拒绝原因、双密码切换、PROFILE 修改——这些都是 SOX / PCI-DSS 4.0 审计的关键事件。仅记录"登录成功/失败"是不够的。

14. **Inactive account cleanup 仍是空白**。只有 Oracle 12c+ 的 `INACTIVE_ACCOUNT_TIME` 内置闲置账户清理；其他引擎都需要 DBA 自行 cron + 审计。这是合规审计经常踩雷的点。

15. **未来方向是"无密码"**。FIDO2 / WebAuthn (MySQL 8.0.29+ FIDO2 插件)、Snowflake JWT 密钥对、AWS RDS IAM Token、Azure SQL Entra ID Interactive (含 MFA)、TiDB tidb_auth_token——这些都让"密码"逐步降级为兜底机制。十年内主流数据库可能完全不需要"密码策略"，转而管理"密钥/令牌生命周期"。

## 参考资料

- NIST SP 800-63B: [Digital Identity Guidelines - Authentication](https://pages.nist.gov/800-63-3/sp800-63b.html)
- NIST SP 800-131A Rev.2: [Transitioning the Use of Cryptographic Algorithms](https://csrc.nist.gov/pubs/sp/800/131/a/r2/final)
- NIST SP 800-53 Rev.5: [Security and Privacy Controls (IA-5 Authenticator Management)](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- PCI-DSS v4.0: [Requirement 8.3 (User Identification and Authentication)](https://www.pcisecuritystandards.org/)
- HIPAA Security Rule: [§164.308(a)(5)(ii)(D) Password Management](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- ISO/IEC 27001:2022 Annex A 9.4.3: Password management system
- CIS PostgreSQL 15 Benchmark: [Password Policy](https://www.cisecurity.org/benchmark/postgresql)
- CIS MySQL 8.0 Benchmark: [Password Policy](https://www.cisecurity.org/benchmark/mysql)
- CIS Oracle 19c Benchmark: [Password Policy](https://www.cisecurity.org/benchmark/oracle_database)
- Oracle: [CREATE PROFILE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-PROFILE.html)
- Oracle: [Password Verification Function](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/configuring-authentication.html)
- Microsoft: [CREATE LOGIN with CHECK_POLICY/CHECK_EXPIRATION](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-login-transact-sql)
- Microsoft: [Password Policy in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/security/password-policy)
- MySQL: [validate_password Component](https://dev.mysql.com/doc/refman/8.0/en/validate-password.html)
- MySQL: [Password Management](https://dev.mysql.com/doc/refman/8.0/en/password-management.html)
- MySQL: [Failed-Login Tracking and Temporary Account Locking](https://dev.mysql.com/doc/refman/8.0/en/password-management.html#failed-login-tracking)
- MariaDB: [simple_password_check Plugin](https://mariadb.com/kb/en/simple_password_check-plugin/)
- MariaDB: [cracklib_password_check Plugin](https://mariadb.com/kb/en/cracklib_password_check-plugin/)
- PostgreSQL: [passwordcheck Module](https://www.postgresql.org/docs/current/passwordcheck.html)
- PostgreSQL: [auth_delay Module](https://www.postgresql.org/docs/current/auth-delay.html)
- credcheck (PG extension): [GitHub](https://github.com/MigOpsRepos/credcheck)
- IBM DB2: [Password Attributes](https://www.ibm.com/docs/en/db2/11.5)
- SAP HANA: [Password Policy Configuration](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Snowflake: [PASSWORD POLICY](https://docs.snowflake.com/en/sql-reference/sql/create-password-policy)
- Snowflake: [User Management Policies](https://docs.snowflake.com/en/user-guide/admin-user-management)
- CockroachDB: [Authentication Cluster Settings](https://www.cockroachlabs.com/docs/stable/authentication.html)
- Vertica: [CREATE PROFILE](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/CREATE_PROFILE.htm)
- Teradata: [DBC.SysSecDefaults](https://docs.teradata.com/r/Teradata-VantageTM-Security-Administration)
- Exasol: [Password Security Policy](https://docs.exasol.com/db/latest/database_concepts/database_users_roles.htm)
- Verizon DBIR 2024: [Data Breach Investigations Report](https://www.verizon.com/business/resources/reports/dbir/)
- Have I Been Pwned: [k-Anonymity API](https://haveibeenpwned.com/API/v3#PwnedPasswords)
