# 透明数据加密 (Transparent Data Encryption)

数据库的最后一道防线不是 SQL 注入防护，也不是访问控制，而是物理介质被偷走时——透明数据加密决定了那块硬盘是无价的金矿还是一堆乱码。

## 为什么 TDE 至关重要

透明数据加密 (Transparent Data Encryption, TDE) 在数据库引擎层对静态数据 (data-at-rest) 进行加密。"透明" 指应用程序无需修改 SQL，加密/解密由引擎在 I/O 路径上自动完成。当数据库文件、备份文件或磁盘介质被未授权方获取时，没有密钥就无法读取数据。

合规法规对静态数据加密的要求几乎是强制性的：

- **HIPAA** (美国健康保险流通与责任法案)：受保护健康信息 (PHI) 的存储介质必须加密，§164.312(a)(2)(iv) 将加密列为可寻址 (addressable) 安全措施。
- **PCI-DSS v4.0** (支付卡行业数据安全标准)：要求 3.5 / 3.6 强制要求主账号 (PAN) 在存储时必须使用强加密 (AES-128 及以上)，并管理加密密钥。
- **GDPR** (欧盟通用数据保护条例)：第 32 条要求实施"适当的技术措施"保护个人数据，加密是被明确推荐的措施之一；数据泄露时若数据已加密，可豁免通知义务 (Article 34.3.a)。
- **SOX / FedRAMP / CCPA / 中国《数据安全法》**：均有类似的静态数据加密要求。

TDE 与列加密 / 应用层加密的核心差异：

1. **TDE**：在数据页 / 表空间 / 文件级别加密，加密发生在 buffer pool 与磁盘之间，内存中数据是明文。优势是对应用透明、性能开销小；劣势是对数据库管理员 (DBA) 不透明，DBA 仍可看到所有数据。
2. **列加密 / 应用加密**：在特定列或应用层加密，加密在客户端或 SQL 层完成。优势是 DBA 也无法访问明文 (SQL Server Always Encrypted)；劣势是需要修改应用、查询能力受限 (无法范围查询、聚合)。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准从未定义透明数据加密相关的 DDL 或语义。所有关于 TDE 的语法、密钥管理、加密算法、密钥轮换都是各厂商私有扩展。这与采样 (TABLESAMPLE)、窗口函数等已被标准化的特性形成鲜明对比。

原因有几个：

- 加密属于物理存储层 (physical layer)，SQL 标准聚焦于逻辑数据模型；
- 密钥管理高度依赖外部基础设施 (HSM、KMS、PKI)，难以抽象为通用 SQL 语法；
- 各厂商加密实现绑定到自己的存储引擎、备份系统、复制协议；
- 出口管制 (Export Control) 历史上对加密算法有限制，标准委员会有意回避。

因此本文的所有语法都是引擎私有的，跨数据库迁移加密配置几乎不可能。

## 支持矩阵

### TDE 基础支持 (表空间 / 数据库 / 文件级)

| 引擎 | TDE 类型 | 加密粒度 | 默认算法 | 起始版本 | 备注 |
|------|----------|----------|----------|----------|------|
| PostgreSQL | 无原生 | -- | -- | -- | 仅 pgcrypto 列级；社区争论 15 年未合并 |
| MySQL | 表空间加密 | 表空间/表 | AES-256 | 5.7.11 (2016) | InnoDB 专属 |
| MariaDB | Data-at-Rest | 表空间/表/日志 | AES-CBC | 10.1 | 比 MySQL 更早 |
| SQLite | 无原生 | -- | -- | -- | SQLCipher 第三方扩展 |
| Oracle | TDE | 列/表空间/数据库 | AES-256 | 10gR2 (2005) | Advanced Security 选件，单独许可 |
| SQL Server | TDE | 数据库 | AES-256 | 2008 Enterprise | 2019 起 Standard 也支持 |
| DB2 | Native Encryption | 数据库 | AES-256 | 10.5 FP5 (2014) | LUW 与 z/OS |
| Snowflake | 自动 | 全部数据 | AES-256 | GA | 强制开启，无法关闭 |
| BigQuery | 自动 | 全部数据 | AES-256 | GA | Google 管理或 CMEK |
| Redshift | 集群加密 | 全部数据 | AES-256 | GA | 创建集群时一次性决定 |
| DuckDB | 无 | -- | -- | -- | 文件加密通过 OS 层 |
| ClickHouse | Encrypted Disk | 磁盘卷 | AES-128-CTR | 21.10 | 通过 storage policy |
| Trino | Connector 级 | 取决于源 | -- | -- | 自身无存储 |
| Presto | Connector 级 | 取决于源 | -- | -- | 同 Trino |
| Spark SQL | 文件级 | Parquet/ORC | AES-128/256-GCM | 3.2+ | Parquet Modular Encryption |
| Hive | 文件级 | HDFS TDE | AES-CTR | 2.6+ | HDFS Encryption Zone |
| Flink SQL | Connector 级 | 取决于源 | -- | -- | 流处理无持久存储 |
| Databricks | DBFS 加密 | 全部 | AES-256 | GA | 云存储层 + Unity Catalog |
| Teradata | TDE | 表 | AES-256 | 16.20 | Database Encryption |
| Greenplum | 无原生 (社区) | -- | -- | -- | VMware Tanzu 商业版有 |
| CockroachDB | Enterprise TDE | Store | AES-128/192/256-CTR | 2.1 (2018) | Enterprise 许可 |
| TiDB | TDE | TiKV store | AES-128/192/256-CTR | 4.0 (2020) | 基于 RocksDB 加密 |
| OceanBase | TDE | 表空间 | AES-256 | 4.0+ | 商业版 |
| YugabyteDB | 集群加密 | 全部数据 | AES-128/192/256 | 2.0+ | 静态加密 + 在途加密 |
| SingleStore | 无原生 | -- | -- | -- | 依赖云存储加密 |
| Vertica | TDE | 数据库 | AES-256 | 9.2+ | KMIP 集成 |
| Impala | 文件级 | HDFS TDE | AES-CTR | 继承 Hadoop | -- |
| StarRocks | 无原生 | -- | -- | -- | 路线图中 |
| Doris | 无原生 | -- | -- | -- | 路线图中 |
| MonetDB | 无 | -- | -- | -- | -- |
| CrateDB | 无原生 | -- | -- | -- | 依赖磁盘 LUKS |
| TimescaleDB | 无 (随 PG) | -- | -- | -- | 同 PostgreSQL 缺失 |
| QuestDB | 无 | -- | -- | -- | -- |
| Exasol | TDE | 全集群 | AES-256 | 7.0+ | -- |
| SAP HANA | Data Volume Encryption | 数据卷/日志/备份 | AES-256-CBC | SPS 09 | 内置密钥库 |
| Informix | TDE | 数据库 | AES-128/192/256 | 12.10 | -- |
| Firebird | 数据库加密 | 数据库 | 插件式 | 3.0+ | 用户提供 plugin |
| H2 | 数据库加密 | 数据库 | AES/XTEA | 早期 | `CIPHER=AES` |
| HSQLDB | 加密数据库 | 数据库 | AES | 2.0+ | `crypt_key` 配置 |
| Derby | 加密数据库 | 数据库 | DES/AES | 10.0+ | `dataEncryption=true` |
| Amazon Athena | 自动 | S3 对象 | AES-256/SSE-KMS | GA | S3 SSE 继承 |
| Azure Synapse | TDE | 数据库 | AES-256 | GA | 默认开启 |
| Google Spanner | 自动 | 全部数据 | AES-256 | GA | + CMEK 选项 |
| Materialize | 无原生 | -- | -- | -- | 依赖云盘 |
| RisingWave | 无原生 | -- | -- | -- | -- |
| InfluxDB | 无原生 | -- | -- | -- | 依赖文件系统加密 |
| DatabendDB | 自动 (云) | 对象存储 | AES-256 | GA | S3/GCS 加密 |
| Yellowbrick | TDE | 全集群 | AES-256 | GA | 内置 KMS |
| Firebolt | 自动 | 全部数据 | AES-256 | GA | 完全托管 |

> 统计：约 33 / 49 引擎提供某种形式的 TDE 或自动加密；其中云原生引擎几乎都是 "默认开启不可关闭"，开源 OLTP 引擎 (PostgreSQL、SQLite、DuckDB、StarRocks、Doris) 普遍缺失。

### 列级加密支持

| 引擎 | 列级加密 | 函数 / 语法 | 客户端密钥 | 范围查询 |
|------|---------|------------|----------|----------|
| PostgreSQL | pgcrypto | `pgp_sym_encrypt()` / `encrypt()` | 否 | 不支持 |
| MySQL | 函数级 | `AES_ENCRYPT()` / `AES_DECRYPT()` | 否 | 不支持 |
| MariaDB | 函数级 | `AES_ENCRYPT()` | 否 | 不支持 |
| Oracle | DBMS_CRYPTO + TDE 列 | `ENCRYPT` 列属性 | 否 | 部分 (确定性) |
| SQL Server | TDE 列 + Always Encrypted | `ENCRYPTBYKEY()` / `ENCRYPTED WITH` | 是 (AE) | 仅确定性 |
| DB2 | 列函数 | `ENCRYPT()` / `DECRYPT_CHAR()` | 否 | 否 |
| Snowflake | 函数 | `ENCRYPT()` / `DECRYPT()` | 否 | 否 |
| BigQuery | KMS 函数 | `AEAD.ENCRYPT()` / `KEYS.NEW_KEYSET()` | 是 (envelope) | 否 |
| Redshift | 函数 | `AES_ENCRYPT()` (UDF) | 否 | 否 |
| Vertica | 函数 | -- | 否 | 否 |
| SAP HANA | 列加密 | DDL `ENCRYPTED` | 否 | 部分 |
| Teradata | 列加密 | -- | 否 | 否 |
| 其他 | 通常无 | -- | -- | -- |

### Always Encrypted (客户端加密)

| 引擎 | 支持 | 密钥模型 | 确定性查询 | 计算飞地 (Enclave) |
|------|------|---------|----------|------------------|
| SQL Server | 2016+ | CMK + CEK | 是 (确定性加密) | 2019+ (Secure Enclaves) |
| Azure SQL | 是 | CMK 在 Azure Key Vault | 是 | 是 |
| 其他 | -- | -- | -- | -- |

> SQL Server Always Encrypted 是市场上唯一原生的客户端透明加密方案，密钥永远不离开客户端，DBA 无法看到明文。

### 密钥管理 (Key Management)

| 引擎 | 本地密钥库 | KMS 集成 | HSM (PKCS#11/KMIP) | 主密钥位置 |
|------|----------|----------|-------------------|----------|
| Oracle | Oracle Wallet / SEPS | OCI Vault | 是 | Wallet 或 HSM |
| SQL Server | DPAPI / Service MK | Azure Key Vault | EKM (Extensible Key Management) | Server / KV |
| MySQL | keyring_file / keyring_encrypted_file | keyring_aws / keyring_oci | keyring_okv (Oracle Key Vault), keyring_hashicorp | 插件式 |
| MariaDB | file_key_management | AWS KMS | Eperi/Hashicorp 插件 | 插件式 |
| PostgreSQL | -- (无原生) | -- | -- | -- |
| DB2 | 本地 keystore (PKCS#12) | -- | KMIP, PKCS#11 | Keystore 或 HSM |
| Snowflake | 内部分层密钥 | 自动 | -- | Snowflake 管理 |
| BigQuery | Google 管理 | Cloud KMS (CMEK) | Cloud HSM | Google 或 KMS |
| Redshift | 内置 | AWS KMS | AWS CloudHSM | KMS 主密钥 |
| ClickHouse | 配置文件 | -- | -- | XML 配置 |
| CockroachDB | 文件 | AWS KMS / GCP KMS | -- | 文件或 KMS |
| TiDB | 文件 | AWS KMS / GCP KMS / Azure KV | -- | KMS 推荐 |
| OceanBase | 内置 | -- | KMIP | -- |
| YugabyteDB | 内置 | AWS KMS / GCP KMS / Azure KV / HashiCorp Vault | -- | KMS |
| Vertica | 内置 | AWS KMS | KMIP | -- |
| SAP HANA | Local Secure Store | AWS KMS / Azure KV | PKCS#11 | LSS 或 HSM |
| Teradata | TDE Wallet | KMIP | KMIP HSM | Wallet 或 HSM |
| Exasol | 内置 | -- | KMIP | -- |
| Spark/Parquet | 文件配置 | KMS Client 接口 | 自定义 KMS | KMS |
| Databricks | 内置 | AWS KMS / Azure KV / GCP KMS | -- | 客户管理或 Databricks 管理 |
| Azure Synapse | Service-Managed | Azure Key Vault (BYOK) | Azure Managed HSM | Azure |
| Google Spanner | 内置 | Cloud KMS (CMEK) | Cloud HSM | Google 或 KMS |

### 加密算法 (AES-128 vs AES-256)

| 引擎 | AES-128 | AES-192 | AES-256 | 模式 |
|------|---------|---------|---------|------|
| Oracle | 是 | 是 | 是 | CBC / CFB / GCM (19c) |
| SQL Server | 是 | 是 | 是 | CBC (TDE 默认 AES-256) |
| MySQL | -- | -- | 是 | AES-256-CBC (innodb_encrypt) |
| MariaDB | 是 | 是 | 是 | CBC / CTR |
| DB2 | 是 | 是 | 是 | CBC |
| ClickHouse | 是 | -- | 是 | CTR (AES-128-CTR 默认) |
| CockroachDB | 是 | 是 | 是 | CTR |
| TiDB | 是 | 是 | 是 | CTR |
| Snowflake | -- | -- | 是 | GCM |
| BigQuery | -- | -- | 是 | GCM |
| Redshift | -- | -- | 是 | CBC |
| Vertica | -- | -- | 是 | CBC |
| SAP HANA | -- | -- | 是 | CBC |
| Spark Parquet | 是 | -- | 是 | GCM (推荐) / CTR |
| H2 | 是 | -- | 是 | -- |
| 其他 | 通常 256 | -- | 是 | -- |

> 趋势观察：新引擎几乎统一选择 AES-256-GCM (含完整性校验)，老牌商业引擎仍以 AES-CBC 为主以保持向后兼容。

### 密钥轮换 (Key Rotation)

| 引擎 | 主密钥轮换 | 数据加密密钥轮换 | 在线轮换 | 备注 |
|------|----------|---------------|---------|------|
| Oracle | `ADMINISTER KEY MANAGEMENT SET KEY` | 自动 | 是 | 仅重加密 master key |
| SQL Server | `ALTER DATABASE ENCRYPTION KEY REGENERATE` | 是 | 是 | 后台扫描重加密 |
| MySQL | `ALTER INSTANCE ROTATE INNODB MASTER KEY` | -- | 是 | 仅 master key |
| MariaDB | 自动版本化 | 是 | 是 | 后台 key rotation thread |
| DB2 | `ADMIN_ROTATE_MASTER_KEY()` | -- | 是 | -- |
| Snowflake | 30 天自动 | 自动分层 | 是 | 完全自动 |
| BigQuery | KMS 控制 | 自动 | 是 | 通过 Cloud KMS |
| Redshift | 手动或自动 (年) | 自动 | 是 | KMS rotate |
| CockroachDB | 配置文件更新后自动 | 是 | 是 | 后台重写 |
| TiDB | 重启 + 配置 | 是 | 部分 | 需协调 PD |
| YugabyteDB | `yb-admin rotate_universe_key` | 是 | 是 | -- |
| Vertica | `ALTER DATABASE ROTATE KEY` | 是 | 是 | -- |
| SAP HANA | 内置工具 | 是 | 是 | -- |

### 性能开销

| 引擎 | OLTP 开销 | OLAP 开销 | CPU 增加 | 备注 |
|------|---------|---------|---------|------|
| Oracle TDE 表空间 | 3-5% | 5-8% | 中 | 利用 Intel AES-NI |
| SQL Server TDE | 2-4% | 5-10% | 中 | 整库扫描重加密耗时长 |
| MySQL InnoDB | 5-8% | -- | 中 | -- |
| MariaDB | 3-7% | -- | 中 | -- |
| DB2 Native Encryption | 1-3% | 3-5% | 低 | -- |
| Snowflake | 不可测量 | 不可测量 | 用户不感知 | 全平台加密 |
| BigQuery | 不可测量 | 不可测量 | -- | 同上 |
| Redshift | <5% | <5% | 低 | -- |
| ClickHouse | 5-10% | 10-15% | 中 | CTR 模式较快 |
| CockroachDB | 5-10% | -- | 中 | 全栈 AES-NI |
| TiDB | 5-10% | -- | 中 | -- |
| Spark Parquet | -- | 5-30% | 中-高 | GCM 比 CTR 慢 |

> Intel AES-NI 指令集 (2010+) 使硬件加速 AES 加解密成为可能，开销从 30% 降至 5% 以下；ARM v8 Crypto Extensions 提供等价能力。

### 许可层级 (Free vs Enterprise)

| 引擎 | TDE 免费 | TDE 需 Enterprise/付费 |
|------|---------|----------------------|
| Oracle | -- | 需 Advanced Security Option (按 CPU 单独定价，约 \$15K/CPU) |
| SQL Server | 2019+ Standard 起 | 2008-2017 仅 Enterprise |
| MySQL | 是 (Community) | 部分高级 KMS 需企业版 |
| MariaDB | 是 (Community) | -- |
| PostgreSQL | (无) | EnterpriseDB / Crunchy / Fujitsu 商业版有 |
| DB2 | -- | Native Encryption 需许可 |
| CockroachDB | -- | Enterprise 许可 |
| TiDB | 是 | -- |
| YugabyteDB | 是 | -- |
| ClickHouse | 是 | -- |
| Vertica | 是 | -- |
| Greenplum | -- | VMware Tanzu 商业版 |
| Snowflake/BigQuery/Redshift 等云服务 | 内含 | -- |

> Oracle TDE 是业界最贵的加密功能之一，单独的 ASO 许可费用常使中型部署直接放弃 TDE；这是 Percona 与 EnterpriseDB 客户的主要价值主张之一。

### 备份文件加密

| 引擎 | 备份加密 | 与 TDE 关系 | 算法 |
|------|---------|------------|------|
| Oracle RMAN | 是 | 独立 (可用 wallet 或 password) | AES-128/192/256 |
| SQL Server | 是 (2014+) | 独立 (但常用同证书) | AES-128/192/256 / Triple DES |
| MySQL mysqldump | 否 | 需手动 OpenSSL pipe | -- |
| MySQL Enterprise Backup | 是 | 是 | AES-256 |
| MariaDB mariabackup | 是 | 是 | AES-256 |
| DB2 BACKUP | 是 | 是 | AES-256 |
| PostgreSQL pg_dump | 否 | -- | (gpg/openssl pipe) |
| pgBackRest | 是 (扩展) | -- | AES-256-CBC |
| Snowflake | 自动 | 是 | AES-256 |
| BigQuery | 自动 | 是 | AES-256 |
| Redshift snapshot | 是 | 是 | AES-256 |
| SAP HANA | 是 | 是 | AES-256 |

### WAL / Redo / Binlog 加密

| 引擎 | WAL/Redo 加密 | Binlog 加密 | Undo 加密 |
|------|--------------|-----------|----------|
| Oracle | 是 (Redo Log) | -- | 是 (Undo) |
| SQL Server | 是 (Log) | -- | -- |
| MySQL | 是 (8.0+ Redo) | 是 (8.0.14+) | 是 (8.0+) |
| MariaDB | 是 (10.1+ Redo) | 是 (10.1+) | -- |
| DB2 | 是 | -- | -- |
| PostgreSQL | -- (无原生) | -- (无 binlog) | -- |
| CockroachDB | 是 | -- | -- |
| TiDB | 是 (Raft log + WAL) | -- | -- |
| YugabyteDB | 是 | -- | -- |
| Snowflake/BigQuery 等 | 自动 | -- | -- |

> MySQL 8.0.14 (2019) 才补齐 binlog 加密，是 InnoDB 完整加密路径的最后一块拼图。在此之前，binlog 是 GDPR / PCI-DSS 审计中被反复指出的明文泄漏点。

## 各引擎详解

### Oracle TDE (业界先驱)

Oracle 在 10gR2 (2005) 引入 TDE，是第一个商用数据库的透明加密实现，至今仍是事实上的设计参考。

```sql
-- 1. 配置 wallet 位置 (sqlnet.ora)
-- ENCRYPTION_WALLET_LOCATION =
--   (SOURCE = (METHOD = FILE)
--     (METHOD_DATA = (DIRECTORY = /u01/app/oracle/admin/orcl/wallet)))

-- 2. 创建并打开 keystore (12c+ 语法)
ADMINISTER KEY MANAGEMENT
    CREATE KEYSTORE '/u01/app/oracle/admin/orcl/wallet'
    IDENTIFIED BY "WalletPassword#123";

ADMINISTER KEY MANAGEMENT
    SET KEYSTORE OPEN IDENTIFIED BY "WalletPassword#123";

-- 3. 设置 master encryption key
ADMINISTER KEY MANAGEMENT
    SET KEY IDENTIFIED BY "WalletPassword#123" WITH BACKUP;

-- 4. 列级加密 (10gR2 起)
CREATE TABLE customers (
    id        NUMBER PRIMARY KEY,
    name      VARCHAR2(100),
    ssn       VARCHAR2(11) ENCRYPT USING 'AES256' NO SALT,
    credit    VARCHAR2(20) ENCRYPT USING 'AES256'
);

-- 5. 表空间加密 (11gR1 起，推荐方案)
CREATE TABLESPACE secure_ts
    DATAFILE '/u01/app/oracle/oradata/orcl/secure01.dbf' SIZE 100M
    ENCRYPTION USING 'AES256'
    DEFAULT STORAGE(ENCRYPT);

-- 6. 整库加密 (12.2+)
ALTER TABLESPACE users ENCRYPTION ONLINE
    USING 'AES256' ENCRYPT FILE_NAME_CONVERT =
    ('users01.dbf', 'users01_enc.dbf');

-- 7. 主密钥轮换
ADMINISTER KEY MANAGEMENT
    SET ENCRYPTION KEY IDENTIFIED BY "WalletPassword#123" WITH BACKUP;
```

Oracle TDE 关键设计点：

- **两层密钥架构**：表/表空间使用数据加密密钥 (DEK)，DEK 本身被存储在数据字典中并由 master key 加密；轮换 master key 只需重加密少量 DEK 元数据，无需重写数据文件。
- **Oracle Wallet (PKCS#12)**：`ewallet.p12` 文件存放 master key，密码保护；`cwallet.sso` 是自动登录版本，启动时无需人工输入。
- **HSM 集成**：可将 master key 存放在符合 PKCS#11 接口的 HSM (Thales、SafeNet、Oracle Key Vault) 中。
- **许可成本**：Advanced Security Option 是 Oracle 数据库企业版的可选附加包，按 CPU 计费，2024 年定价约 \$15,000/CPU + 22% 年维护，是部署 Oracle TDE 的主要门槛。

### SQL Server TDE 与 Always Encrypted

SQL Server 在 2008 Enterprise 引入 TDE，2016 引入 Always Encrypted，二者解决不同威胁模型。

```sql
-- ============ TDE：服务端透明加密 ============

-- 1. 在 master 数据库创建 master key
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPwd!2024';

-- 2. 创建用于保护 DEK 的证书
CREATE CERTIFICATE TDECert
    WITH SUBJECT = 'TDE Certificate for SalesDB';

-- 3. 备份证书 (关键：丢失后无法恢复任何加密备份!)
BACKUP CERTIFICATE TDECert
    TO FILE = 'C:\Backup\TDECert.cer'
    WITH PRIVATE KEY (
        FILE = 'C:\Backup\TDECert.pvk',
        ENCRYPTION BY PASSWORD = 'CertBackupPwd!2024'
    );

-- 4. 在用户数据库创建 DEK
USE SalesDB;
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE TDECert;

-- 5. 启用 TDE
ALTER DATABASE SalesDB SET ENCRYPTION ON;

-- 6. 检查加密进度
SELECT db_name(database_id), encryption_state, percent_complete
FROM sys.dm_database_encryption_keys;
-- encryption_state: 0=无, 1=未加密, 2=加密中, 3=加密, 4=轮换, 5=解密中

-- ============ Always Encrypted：客户端加密 ============

-- 1. 创建列主密钥 (CMK) 元数据，密钥存放于客户端 (Windows Cert Store / Azure KV)
CREATE COLUMN MASTER KEY MyCMK
    WITH (
        KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT',
        KEY_PATH = 'https://myvault.vault.azure.net/keys/MyCMK/abcd1234'
    );

-- 2. 创建列加密密钥 (CEK)，由 CMK 加密后存于服务端
CREATE COLUMN ENCRYPTION KEY MyCEK
    WITH VALUES (
        COLUMN_MASTER_KEY = MyCMK,
        ALGORITHM = 'RSA_OAEP',
        ENCRYPTED_VALUE = 0x01700000016C0...
    );

-- 3. 在表定义中标记列
CREATE TABLE Patients (
    PatientId   INT IDENTITY PRIMARY KEY,
    SSN         CHAR(11) COLLATE Latin1_General_BIN2
                ENCRYPTED WITH (
                    COLUMN_ENCRYPTION_KEY = MyCEK,
                    ENCRYPTION_TYPE = DETERMINISTIC,
                    ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
                ),
    Diagnosis   NVARCHAR(200)
                ENCRYPTED WITH (
                    COLUMN_ENCRYPTION_KEY = MyCEK,
                    ENCRYPTION_TYPE = RANDOMIZED,
                    ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
                )
);

-- 4. 客户端必须使用支持 AE 的驱动 (.NET / JDBC / ODBC) 并提供 CMK 访问权限
-- 服务端 SELECT 看到的全是密文：
SELECT SSN, Diagnosis FROM Patients;
-- 0x01C8B27F... | 0x019F8A3D...
```

### MySQL InnoDB 表空间加密

MySQL 5.7.11 (2016 年 4 月) 引入 InnoDB 表空间加密，8.0 系列逐步补齐了 redo / undo / binlog 的加密。

```sql
-- 1. 安装 keyring 插件 (插件式架构)
INSTALL PLUGIN keyring_file SONAME 'keyring_file.so';
-- 或生产环境：keyring_okv (Oracle Key Vault)、keyring_aws、keyring_hashicorp

-- 2. my.cnf 配置
-- [mysqld]
-- early-plugin-load=keyring_file.so
-- keyring_file_data=/var/lib/mysql-keyring/keyring
-- innodb_redo_log_encrypt=ON
-- innodb_undo_log_encrypt=ON
-- binlog_encryption=ON         -- 8.0.14+
-- default_table_encryption=ON  -- 8.0.16+

-- 3. 创建加密表
CREATE TABLE secret_data (
    id INT PRIMARY KEY,
    data BLOB
) ENCRYPTION='Y';

-- 4. 加密现有表 (file-per-table)
ALTER TABLE existing_table ENCRYPTION='Y';

-- 5. 加密通用表空间
CREATE TABLESPACE secure_ts
    ADD DATAFILE 'secure01.ibd'
    ENCRYPTION='Y';

-- 6. 主密钥轮换
ALTER INSTANCE ROTATE INNODB MASTER KEY;

-- 7. 查看加密状态
SELECT TABLE_NAME, CREATE_OPTIONS
FROM INFORMATION_SCHEMA.TABLES
WHERE CREATE_OPTIONS LIKE '%ENCRYPTION%';
```

### MariaDB Data-at-Rest Encryption

MariaDB 10.1 (2015) 早于 MySQL 5.7.11 推出加密，且实现更彻底。

```ini
# my.cnf
[mysqld]
plugin_load_add = file_key_management
file_key_management_filename = /etc/mysql/keys.txt
file_key_management_filekey = FILE:/etc/mysql/keyfile.key
file_key_management_encryption_algorithm = AES_CTR

innodb_encrypt_tables = ON
innodb_encrypt_log = ON
innodb_encrypt_temporary_tables = ON
innodb_encryption_threads = 4
innodb_encryption_rotate_key_age = 1
encrypt_tmp_disk_tables = ON
encrypt_binlog = ON
aria_encrypt_tables = ON
```

```sql
-- DDL 级别覆盖
CREATE TABLE secret (id INT, data TEXT) ENCRYPTED=YES ENCRYPTION_KEY_ID=2;
ALTER TABLE existing ENCRYPTED=YES;

-- 检查加密线程进度
SELECT * FROM INFORMATION_SCHEMA.INNODB_TABLESPACES_ENCRYPTION;
```

MariaDB 的关键差异：

- **多密钥支持**：每张表可以使用不同的密钥 (`ENCRYPTION_KEY_ID`)，密钥版本化存储；
- **后台轮换线程**：`innodb_encryption_threads` 控制并行重加密度；
- **临时表 / Aria 引擎也加密**：覆盖范围更全面。

### PostgreSQL：没有原生 TDE

截至 PostgreSQL 17 (2024)，社区版 PostgreSQL 没有任何形式的透明数据加密。这是企业用户最常抱怨的缺失功能之一。

```sql
-- 替代方案 1: pgcrypto 列级加密 (内置 contrib)
CREATE EXTENSION pgcrypto;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email TEXT,
    -- 对称加密
    ssn_enc BYTEA  -- pgp_sym_encrypt('123-45-6789', 'mykey')
);

-- 写入
INSERT INTO users(email, ssn_enc)
VALUES ('a@b.com', pgp_sym_encrypt('123-45-6789', 'mykey'));

-- 读取 (密钥每次都要传)
SELECT email, pgp_sym_decrypt(ssn_enc, 'mykey') FROM users;

-- 替代方案 2: 文件系统加密 (LUKS / dm-crypt / ZFS native encryption)
-- 优点：对 PG 完全透明；缺点：进程访问 = 明文访问，不防 DBA

-- 替代方案 3: 商业发行版
-- - EnterpriseDB EDB Postgres Advanced Server: 完整 TDE
-- - Crunchy Data: pg_tde 扩展 (实验性)
-- - Fujitsu Enterprise Postgres: 完整 TDE + 数据屏蔽
-- - Percona Distribution for PostgreSQL: pg_tde 实验性集成
```

### DB2 Native Encryption

DB2 LUW 10.5 FP5 (2014) 引入 Native Encryption，集成在数据库引擎内，无需额外许可 (相比 Oracle ASO)。

```sql
-- 1. 创建本地 keystore (db2 命令行)
-- gsk8capicmd_64 -keydb -create -db /home/db2inst1/keystore.p12 \
--   -pw "KeyStorePwd#1" -strong -type pkcs12 -stash

-- 2. 配置 DBM (database manager)
-- db2 update dbm cfg using KEYSTORE_LOCATION /home/db2inst1/keystore.p12
-- db2 update dbm cfg using KEYSTORE_TYPE PKCS12

-- 3. 创建加密数据库
CREATE DATABASE securedb ENCRYPT
    CIPHER AES KEY LENGTH 256
    MASTER KEY LABEL 'DB2_SECURE_DB_KEY';

-- 4. 加密现有数据库 (需要离线 backup/restore)
BACKUP DATABASE olddb;
RESTORE DATABASE olddb FROM '/backup' ENCRYPT;

-- 5. 主密钥轮换
CALL SYSPROC.ADMIN_ROTATE_MASTER_KEY('NEW_KEY_LABEL');

-- 6. 备份天然加密
BACKUP DATABASE securedb ENCRYPT;
```

### ClickHouse 加密磁盘

ClickHouse 21.10+ 通过存储策略 (storage policy) 提供磁盘卷级加密。

```xml
<!-- config.xml -->
<storage_configuration>
    <disks>
        <disk_local>
            <type>local</type>
            <path>/var/lib/clickhouse/</path>
        </disk_local>
        <disk_encrypted>
            <type>encrypted</type>
            <disk>disk_local</disk>
            <path>encrypted/</path>
            <algorithm>AES_128_CTR</algorithm>
            <key_hex>00112233445566778899aabbccddeeff</key_hex>
        </disk_encrypted>
    </disks>
    <policies>
        <encrypted_policy>
            <volumes>
                <main><disk>disk_encrypted</disk></main>
            </volumes>
        </encrypted_policy>
    </policies>
</storage_configuration>
```

```sql
CREATE TABLE secure_events (
    event_time DateTime,
    user_id UInt64,
    payload String
) ENGINE = MergeTree()
ORDER BY (event_time, user_id)
SETTINGS storage_policy = 'encrypted_policy';
```

### Snowflake：永远开启的 AES-256

Snowflake 是云数据仓库中加密透明度最高的代表：所有客户数据都强制使用 AES-256 加密，无法关闭，无法选择算法，用户甚至感觉不到加密的存在。

- **分层密钥架构**：根密钥 → 账号密钥 → 表密钥 → 文件密钥 (4 层)；
- **30 天自动密钥轮换**：所有层级；
- **Tri-Secret Secure (BYOK)**：企业版可提供自己的密钥，与 Snowflake 密钥共同保护数据，二者缺一不可解密；
- **Periodic Rekeying**：超过 1 年的数据可选择性重加密。

```sql
-- 用户唯一相关的 SQL 是周期性重加密配置
ALTER ACCOUNT SET PERIODIC_DATA_REKEYING = TRUE;

-- 列级加密通过函数实现
SELECT ENCRYPT('sensitive', 'passphrase', 'AES_256_CBC') AS enc_value;
```

### BigQuery：CMEK 与默认加密

BigQuery 默认使用 Google 管理的 AES-256 密钥；可选 Customer-Managed Encryption Keys (CMEK) 通过 Cloud KMS 控制密钥生命周期。

```sql
-- 创建受 CMEK 保护的数据集
CREATE SCHEMA secure_dataset
OPTIONS (
    location = 'us',
    default_kms_key_name = 'projects/my-proj/locations/us/keyRings/my-ring/cryptoKeys/my-key'
);

-- 列级 AEAD (Google Tink envelope encryption)
DECLARE kms_resource_name STRING DEFAULT
    'gcp-kms://projects/my-proj/locations/us/keyRings/my-ring/cryptoKeys/my-key';

DECLARE first_level_keyset BYTES DEFAULT
    KEYS.NEW_WRAPPED_KEYSET(kms_resource_name, 'AEAD_AES_GCM_256');

SELECT AEAD.ENCRYPT(
    KEYS.KEYSET_CHAIN(kms_resource_name, first_level_keyset),
    'sensitive plaintext',
    'authenticated additional data'
) AS encrypted;
```

### Redshift：集群级 KMS 加密

```sql
-- 创建加密集群 (CLI / Console，非 SQL)
-- aws redshift create-cluster --cluster-identifier mycluster \
--   --node-type ra3.xlplus --number-of-nodes 2 \
--   --master-username admin --master-user-password ... \
--   --encrypted --kms-key-id alias/aws/redshift

-- 启用现有集群加密 (后台异步)
-- aws redshift modify-cluster --cluster-identifier mycluster --encrypted

-- Redshift 内部使用三层密钥：
-- - Cluster Encryption Key (CEK) -- AWS KMS CMK
-- - Database Encryption Key (DEK) -- 加密数据库密钥
-- - 数据块密钥 -- 实际加密块
```

### TiDB / CockroachDB：开源 NewSQL 的 TDE

```toml
# CockroachDB: store-level encryption-at-rest (Enterprise)
# cockroach start --store=path=/mnt/data,attrs=ssd \
#   --enterprise-encryption=path=/mnt/data,key=/keys/aes-128.key,old-key=plain
```

```toml
# TiDB / TiKV: encryption.toml
[security.encryption]
data-encryption-method = "aes128-ctr"
data-key-rotation-period = "168h"  # 7 天
master-key.type = "kms"
master-key.key-id = "arn:aws:kms:us-east-1:123:key/abcd1234"
master-key.region = "us-east-1"
```

### SQLite + SQLCipher

SQLite 自身不提供加密。SQLCipher (Zetetic) 是事实标准的第三方加密扩展，被广泛用于移动应用 (iOS/Android)。

```sql
-- 打开加密数据库
PRAGMA key = 'mySecretPassphrase';

-- 之后所有读写自动 AES-256-CBC 加密
CREATE TABLE notes (id INTEGER PRIMARY KEY, content TEXT);
INSERT INTO notes VALUES (1, 'sensitive note');

-- 修改密钥
PRAGMA rekey = 'newSecretPassphrase';

-- SQLCipher 在每个数据库页 (默认 4KB) 头部存储 IV，
-- 整页加密，对 SQL 层完全透明。
```

### DuckDB：无 TDE

DuckDB 作为嵌入式分析引擎，没有内置 TDE，依靠操作系统层 (LUKS/FileVault/BitLocker) 或文件权限保护。这是嵌入式数据库的常见选择：单用户、单进程模型下，TDE 的威胁模型 (防物理介质泄漏) 通常由 OS 解决。

## Oracle TDE Wallet 与主密钥深度剖析

Oracle Wallet 是 Oracle TDE 体系的核心组件，理解它就理解了几乎所有 RDBMS 的双层密钥设计。

### Wallet 文件结构

Oracle wallet 是符合 PKCS#12 标准的密钥容器，存储在 `WALLET_LOCATION` 指定的目录：

```
$ORACLE_BASE/admin/$ORACLE_SID/wallet/
├── ewallet.p12        # 密码保护的主 wallet
├── cwallet.sso        # 自动登录 wallet (无需密码即可打开)
├── ewallet_<timestamp>.p12  # 历史版本 (备份)
└── ...
```

- **ewallet.p12**：PKCS#12 加密容器，需要密码 (`IDENTIFIED BY` 子句) 才能打开；
- **cwallet.sso**：单点登录版本，密码已被 OS 文件权限取代 (Oracle 用户可读)，数据库启动时自动加载；启用方式：`ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE FROM KEYSTORE`。

### 双层密钥架构

```
┌──────────────────────────────────────────────────┐
│                   TDE Master Key                 │
│    存储于 Wallet (或 HSM/Oracle Key Vault)        │
│              AES-256 主密钥                       │
└────────────────────┬─────────────────────────────┘
                     │  encrypts
                     ▼
┌──────────────────────────────────────────────────┐
│        Tablespace / Column Encryption Keys       │
│              (DEK, 表空间 / 列级)                  │
│        存储于数据字典 (SYS.ENC$, 加密)              │
└────────────────────┬─────────────────────────────┘
                     │  encrypts
                     ▼
┌──────────────────────────────────────────────────┐
│         Actual Data Blocks / Column Values        │
│            (在 buffer pool 与磁盘之间)             │
└──────────────────────────────────────────────────┘
```

这种设计的关键好处是：

1. **轮换主密钥极快**：只需用新主密钥重加密少量 DEK 元数据 (KB 级)，不需要重写 TB 级数据文件；
2. **HSM 集成简单**：HSM 只负责保护一个 master key，所有加解密的高频操作仍在数据库进程内完成；
3. **跨数据库迁移**：导出 wallet 即可在新实例打开同样的加密数据。

### Oracle Key Vault (OKV)

OKV 是 Oracle 提供的集中式密钥管理服务器，可以替代本地 wallet：

- 管理多个数据库实例的 master key；
- 自动备份与高可用 (集群)；
- 与 RAC、Data Guard、GoldenGate 集成；
- 兼容 KMIP 标准，可作为通用 KMIP server 给 MySQL / DB2 / SAP HANA 使用。

## SQL Server Always Encrypted vs TDE：威胁模型差异

二者都叫"加密"，但解决完全不同的威胁。

| 维度 | TDE | Always Encrypted |
|------|-----|-----------------|
| 加密发生位置 | 数据库引擎 (服务端) | 客户端驱动 |
| 内存中数据形态 | 明文 | 密文 |
| 防御目标 | 物理介质丢失、备份盗取 | 防止 DBA / 高权限内部人员窥视 |
| DBA 是否可见明文 | 是 | 否 |
| 密钥存放位置 | 服务端证书 | 客户端 (Cert Store / Azure KV) |
| SQL 查询能力 | 全部支持 | 仅相等比较 (确定性加密)，范围/模糊需要 Enclave |
| 性能开销 | 5-10% | 显著 (取决于驱动) |
| 应用透明度 | 完全透明 | 需要 SqlClient `Column Encryption Setting=Enabled` |
| 适用合规场景 | HIPAA、PCI-DSS 静态数据 | "DBA 不可信" 模型，金融/医疗高敏感字段 |

威胁模型示例：

- **TDE 防御**：磁盘从机房被偷走 → 攻击者无法读取 .mdf / .ldf；备份磁带丢失 → 攻击者无法恢复数据库。
- **TDE 不能防御**：拥有 SQL 登录的 DBA 仍可 `SELECT *`；服务器被入侵后内存中的明文可被读取。
- **Always Encrypted 防御**：DBA 完全无法看到敏感列；云提供商 (Azure SQL) 内部员工无法解密；服务端内存也是密文。
- **Always Encrypted 不能防御**：客户端被入侵后明文泄漏；密钥管理失误 (CMK 丢失 = 数据丢失)。

SQL Server 2019 引入 **Always Encrypted with Secure Enclaves**：基于 Intel SGX 在服务端创建加密的可信执行环境 (TEE)，让密文数据在飞地内被解密后用于范围查询和模糊匹配，但 DBA 仍看不到明文。这是目前业界最先进的隐私计算 + TDE 融合方案。

## 为什么 PostgreSQL 一直没有原生 TDE

PostgreSQL 社区从 2016 年开始反复讨论原生 TDE，至 2024 年的 PG 17 仍未合并。这是 PostgreSQL 商业生态最大的一个分裂点。

### 历史时间线

- **2016**：NTT 提交首个 TDE patch 提议，使用表空间级加密；
- **2018**：Cybertec 提出基于 cluster-wide encryption 的设计；
- **2019-2020**：多个公司 (Cybertec、EnterpriseDB、Fujitsu、Percona) 提交独立 patch，互相不兼容；
- **2021**：Sawada Masahiko 提出 buffer-level encryption 设计 (cluster file encryption, CFE)；
- **2022-2023**：Stephen Frost 等核心开发者主导 KMIP 集成讨论；
- **2024**：仍处于 patch 评审阶段，预计 PG 18 或 PG 19 才可能合并最简版本。

### 社区反对意见

PostgreSQL 核心开发者 (Bruce Momjian、Tom Lane 等) 对原生 TDE 的态度长期保守，主要论点：

1. **威胁模型可疑**：能物理拿到磁盘的攻击者通常也能拿到内存 dump 或运行中的密钥，TDE 防御范围有限；
2. **OS 层加密更通用**：LUKS/dm-crypt/ZFS native encryption 在 Linux 上免费、性能好、对 PG 完全透明；
3. **代码复杂度爆炸**：加密影响 buffer manager、checkpoint、recovery、replication、WAL 归档、pg_basebackup 等几乎所有子系统，引入维护负担巨大；
4. **密钥管理是无底洞**：KMIP / KMS / HSM / Wallet / 密钥轮换 / 备份加密 / replica 密钥分发……每个环节都需要长期维护；
5. **合规理由不充分**：合规审计接受 OS 层加密 (LUKS) 作为替代；客户更需要的是"声明合规"而不是技术上的差异。

### 商业发行版的应对

主要 PG 商业发行版都自己实现了 TDE，构成产品差异化的核心卖点：

| 发行版 | TDE 实现 | 起始版本 |
|--------|----------|---------|
| EnterpriseDB EDB Advanced Server | 完整 TDE，集成 EDB Key Management | EPAS 15+ |
| Fujitsu Enterprise Postgres | 表空间级 TDE + 数据屏蔽 | 9.6+ |
| Crunchy Data | OS 层 + pg_tde 实验性扩展 | -- |
| Percona Distribution | pg_tde (基于 EDB 实现的开源版) | 16+ |
| Cybertec PostgreSQL | cluster-wide TDE patch | 11+ |
| Yugabyte (兼容 PG) | 内置集群加密 | 2.0+ |

> 在 PG 主线合并 TDE 之前，企业 PG 用户的现实选择是：(1) 接受 OS 层加密作为合规基线；(2) 购买商业发行版 (EDB / Fujitsu) 获得真 TDE；(3) 迁移到 Yugabyte / CockroachDB 等内建 TDE 的兼容引擎。

## 关键发现

### 1. 云原生引擎 vs 传统 RDBMS 的"加密哲学"鸿沟

云原生引擎 (Snowflake、BigQuery、Redshift、Spanner、Athena、Firebolt、Yellowbrick) 几乎全部默认强制开启 AES-256，用户感知不到加密的存在；传统 RDBMS (Oracle、SQL Server、DB2) 的 TDE 是可选功能，需要 DBA 主动配置且常常需要额外许可。

这反映了根本性的产品哲学差异：云服务的合规责任由提供商承担，"默认安全"是商业必需品；传统 DBMS 的合规责任由用户承担，加密是付费溢价功能。

### 2. PostgreSQL 是 OLTP 引擎中加密能力的最大空白

在所有主流 OLTP 引擎中，PostgreSQL 是唯一没有原生 TDE 的，且短期 (1-2 年) 内不会改变。这与 PostgreSQL 在其他方面的领先形成戏剧性对比，也是商业 PG 发行版的核心价值。对合规要求严格的企业，这是仍然选择 Oracle / SQL Server / EDB 的主要技术原因之一。

### 3. AES-NI 让 TDE 性能不再是问题

2010 年 Intel 引入 AES-NI 指令集后，硬件加速的 AES 加解密只占 CPU 周期的极小部分。十年前 TDE 的 20-30% 性能开销已降至 5% 以下。绝大部分现代部署中，TDE 的性能成本远低于"加密带来的合规收益"，这意味着技术上反对 TDE 的理由 (性能) 已基本失效。

### 4. 双层密钥架构是事实标准

Oracle、SQL Server、MySQL、DB2、Snowflake、CockroachDB 等几乎所有支持 TDE 的引擎都采用 master key + data encryption key 的双层 (或更多层) 架构。这种设计的核心优势是：主密钥轮换无需重写数据文件。设计新引擎时，这是首选方案。

### 5. KMS / HSM 集成是企业部署的真正难点

加密算法本身并不复杂，难的是密钥管理：备份、轮换、灾难恢复、跨区域复制、HSM 故障切换、审计日志。云引擎将 KMS 作为基础设施抽象 (AWS KMS、Azure Key Vault、Cloud KMS)，自建部署则需要选型 KMIP server、HSM 设备或 HashiCorp Vault。**TDE 项目的 80% 工作量在密钥管理上，不在加密算法上。**

### 6. 备份加密往往是最容易被忽略的攻击面

启用 TDE 的数据库未必备份就被加密。Oracle RMAN、SQL Server BACKUP、MySQL mysqldump、PostgreSQL pg_dump 都需要单独配置备份加密。审计中常见的合规失败点是："数据库已加密但备份磁带未加密"。MariaDB 与 DB2 在这方面做得最好——一旦启用 TDE，备份天然继承加密。

### 7. binlog / WAL / redo log 是 GDPR 审计的高发漏点

应用层只看到表数据被加密，但事务日志 (binlog、WAL、redo log) 常以明文记录所有 DML，包括 UPDATE 前后镜像。MySQL 直到 8.0.14 (2019) 才补齐 binlog 加密；PostgreSQL 至今没有 WAL 加密。在 GDPR 数据泄漏通知的免责条款中，仅"主数据已加密"通常不够，必须证明"所有持久化路径"都加密。

### 8. 客户端加密 (Always Encrypted) 是隐私计算的开端

SQL Server Always Encrypted 是商业数据库中最早商业化的"DBA 也看不到明文"方案。其威胁模型直接对应零信任架构 (Zero Trust) 与多方计算 (MPC) 的部分需求。配合 2019 引入的 Secure Enclaves，已能在密文上进行范围查询。这一方向 (TEE + DBMS) 将是未来 5-10 年隐私计算的主战场，但目前仅 SQL Server 有商用产品。

### 9. 嵌入式数据库的 TDE 取决于场景

DuckDB、SQLite、H2、HSQLDB、Derby 这类嵌入式引擎对 TDE 的态度差异很大：DuckDB 直接放弃 (依赖 OS)，SQLite 提供第三方 (SQLCipher)，H2/HSQLDB/Derby 则有内建简单加密。选择取决于威胁模型——嵌入式场景中 TDE 主要防御移动设备丢失 (iOS/Android 应用使用 SQLCipher 是事实标准)，而桌面 / 服务器嵌入式更倾向依赖 OS。

### 10. 出口管制历史的余响

直到 2000 年左右，美国对强加密软件的出口仍有严格限制。这造成数据库加密功能晚于操作系统加密 5-10 年才商品化 (Oracle 2005、SQL Server 2008、MySQL 2016)，并塑造了"加密是付费高级功能"的产品观念。与之相比，Linux dm-crypt (2003)、BitLocker (Vista, 2007) 在 OS 层早已普及。这一历史遗产至今仍解释了为什么 PostgreSQL 这样的开源数据库没有把 TDE 视为基础功能。

## 参考资料

- PCI-DSS v4.0: [Payment Card Industry Data Security Standard](https://www.pcisecuritystandards.org/document_library/)
- HIPAA Security Rule: 45 CFR §164.312
- GDPR Article 32 / 34: [Regulation (EU) 2016/679](https://gdpr-info.eu/)
- Oracle: [Advanced Security Guide - Transparent Data Encryption](https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/introduction-to-transparent-data-encryption.html)
- SQL Server: [Transparent Data Encryption (TDE)](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/transparent-data-encryption)
- SQL Server: [Always Encrypted](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-database-engine)
- MySQL: [InnoDB Data-at-Rest Encryption](https://dev.mysql.com/doc/refman/8.0/en/innodb-data-encryption.html)
- MariaDB: [Data-at-Rest Encryption](https://mariadb.com/kb/en/data-at-rest-encryption-overview/)
- PostgreSQL Wiki: [Transparent Data Encryption](https://wiki.postgresql.org/wiki/Transparent_Data_Encryption)
- DB2: [Native Encryption](https://www.ibm.com/docs/en/db2/11.5?topic=encryption-db2-native)
- Snowflake: [End-to-End Encryption](https://docs.snowflake.com/en/user-guide/security-encryption-end-to-end)
- BigQuery: [Customer-Managed Encryption Keys](https://cloud.google.com/bigquery/docs/customer-managed-encryption)
- Redshift: [Database Encryption](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-db-encryption.html)
- ClickHouse: [Encrypted Disks](https://clickhouse.com/docs/en/operations/storing-data#encrypted-virtual-file-system)
- CockroachDB: [Encryption At Rest](https://www.cockroachlabs.com/docs/stable/encryption.html)
- TiDB: [Encryption at Rest](https://docs.pingcap.com/tidb/stable/encryption-at-rest)
- YugabyteDB: [Encryption at Rest](https://docs.yugabyte.com/preview/secure/encryption-at-rest/)
- SAP HANA: [Data Volume Encryption](https://help.sap.com/docs/SAP_HANA_PLATFORM/b3ee5778bc2e4a089d3299b82ec762a7/dc01f36fbb5710148b668201a6e95cf2.html)
- SQLCipher: [SQLCipher Documentation](https://www.zetetic.net/sqlcipher/documentation/)
- Apache Parquet: [Modular Encryption](https://parquet.apache.org/docs/file-format/data-pages/encryption/)
- KMIP: OASIS Key Management Interoperability Protocol Specification v2.1
- NIST SP 800-57: Recommendation for Key Management
- Intel: [AES-NI Instruction Set](https://www.intel.com/content/www/us/en/developer/articles/technical/advanced-encryption-standard-instructions-aes-ni.html)
