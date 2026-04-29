# 加密密钥管理 (Encryption Key Management)

加密本身从来不是数据库安全的难点——AES-256 用一行代码就能调用，真正决定企业数据是否安全的，是钥匙放在哪里、谁持有、何时轮换、撤销后能否快速生效。这一切构成了密钥管理 (Key Management)，它是 TDE、SSL/TLS、列加密之上更难、更被忽视的一层。

## 为什么密钥管理比加密本身更重要

一个反直觉的事实：**几乎所有数据库泄露事故的根本原因都不是加密算法被攻破，而是密钥管理出了问题**——密钥与密文存在同一磁盘 (备份带连同密钥一起被偷)、密钥从未轮换 (前员工带走的密钥仍能解密数月后的数据)、密钥用途不分离 (一把万能钥匙开所有库) 等。Verizon 的《数据泄露调查报告》(DBIR) 多年来反复指出，密码学层面的失败很少出现在算法上，绝大多数发生在密钥生命周期管理上。

合规法规对密钥管理有非常具体的要求：

- **PCI-DSS v4.0 §3.6**：明确要求密钥的生成、分发、存储、轮换、撤销、销毁全生命周期受控；密钥的明文形态绝不能与受其保护的密文一同存储；至少每年一次的密钥轮换。
- **NIST SP 800-57**：加密密钥管理建议，定义了密钥的有效期、加密强度、轮换周期 (典型 1–5 年)。
- **FIPS 140-2/140-3**：联邦加密模块认证标准，对密钥的产生、存储、销毁有详细要求。
- **GDPR 第 32 条**：要求实施"适当的技术措施"保护个人数据，密钥管理被默认视为加密合规的一部分。
- **中国《密码法》**：明确商用密码使用须遵守密码管理规定，密钥不得存储在境外。

## KEK / DEK 两层密钥模型

现代数据库密钥管理几乎全部基于 **两层密钥** 架构：

1. **DEK (Data Encryption Key, 数据加密密钥)**：直接用于加密用户数据。性能敏感，调用频繁；可能有数十、数百甚至数千把 (按表、按列、按租户细分)。
2. **KEK (Key Encryption Key, 密钥加密密钥)**：用于加密 DEK 本身。访问频率极低，仅在数据库启动、密钥轮换、密钥换出时使用；通常存储在 HSM、KMS、Wallet、Keystore 等独立基础设施。

```
[用户数据] ──加密用 DEK──> [密文数据页]
                          ↑
                       DEK 在内存中

[DEK] ──加密用 KEK──> [加密后的 DEK 持久化到磁盘/KMS]
                      ↑
                  KEK 不离开 HSM/KMS
```

这种设计被称为 **Envelope Encryption (信封加密)**：用一把外层钥匙加密内层钥匙，再用内层钥匙加密数据。优势：

- **密钥分离**：DEK 频繁使用、便于轮换；KEK 高度受保护、几乎不动。
- **轮换效率**：要轮换 KEK 只需重新加密 DEK，无需重新加密数十 TB 的数据。
- **HSM 不暴露**：KEK 永远不离开 HSM/KMS，所有 HSM 操作都是 "用 KEK 解密这把 DEK"，DEK 才进入数据库进程内存。
- **审计可追溯**：所有 KEK 操作都在 HSM/KMS 中留下不可抵赖的日志。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准从未定义密钥管理相关 DDL 或语义。所有 `CREATE MASTER KEY`、`ROTATE KEY`、`ALTER ENCRYPTION KEY` 都是各厂商私有扩展，且语法差异极大。原因与 TDE 类似：

- 密钥管理高度依赖外部基础设施 (HSM、KMS、PKI)，难以抽象为通用 SQL 语法；
- 各厂商绑定到自己的存储引擎、备份系统、复制协议；
- 出口管制 (Export Control) 历史上对加密产品有限制，标准委员会有意回避；
- KMIP、PKCS#11 等行业标准已经覆盖了密钥管理协议层，SQL 层无需重复定义。

行业标准 (非 SQL 标准) 包括：

- **PKCS#11 (1995)**：RSA 安全公司提出的硬件令牌接口标准，几乎所有 HSM 都支持。
- **KMIP (Key Management Interoperability Protocol, 2010)**：OASIS 主导的密钥管理协议，支持密钥的生成、分发、撤销、轮换。
- **JCEKS / PKCS#12**：Java/JVM 生态的本地密钥库格式。

## 支持矩阵 (45+ 引擎)

### 原生密钥管理基础支持

| 引擎 | 原生密钥管理 | KEK/DEK 分层 | 密钥层数 | 起始版本 | 备注 |
|------|------------|------------|---------|---------|------|
| PostgreSQL | 否 (仅扩展/补丁) | -- | -- | -- | 核心无 TDE，也无密钥管理 |
| MySQL | 是 (keyring) | 是 (Master Key + Tablespace Key) | 2 层 | 5.7.11 (2016) | keyring_file / keyring_okv 插件 |
| MariaDB | 是 (Encryption Key Mgmt) | 是 (Key ID + 实际密钥) | 2 层 | 10.1 | file_key_management / aws_key_management |
| SQLite | 否 | -- | -- | -- | SQLCipher 扩展提供 |
| Oracle | 是 (Wallet/HSM) | 是 (Master Key + Table/Tablespace Key) | 2 层 | 10gR2 (2005) | TDE Master Key 在 Wallet/HSM |
| SQL Server | 是 (DMK/CMK + EKM) | 是 (Service Key → DMK → CMK → DEK) | 4 层 | 2008 EE | Always Encrypted 引入 CMK + CEK |
| DB2 | 是 (Native Encryption) | 是 (Master Key + DB Key) | 2 层 | 10.5 FP5 (2014) | 内置或集成 KMIP |
| Snowflake | 是 (层级密钥模型) | 是 (Root → Account → Table → File Key) | 4 层 | GA | 自动每 30 天轮换 |
| BigQuery | 是 (Google KMS / CMEK) | 是 (KEK in KMS, DEK 加密数据) | 2 层 | GA | 默认 Google 管理，可选 CMEK |
| Redshift | 是 (KMS / HSM) | 是 (Cluster Key → Database Key → Block Key) | 3 层 | GA | KMS / CloudHSM |
| DuckDB | 否 | -- | -- | -- | 文件级加密但无密钥管理框架 |
| ClickHouse | 是 (encrypted disk) | 部分 (key_hex 配置) | 1-2 层 | 21.10+ | 仅磁盘级，无成熟密钥管理 |
| Trino | 否 (Connector 级) | -- | -- | -- | 无原生存储 |
| Presto | 否 (Connector 级) | -- | -- | -- | 无原生存储 |
| Spark SQL | 是 (Parquet Modular) | 是 (KEK + DEK per column) | 2 层 | 3.2+ | KMS 集成 (AWS/Hashicorp/Vault) |
| Hive | 是 (HDFS TDE) | 是 (KMS 中 EZ Key + DEK) | 2 层 | 2.6+ | Hadoop KMS |
| Flink SQL | 否 (Connector 级) | -- | -- | -- | 流处理 |
| Databricks | 是 (Cloud KMS) | 是 (Customer-managed Key + DEK) | 2 层 | GA | Unity Catalog 集成 |
| Teradata | 是 (KMIP/HSM) | 是 (Master Key + Database Key) | 2 层 | 16.20+ | Database Encryption Keys |
| Greenplum | 否 (社区) / 是 (商业) | 商业版有 | 2 层 | -- | VMware Tanzu 商业版 |
| CockroachDB | 是 (Enterprise) | 是 (Store Key + Data Key) | 2 层 | 2.1 (2018) | AWS KMS / GCP KMS |
| TiDB | 是 (TiKV) | 是 (Master Key + Data Key) | 2 层 | 4.0 (2020) | AWS KMS / GCP KMS / file |
| OceanBase | 是 (TDE) | 是 (Master Key + Tablespace Key) | 2 层 | 4.0+ | 商业版 |
| YugabyteDB | 是 (Universe Key) | 是 (Universe Key + Data Key) | 2 层 | 2.0+ | 内置或外部 KMS |
| SingleStore | 否 (依赖云) | -- | -- | -- | 依赖云 KMS |
| Vertica | 是 (KMIP) | 是 (Master Key + Data Key) | 2 层 | 9.2+ | KMIP 集成 |
| Impala | 是 (HDFS KMS 继承) | 是 | 2 层 | 继承 Hadoop | -- |
| StarRocks | 否 | -- | -- | -- | 路线图 |
| Doris | 否 | -- | -- | -- | 路线图 |
| MonetDB | 否 | -- | -- | -- | -- |
| CrateDB | 否 | -- | -- | -- | -- |
| TimescaleDB | 否 (随 PG) | -- | -- | -- | -- |
| QuestDB | 否 | -- | -- | -- | -- |
| Exasol | 是 (内置) | 是 | 2 层 | 7.0+ | 内置 KMS |
| SAP HANA | 是 (Secure Store) | 是 (SSFS + 多种密钥) | 多层 | SPS 09 | Secure Store File System (SSFS) |
| Informix | 是 (KMS) | 是 (Master + Database Key) | 2 层 | 12.10 | KMIP / 内置 |
| Firebird | 插件式 | 视插件 | 视插件 | 3.0+ | 用户实现 plugin |
| H2 | 否 (仅密码) | -- | -- | -- | 数据库密码即密钥 |
| HSQLDB | 否 | -- | -- | -- | 仅 crypt_key |
| Derby | 否 | -- | -- | -- | bootPassword |
| Amazon Athena | 是 (KMS) | 是 (S3 SSE-KMS) | 2 层 | GA | 继承 S3 |
| Azure Synapse | 是 (Azure Key Vault) | 是 (TDE Protector + DEK) | 2 层 | GA | -- |
| Google Spanner | 是 (Google KMS / CMEK) | 是 | 2 层 | GA | -- |
| Materialize | 否 | -- | -- | -- | -- |
| RisingWave | 否 | -- | -- | -- | -- |
| InfluxDB | 否 | -- | -- | -- | -- |
| DatabendDB | 是 (云 KMS) | 是 | 2 层 | GA | 对象存储 SSE-KMS |
| Yellowbrick | 是 (内置 + KMIP) | 是 | 2 层 | GA | -- |
| Firebolt | 是 (云 KMS) | 是 | 2 层 | GA | -- |

> 统计：约 30+ / 49 引擎提供原生 KEK/DEK 两层密钥管理；其中 14 个云原生引擎无一例外强制开启自动密钥管理；开源 OLTP 引擎 (PostgreSQL、SQLite、DuckDB、StarRocks、Doris、MonetDB) 普遍缺失。

### HSM (PKCS#11) 集成支持

| 引擎 | PKCS#11 支持 | 配置方式 | 备注 |
|------|------------|---------|------|
| Oracle | 是 (Wallet via HSM) | `WALLET_LOCATION = HSM` | 经典 HSM 集成 |
| SQL Server | 是 (EKM) | `CREATE CRYPTOGRAPHIC PROVIDER` | Extensible Key Management |
| MySQL | 是 (keyring_okv) | OKV (Oracle Key Vault) | 5.7.11+ |
| MariaDB | 是 (HashiCorp Vault) | hashicorp_key_management | 10.5+ |
| DB2 | 是 (HSM via centralized KMIP) | gskit + HSM | 11.5+ |
| PostgreSQL | 否 (核心) / 是 (扩展) | EDB / Cybertec 商业版 | 社区版无 |
| Teradata | 是 (HSM) | 通过 KMIP | 16.20+ |
| Vertica | 是 (KMIP/HSM) | KMIP 协议 | 9.2+ |
| Snowflake | 否 (托管) | 不暴露 | Snowflake 自己管 HSM |
| BigQuery | 是 (Cloud HSM) | Google Cloud HSM | 通过 CMEK |
| Redshift | 是 (CloudHSM) | AWS CloudHSM | -- |
| SAP HANA | 是 (SSFS via PKCS#11) | secure_store_data_volume_encryption | -- |
| Informix | 是 (KMS via KMIP) | -- | -- |
| CockroachDB | 否 (KMS only) | -- | -- |
| TiDB | 否 (KMS only) | -- | -- |

> 注：传统企业 (金融、医疗、政府) 的 HSM 集成几乎是 PKCS#11；云原生引擎几乎都通过云 KMS 间接接入云厂商的 HSM (如 AWS CloudHSM、Azure Dedicated HSM)。

### 云 KMS 集成

| 引擎 | AWS KMS | Azure Key Vault | GCP KMS | Hashicorp Vault |
|------|---------|----------------|---------|----------------|
| Oracle | 是 (OKV + AWS) | 是 | 是 | 是 |
| SQL Server | 是 (EKM 提供商) | 是 (Azure Key Vault EKM) | 是 (有限) | 是 |
| MySQL | 是 (keyring_aws) | -- | -- | 第三方插件 |
| MariaDB | 是 (aws_key_management) | -- | -- | 是 (hashicorp_key_management) |
| PostgreSQL | 是 (商业扩展) | 是 (商业扩展) | 是 (商业扩展) | 是 (商业扩展) |
| DB2 | 是 (KMIP 接 AWS KMS) | 是 | -- | 是 |
| Snowflake | 是 (Tri-Secret Secure) | 是 | 是 | -- |
| BigQuery | -- | -- | 是 (CMEK) | -- |
| Redshift | 是 (KMS/CloudHSM) | -- | -- | -- |
| ClickHouse | 是 (S3 with KMS) | 是 | 是 | -- |
| Spark SQL | 是 | 是 | 是 | 是 |
| Hive | 是 (Hadoop KMS) | -- | 是 | -- |
| Databricks | 是 (Customer-managed) | 是 | 是 | -- |
| CockroachDB | 是 | -- | 是 | -- |
| TiDB | 是 | -- | 是 | -- |
| OceanBase | 是 (商业) | -- | -- | -- |
| YugabyteDB | 是 | 是 | 是 | -- |
| Vertica | 是 (KMIP) | 是 (KMIP) | 是 (KMIP) | -- |
| AWS RDS (任一引擎) | 是 (内置) | -- | -- | -- |
| Azure SQL Database | -- | 是 (内置 / TDE Protector) | -- | -- |
| Google Cloud SQL | -- | -- | 是 (CMEK) | -- |
| SAP HANA | 是 | 是 | 是 | -- |
| Amazon Athena | 是 (S3 SSE-KMS) | -- | -- | -- |
| Azure Synapse | -- | 是 (TDE Protector) | -- | -- |
| Google Spanner | -- | -- | 是 (CMEK) | -- |
| DatabendDB | 是 | 是 | 是 | -- |
| Firebolt | 是 | -- | -- | -- |
| Yellowbrick | 是 | -- | -- | -- |

### 密钥轮换语法 (ROTATE / ALTER KEY)

| 引擎 | 轮换 DEK 语法 | 轮换 KEK 语法 | 是否需要重写数据 |
|------|-------------|-------------|---------------|
| Oracle | `ALTER TABLESPACE ... ENCRYPTION USING 'AES256' REKEY` | `ADMINISTER KEY MANAGEMENT SET KEY` | DEK 轮换需要；KEK 轮换不需要 |
| SQL Server | `ALTER DATABASE ENCRYPTION KEY REGENERATE WITH ALGORITHM = AES_256` | `ALTER MASTER KEY REGENERATE` | DEK 轮换重写所有数据；CMK/DMK 轮换不需要 |
| MySQL | `ALTER INSTANCE ROTATE INNODB MASTER KEY` | (轮换 Master Key 即可) | 无需重写表数据，仅重新加密 Tablespace Key |
| MariaDB | (按 key_id 在密钥管理插件中) | (在外部 KMS 中) | 无需重写 |
| DB2 | `ADMIN_ROTATE_MASTER_KEY` | (HSM/KMIP 中) | DEK 轮换需要重新生成数据密钥 |
| Snowflake | (自动每 30 天) | (自动每 1 年) | 自动后台进行，不影响查询 |
| BigQuery | (CMEK 在 GCP KMS 轮换) | -- | 自动惰性重写 |
| Redshift | `ALTER CLUSTER ... ROTATE ENCRYPTION KEY` | (KMS 中) | 是 (后台重写) |
| CockroachDB | (在 KMS 中创建新密钥再切换) | (在 KMS 中) | 仅新数据使用新密钥 |
| TiDB | (在 KMS 中创建新密钥再切换) | (在 KMS 中) | 仅新数据使用新密钥；旧数据通过 compaction 逐步轮换 |
| Vertica | `ALTER KEY ... ROTATE` | (KMIP 中) | DEK 轮换重写 |
| Teradata | `ROTATE ALL DATABASE KEYS` | -- | DEK 轮换重写 |
| SAP HANA | `ALTER SYSTEM ENCRYPTION KEY USE NEW KEY` | (SSFS 中) | DEK 轮换不重写所有数据 |
| Exasol | `ALTER SYSTEM ROTATE KEY` | -- | -- |
| YugabyteDB | `yb-admin rotate_universe_key` | -- | -- |
| PostgreSQL | (无原生支持) | -- | -- |

### 密钥版本管理

| 引擎 | 密钥版本化 | 可读旧版本 | 历史保留 |
|------|----------|-----------|---------|
| Oracle | 是 (Wallet 历史) | 是 | 完整历史保留 |
| SQL Server | 是 (`KEY_GUID`) | 是 (备份恢复) | 直至显式删除 |
| MySQL | 是 (Master Key ID 递增) | 是 | 无限期 |
| MariaDB | 是 (key_id + version) | 是 | 视插件 |
| Snowflake | 是 (Account Key 版本号) | 是 (历史快照) | 至少 1 年 |
| BigQuery | 是 (KMS 密钥版本) | 是 | KMS 控制 |
| AWS KMS (适用所有 RDS / Redshift) | 是 (KeyId + version) | 是 | 永久 (除非禁用) |
| GCP KMS | 是 (Crypto Key Version) | 是 | 永久 |
| Azure Key Vault | 是 (Key Version URI) | 是 | 软删除 90 天 |
| CockroachDB | 是 (Store Key + Data Key) | 是 | 视 KMS |
| TiDB | 是 (KMS 控制) | 是 | 视 KMS |
| Vertica | 是 (KMIP UUID) | 是 | 视 KMIP 服务器 |
| SAP HANA | 是 (SSFS 版本) | 是 | 完整历史 |
| Spark Parquet | 是 (Key Material 内嵌版本) | 是 | 文件中保留 |

## 各引擎密钥管理详解

### Oracle TDE：Master Key + Database Key (Wallet/HSM)

Oracle 是最早 (2005, 10gR2) 提供企业级 TDE + 密钥管理的数据库。其架构：

```
┌─────────────────────────────────┐
│  Software Wallet / HSM          │
│  └─ TDE Master Encryption Key   │
└─────────────┬───────────────────┘
              │ encrypts
              ▼
┌─────────────────────────────────┐
│  Database Files                 │
│  ├─ Tablespace Encryption Key   │
│  └─ Column Encryption Key       │
└─────────────────────────────────┘
```

```sql
-- 创建 Wallet (12c+ 用 keystore 替代 wallet 关键字)
ADMINISTER KEY MANAGEMENT
    CREATE KEYSTORE '/u01/app/oracle/wallet'
    IDENTIFIED BY "wallet_password";

-- 打开 Keystore
ADMINISTER KEY MANAGEMENT
    SET KEYSTORE OPEN
    IDENTIFIED BY "wallet_password";

-- 设置自动登录 (生产环境慎用)
ADMINISTER KEY MANAGEMENT
    CREATE AUTO_LOGIN KEYSTORE
    FROM KEYSTORE '/u01/app/oracle/wallet'
    IDENTIFIED BY "wallet_password";

-- 创建 Master Key (此时同时生成默认 DEK)
ADMINISTER KEY MANAGEMENT
    SET KEY
    IDENTIFIED BY "wallet_password"
    WITH BACKUP USING 'master_key_backup';

-- 在表空间级开启加密
CREATE TABLESPACE secure_data
    DATAFILE '/data/secure01.dbf' SIZE 1G
    ENCRYPTION USING 'AES256'
    DEFAULT STORAGE(ENCRYPT);

-- 列级加密
CREATE TABLE customers (
    id NUMBER PRIMARY KEY,
    ssn VARCHAR2(11) ENCRYPT USING 'AES256'  -- 列级 DEK
);

-- 切换到 HSM (PKCS#11)
ADMINISTER KEY MANAGEMENT
    SET ENCRYPTION KEY
    IDENTIFIED BY "user_id:password"
    MIGRATE USING "wallet_password"
    WITH BACKUP;

-- Master Key 轮换 (DEK 不变，仅外层 KEK 重新加密)
ADMINISTER KEY MANAGEMENT
    SET KEY
    IDENTIFIED BY "wallet_password"
    WITH BACKUP USING 'rotation_2026';

-- 表空间 DEK 轮换 (重写所有数据)
ALTER TABLESPACE secure_data
    ENCRYPTION USING 'AES256' REKEY;
```

Oracle 的设计特点：

- **Wallet** 是 PKCS#12 标准格式的本地密钥库，默认存放 Master Key。
- **HSM 模式** 下 Master Key 存于 HSM，从不离开；Oracle 通过 PKCS#11 调用 HSM 解密 DEK。
- **Auto Login Wallet** 牺牲安全换便利，重启数据库无需手输密码。生产环境应避免。
- **Oracle Key Vault (OKV)** 是 Oracle 自己的集中式密钥管理服务器，支持 KMIP；可横向集成 MySQL keyring_okv。

### SQL Server TDE：4 层密钥层级 + EKM

SQL Server 自 2008 Enterprise Edition 提供 TDE，2019 起 Standard 也支持。其密钥层级是数据库领域最复杂的：

```
Service Master Key (SMK)
    │  encrypts
    ▼
Database Master Key (DMK)
    │  encrypts
    ▼
Certificate / Asymmetric Key  (Server Certificate)
    │  encrypts
    ▼
Database Encryption Key (DEK)
    │  encrypts
    ▼
Database Pages
```

```sql
-- 1. 创建 master 数据库的 Master Key
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPassword#1';

-- 2. 创建用于 TDE 的服务器证书 (实际是 KEK)
CREATE CERTIFICATE TDE_Cert
    WITH SUBJECT = 'TDE Certificate for Production';

-- 3. 备份证书 (绝对必要！丢失证书 = 丢失数据)
BACKUP CERTIFICATE TDE_Cert
    TO FILE = 'C:\Backup\TDE_Cert.cer'
    WITH PRIVATE KEY (
        FILE = 'C:\Backup\TDE_Cert_PrivateKey.pvk',
        ENCRYPTION BY PASSWORD = 'CertBackupPassword#1'
    );

-- 4. 在目标数据库创建 DEK (用证书加密)
USE ProductionDB;
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE TDE_Cert;

-- 5. 开启 TDE
ALTER DATABASE ProductionDB SET ENCRYPTION ON;

-- 6. 检查加密状态
SELECT db.name, dek.encryption_state, dek.encryption_state_desc
FROM sys.dm_database_encryption_keys dek
JOIN sys.databases db ON dek.database_id = db.database_id;

-- DEK 轮换 (重写所有数据页)
USE ProductionDB;
ALTER DATABASE ENCRYPTION KEY
    REGENERATE WITH ALGORITHM = AES_256;

-- DMK 轮换 (不需要重写数据)
USE master;
ALTER MASTER KEY REGENERATE WITH ENCRYPTION BY PASSWORD = 'NewPassword#1';
```

#### SQL Server EKM (Extensible Key Management)

EKM 允许将 Server Certificate (KEK) 的私钥放在外部 HSM 而非数据库内部：

```sql
-- 1. 启用 EKM
EXEC sp_configure 'EKM provider enabled', 1;
RECONFIGURE;

-- 2. 注册 HSM/KMS 提供商 (例如 Azure Key Vault Connector)
CREATE CRYPTOGRAPHIC PROVIDER AzureKeyVaultProvider
    FROM FILE = 'C:\Program Files\Microsoft\AzureKeyVault\AKVCLR.dll';

-- 3. 创建凭据
CREATE CREDENTIAL AzureCredential
    WITH IDENTITY = 'ContosoVault',
         SECRET = 'application-id|app-secret'
    FOR CRYPTOGRAPHIC PROVIDER AzureKeyVaultProvider;

GRANT ALTER ON CRYPTOGRAPHIC PROVIDER::AzureKeyVaultProvider TO sql_login;
ALTER LOGIN sql_login ADD CREDENTIAL AzureCredential;

-- 4. 从 Key Vault 创建非对称密钥 (KEK 在 HSM 中，永不下载到 SQL Server)
CREATE ASYMMETRIC KEY TDE_AKV_Key
    FROM PROVIDER AzureKeyVaultProvider
    WITH PROVIDER_KEY_NAME = 'TDEKey',
         CREATION_DISPOSITION = OPEN_EXISTING;

-- 5. 用 HSM 中的非对称密钥来加密 DEK
USE ProductionDB;
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER ASYMMETRIC KEY TDE_AKV_Key;

ALTER DATABASE ProductionDB SET ENCRYPTION ON;
```

#### SQL Server Always Encrypted (2016+) 列级加密

Always Encrypted 是 SQL Server 2016 引入的客户端加密模型，DBA 也无法看到明文：

```
Column Master Key (CMK)            Column Encryption Key (CEK)
   │                                       │
   │ stored in:                            │ stored in: 数据库元数据 (ENCRYPTED)
   │  Windows Cert Store /                 │
   │  Azure Key Vault /                    │
   │  HSM (PKCS#11)                        │
   │                                       │
   └──── encrypts ──────►───────────────►──┘
                                           │
                                           ▼
                                   encrypts column data
```

```sql
-- 1. 在 Azure Key Vault 中创建 CMK (此处 CMK 由密钥管理人员创建)
-- (略，通过 PowerShell / CLI 完成)

-- 2. 在 SQL Server 中注册 CMK (仅引用，密钥不在 SQL Server)
CREATE COLUMN MASTER KEY CMK_Auto1
WITH (
    KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT',
    KEY_PATH = 'https://contosokv.vault.azure.net/keys/CMK_Auto1/abcd1234...'
);

-- 3. 创建 CEK，用 CMK 加密 (SQL Server 拿到的是密文 CEK)
CREATE COLUMN ENCRYPTION KEY CEK_Auto1
WITH VALUES (
    COLUMN_MASTER_KEY = CMK_Auto1,
    ALGORITHM = 'RSA_OAEP',
    ENCRYPTED_VALUE = 0x01700000016C006F00...   -- 用 CMK 加密的 CEK
);

-- 4. 在表中标注哪些列加密
CREATE TABLE Patients (
    PatientId INT IDENTITY PRIMARY KEY,
    SSN CHAR(11) COLLATE Latin1_General_BIN2 ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = CEK_Auto1,
        ENCRYPTION_TYPE = DETERMINISTIC,            -- 可索引、可等值查询
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    ) NOT NULL,
    Diagnosis NVARCHAR(200) ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = CEK_Auto1,
        ENCRYPTION_TYPE = RANDOMIZED,                -- 不可索引，最高安全
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
);
```

特点：

- 加密 / 解密在客户端 (.NET, JDBC) 驱动层完成；SQL Server 看到的全是密文。
- 即使 DBA 拿到数据库文件 + 内存 dump，没有 CMK 也无法解密。
- 代价：列只支持有限操作 (确定性可等值查询，随机性不可比较)；JOIN / GROUP BY 受限。
- 2019 引入 **Always Encrypted with Secure Enclaves**：通过 Intel SGX / VBS Enclaves 在服务端可信环境内做范围查询、模糊查询。

### MySQL Keyring Plugin (5.7.11+, 2016)

MySQL 在 5.7.11 引入 keyring 插件框架，支持插件化的密钥后端：

```
┌────────────────────────────────────────┐
│  Keyring Plugin                        │
│  ├─ keyring_file (本地磁盘)            │
│  ├─ keyring_okv (Oracle Key Vault)     │
│  ├─ keyring_aws (AWS KMS)              │
│  ├─ keyring_hashicorp (HashiCorp)      │
│  └─ keyring_encrypted_file (encrypted) │
└────────────┬───────────────────────────┘
             │ stores/retrieves
             ▼
        Master Key (KEK)
             │
             │ encrypts
             ▼
       Tablespace Key (DEK, per .ibd)
             │
             │ encrypts
             ▼
        InnoDB Data Pages
```

```ini
# my.cnf 启用 keyring 插件
[mysqld]
early-plugin-load = keyring_file.so
keyring_file_data = /var/lib/mysql-keyring/keyring
```

```sql
-- 创建加密表 (使用默认 master key)
CREATE TABLE customers (
    id INT PRIMARY KEY,
    ssn VARCHAR(20)
) ENCRYPTION = 'Y';

-- 将现有表改为加密
ALTER TABLE orders ENCRYPTION = 'Y';

-- 轮换 Master Key (重新加密所有 tablespace key, 不重写数据)
ALTER INSTANCE ROTATE INNODB MASTER KEY;

-- 8.0+: 使用 keyring_aws (KEK 在 AWS KMS)
-- my.cnf:
-- early-plugin-load = keyring_aws.so
-- keyring_aws_cmk_id = arn:aws:kms:us-east-1:111122223333:key/abc-...
-- keyring_aws_region = us-east-1
-- keyring_aws_data_file = /var/lib/mysql-keyring/aws_data
-- keyring_aws_conf_file = /var/lib/mysql-keyring/aws_conf

-- 8.0.16+ 支持组件化 (component_keyring_*)
-- mysql.component_keyring_aws_load + my.cnf 配置
```

MySQL 8.0 引入 **redo log / undo log / binary log** 加密：

```ini
[mysqld]
innodb_redo_log_encrypt = ON
innodb_undo_log_encrypt = ON
binlog_encryption = ON
```

### MariaDB Encryption (10.1+)

MariaDB 比 MySQL 更早引入 (10.1, 2015) 数据加密。其密钥管理使用 **加密密钥管理插件 (Encryption Key Management Plugin)**：

```ini
# my.cnf - file_key_management 插件
[mariadb]
plugin-load-add = file_key_management.so
file_key_management_filename = /etc/mysql/keys.txt
file_key_management_filekey = FILE:/etc/mysql/keyfile.key
```

```
# /etc/mysql/keys.txt 格式
1;770A8A65DA156D24EE2A093277530142
2;1F2D3A4B5C6D7E8F9A0B1C2D3E4F5A6B7C8D9E0F1A2B3C4D5E6F7A8B9C0D1E2F
3;0123456789ABCDEF...
```

```sql
-- 创建加密表，指定使用哪把 key_id
CREATE TABLE secrets (
    id INT PRIMARY KEY,
    data VARBINARY(255)
) ENCRYPTED = YES ENCRYPTION_KEY_ID = 2;

-- 全局开启所有表加密
SET GLOBAL innodb_encrypt_tables = ON;
SET GLOBAL innodb_encrypt_log = ON;
SET GLOBAL innodb_encryption_threads = 4;

-- 使用 hashicorp_key_management 插件 (10.5+)
-- plugin-load-add = hashicorp_key_management.so
-- hashicorp_key_management_vault_url = https://vault:8200/
-- hashicorp_key_management_token = <vault-token>
-- hashicorp_key_management_secret_path = mariadb/keys

-- 使用 aws_key_management 插件
-- plugin-load-add = aws_key_management.so
-- aws_key_management_master_key_id = arn:aws:kms:...
```

MariaDB 的设计哲学：密钥 ID 是数字而非 GUID；密钥版本由插件维护而不在数据库内；加密粒度可以细到表级别甚至索引级。

### PostgreSQL：核心无 TDE，密钥管理依赖扩展

PostgreSQL 是最大的"缺失方"。社区从 2016 年起就有 TDE 提案，但因为架构复杂和审查严格，至 PostgreSQL 17 (2024) 仍未合并到核心。商业发行版填补这个空缺：

```sql
-- 选项 1: pgcrypto (列级加密，存在已久但非 TDE)
CREATE EXTENSION pgcrypto;

-- 用对称密钥加密 (密钥来自客户端)
INSERT INTO secrets (data)
VALUES (pgp_sym_encrypt('sensitive', 'mypassword'));

-- 解密
SELECT pgp_sym_decrypt(data::bytea, 'mypassword') FROM secrets;

-- 选项 2: EDB Postgres Advanced Server (商业)
-- 自动 TDE，密钥来自 EDB 自己的密钥管理或外部 HSM
-- ALTER SYSTEM SET edb.tde_status = 'on';

-- 选项 3: Cybertec PostgreSQL TDE (商业)
-- 数据页加密，密钥可来自外部命令
-- initdb --data-encryption --encryption-key-command="get_kek.sh"

-- 选项 4: 文件系统/磁盘级 (LUKS, dm-crypt) - 通用但粗粒度
```

PostgreSQL 社区 TDE 计划 (https://wiki.postgresql.org/wiki/Transparent_Data_Encryption) 中讨论的设计：

- 集群级密钥 (Cluster Key) 由 `cluster_key_command` 配置项动态获取；
- 数据页加密使用 AES-XTS 或 AES-GCM；
- WAL 加密；备份加密；TOAST 加密。

### SAP HANA Secure Store (SSFS)

SAP HANA 的密钥管理由 **Secure Store File System (SSFS)** 实现：

```
SSFS (Secure Store File System)
├─ Persistence Master Key (持久化主密钥)
├─ Database Encryption Master Key
├─ LM Structure Master Key
└─ Internal Application Master Key
       │
       │ encrypts
       ▼
   Page Encryption Key (DEK, per data volume)
       │
       │ encrypts
       ▼
   HANA Data Pages / Redo Log / Backup
```

```sql
-- 检查加密状态
SELECT * FROM SYS.M_PERSISTENCE_ENCRYPTION_STATUS;

-- 启动数据卷加密
ALTER SYSTEM PERSISTENCE ENCRYPTION ON;

-- 启动重做日志加密
ALTER SYSTEM LOG ENCRYPTION ON;

-- 启动备份加密
ALTER SYSTEM BACKUP ENCRYPTION ON;

-- 切换密钥 (生成新的 DEK 并启用)
ALTER SYSTEM PERSISTENCE ENCRYPTION CREATE NEW KEY;
ALTER SYSTEM PERSISTENCE ENCRYPTION USE NEW KEY;

-- 持续轮换：每段时间执行 CREATE + USE，旧密钥保留用于解密历史数据
```

SAP HANA 的 SSFS 主密钥可以放在 HSM (PKCS#11) 中，从而实现外部 KEK：

```
hdbnsutil -secureStoreFile -hsm
    -slot=<slot> -pin=<pin>
    -mechanism=CKM_AES_KEY_WRAP
```

### IBM DB2 Native Encryption

DB2 自 10.5 FP5 (2014) 提供 Native Encryption，集成于 LUW 与 z/OS：

```sql
-- 创建加密数据库 (创建时一次性决定)
CREATE DB SECDB ENCRYPT
    CIPHER AES KEY LENGTH 256
    MASTER KEY LABEL "secdb.master.20260101";

-- 列出当前 master key
SELECT SUBSTR(MK_LABEL, 1, 50), KEY_LIB
FROM TABLE(SYSPROC.ADMIN_GET_ENCRYPTION_INFO()) AS T;

-- 轮换 master key (KEK)
CALL SYSPROC.ADMIN_ROTATE_MASTER_KEY('secdb.master.20260601');

-- 集成 KMIP (KMIP_OBJECT_ID 指向外部 KMS)
-- db2 update dbm cfg using KEYSTORE_TYPE PKCS12
-- db2 update dbm cfg using KEYSTORE_LOCATION /home/db2inst/sqllib/security/keystore.p12
-- 或
-- db2 update dbm cfg using KEYSTORE_TYPE KMIP
-- db2 update dbm cfg using KEYSTORE_LOCATION /etc/kmip/client.cfg

-- 备份加密 (使用单独的密钥)
BACKUP DB SECDB
    ENCRYPT
    CIPHER AES KEY LENGTH 256
    MASTER KEY LABEL "secdb.backup.20260101";
```

### Snowflake：层级密钥模型 + 自动轮换

Snowflake 是云数据仓库中密钥管理最严密的实现，使用 **4 层层级密钥模型**：

```
┌──────────────────────────────────────────────┐
│  Root Key                                    │
│  存储在: HSM (CloudHSM)                      │
│  轮换周期: 每年                              │
└────────────┬─────────────────────────────────┘
             │ encrypts
             ▼
┌──────────────────────────────────────────────┐
│  Account Master Keys (per account)           │
│  存储在: 元数据存储 (加密形式)               │
│  轮换周期: 每 30 天 (自动)                   │
└────────────┬─────────────────────────────────┘
             │ encrypts
             ▼
┌──────────────────────────────────────────────┐
│  Table Master Keys (per table)               │
│  存储在: 元数据存储 (加密形式)               │
│  轮换周期: 每 30 天 (自动)                   │
└────────────┬─────────────────────────────────┘
             │ encrypts
             ▼
┌──────────────────────────────────────────────┐
│  File Keys (per micro-partition file)        │
│  存储在: 文件 footer (加密形式)              │
│  轮换周期: 永不 (因为文件不可变)             │
└────────────┬─────────────────────────────────┘
             │ encrypts
             ▼
        Data (in object storage)
```

Snowflake 的关键创新：

- **每 30 天自动轮换**：账户级、表级密钥都会自动轮换。新数据用新密钥；旧数据保留旧密钥。
- **Periodic Rekeying** (Enterprise+ 选项)：每年自动重写超过 1 年的数据，使其使用新密钥。这意味着任何攻击者拿到的密钥最多有 1 年的"影响窗口"。
- **Tri-Secret Secure** (Business Critical+)：客户管理的 KEK + Snowflake 管理的 KEK + 客户管理的访问令牌，三方任一缺失都无法解密。

```sql
-- Snowflake 中无需任何 SQL 来管理密钥；一切自动
-- 但可查询当前密钥版本
SELECT SYSTEM$GET_ENCRYPTION_KEY_INFO();

-- Tri-Secret Secure 需要客户在 AWS/Azure/GCP KMS 中提供 CMK
-- 然后 Snowflake 账号管理员配置:
-- ALTER ACCOUNT SET KMS_KEY_ARN = 'arn:aws:kms:us-east-1:...:key/...';

-- 启用 periodic rekeying (Business Critical 以上)
ALTER ACCOUNT SET PERIODIC_DATA_REKEYING = TRUE;
```

### BigQuery CMEK / KMS

BigQuery 默认使用 Google 管理的密钥；可选 **Customer-Managed Encryption Keys (CMEK)**，让客户掌握 KEK：

```
┌──────────────────────────────────────────┐
│  Google Cloud KMS                        │
│  └─ Customer-managed KEK                 │
└────────────┬─────────────────────────────┘
             │ wraps
             ▼
┌──────────────────────────────────────────┐
│  BigQuery DEK (per dataset/table)        │
└────────────┬─────────────────────────────┘
             │ encrypts
             ▼
        Table Data in Storage
```

```sql
-- 在 GCP KMS 中创建 KEK
-- gcloud kms keyrings create bq-keyring --location=us
-- gcloud kms keys create bq-cmek --keyring=bq-keyring --location=us --purpose=encryption

-- 创建使用 CMEK 的数据集
CREATE SCHEMA my_secure_dataset
OPTIONS (
    location = 'us',
    default_kms_key_name = 'projects/my-proj/locations/us/keyRings/bq-keyring/cryptoKeys/bq-cmek'
);

-- 创建使用 CMEK 的表
CREATE TABLE my_secure_dataset.patients (
    patient_id INT64,
    diagnosis STRING
)
OPTIONS (
    kms_key_name = 'projects/my-proj/locations/us/keyRings/bq-keyring/cryptoKeys/bq-cmek'
);

-- 查询表的 KMS 密钥
SELECT table_name, options_value
FROM my_secure_dataset.INFORMATION_SCHEMA.TABLE_OPTIONS
WHERE option_name = 'kms_key_name';

-- 轮换 KEK (在 KMS 中)
-- gcloud kms keys versions create --location=us --keyring=bq-keyring --key=bq-cmek
-- BigQuery 会在下次写入时使用新版本，旧版本保留以读取历史数据
```

### AWS RDS：KMS 集成

AWS RDS 上的所有数据库引擎 (MySQL, PostgreSQL, Oracle, SQL Server, MariaDB, Db2, Aurora) 都通过 AWS KMS 提供加密：

```bash
# 创建启用加密的 RDS 实例 (创建时一次性决定，无法之后开启)
aws rds create-db-instance \
    --db-instance-identifier my-encrypted-db \
    --db-instance-class db.t3.medium \
    --engine postgres \
    --master-username admin \
    --master-user-password ... \
    --allocated-storage 100 \
    --storage-encrypted \
    --kms-key-id arn:aws:kms:us-east-1:111122223333:key/abc-...

# 复制快照到另一区域 (可换 KMS key)
aws rds copy-db-snapshot \
    --source-db-snapshot-identifier ... \
    --target-db-snapshot-identifier ... \
    --kms-key-id arn:aws:kms:us-west-2:111122223333:key/def-...

# Aurora 也支持 KMS
aws rds create-db-cluster \
    --db-cluster-identifier my-aurora \
    --engine aurora-postgresql \
    --storage-encrypted \
    --kms-key-id arn:aws:kms:...
```

KMS 集成的关键点：

- **Envelope Encryption**：RDS 从 KMS 申请一个 Data Key，Data Key 的明文保留在 RDS 内存，密文保存在元数据。
- **Per-Volume Encryption**：底层 EBS 卷加密，对数据库进程透明。
- **跨区域复制需要密钥协商**：跨区域备份还原需要在目标区域有可用的 KMS 密钥。
- **CloudHSM** 选项：把 KMS 的 KEK 放在 CloudHSM 中，受 FIPS 140-2 Level 3 保护。
- **轮换**：KMS 自动每年轮换密钥版本；旧版本保留用于解密。

### CockroachDB Enterprise Encryption-at-Rest

CockroachDB 的 TDE 仅企业版可用，使用 **2 层密钥** 模型：

```
Store Key (KEK)
   │
   │ stored in: AWS KMS / GCP KMS / file
   │
   │ encrypts
   ▼
Data Key (DEK)
   │
   │ encrypts
   ▼
RocksDB SST files
```

```bash
# 启动时指定密钥
cockroach start \
    --enterprise-encryption=path=/data,key=/keys/aes-256.key,old-key=/keys/aes-128.key,rotation-period=24h \
    --listen-addr=...

# 在 KMS 中托管
cockroach start \
    --enterprise-encryption=path=/data,key=aws-kms://arn:aws:kms:us-east-1:111:key/abc...

# 触发密钥轮换 (创建新密钥并切换)
cockroach node decommission 3 ...
# 删除旧节点上的密钥后，旧文件由自动 compaction 重写
```

```sql
-- 查看加密状态
SELECT * FROM crdb_internal.kv_store_status;

-- 节点级加密信息
SHOW STORE STATUS;
```

### TiDB：TiKV Encryption with KMS

TiDB 通过 TiKV 存储引擎实现加密，支持 AWS KMS / GCP KMS：

```toml
# tikv.toml - 使用 AWS KMS
[security.encryption]
data-encryption-method = "aes256-ctr"
data-key-rotation-period = "168h"  # 每周轮换 DEK

[security.encryption.master-key]
type = "kms"
key-id = "arn:aws:kms:us-east-1:111122223333:key/abc-..."
region = "us-east-1"
endpoint = ""

# 或本地文件 (开发用)
# [security.encryption.master-key]
# type = "file"
# path = "/etc/tikv/master.key"
```

```sql
-- 查询当前加密状态 (TiDB)
SELECT * FROM information_schema.encryption_status;

-- 旧版本: 使用 ADMIN 命令
ADMIN SHOW DDL JOBS;

-- 轮换密钥的策略
-- TiKV 会自动将 1 周内未访问的 DEK 标记为 retired，但仍保留以解密旧数据
-- compaction 会逐步用新 DEK 重写所有 SST 文件
```

### YugabyteDB：Universe Key

YugabyteDB 用 **Universe Key** 作为整个集群的 KEK：

```bash
# 1. 在主控节点创建 Universe Key
yb-admin --master_addresses ... create_cdc_stream_for_table ...
yb-admin add_universe_key_to_all_masters key_id_1 /path/to/key.bin
yb-admin enable_encryption_in_memory
yb-admin enable_encryption_at_rest key_id_1

# 2. 轮换 Universe Key
yb-admin add_universe_key_to_all_masters key_id_2 /path/to/key2.bin
yb-admin rotate_universe_key_in_memory key_id_2
yb-admin enable_encryption_at_rest key_id_2

# 3. 集成 HashiCorp Vault (Yugabyte Anywhere 商业版)
```

### Vertica：KMIP 集成

Vertica 通过 KMIP 协议集成各种 KMS / HSM：

```sql
-- 从 KMIP 服务器创建 master key
CREATE KEY vmart_key
    USING PARAMETERS
    kmip_server = 'kmip.example.com:5696',
    cmk_uid = 'd3e4f5a6-b7c8-d9e0-f1a2-b3c4d5e6f7a8',
    auth_cert = '/etc/vertica/kmip_client.crt',
    auth_key = '/etc/vertica/kmip_client.key';

-- 设置数据库加密密钥
ALTER DATABASE my_db SET PARAMETER EncryptionKey = 'vmart_key';

-- 轮换密钥
ALTER KEY vmart_key ROTATE;
```

### Spark Parquet Modular Encryption

Spark 3.2+ 支持 Parquet Modular Encryption (PME)，这是 Apache Parquet 2.7+ 的列级加密标准：

```
┌─────────────────────────────────────────┐
│  KMS (AWS KMS / Hashicorp Vault / 自定义)│
│  └─ Master Key                          │
└────────────┬────────────────────────────┘
             │ wraps
             ▼
┌─────────────────────────────────────────┐
│  Footer Key + Column Keys (per file)    │
│  存储在: Parquet 文件 footer 中 (密文)  │
└────────────┬────────────────────────────┘
             │ encrypts
             ▼
       Column data + footer metadata
```

```scala
// Spark 写入加密 Parquet
spark.conf.set("parquet.encryption.kms.client.class",
    "org.apache.parquet.crypto.keytools.mocks.InMemoryKMS")
spark.conf.set("parquet.encryption.key.list",
    "k1: AAECAwQFBgcICQoLDA0ODw==, k2: AAECAAECAAECAAECAAECAA==")
spark.conf.set("parquet.encryption.column.keys",
    "k2: SSN, Salary; k1: PII")
spark.conf.set("parquet.encryption.footer.key", "k1")

df.write.parquet("s3://bucket/encrypted/")
```

特点：
- 可以**对单列加密** (其他列明文)；
- 可以**整文件加密** (footer 也加密)；
- 支持 **AES-GCM** (推荐) 与 **AES-GCM-CTR** (允许部分明文 footer)；
- 与 KMS 解耦：用户自己实现 KMS Client 即可。

## Envelope Encryption 深度解析

### 原理与流程

信封加密 (Envelope Encryption) 是几乎所有现代密钥管理系统的基础：

```
写入数据时:
1. 应用调用 KMS: 生成新 DEK (返回明文 DEK + 密文 DEK)
2. 应用用明文 DEK 加密数据 (在客户端内存中完成)
3. 应用丢弃明文 DEK (从内存清除)
4. 应用持久化: 加密后的数据 + 密文 DEK
   - 密文 DEK 通常存于数据头部、文件 footer 或元数据库

读取数据时:
1. 应用读取: 密文 DEK + 加密数据
2. 应用调用 KMS Decrypt(密文 DEK) → 明文 DEK
3. 应用用明文 DEK 解密数据
4. 应用丢弃明文 DEK
```

### 性能优化：DEK 缓存

每次读取都调用 KMS 性能不可接受。实践中：

```
DEK 缓存策略:
- 进程级缓存: DEK 使用次数到限值或时间到 (默认 5 分钟) 后失效
- 与 KMS 的来回: 每次 GenerateDataKey 调用约 50-200ms (网络延迟)
- 缓存命中后开销: 仅 AES 操作约几微秒

风险:
- 缓存时间越长，密钥泄露窗口越大
- 重启后必须重新拉取
- 需要平衡: 性能 vs 撤销响应时间
```

AWS Encryption SDK / Snowflake / BigQuery 都实现了"用次数限制 + 时间限制"双触发的 DEK 缓存。

### Envelope Encryption 与 KEK 轮换

优雅之处：**轮换 KEK 时只需重新加密 DEK，不需要重写数据**：

```
轮换前:
KEK_v1 ─encrypts─> DEK_密文_v1 ─encrypts─> 数据 (TB 级)

轮换 KEK:
1. 用 KEK_v1 解密 DEK_密文_v1 → DEK_明文
2. 用 KEK_v2 加密 DEK_明文 → DEK_密文_v2
3. 持久化 DEK_密文_v2，丢弃 DEK_明文
4. 数据本身完全不动

成本: O(密钥数) 而非 O(数据量)
```

这就是为什么 Oracle、SQL Server、MySQL 等都能在生产环境频繁轮换 Master Key——只重新加密 DEK，速度极快。

### 多重信封 (Nested Envelope)

Snowflake 4 层、SQL Server 4 层都是嵌套的信封加密：

```
KEK_root ─encrypts─> KEK_account ─encrypts─> KEK_table ─encrypts─> DEK_file ─encrypts─> data
```

每一层都有独立的轮换周期，可以做到：
- KEK_root：每 1 年人工轮换 (HSM 中)
- KEK_account：每 30 天自动轮换
- KEK_table：每 30 天自动轮换
- DEK_file：永不轮换 (因为文件不可变)

层数越多，**爆破半径** (compromise radius) 越小：泄露任意一把中间 KEK 仅影响其下游若干 DEK，而非整个数据库。

## Snowflake 层级密钥模型详解

Snowflake 的实现是公开文档中最详细的层级密钥架构案例。其完整设计：

### 加密的物体与密钥

| 加密对象 | 加密密钥 | 密钥来源 |
|---------|---------|---------|
| Micro-partition file | File Key | per-file 随机生成 |
| File Key | Table Master Key (TMK) | 每表一个 |
| Table Master Key | Account Master Key (AMK) | 每账户一个 |
| Account Master Key | Root Key | Snowflake 全局，存储于 CloudHSM |

### 自动轮换周期

```
Root Key:        每 1 年 (CloudHSM 中)
Account Master:  每 30 天
Table Master:    每 30 天
File Key:        永不 (因 micro-partition 不可变)
Periodic Rekey:  每 1 年 (重写 1 年以上的旧数据)
```

### Tri-Secret Secure 增强模式

Business Critical 及以上账户可启用：

```
                ┌──────────────┐
Snowflake KEK ──┤              │
                │   Composite  ├─ encrypts ─> Account Master Key
Customer KEK  ──┤   Encryption │
                └──────────────┘
```

实际原理是把两把 KEK 通过 XOR 或 KDF 组合成一把"复合 KEK"。客户可以随时撤销自己的 KEK，使 Snowflake 也无法解密数据 ("钥匙撕毁"模式)。

### 跨区域复制下的密钥

Snowflake 的全球化复制 (Replication) 涉及跨区域密钥传递：

```
Source Region                          Target Region
──────────────                          ─────────────
[Account Master Key A] ──ENCRYPT────►─ [stored as ciphertext]
                          shared secret
                          via TLS 1.3
```

实现细节是 Snowflake 在两个区域之间建立基于 TLS 双向认证的密钥协商通道，传输 AMK 的密文形态。

## 密钥轮换策略

密钥轮换 (Key Rotation) 是密钥管理的核心治理流程，不同层级、不同场景采用不同策略。

### 主动轮换 vs 被动轮换

**主动轮换 (Periodic Rotation)**：

定期（如每 30 天、每 1 年）轮换密钥，无论是否有泄露迹象。优势：

- 限制密钥的"暴露窗口"——即便密钥被偷，攻击者也只能解密轮换前的数据。
- 满足合规要求 (PCI-DSS 要求至少每年一次)。
- 平时演练，确保轮换流程在真正需要时不出故障。

**被动轮换 (Reactive Rotation / Emergency Rotation)**：

发生密钥泄露事件后立即轮换。要求：

- 5-30 分钟内完成 KEK 轮换 (因为 KEK 不需要重写数据)；
- 24 小时内开始数据 DEK 轮换的后台任务；
- 30 天内完成全部历史数据的重新加密。

### 各引擎轮换策略对比

| 引擎 | 自动轮换 | 推荐手动周期 | 紧急轮换 RTO | 是否需要重写数据 |
|------|---------|------------|------------|---------------|
| Oracle | 否 | KEK 每年, DEK 每 5 年 | 数小时 (KEK), 周级 (DEK) | DEK 轮换需要 |
| SQL Server | 否 | KEK 每年, DEK 每 2 年 | 数小时 (KEK), 天级 (DEK) | DEK 轮换重写 |
| MySQL | 否 | Master Key 每年 | 几分钟 | 否 |
| MariaDB | 视插件 | 同 MySQL | 几分钟 | 否 |
| DB2 | 否 | 每 2 年 | 数小时 | DEK 轮换重写 |
| Snowflake | 是 (30 天 + 1 年) | -- | < 1 小时 (KEK) | 后台自动 |
| BigQuery | 否 (KMS 控制) | 每年 | < 1 小时 | 惰性重写 |
| AWS RDS (KMS) | 是 (KMS 自动每年) | -- | < 1 小时 | KMS 透明 |
| Azure SQL DB | 是 (Service-Managed) 或客户控制 (CMK) | 每年 | < 1 小时 | 透明 |
| GCP CloudSQL | 是 (CMEK 客户控制) | 每年 | < 1 小时 | 惰性重写 |
| CockroachDB | 否 | 每年 | 数小时 | 渐进 (compaction) |
| TiDB | 否 | 每年 | 数小时 | 渐进 (compaction) |

### 渐进式轮换 (Lazy Rotation)

对于 PB 级数据库，重写所有数据成本太高。LSM 树架构 (CockroachDB / TiDB / Cassandra) 利用 **compaction** 实现"零成本"渐进轮换：

```
T0: 新数据用 DEK_v2 写入；旧 SST 文件继续用 DEK_v1
T1: compaction 触发，合并多个 SST → 合并后的 SST 用 DEK_v2
T2: 经过几轮 compaction，所有旧 SST 都被重写过
T3: 旧 DEK_v1 已无文件引用，可以彻底销毁
```

这种方式将轮换成本摊销到本来就要做的 compaction 中，对在线业务几乎无感。

### 密钥撤销与销毁

**撤销 (Revocation)** 与 **销毁 (Destruction)** 不同：

- **撤销**：禁用密钥，但仍可查询历史；通常 KMS 提供 `DisableKey` 接口；可恢复。
- **销毁**：彻底删除密钥，所有用此密钥加密的数据**永久不可恢复**；不可逆。

NIST SP 800-57 推荐：

```
密钥状态转换图:
  Pre-activated → Active → Suspended ⇄ Active
                       └─→ Deactivated → Compromised → Destroyed
                                      └─→ Archived → Destroyed
```

AWS KMS 销毁前要等待 7-30 天 ("scheduled deletion")，给运维窗口反悔；GCP KMS 同样支持 24 小时-30 天延期。

## 关键发现

1. **PostgreSQL 是最大遗憾**：作为流行度第一的开源 OLTP 数据库，至 PostgreSQL 17 仍无核心 TDE / 密钥管理支持。社区已讨论 8+ 年，分歧主要在性能开销与代码复杂度。商业发行版 (EDB, Cybertec) 填补这个空缺。

2. **云原生引擎完胜传统引擎**：Snowflake、BigQuery、Spanner、Aurora 等几乎"零运维密钥管理"——开箱即用、自动轮换、跨区域同步。传统引擎需要 DBA 手动配置 Wallet、备份证书、轮换密钥。

3. **KEK/DEK 两层是标配**：Oracle、SQL Server、MySQL、Snowflake、所有云数据库都采用 KEK + DEK 两层模型；区别仅在层数 (2 层 vs 4 层) 和密钥后端 (Wallet vs HSM vs KMS)。

4. **Always Encrypted 是异类**：SQL Server 2016 引入的 Always Encrypted 是少数让 DBA 也无法看到明文的方案。代价是查询能力受限 (确定性可等值，随机性几乎无法查询)。SGX/VBS Enclaves 缓解了这一限制。

5. **Snowflake 的 30 天自动轮换是新基准**：传统数据库每年轮换一次已被认为合规；Snowflake 提升到 30 天，使密钥泄露的影响窗口缩短一个数量级。开源数据库目前还做不到。

6. **HSM (PKCS#11) 是金融与政府的硬要求**：传统企业 (尤其是金融、医疗、政府) 几乎都要求 KEK 在 PKCS#11 兼容的 HSM 中，受 FIPS 140-2 Level 3 保护。云 KMS 也提供 CloudHSM 等高保护选项。

7. **KMIP 是异构密钥服务的桥梁**：当企业需要让多个数据库 (Oracle / SQL Server / Vertica / DB2) 共用一个密钥服务器时，KMIP 是唯一的开放标准选择。商业 KMIP 服务器 (Thales CipherTrust, IBM Guardium) 是这个领域的主流。

8. **BERNOULLI 与渐进轮换的本质差异**：传统 RDBMS 的 DEK 轮换会重写所有数据 (Oracle, SQL Server)；LSM 树架构 (CockroachDB / TiDB / Cassandra) 通过 compaction 实现零成本轮换，是分布式数据库相对单机数据库的一个明显优势。

9. **三密钥安全 (Tri-Secret Secure) 的趋势**：Snowflake、AWS、Azure 都提供"客户与厂商共同持有 KEK"的模式；客户随时可以"撕毁钥匙"使整个数据集失效。这是对"厂商内鬼" (insider threat) 风险的回应。

10. **MySQL keyring 插件框架的影响力**：MySQL 5.7.11 (2016) 引入的 keyring 插件框架被很多其他数据库借鉴 (MariaDB 加密插件、TiKV master key 配置都有类似设计)：抽象出一个密钥管理 SPI，让不同后端可插拔。

11. **没有 SQL 标准恰恰是优势**：SQL 标准缺位让各引擎可以自由集成 HSM、KMS、PKI、KMIP 等不断进化的外部基础设施，而不被陈旧的语法束缚。如果 SQL 早期标准化了 `CREATE KEY ... FOR ENCRYPTION USING ...` 这样的语法，可能反而阻碍今天的多样化集成。

12. **密钥备份是另一个被忽视的话题**：丢失证书 / Wallet 的密码 = 永久数据丢失，比硬盘损坏后果更严重。SQL Server 的 `BACKUP CERTIFICATE`、Oracle 的 Wallet 备份、KMS 的密钥导出 (or 不可导出) 都需要明确流程。生产系统必须有"密钥灾难恢复演练"。

## 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 严格合规 (PCI-DSS, HIPAA) + 自管 IT | Oracle TDE + HSM | 业内最久的成熟方案，HSM 与 Wallet 管理完善 |
| 中小型企业 + 自管 IT | SQL Server TDE + 备份证书 | 配置最简单，文档丰富 |
| MySQL 生态 | MySQL 8.0 + keyring_aws | 集成 AWS KMS，配置简洁 |
| 云原生 SaaS | Snowflake + Tri-Secret Secure | 自动轮换 + 客户可撤销 |
| 大数据分析 | BigQuery CMEK 或 Databricks Unity Catalog | KMS 集成完善 |
| 严格 DBA 隔离 | SQL Server Always Encrypted | DBA 看不到明文 |
| HTAP / 分布式 OLTP | TiDB + AWS KMS | 渐进式轮换，无停机 |
| 内部敏感数据 + 自管 | PostgreSQL + Cybertec / EDB | 仍是 PostgreSQL 生态 |
| 极端隐私要求 | SQL Server AE + Secure Enclaves 或 Snowflake Tri-Secret | 多方协同保护 |
| 成本敏感 + 简单需求 | MariaDB file_key_management | 开源免费，本地文件密钥 |

## 参考资料

- NIST SP 800-57 Part 1: [Recommendation for Key Management](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final)
- PCI-DSS v4.0 §3.5/3.6: [Payment Card Industry Data Security Standard](https://www.pcisecuritystandards.org/)
- PKCS#11 v3.1: [Cryptographic Token Interface Standard](https://docs.oasis-open.org/pkcs11/pkcs11-base/v3.1/pkcs11-base-v3.1.html)
- KMIP v2.1: [Key Management Interoperability Protocol Specification](https://docs.oasis-open.org/kmip/kmip-spec/v2.1/kmip-spec-v2.1.html)
- Oracle: [Advanced Security Guide - Configuring TDE](https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/)
- SQL Server: [Transparent Data Encryption](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/transparent-data-encryption)
- SQL Server: [Always Encrypted](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-database-engine)
- MySQL: [The MySQL Keyring](https://dev.mysql.com/doc/refman/8.0/en/keyring.html)
- MariaDB: [Data-at-Rest Encryption](https://mariadb.com/kb/en/data-at-rest-encryption/)
- DB2: [Native Encryption](https://www.ibm.com/docs/en/db2/11.5?topic=security-db2-native-encryption)
- Snowflake: [End-to-End Encryption / Hierarchical Key Model](https://docs.snowflake.com/en/user-guide/security-encryption-end-to-end)
- Snowflake: [Tri-Secret Secure](https://docs.snowflake.com/en/user-guide/security-encryption-manage)
- BigQuery: [Customer-managed Encryption Keys (CMEK)](https://cloud.google.com/bigquery/docs/customer-managed-encryption)
- AWS: [Key Management Service Cryptographic Details](https://docs.aws.amazon.com/kms/latest/cryptographic-details/)
- AWS RDS: [Encrypting Amazon RDS resources](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html)
- Azure: [Azure Key Vault and TDE Protector](https://learn.microsoft.com/en-us/azure/azure-sql/database/transparent-data-encryption-byok-overview)
- CockroachDB: [Encryption At Rest](https://www.cockroachlabs.com/docs/stable/encryption.html)
- TiDB: [Encryption at Rest](https://docs.pingcap.com/tidb/stable/encryption-at-rest)
- SAP HANA: [Data and Log Volume Encryption](https://help.sap.com/docs/SAP_HANA_PLATFORM/b3ee5778bc2e4a089d3299b82ec762a7/dc01f36fbb5710148b668201a6e95cf2.html)
- Spark: [Parquet Modular Encryption](https://spark.apache.org/docs/latest/sql-data-sources-parquet.html#columnar-encryption)
- Verizon Data Breach Investigations Report (DBIR), 历年版本
