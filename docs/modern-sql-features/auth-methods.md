# 认证方式 (Authentication Methods)

一次"用户名+密码"登录，就能让整个数据库成为攻击者的前进基地——凭据泄露仍然是 Verizon DBIR 年度报告中排名第一的数据库入侵原因。本文横向对比 48 款主流数据库/分析引擎的客户端认证机制，涵盖 SCRAM、MD5、明文密码、Kerberos/GSSAPI、LDAP、mTLS 证书认证、云 IAM/OIDC 等主流方案，并讨论"为什么密码认证正在被淘汰"。

## 为什么密码认证正在被废弃

截至 2026 年，主流数据库正在系统性地把"可选的强认证"升格为"默认启用的强认证"：

1. **明文密码不可逆修复**：MySQL 在 8.0 把默认认证插件从 `mysql_native_password`（SHA1 一次性哈希挑战）切换到 `caching_sha2_password`（SHA-256 + Salt）。MySQL 9.0 里 `mysql_native_password` 已经默认禁用。
2. **MD5 的退役**：PostgreSQL 10 (2017) 引入 RFC 5802 的 SCRAM-SHA-256 作为默认首选，替换之前的 MD5 挑战-响应。MD5 已被 NIST SP 800-131A 明确判为"不可用于认证"。
3. **密码复用导致的横向移动**：一旦运维人员在多个库用相同密码，一次泄露就波及全集群。Kerberos/SAML/OIDC 通过中心化令牌解决此问题。
4. **合规要求**：PCI-DSS v4.0（2025 年 3 月强制生效）要求多因素认证（MFA）覆盖所有对 CDE 的访问；HIPAA、GDPR、中国《数据安全法》均要求"强身份认证"。纯密码不再满足任何一条主流合规。
5. **云数据库的 IAM 化**：AWS RDS/Aurora、Google Cloud SQL、Azure SQL、Snowflake、BigQuery 均已把数据库登录与云平台身份体系打通。密码在云上正在变成"最后的后备选项"。
6. **SCRAM、mTLS、OIDC 成本下降**：开源服务端（Postgres、MongoDB、Kafka 等）内置了 SCRAM；Let's Encrypt / 私有 CA 让 mTLS 证书签发成本接近零；Keycloak/Dex/Auth0 把 OIDC 集成时间压到小时级别。

结果是，2026 年新部署的数据库里，"只用密码登录"已经是审计报告里的红色高风险项。

## 没有 SQL 标准，只有 CIS/NIST 指南

与 `TABLESAMPLE`、`MERGE` 不同，"如何登录数据库"不在 ISO/IEC 9075 的覆盖范围。行业参考来自三条主线：

| 规范 | 说明 |
|------|------|
| **NIST SP 800-63B** | 身份凭据等级（IAL/AAL），要求 AAL2 以上使用多因素或加密挑战 |
| **NIST SP 800-131A Rev.2** | 不再允许 MD5、SHA-1 用于认证；建议 SCRAM-SHA-256 或更强算法 |
| **NIST FIPS 140-3** | 加密模块的联邦合规等级；FIPS 模式下禁用 MD5/RC4/DES |
| **CIS Benchmarks** | 为 PostgreSQL/MySQL/Oracle/SQL Server/MongoDB 等提供加固清单，均要求禁用弱认证 |
| **PCI-DSS v4.0** | 对支付卡数据系统强制 MFA、强制密码轮换、禁止共享账户 |
| **IETF RFC 5802** | SCRAM 挑战-响应协议，PostgreSQL/MongoDB/Kafka/Redis 7+ 采用 |
| **IETF RFC 4120** | Kerberos v5；大多数企业数据库通过 GSSAPI/SASL 实现 |
| **IETF RFC 4511** | LDAP v3；企业目录服务集成 |
| **OAuth 2.0 / OIDC** | RFC 6749 + OpenID Connect Core 1.0；云数据库令牌认证基础 |
| **SAML 2.0** | OASIS 标准；企业 SSO 集成 Snowflake、Databricks 等 |

数据库厂商自行选择实现子集，具体表现是：插件化认证架构（PostgreSQL `pg_hba.conf`、MySQL 认证插件、Oracle SQLNET authentication services）、默认算法各异、可配置范围各异。这就是本文存在的理由。

## 支持矩阵（48 引擎总览）

### 主流认证方式支持

| 引擎 | SCRAM-SHA-256 | MD5 | 明文密码 | Kerberos/GSSAPI | LDAP | mTLS (证书) | IAM/OIDC | 版本 |
|------|--------------|-----|---------|-----------------|------|-------------|----------|------|
| PostgreSQL | 默认 (10+) | 可用但弃用 | 可用 | 是 (GSSAPI) | 是 | 是 | 扩展 (AWS IAM) | 8.0+ |
| MySQL | -- (caching_sha2) | -- | 是 | 插件 | 插件 | 是 | AWS IAM, Azure AD | 5.0+ |
| MariaDB | -- (ed25519 替代) | -- | 是 | GSSAPI 插件 | PAM | 是 | -- | 10.x+ |
| SQLite | -- | -- | -- (无远程) | -- | -- | -- | -- | 嵌入式 |
| Oracle | -- (O7L_MR 等) | -- | 是 | 是 (8i+) | 是 (OID) | 是 | OCI IAM, Azure AD | 7.3+ |
| SQL Server | -- | -- | SQL Login | 是 (默认) | 是 (AD) | 是 | Azure AD / Entra ID | 6.5+ |
| DB2 | 可选 | -- | 是 | 是 (GSSAPI) | 是 | 是 | IBM IAM | 8.0+ |
| Snowflake | -- | -- | 可用 | -- | -- | 密钥对 (JWT) | OAuth, SAML, OIDC | GA |
| BigQuery | -- | -- | -- | -- | -- | 服务账户密钥 | GCP IAM (默认) | GA |
| Redshift | -- | -- (弃用) | 可用 | 是 | 是 | 是 | AWS IAM (默认推荐) | GA |
| DuckDB | -- | -- | 可用 | -- | -- | -- | -- | 嵌入式 |
| ClickHouse | 是 (23.3+) | -- | 是 | 是 | 是 | 是 | 是 (OIDC in 23.9+) | 早期 |
| Trino | -- | -- | 文件/LDAP | 是 | 是 | 是 | OAuth2, JWT | 早期 |
| Presto | -- | -- | 文件/LDAP | 是 | 是 | 是 | JWT | 早期 |
| Spark SQL | -- | -- | Basic | 是 (Kerberos) | PAM | 是 | 是 (Databricks) | 2.0+ |
| Hive | -- | -- | Basic | 是 (主流) | 是 | 是 | -- | 0.13+ |
| Flink SQL | -- | -- | Basic | 是 | -- | 是 | -- | 1.16+ |
| Databricks | -- | -- | -- | -- | -- | 是 | OAuth, PAT, SCIM | GA |
| Teradata | -- (TD2 + SHA-256) | -- | 是 (TD2) | 是 | 是 (LDAP) | 是 | OIDC (17.20+) | 16.20+ |
| Greenplum | 继承 PG | 继承 PG | 继承 PG | 是 | 是 | 是 | -- | 6.x+ |
| CockroachDB | 是 (v20.2+) | -- | 是 | 是 (v23.1+) | 是 | 是 (默认推荐) | OIDC (v22.1+) | v1.0+ |
| TiDB | -- | -- | caching_sha2 | -- | 是 (5.2+) | 是 | tidb_auth_token (6.5+) | 4.0+ |
| OceanBase | -- | -- | 是 | 是 (4.0+) | 是 | 是 | -- | 3.x+ |
| YugabyteDB | 继承 PG | 继承 PG | 继承 PG | 是 | 是 | 是 | OIDC (2.18+) | 2.0+ |
| SingleStore | -- | -- | 是 (类 MySQL) | 是 | 是 (SAML) | 是 | JWT | 7.0+ |
| Vertica | 是 (11.1+) | 是 | 是 | 是 | 是 | 是 | OAuth (12.0+) | 7.x+ |
| Impala | -- | -- | 是 | 是 (主流) | 是 | 是 | -- | 2.0+ |
| StarRocks | -- | -- | 是 (类 MySQL) | -- | 是 (3.0+) | 是 | -- | 2.x+ |
| Doris | -- | -- | 是 (类 MySQL) | -- | 是 (2.0+) | 是 | -- | 1.2+ |
| MonetDB | -- (SHA-512 挑战) | -- | 是 | -- | -- | 是 (Jun2023+) | -- | Jul2015+ |
| CrateDB | -- | -- | 是 | -- | -- | 是 | JWT (5.5+) | 3.0+ |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| QuestDB | -- | -- | 是 | -- | -- | -- | JWK (REST) | 6.6+ |
| Exasol | -- | -- | 是 | 是 (Kerberos) | 是 | 是 (OpenID Connect) | 是 (7.1+) | 6.x+ |
| SAP HANA | -- (SCRAM-SHA-256 HANA 2.0 SPS 03+) | -- | 是 | 是 | 是 | 是 (X.509) | SAML / OIDC (SPS 05+) | 1.0+ |
| Informix | -- | -- | 是 | 是 (PAM) | 是 | 是 | -- | 11.x+ |
| Firebird | SRP (4.x+) | -- (Legacy_Auth 弃用) | -- | -- | -- | 是 (3.0+) | -- | 3.0+ |
| H2 | -- | -- | 是 (SHA-256 内部) | -- | -- | -- | -- | 早期 |
| HSQLDB | -- | -- | 是 (内部哈希) | -- | 是 | -- | -- | 早期 |
| Derby | -- | -- | 是 | -- | 是 | 是 | -- | 早期 |
| Amazon Athena | -- | -- | -- | -- | -- | -- | AWS IAM (默认) | GA |
| Azure Synapse | -- | -- | SQL Login | -- | -- | 是 | Entra ID (主推) | GA |
| Google Spanner | -- | -- | -- | -- | -- | 服务账户密钥 | GCP IAM (默认) | GA |
| Materialize | 是 (继承 PG) | -- | 是 | -- | -- | 是 | Frontegg (Cloud) | GA |
| RisingWave | 是 (继承 PG) | -- | 是 | -- | -- | 是 | OIDC (Cloud) | GA |
| InfluxDB (SQL) | -- | -- | Token | -- | -- | -- | Token / OIDC | 3.0+ |
| Databend | 是 | -- | 是 | -- | -- | 是 | JWT (OIDC/OAuth2) | GA |
| Yellowbrick | 继承 PG | 继承 PG | 继承 PG | 是 | 是 | 是 | OIDC | GA |
| Firebolt | -- | -- | -- | -- | -- | 服务账户 | OAuth2 (默认) | GA |

> 统计：48 个引擎中，46 个支持 TLS 加密下的密码认证；26 个支持 Kerberos/GSSAPI；31 个支持 LDAP；36 个支持 mTLS/证书登录；云原生引擎（Snowflake、BigQuery、Redshift、Databricks、Athena、Synapse、Spanner、Firebolt 等 10+）默认要求 IAM/OIDC/SAML 而非密码。

### 密码哈希算法与强度

| 引擎 | 算法 | 盐 (Salt) | 迭代次数 | FIPS 兼容 |
|------|------|----------|---------|-----------|
| PostgreSQL SCRAM-SHA-256 | SCRAM-SHA-256 | 16B 随机 | 默认 4096 | 是 |
| PostgreSQL MD5 (弃用) | `md5(password + username)` | 用户名 | 1 | 否 |
| MySQL caching_sha2_password | SHA-256 多轮 | 随机 | 默认 5000 | 是 |
| MySQL mysql_native_password (弃用) | SHA1 双轮 | 8B 挑战 | 1 | 否 |
| MySQL sha256_password | SHA-256 | 随机 | 5000 | 是 |
| MariaDB ed25519 | Ed25519 公钥签名 | -- | -- | 是 |
| Oracle 12c+ | PBKDF2-SHA-512 (O7L_MR) | 随机 16B | 4096 | 是 |
| SQL Server | PBKDF2-SHA-512 (2012+), 之前 SHA1 | 随机 | 迭代次数固定 | 是 (2019+) |
| MongoDB | SCRAM-SHA-256 (4.0+), SCRAM-SHA-1 (3.0+) | 随机 | 15000+ | 是 |
| Redis 7+ | SCRAM-SHA-256 | 随机 | 可配 | 是 |
| Firebird 3+ SRP | SRP-256 挑战-响应 | -- | -- | 是 |

> 关键事实：SHA1、MD5 已被 NIST SP 800-131A 禁用于认证。仍使用 `mysql_native_password`、Oracle 10g 密码哈希或 PostgreSQL `md5` 认证的部署在 PCI-DSS 审计中会直接失分。

### Kerberos / GSSAPI 支持细节

| 引擎 | 实现 | 票据缓存 | KDC 要求 | 备注 |
|------|------|---------|---------|------|
| PostgreSQL | GSSAPI (MIT Kerberos / Heimdal) | `~/.krb5cc_uid` | MIT/AD/FreeIPA | `gss` 方式，支持加密 |
| MySQL | authentication_kerberos 插件 (8.0.26+) | OS-native | MIT/AD | 企业版默认，社区版插件 |
| MariaDB | auth_gssapi 插件 | 系统 | MIT/AD | MSSQL 兼容模式 |
| Oracle | Oracle Advanced Security (OAS) | OS-native | 任意 | 8i+，与 OUD/AD 集成 |
| SQL Server | SSPI (Windows) / Kerberos (Linux) | OS-native | AD | 默认 Windows Integrated |
| DB2 | GSSAPI 插件 | `DB2GSSCLIENT.DLL` | AD/MIT | AUTHENTICATION KERBEROS |
| Hive / HiveServer2 | SASL GSSAPI | Hadoop UGI | AD/MIT | 企业 Hadoop 标配 |
| Impala | Hadoop SASL | Hadoop UGI | AD/MIT | 与 Hive 相同 |
| Spark SQL | Hadoop Delegation Token | UGI | AD/MIT | 长时任务用 token 续期 |
| CockroachDB | GSSAPI (v23.1+) | OS-native | AD/MIT | 企业版特性 |
| Greenplum | 继承 PG GSSAPI | 同 PG | AD/MIT | 默认 disabled |
| YugabyteDB | 继承 PG GSSAPI | 同 PG | AD/MIT | 2.6+ |
| Teradata | TDGSS (Teradata GSS) | OS-native | AD | 16.20+ 默认建议 |
| Vertica | GSS | OS-native | AD/MIT | 内置 |
| OceanBase | Kerberos (4.0+) | OS-native | AD | 企业版 |
| SAP HANA | Kerberos | OS-native | AD | 企业版 |

### LDAP / LDAP BIND 支持细节

| 引擎 | LDAP 模式 | BIND 查询 | TLS (LDAPS/StartTLS) | 备注 |
|------|----------|----------|---------------------|------|
| PostgreSQL | `simple` bind / `search+bind` | 是 (两阶段) | 是 | `pg_hba.conf: ldap` |
| MySQL | authentication_ldap_sasl / _simple | 是 | 是 | 企业版 & MySQL 8.0.28+ 社区 SASL |
| MariaDB | PAM + nss_ldap | PAM 代理 | 是 | pam_ldap 或 SSSD |
| Oracle | Enterprise User Security (EUS) | OID/AD | 是 | 企业版 + OID |
| SQL Server | AD 实际上是 LDAP，走 Kerberos | -- | 是 | 继承 Windows 域 |
| DB2 | LDAP 插件 (EE 9.x+) | 是 | 是 | 可用 Tivoli DS 或 AD |
| Hive/Trino/Presto | 内置 LDAP 认证器 | 是 | 是 | 常见于企业 BI 登录 |
| Impala | LDAP | 是 | 是 | HS2 层 |
| ClickHouse | `<ldap>` 配置块 | 是 | 是 | 21.4+ |
| CockroachDB | v23.1+ | 是 | 是 | 企业版 |
| TiDB | `tidb_auth_ldap` 插件 (5.2+) | 是 | 是 | 支持 SASL bind |
| SingleStore | SAML + LDAP | 是 | 是 | 可 fall back 到本地密码 |
| Vertica | LDAPLink | 是 | 是 | 可与本地账户联动 |
| Teradata | LDAP (QDM) | 是 | 是 | 16.20+ 标配 |
| Exasol | LDAP | 是 | 是 | -- |
| SAP HANA | LDAP | 是 | 是 | HANA 2.0 SPS 03+ |
| StarRocks/Doris | LDAP 插件 | 是 | 是 | 3.0+ / 2.0+ |
| Yellowbrick/Greenplum | 继承 PG | 是 | 是 | -- |

### 证书 (mTLS) / 密钥对认证

| 引擎 | 客户端证书 | 公钥登录 | JWT/OIDC Key 导入 | 说明 |
|------|-----------|---------|-------------------|------|
| PostgreSQL | `cert` 认证方式 | -- | -- | mTLS + `ssl_cert_subject` 映射用户名 |
| MySQL | `REQUIRE X509` / `REQUIRE SUBJECT` | -- | -- | GRANT 中声明证书要求 |
| MariaDB | `REQUIRE X509` | ed25519 公钥 | -- | auth_ed25519 插件 |
| Oracle | TCPS + 证书登录 | -- | -- | Wallet (oracle.net.wallet_location) |
| SQL Server | Certificate Mapping | -- | -- | AD 证书颁发机构集成 |
| Snowflake | -- | RSA/EC 密钥对 + JWT | 导入公钥 | `ALTER USER ... SET RSA_PUBLIC_KEY` |
| CockroachDB | 默认客户端证书 | -- | -- | CN = username |
| TiDB | `REQUIRE X509` (继承 MySQL) | -- | -- | -- |
| ClickHouse | `<ssl_certificates>` | -- | -- | 22.3+ |
| Vertica | mTLS | -- | -- | -- |
| SAP HANA | X.509 证书 | -- | -- | -- |
| Firebird | WireCrypt + 证书 (4.0+) | -- | -- | -- |
| BigQuery | -- | 服务账户 P12/JSON 密钥 | -- | 推荐使用 workload identity |
| Google Spanner | -- | 服务账户密钥 | -- | -- |
| AWS RDS (Postgres/MySQL) | mTLS + IAM Token | -- | -- | RDS IAM DB auth |

### 云 IAM / OIDC / SAML 支持

| 引擎 | IAM 登录 | OAuth 2.0 / OIDC | SAML 2.0 | 令牌类型 |
|------|---------|-----------------|----------|---------|
| Snowflake | -- | 是 (OIDC 2023+) | 是 | 短期 OAuth2 access token |
| BigQuery | GCP IAM (默认) | OIDC (Workload Identity Federation) | -- | Google-issued OAuth2 token |
| Redshift | AWS IAM (推荐) | -- | IAM 联合登录 | `GetClusterCredentials` 动态密码 |
| Databricks | OAuth2 / PAT | 是 | 是 | Workspace/PAT Token |
| Amazon Athena | AWS IAM (默认) | -- | -- | SigV4 签名 |
| AWS RDS Postgres/MySQL/MariaDB | IAM 数据库认证 | -- | -- | 15 分钟有效的 token |
| Azure SQL Database | Entra ID (AAD) | 是 | 是 | AAD access token |
| Azure Synapse | Entra ID (主推) | 是 | 是 | AAD access token |
| Google Spanner | GCP IAM (默认) | OIDC | -- | Google OAuth2 |
| Google Cloud SQL | IAM DB Auth (2023 GA) | -- | -- | 1 小时有效 |
| Firebolt | OAuth2 (默认) | 是 | -- | 服务账户 client secret |
| CockroachDB | -- | OIDC (v22.1+) | 是 (企业版) | JWT |
| Vertica | -- | OAuth (v12.0+) | -- | JWT |
| TiDB | -- | tidb_auth_token (v6.5+, 2022) | -- | JWT |
| Trino / Presto | -- | JWT / OAuth2 | -- | JWT bearer |
| SingleStore | -- | JWT | 是 | bearer |
| RisingWave Cloud | -- | OIDC | -- | -- |
| Materialize Cloud | -- | Frontegg (OIDC) | -- | -- |
| Databend | -- | JWT (OAuth2/OIDC) | -- | -- |
| InfluxDB 3 | -- | 是 | -- | API Token |
| CrateDB | -- | JWT (5.5+) | -- | -- |
| Yellowbrick | -- | OIDC | 是 | -- |
| SAP HANA | -- | OIDC (SPS 05+) | 是 | -- |
| Exasol | -- | OpenID Connect (7.1+) | 是 | -- |
| Teradata | -- | OIDC (17.20+) | 是 | JWT |

> 统计：约 28 个引擎支持 OAuth2/OIDC/SAML 中至少一种；10 个云数据库默认要求云平台 IAM（无密码登录选项）。

## 各引擎深入解析

### PostgreSQL：SCRAM-SHA-256 的标杆

PostgreSQL 10 (2017 年 10 月) 引入 SCRAM-SHA-256，替代 MD5 成为推荐默认。`pg_hba.conf` 是认证策略的总开关：

```conf
# TYPE  DATABASE  USER  ADDRESS         METHOD
local   all       all                    peer
host    all       all   10.0.0.0/8      scram-sha-256
host    all       all   ::1/128         scram-sha-256
hostssl all       all   0.0.0.0/0       cert clientcert=verify-full
hostgssenc all    all   0.0.0.0/0       gss include_realm=0 krb_realm=EXAMPLE.COM
```

`password_encryption` 参数决定新建密码的哈希方式（从 PG 14 开始默认 `scram-sha-256`）。迁移步骤：

```sql
-- 1. 切换默认密码哈希
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();

-- 2. 逐个用户修改密码（会自动以新算法存储）
\password alice

-- 3. pg_hba.conf 把 md5 改为 scram-sha-256
-- 4. 重载配置，旧驱动会失败，需要 psycopg2 2.8+/pgjdbc 42.2.0+ 等支持 SCRAM 的驱动
```

支持的认证方式（`pg_hba.conf` 的 METHOD 列）：`trust`、`reject`、`md5`（弃用）、`password`（明文，仅应用于 TLS 内）、`scram-sha-256`、`gss`、`sspi`、`ident`、`peer`、`ldap`、`radius`、`cert`、`pam`、`bsd`、`oauth`（16+ 新增）。

### MySQL：caching_sha2_password 默认化

MySQL 5.6 引入 `sha256_password`，MySQL 8.0 (2018) 把默认认证插件切换为 `caching_sha2_password`：

```sql
-- 查看当前用户的认证插件
SELECT user, host, plugin FROM mysql.user;

-- 修改默认插件（my.cnf）
[mysqld]
default_authentication_plugin=caching_sha2_password    -- 8.0
-- MySQL 8.0.27+ 引入 authentication_policy，优先于 default_authentication_plugin
authentication_policy=*,,  -- 第一项是主 plugin，其余是多因子

-- 创建用户时显式指定
CREATE USER 'alice'@'%' IDENTIFIED WITH caching_sha2_password BY 'strong_password';
```

MySQL 9.0（2024）把 `mysql_native_password`（SHA1 挑战-响应）默认禁用，需要显式 `--mysql-native-password=ON` 才可启用。驱动兼容性：Connector/J 8.0.11+、Go mysql 1.5+、PyMySQL 1.0+、libmysqlclient 8.0+ 支持 `caching_sha2_password`。

**认证插件家族**（MySQL 8.x 随附）：

| 插件 | 用途 | 备注 |
|------|------|------|
| `caching_sha2_password` | 默认，SHA-256 + 缓存 | 8.0+ 默认 |
| `sha256_password` | SHA-256，无缓存 | 首次必须 TLS 或公钥握手 |
| `mysql_native_password` | 旧 SHA1 | 9.0+ 默认禁用 |
| `authentication_ldap_sasl` | LDAP (SASL) | 社区 8.0.28+，企业版更早 |
| `authentication_ldap_simple` | LDAP simple bind | 企业版 |
| `authentication_kerberos` | Kerberos | 8.0.26+ |
| `authentication_fido` | FIDO2/WebAuthn | 8.0.29+ 企业版，社区版 8.0.32+ |
| `authentication_oci` | OCI (Oracle Cloud) | 企业版 |
| `authentication_windows` | Windows Integrated | 企业版 |

MySQL 8.0.27+ 支持多因子认证（最多 3 个因子），通过 `authentication_policy` 声明。

### Oracle：OS 认证与 Kerberos 的起点

Oracle 从 7.3 开始支持 OS 认证（`OPS$username`），从 8i (1999) 开始支持 Kerberos 作为 Oracle Advanced Security (OAS) 的一部分。现代部署常见三种方式：

```sql
-- 1. 密码认证（默认）
CREATE USER alice IDENTIFIED BY strong_password;

-- 2. 操作系统认证
CREATE USER ops$alice IDENTIFIED EXTERNALLY;

-- 3. 目录服务 (EUS - Enterprise User Security)
CREATE USER alice IDENTIFIED GLOBALLY AS 'CN=alice,OU=Users,DC=example,DC=com';
```

`sqlnet.ora` 控制认证服务链：

```
SQLNET.AUTHENTICATION_SERVICES = (TCPS, KERBEROS5, BEQ, NONE)
SQLNET.KERBEROS5_CONF = /etc/krb5.conf
SQLNET.KERBEROS5_KEYTAB = /etc/v5srvtab
SQLNET.KERBEROS5_CC_NAME = /tmp/krb5cc_oracle
```

Oracle 12c+ 密码哈希使用 SHA-512 + PBKDF2（O7L_MR verifier），在 18c 开始 `allowed_logon_version_server` 的默认值为 12，拒绝 10g 及以下版本的哈希算法。Oracle Cloud 提供 IAM 数据库认证（2022+）。

### SQL Server：Windows Integrated 默认

SQL Server 有三种登录类型：

1. **Windows Authentication (Integrated)** – 默认推荐，走 Kerberos (域环境) 或 NTLM (工作组)。SSPI 协议自动协商。
2. **SQL Server Authentication (SQL Login)** – 在服务器本地建账户，密码哈希用 SHA-512 (2012+)。
3. **Azure Active Directory (Entra ID) Authentication** – Azure SQL / SQL Server 2022+ 支持，返回 access token 直连。

```sql
-- Windows 登录
CREATE LOGIN [CORP\alice] FROM WINDOWS;

-- SQL 登录
CREATE LOGIN alice WITH PASSWORD = 'strong_password!',
    CHECK_POLICY = ON, CHECK_EXPIRATION = ON;

-- Azure AD (Entra ID) 登录
CREATE LOGIN [alice@contoso.com] FROM EXTERNAL PROVIDER;

-- 证书映射
CREATE CERTIFICATE CertAlice FROM FILE = 'C:\alice.cer';
CREATE LOGIN LoginAlice FROM CERTIFICATE CertAlice;
```

连接字符串示例：

```
# Windows Integrated (SSPI)
Server=srv;Database=db;Integrated Security=SSPI;

# SQL Login
Server=srv;Database=db;User Id=alice;Password=***;

# Entra ID Password
Server=tcp:srv.database.windows.net;Database=db;
  Authentication=Active Directory Password;User Id=alice@contoso.com;Password=***;

# Entra ID Interactive (带 MFA)
Authentication=Active Directory Interactive;

# Entra ID Managed Identity
Authentication=Active Directory Managed Identity;
```

Azure SQL DB 从 2023 起要求 Entra ID 作为身份主 key；SQL 登录会被逐步降级到只读。

### Snowflake：OAuth/SAML/密钥对认证

Snowflake 强制 TLS，且从 2024 年起要求企业账户启用 MFA。支持的认证方式：

```sql
-- 1. 用户名/密码 (默认, 但强制 MFA)
-- 连接字符串：ACCOUNT=xy12345;USER=alice;PASSWORD=***;AUTHENTICATOR=SNOWFLAKE;

-- 2. 密钥对认证 (JWT)
ALTER USER alice SET RSA_PUBLIC_KEY='MIIBIjANBgkq...';
-- 连接字符串：AUTHENTICATOR=SNOWFLAKE_JWT;PRIVATE_KEY_FILE=./alice.p8;

-- 3. OAuth 2.0
-- AUTHENTICATOR=OAUTH;TOKEN=<oauth_access_token>

-- 4. SAML SSO (企业常用)
-- 浏览器跳转到 IdP 完成 SAML 断言交换
-- AUTHENTICATOR=EXTERNALBROWSER 或 AUTHENTICATOR=<saml_integration_name>

-- 5. OIDC (预览 / 2024+)
-- AUTHENTICATOR=OIDC

-- 6. 代理服务 (KeyPair + Service Account, for ELT 工具)
```

Snowflake 2024 年 11 月发布的"增强 MFA 政策"要求所有人类账户启用 MFA；2025 年起 Snowflake 将在新租户上默认禁用纯密码登录。

### BigQuery：GCP IAM 默认

BigQuery 没有"数据库用户"这个概念，所有身份都是 Google Cloud 身份：

1. **Google 账户**（用户）– `alice@example.com`，通过浏览器或 `gcloud auth login` 登录。
2. **服务账户**（机器）– `bqservice@project.iam.gserviceaccount.com`，使用 JSON/P12 密钥或 Workload Identity Federation。
3. **Workload Identity Federation** – 从外部 OIDC/SAML IdP 联邦交换出 Google token，无需下发服务账户密钥。

权限通过 IAM 角色（`roles/bigquery.dataViewer` 等）控制，粒度可细到表级 / 列级 / 行级策略。所有连接走 HTTPS + OAuth2 bearer token，**没有密码认证选项**。

```bash
# 用户身份
gcloud auth application-default login

# 服务账户 (密钥文件方式, 不推荐)
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json

# Workload Identity Federation (推荐)
gcloud iam workload-identity-pools create-cred-config \
    projects/123/locations/global/workloadIdentityPools/my-pool/providers/my-provider \
    --service-account=bqsvc@proj.iam.gserviceaccount.com \
    --output-file=credentials.json
```

### CockroachDB：证书 + 密码双栈

CockroachDB 把 mTLS 列为默认认证机制：每个 SQL 客户端都需要一张由集群 CA 签发的证书，`CN` 字段即用户名。

```bash
# 创建用户证书
cockroach cert create-client alice \
    --certs-dir=certs --ca-key=my-safe-directory/ca.key

# 客户端连接
cockroach sql --certs-dir=./certs --user=alice \
    --host=cockroach.example.com:26257
```

密码认证需要显式打开：

```sql
CREATE USER alice WITH PASSWORD 'strong_password';
-- cluster setting
SET CLUSTER SETTING server.user_login.password_hashes.default_cost = 10;
-- 选择哈希算法：bcrypt / scram-sha-256 (v22.1+)
SET CLUSTER SETTING server.user_login.password_encryption = 'scram-sha-256';
```

CockroachDB v22.1 引入 SCRAM-SHA-256 以替代 bcrypt；v22.1 引入 OIDC (通过 HTTP 控制台) 用于运维登录；v23.1 引入 GSSAPI。企业版还支持 JWT-based 登录 (v23.2+)。

### TiDB：tidb_auth_token 与云原生

TiDB 4.0 起完全兼容 MySQL 协议（包括 caching_sha2_password）。v6.5（2022 年 12 月）引入 `tidb_auth_token`，用 JWT bearer token 替代密码：

```sql
-- 创建 token 用户
CREATE USER 'alice'@'%' IDENTIFIED WITH 'tidb_auth_token'
    REQUIRE TOKEN_ISSUER 'https://auth.example.com'
    ATTRIBUTE '{"email": "alice@example.com"}';

-- 配置 TiDB 以信任指定的 OIDC issuer
-- tidb.toml:
-- [security]
-- auth-token-jwks = "https://auth.example.com/.well-known/jwks.json"
```

客户端连接时用 JWT 作为"密码"字段：

```
mysql -h tidb.example.com -u alice -p'eyJhbGciOiJSUzI1NiIs...'
```

TiDB Cloud 将此作为默认登录方式之一，与 SSO (Google/GitHub/Microsoft) 打通。TiDB 5.2 起支持 LDAP 认证插件。

## Kerberos / GSSAPI 握手流程

Kerberos 是最广泛的企业 SSO 认证协议。典型数据库登录时序（以 PostgreSQL GSSAPI 为例）：

```
客户端 (alice@EXAMPLE.COM)        KDC (kdc.example.com)        数据库 (postgres/db.example.com@EXAMPLE.COM)
    |                                   |                               |
    | 1. AS-REQ (请求 TGT)             |                               |
    | (用户密码派生长期密钥加密)         |                               |
    |---------------------------------->|                               |
    |                                   |                               |
    | 2. AS-REP (TGT + session key)    |                               |
    |<----------------------------------|                               |
    |                                   |                               |
    | 3. TGS-REQ (用 TGT 请求服务票据) |                               |
    |---------------------------------->|                               |
    |                                   |                               |
    | 4. TGS-REP (Service Ticket)      |                               |
    |<----------------------------------|                               |
    |                                                                   |
    | 5. AP-REQ (Service Ticket 直接发给数据库, 证明身份)               |
    |------------------------------------------------------------------>|
    |                                                                   |
    | 6. (可选) AP-REP (相互认证)                                       |
    |<------------------------------------------------------------------|
    |                                                                   |
    | 7. SQL 请求开始，会话可选 GSSAPI 加密包装 (Kerberos wrap)         |
    |<----------------------------------------------------------------->|
```

关键属性：

- **无需把密码发送给数据库**：密码只用来和 KDC 认证，数据库从不接触密码。
- **互相认证**：数据库的 keytab (`postgres/db.example.com@EXAMPLE.COM`) 让客户端验证"连接的数据库是真的"。
- **票据有效期**：默认 TGT 10 小时，Service Ticket 更短；长时任务需要 renewable ticket 或 keytab。
- **NTLM fallback**：Windows SSPI 在 KDC 不可达或非域环境下会降级到 NTLM（挑战-响应，安全性弱于 Kerberos）。Kerberos-first 的部署应禁用 NTLM fallback。

**keytab 管理最佳实践**：

```bash
# 为数据库服务生成 keytab
kadmin.local -q "addprinc -randkey postgres/db.example.com@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/postgresql/krb5.keytab postgres/db.example.com@EXAMPLE.COM"

# 权限 (root 只读)
chown postgres:postgres /etc/postgresql/krb5.keytab
chmod 600 /etc/postgresql/krb5.keytab

# postgresql.conf
krb_server_keyfile = '/etc/postgresql/krb5.keytab'
```

**常见问题**：

1. **Clock Skew > 5min** → KDC 会拒绝签发票据。所有节点必须 NTP 同步。
2. **Reverse DNS 不匹配** → `kinit` 在 `dns_canonicalize_hostname = true` 时会尝试反查主机名，反查结果和 SPN 不匹配会失败。
3. **UDP 包太大** → MIT Kerberos 默认用 UDP，TGT 超过 1472 字节会失败，需要 `udp_preference_limit = 1` 改为 TCP。
4. **票据续期失败** → 长时任务（Spark、Flink）需要 `kinit -R` 或 `principal + keytab` 组合。

## 云 IAM 认证：无密码的未来

### AWS RDS IAM 数据库认证

AWS RDS (PostgreSQL, MySQL, MariaDB) 支持把 IAM 身份映射到数据库用户：

```bash
# 1. 创建数据库用户并启用 IAM 认证
# PostgreSQL:
CREATE USER alice;
GRANT rds_iam TO alice;

# MySQL:
CREATE USER 'alice' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';

# 2. IAM 策略 (允许 alice 用户连接)
# {
#   "Effect": "Allow",
#   "Action": "rds-db:connect",
#   "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:db-ABCD/alice"
# }

# 3. 生成 15 分钟有效的 token
TOKEN=$(aws rds generate-db-auth-token \
    --hostname mydb.xxx.us-east-1.rds.amazonaws.com \
    --port 5432 --region us-east-1 --username alice)

# 4. 用 token 作为密码连接
PGPASSWORD=$TOKEN psql -h mydb.xxx.rds.amazonaws.com -U alice -d mydb \
    "sslmode=require"
```

Token 有效期 15 分钟，需要应用层定期刷新。优势：无长期密码、与 IAM Role 打通（EC2 实例角色、EKS IRSA、Lambda 执行角色）；劣势：每次连接建立都需要调 STS（轻微延迟）。

### Azure SQL + Entra ID (AAD)

Azure SQL Database / Synapse 支持五种 Entra ID (原 Azure AD) 认证：

| 模式 | 连接字符串 | 用途 |
|------|-----------|------|
| Entra ID Password | `Authentication=Active Directory Password` | 传统用户名+AAD 密码 |
| Entra ID Integrated | `Authentication=Active Directory Integrated` | 加域 Windows SSO |
| Entra ID Interactive | `Authentication=Active Directory Interactive` | 带 MFA 弹出浏览器 |
| Managed Identity | `Authentication=Active Directory Managed Identity` | VM/App Service/AKS |
| Service Principal | `Authentication=Active Directory Service Principal` | CI/CD、批处理 |

创建 AAD 登录：

```sql
-- master 数据库
CREATE LOGIN [alice@contoso.com] FROM EXTERNAL PROVIDER;

-- 用户数据库
CREATE USER [alice@contoso.com] FROM EXTERNAL PROVIDER;

-- 组登录
CREATE USER [SQLAdmins] FROM EXTERNAL PROVIDER;
```

### Google Cloud SQL IAM Database Authentication

2023 年 GA，原理类似 AWS RDS：

```bash
# 1. 启用 cloud SQL IAM
gcloud sql instances patch INSTANCE --database-flags=cloudsql.iam_authentication=on

# 2. 创建用户
gcloud sql users create alice@example.com \
    --instance=INSTANCE --type=cloud_iam_user

# 3. 授予 roles/cloudsql.instanceUser
gcloud projects add-iam-policy-binding PROJECT \
    --member="user:alice@example.com" \
    --role="roles/cloudsql.instanceUser"

# 4. 获取 access token 作为密码
PGPASSWORD=$(gcloud auth print-access-token) \
    psql -h IP -U alice@example.com -d DB
```

### Snowflake OAuth2 Integration

```sql
CREATE SECURITY INTEGRATION my_oauth
    TYPE = oauth
    OAUTH_CLIENT = CUSTOM
    OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
    OAUTH_REDIRECT_URI = 'https://myapp.example.com/callback'
    ENABLED = TRUE;

-- 或外部 OAuth (Okta, Entra ID, Ping Identity):
CREATE SECURITY INTEGRATION my_external_oauth
    TYPE = external_oauth
    ENABLED = true
    EXTERNAL_OAUTH_ISSUER = 'https://myidp.example.com'
    EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://myidp.example.com/.well-known/jwks.json'
    EXTERNAL_OAUTH_AUDIENCE_LIST = ('https://xy12345.snowflakecomputing.com')
    EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'sub'
    EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME'
    EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE';
```

### TiDB Cloud SSO

TiDB Cloud 默认启用 Google/GitHub/Microsoft SSO；本地用 `tidb_auth_token` 插件将 JWT 直接作为登录密码：

```sql
-- 服务端配置 JWKS 端点后，创建 token 用户
CREATE USER 'alice'@'%' IDENTIFIED WITH 'tidb_auth_token'
    REQUIRE TOKEN_ISSUER 'https://auth.example.com'
    ATTRIBUTE '{"token_audience":"tidb-cluster"}';

-- 客户端用 JWT 作为密码
-- mysql -h tidb -u alice -p"$(curl -s auth.example.com/token | jq -r .access_token)"
```

## 证书认证 (mTLS) 深入

mTLS 把 TLS 握手里的客户端证书直接用作身份凭据，彻底规避密码。典型部署：

```
CA (企业 PKI)
  │
  ├─ 签发数据库服务器证书 (SAN: db.example.com)
  │
  └─ 签发客户端证书 (CN=alice@corp, SAN: email:alice@corp)
         │
         ├─ 存入 PKCS#12 (.p12) 或 PEM (.crt + .key) 文件
         │
         └─ 放入 HSM / TPM / YubiKey (更安全)
```

### PostgreSQL cert 方式

```conf
# pg_hba.conf
hostssl all all 0.0.0.0/0 cert clientcert=verify-full
```

```bash
# 签发客户端证书 (CN=alice)
openssl req -new -key alice.key -out alice.csr -subj "/CN=alice"
openssl x509 -req -in alice.csr -CA ca.crt -CAkey ca.key -out alice.crt

# 客户端连接
psql "host=db sslmode=verify-full sslcert=alice.crt sslkey=alice.key sslrootcert=ca.crt dbname=mydb user=alice"
```

默认证书 CN 必须等于数据库用户名，也可通过 `pg_ident.conf` 做映射：

```
# pg_ident.conf
# MAPNAME       SYSTEM-USERNAME         PG-USERNAME
cert-map        alice.example.com       alice
cert-map        /^(.*)\.example\.com$   \1_db
```

### MySQL REQUIRE X509

```sql
CREATE USER 'alice'@'%' IDENTIFIED BY 'fallback_pw'
    REQUIRE SUBJECT '/CN=alice/O=Corp'
          AND ISSUER  '/CN=Corp CA';
-- 或简单的
CREATE USER 'bob'@'%' REQUIRE X509;
```

### Snowflake 密钥对 (JWT)

Snowflake 的"密钥对认证"是证书认证的变体，但只绑定公钥，不涉及 CA：

```sql
-- 注册公钥
ALTER USER alice SET RSA_PUBLIC_KEY='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...';

-- 支持两个 key rotate
ALTER USER alice SET RSA_PUBLIC_KEY_2='...';
```

客户端用私钥签 JWT（iat/exp/sub/iss 标准声明），连接时用 `AUTHENTICATOR=SNOWFLAKE_JWT`：

```python
import jwt, datetime
token = jwt.encode({
    "iss": f"{account}.{user}.{pub_key_fp}",
    "sub": f"{account}.{user}",
    "iat": datetime.datetime.utcnow(),
    "exp": datetime.datetime.utcnow() + datetime.timedelta(minutes=59)
}, private_key, algorithm="RS256")
```

## 认证审计与合规

### 关键审计字段

数据库应记录的最小认证事件集：

| 字段 | 说明 |
|------|------|
| 时间戳 | UTC + 毫秒精度 |
| 客户端 IP | 含端口 |
| 用户名 | 包括认证插件声明的映射前/后 |
| 认证方式 | scram/md5/gss/ldap/cert/oauth/... |
| 成功/失败 | 失败原因枚举（密码错、证书不匹配、TGT 过期等） |
| 会话 ID | 便于后续操作追溯 |
| TLS 版本 + 密码套件 | 满足 PCI-DSS 4.0 要求 |
| MFA 因子 | `password+fido`、`password+oidc` 等 |

### 审计功能支持矩阵

| 引擎 | 登录审计 | 失败日志 | MFA 记录 | 集中上报 |
|------|---------|---------|---------|---------|
| PostgreSQL | `log_connections` / `pgaudit` | 是 | 是 (oauth 16+) | syslog/JSON |
| MySQL | `audit_log` 插件 (企业版) / 社区版 audit_log_filter | 是 | 是 | syslog/JSON |
| Oracle | Unified Audit (12c+) | 是 | 是 | AVDF |
| SQL Server | SQL Server Audit | 是 | 是 (Entra ID) | Event Log / Azure Monitor |
| Snowflake | `LOGIN_HISTORY` (ACCOUNT_USAGE) | 是 | 是 | Snowpipe / Event Table |
| BigQuery | GCP Audit Logs | 是 | 是 | Cloud Logging |
| AWS RDS | CloudTrail + DB Audit | 是 | 是 | CloudWatch Logs |
| Azure SQL | Auditing (built-in) | 是 | 是 | Log Analytics |
| Databricks | Unity Catalog Audit | 是 | 是 | System Tables |

## 常见漏配与反模式

1. **`trust` 认证留在 pg_hba.conf** – PostgreSQL 默认本地 `trust` 已经被 CIS 禁止；生产环境所有行都应非 trust。
2. **明文密码写在连接字符串** – 应用层泄漏的 `.env`、日志文件、Kubernetes Secret（未加密 etcd）是最常见来源。
3. **同一服务账户被多个应用共享** – 一旦轮换需要改多处；审计无法区分"是 A 还是 B 服务连的"。
4. **MD5/SHA1 哈希未升级** – 升级 PostgreSQL 主版本后仍旧在 `pg_hba.conf` 留 `md5` 行；MySQL 5.7 → 8.0 迁移时忘记把 `mysql_native_password` 用户重建。
5. **禁用了 MFA 的根账户** – Snowflake ACCOUNTADMIN、AWS root 账户、Azure SQL 主服务器管理员常常"为了方便"关闭 MFA。
6. **证书未绑定用户** – MySQL 只声明 `REQUIRE SSL` 而不是 `REQUIRE X509`，导致 CA 内任何证书都可登录。
7. **OIDC audience 未校验** – TiDB tidb_auth_token、Snowflake External OAuth 必须校验 `aud` 声明，否则其他租户的 JWT 也会通过。
8. **Kerberos keytab 权限过宽** – `/etc/krb5.keytab` 必须 600 且属数据库服务账户。
9. **长期服务账户 key 未轮换** – BigQuery/Spanner 服务账户 JSON key 默认永不过期；应该强制每 90 天轮换或改用 Workload Identity。
10. **DBA 用个人 OS 账户 peer 认证免密进入 postgres 超级用户** – 便于运维但绕过审计，`peer` + `superuser` 组合应替换为 `sudo -u postgres psql` + 集中审计。

## 密码策略与账户生命周期

### 内置策略支持

| 引擎 | 复杂度 | 过期 | 历史 | 锁定 (失败尝试) | MFA |
|------|-------|------|------|----------------|-----|
| PostgreSQL | 扩展 `passwordcheck`/`credcheck` | `VALID UNTIL` | 扩展 | 扩展 `auth_delay` | OAuth 16+ |
| MySQL | `validate_password` 组件 | `PASSWORD EXPIRE` | `password_history` | `FAILED_LOGIN_ATTEMPTS` | 8.0.27+ (MFA) |
| Oracle | `PROFILE` 参数 | 是 | 是 | 是 | MFA via OAS |
| SQL Server | `CHECK_POLICY = ON` (走 Windows policy) | `CHECK_EXPIRATION` | Windows | Windows | Entra ID MFA |
| Snowflake | 固定 (长度+种类) | `DAYS_TO_EXPIRY` | 是 | `MINS_TO_UNLOCK` | 强制 MFA (2024+) |
| AWS RDS | 无（推荐 IAM auth） | 无 | 无 | 无 | IAM + Secrets Manager |

### 典型策略配置

PostgreSQL + credcheck：

```sql
CREATE EXTENSION credcheck;
ALTER SYSTEM SET credcheck.password_min_length = 14;
ALTER SYSTEM SET credcheck.password_min_special = 2;
ALTER SYSTEM SET credcheck.password_min_upper = 2;
ALTER SYSTEM SET credcheck.password_valid_until = '90 days';
ALTER SYSTEM SET credcheck.password_reuse_history = 5;
```

MySQL：

```sql
INSTALL COMPONENT 'file://component_validate_password';
SET GLOBAL validate_password.length = 14;
SET GLOBAL validate_password.policy = STRONG;
SET GLOBAL password_history = 5;
SET GLOBAL password_reuse_interval = 90;  -- days

CREATE USER 'alice'@'%' IDENTIFIED BY 'Strong#Passw0rd!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;  -- days
```

Oracle：

```sql
CREATE PROFILE app_profile LIMIT
    PASSWORD_LIFE_TIME 90
    PASSWORD_GRACE_TIME 7
    PASSWORD_REUSE_TIME 365
    PASSWORD_REUSE_MAX 5
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1
    PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function;

ALTER USER alice PROFILE app_profile;
```

## 对引擎开发者的实现建议

### 1. 认证插件架构

模板：

```
AuthPlugin trait {
    fn identify(&self) -> MethodId;        // scram, md5, gss, ...
    fn challenge(&self, user: &str) -> Challenge;
    fn verify(&self, challenge: Challenge, response: Response) -> Result<Principal>;
    fn supports_mutual_auth(&self) -> bool;
    fn supports_channel_binding(&self) -> bool;
    fn supports_delegation(&self) -> bool;  // e.g. Kerberos forwardable
}

// 按连接注入
Connection {
    tls: TlsState,
    auth_plugin: Box<dyn AuthPlugin>,
    principal: Option<Principal>,
}
```

要点：
- 认证成功后保留 principal 信息以供后续授权与审计。
- 插件应受 `authentication_policy` 列表驱动；多因子需要前一步输出作为下一步的上下文。

### 2. SCRAM 实现细节

RFC 5802 的 SCRAM-SHA-256 交换（4 步：`client-first-message`, `server-first-message`, `client-final-message`, `server-final-message`）需要：

- 在数据库只存 `StoredKey = H(ClientKey)` 和 `ServerKey`，不存密码明文。
- `iteration_count` 默认 ≥ 4096，现代推荐 ≥ 10000。
- 支持 `channel-binding = tls-server-end-point`，绑定 TLS 通道，抵御 MITM。
- 对未知用户也要返回虚假 salt + iteration，避免用户枚举（timing & response 一致）。

### 3. 密码哈希迁移策略

从 MD5 到 SCRAM / 从 `mysql_native_password` 到 `caching_sha2_password` 的无痛迁移：

```
策略：双写 (dual-hash) 过渡
  1. 用户下一次登录成功时，用提交的密码重新计算新算法哈希
  2. 同时保留旧哈希一段时间 (过渡期)，以防需要回滚
  3. 过渡期结束后，标记仍是旧哈希的账户为"必须改密码"
  4. 拒绝用旧哈希创建新用户
```

### 4. 证书与 PRN 映射

mTLS 映射用户名时应支持：

```
映射源：
  - Subject DN 完整匹配（保守）
  - Subject CN 字段
  - SAN 中的 email/UPN/DNS
  - Subject Alternative Name 的 otherName (Kerberos PKINIT)

映射规则：
  - 精确匹配
  - 正则替换（例如 CN=alice@corp → alice）
  - 外部 LDAP 查询 (证书 -> 目录条目 -> 数据库用户)
```

### 5. Token 校验的缓存与失效

JWT / OAuth access token 的验证成本：

```
首次：
  1. 下载 JWKS (HTTP + JSON 解析)
  2. 验证 JWT 签名
  3. 验证 iss/aud/exp/nbf/iat
  4. 提取 sub → 映射到数据库用户
  5. 缓存结果

后续同一 JWT：
  - 仅校验签名缓存 + 过期时间（毫秒级）
  
JWKS 缓存：
  - 按 Cache-Control / max-age 头 (通常 1h)
  - 过期后刷新失败要保留旧 keys 避免误杀
  - JWKS rotate 事件时主动清空
```

### 6. 审计钩子

每个认证路径都应调用：

```rust
fn audit_login(event: LoginEvent) {
    // event = {
    //   ts, peer_ip, user, method, outcome, reason,
    //   tls_version, tls_cipher, mfa_factors, session_id,
    //   plugin_version, replication_state
    // }
    audit_sink.append(event);
}
```

对 `trust` / `peer` / `ident` 等"无凭据"方式尤其重要——不能因为"省事"就省略审计。

### 7. 防御用户枚举与计时攻击

- 对"不存在用户"与"密码错误"返回相同响应时间（模拟 bcrypt/SCRAM 计算）。
- 对失败计数加指数回退。
- 不在错误消息里暴露用户是否存在（统一返回 "authentication failed"）。

### 8. 与连接池的交互

PgBouncer / ProxySQL 在 `auth_pass_through` 或"服务账户池"两种模式之间有取舍：

- **服务账户模式**：连接池用自己的账户登录数据库，应用只对池认证。简单但审计粒度低。
- **Auth Passthrough**：连接池把客户端凭据透传到数据库。兼容所有认证，但需要会话级连接。
- **SCRAM Passthrough (PgBouncer 1.17+)**：PgBouncer 代理 SCRAM 挑战-响应，让事务池也能用 SCRAM。
- **OAuth / JWT Passthrough**：把 bearer token 直接作为"密码"透传，是云原生连接池的趋势。

## 关键发现

1. **密码认证正在被系统性淘汰**。PostgreSQL 10 的 SCRAM、MySQL 8.0 的 caching_sha2_password、MySQL 9.0 禁用 mysql_native_password、Snowflake 2024 年强制 MFA——所有主流引擎都在 2017–2026 这十年里同步升级了默认算法，并开始推动"零密码"的方向。
2. **没有 SQL 标准，但事实标准已收敛**。SCRAM (RFC 5802)、Kerberos (RFC 4120)、LDAP (RFC 4511)、OIDC (OpenID Connect 1.0)、mTLS (RFC 8705) 成为新数据库的必选题。不支持至少三种的引擎无法进入企业采购清单。
3. **云数据库与传统数据库的分化**。BigQuery、Athena、Firebolt 等云数据库**没有密码登录选项**，必须走 IAM/OAuth；PostgreSQL、MySQL、Oracle 等传统引擎仍然把密码作为默认，IAM 通过插件或企业版叠加。
4. **MFA 正在成为默认开启**。Snowflake 2024 年起对所有人类账户强制 MFA；Azure SQL 主推 Entra ID Interactive（含 MFA）；AWS Root、Databricks 主账户已默认 MFA。纯密码的窗口期只剩几年。
5. **Kerberos/GSSAPI 仍是企业内网王者**。26 个引擎支持 Kerberos，是企业内网 SSO 的默认选项，和 AD/FreeIPA/OUD 深度集成。云原生方向的 OIDC 与它并存而非替代——Kerberos 在局域网性能更好，OIDC 在跨域/移动更灵活。
6. **证书 (mTLS) 是零信任架构的支柱**。CockroachDB 默认要求客户端证书，PostgreSQL/MySQL 的 `cert`/`REQUIRE X509` 提供等效能力。Snowflake 的 RSA 密钥对是云上的 mTLS 变体。36 个引擎支持 mTLS，是"零密码架构"的技术基础。
7. **IAM/OIDC/SAML 是 2020 年代的新标准**。约 28 个引擎在 2022–2025 期间新增 OAuth/OIDC/SAML 支持——TiDB 6.5、CockroachDB 22.1、Vertica 12.0、SAP HANA SPS 05、Teradata 17.20、Exasol 7.1。引擎若无此特性将无法服务现代 SSO 环境。
8. **MySQL 兼容阵营差异最大**。虽然 MySQL 协议字段相同，但 `caching_sha2_password` 的缓存握手、`sha256_password` 的 RSA 公钥握手，在 TiDB、OceanBase、Doris、StarRocks、Databend 之间实现程度不一，老驱动可能需要降级到 `mysql_native_password` 才能连接某些兼容引擎。
9. **LDAP 仍是中等规模企业的主力**。31 个引擎支持 LDAP，覆盖了不想上 Kerberos 但需要集中身份的场景。LDAP 的坑在于 `search+bind` 需要两阶段、服务账户凭据放在服务端配置文件里。
10. **审计与认证分不开**。2026 年合规要求（PCI-DSS 4.0、SOX、ISO 27001、等保 2.0）把"认证事件审计"列为必检项，选型时必须同时看两项能力。仅支持认证但不支持审计（或审计不含 MFA 因子字段）的引擎会被淘汰。
11. **无密码只是"把凭据问题外推"**。OIDC access token、服务账户 key、Kerberos keytab 本质还是"长期机密"。仍需密钥轮换、HSM 保护、secret 管理（HashiCorp Vault、AWS Secrets Manager、GCP Secret Manager、Azure Key Vault）。
12. **引擎开发者应把认证层与 TLS 层解耦**。TLS 提供通道加密与服务端认证，认证插件提供主体身份。两者正交组合：`TLS + SCRAM`、`TLS + GSSAPI`、`TLS + OAuth2`、`mTLS + Kerberos delegation`。设计得正交，后续添加新认证方式就能零成本复用 TLS 基础设施。

## 参考资料

- RFC 5802: [SCRAM: Salted Challenge Response Authentication Mechanism](https://datatracker.ietf.org/doc/html/rfc5802)
- RFC 7677: [SCRAM-SHA-256 and SCRAM-SHA-256-PLUS](https://datatracker.ietf.org/doc/html/rfc7677)
- RFC 4120: [The Kerberos Network Authentication Service (V5)](https://datatracker.ietf.org/doc/html/rfc4120)
- RFC 4511: [Lightweight Directory Access Protocol (LDAP)](https://datatracker.ietf.org/doc/html/rfc4511)
- RFC 6749: [The OAuth 2.0 Authorization Framework](https://datatracker.ietf.org/doc/html/rfc6749)
- OpenID Connect Core 1.0: [OIDC Spec](https://openid.net/specs/openid-connect-core-1_0.html)
- NIST SP 800-63B: [Digital Identity Guidelines - Authentication](https://pages.nist.gov/800-63-3/sp800-63b.html)
- NIST SP 800-131A Rev.2: [Transitioning the Use of Cryptographic Algorithms](https://csrc.nist.gov/pubs/sp/800/131/a/r2/final)
- FIPS 140-3: [Security Requirements for Cryptographic Modules](https://csrc.nist.gov/pubs/fips/140-3/final)
- PCI-DSS v4.0: [Payment Card Industry Data Security Standard](https://www.pcisecuritystandards.org/)
- CIS Benchmarks: [PostgreSQL/MySQL/Oracle/SQL Server](https://www.cisecurity.org/cis-benchmarks)
- PostgreSQL: [Client Authentication](https://www.postgresql.org/docs/current/client-authentication.html)
- PostgreSQL: [pg_hba.conf](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
- MySQL: [Pluggable Authentication](https://dev.mysql.com/doc/refman/8.0/en/pluggable-authentication.html)
- MySQL: [Multifactor Authentication](https://dev.mysql.com/doc/refman/8.0/en/multifactor-authentication.html)
- Oracle: [Oracle Advanced Security Administrator's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/)
- Microsoft: [SQL Server Authentication](https://learn.microsoft.com/en-us/sql/relational-databases/security/choose-an-authentication-mode)
- Microsoft: [Azure SQL Entra ID Authentication](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- Snowflake: [Authentication Policies](https://docs.snowflake.com/en/user-guide/authentication-policies)
- Snowflake: [Key Pair Authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth)
- Snowflake: [External OAuth](https://docs.snowflake.com/en/user-guide/oauth-ext-overview)
- CockroachDB: [Authentication](https://www.cockroachlabs.com/docs/stable/authentication.html)
- TiDB: [tidb_auth_token](https://docs.pingcap.com/tidb/stable/security-compatibility-with-mysql#tidb_auth_token-authentication-method)
- AWS: [RDS IAM Database Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- Google Cloud: [Cloud SQL IAM Database Authentication](https://cloud.google.com/sql/docs/postgres/authentication)
- BigQuery: [Authentication Overview](https://cloud.google.com/bigquery/docs/authentication)
- Verizon DBIR 2024: [Data Breach Investigations Report](https://www.verizon.com/business/resources/reports/dbir/)
