# SSL/TLS 连接加密 (Connection Encryption)

一次未加密的数据库连接就足以让企业登上合规事故头条——在 GDPR、HIPAA、PCI-DSS 和中国《数据安全法》的共同压力下，传输层加密已经从"可选的性能优化项"变成了数据库上线的最低准入门槛。本文横向对比 48 款主流数据库/分析引擎的 SSL/TLS 能力，涵盖 TLS 版本、证书校验、mTLS、FIPS 合规、强制加密等关键维度。

## 没有 SQL 标准，只有 RFC

与 SQL:2003 的 `TABLESAMPLE`、SQL:2011 的 `MERGE` 不同，"连接加密"并不在 ISO SQL 标准的覆盖范围内。传输层由 IETF 的 TLS 系列 RFC 规范：

- **TLS 1.0** – RFC 2246 (1999)，已被 RFC 8996 弃用
- **TLS 1.1** – RFC 4346 (2006)，已被 RFC 8996 弃用
- **TLS 1.2** – RFC 5246 (2008)，目前的行业基线
- **TLS 1.3** – RFC 8446 (2018)，当前推荐版本，握手延迟更低，移除了 RSA 密钥交换、CBC 模式等已知弱点
- **mTLS** – RFC 8705 描述了客户端证书绑定，数据库通常通过 libssl/BoringSSL/SChannel 实现
- **FIPS 140-2** – NIST FIPS 140-2/140-3 定义加密模块的联邦合规要求

每个数据库厂商自行在其网络协议上叠加 TLS，具体表现是：连接字符串参数不统一、默认行为不统一、证书校验粒度不统一。这也是本文存在的理由。

## 支持矩阵（48 引擎总览）

### TLS 基础支持与最低版本

| 引擎 | TLS 支持 | 默认最低版本 | TLS 1.3 | 版本 |
|------|---------|-------------|---------|------|
| PostgreSQL | 是 | TLS 1.2 (可配) | 是 (13+, OpenSSL 1.1.1) | 8.0+ |
| MySQL | 是 | TLS 1.2 | 是 (8.0.16+) | 5.5+ |
| MariaDB | 是 | TLS 1.2 | 是 (10.5+) | 5.5+ |
| SQLite | 否（嵌入式） | -- | -- | -- |
| Oracle | 是 | TLS 1.2 (12.2+) | 是 (19c+) | 11g+ |
| SQL Server | 是 | TLS 1.2 | 是 (2022+) | 2005+ |
| DB2 | 是 | TLS 1.2 | 是 (11.5.7+) | 9.1+ |
| Snowflake | 强制 | TLS 1.2 | 是 | GA |
| BigQuery | 强制 (HTTPS/gRPC) | TLS 1.2 | 是 | GA |
| Redshift | 是 | TLS 1.2 | 是 | GA |
| DuckDB | httpfs (TLS) | TLS 1.2 | 是 | 0.8+ |
| ClickHouse | 是 (端口 9440) | TLS 1.2 | 是 (21.3+) | 早期 |
| Trino | 是 | TLS 1.2 | 是 (JDK 11+) | 早期 |
| Presto | 是 | TLS 1.2 | 是 | 早期 |
| Spark SQL | 是 (Thrift/JDBC) | TLS 1.2 | 是 (Spark 3.0+) | 2.0+ |
| Hive | 是 (HiveServer2) | TLS 1.2 | 是 | 0.13+ |
| Flink SQL | 是 (SQL Gateway) | TLS 1.2 | 是 | 1.16+ |
| Databricks | 强制 (HTTPS/JDBC) | TLS 1.2 | 是 | GA |
| Teradata | 是 | TLS 1.2 | 是 (17.10+) | 16.20+ |
| Greenplum | 是 (继承 PG) | TLS 1.2 | 是 (6.20+) | 4.x+ |
| CockroachDB | 默认启用 | TLS 1.2 | 是 | v1.0+ |
| TiDB | 是 | TLS 1.2 | 是 (6.0+) | 4.0+ |
| OceanBase | 是 | TLS 1.2 | 是 (4.0+) | 2.x+ |
| YugabyteDB | 是 | TLS 1.2 | 是 | 2.0+ |
| SingleStore | 是 | TLS 1.2 | 是 (7.5+) | 6.0+ |
| Vertica | 是 | TLS 1.2 | 是 (11.0+) | 7.x+ |
| Impala | 是 | TLS 1.2 | 是 (4.0+) | 2.0+ |
| StarRocks | 是 | TLS 1.2 | 是 (3.0+) | 2.x+ |
| Doris | 是 | TLS 1.2 | 是 (2.0+) | 1.2+ |
| MonetDB | 是 | TLS 1.2 | 是 | Jul2017+ |
| CrateDB | 是 (企业版) | TLS 1.2 | 是 | 3.0+ |
| TimescaleDB | 继承 PG | TLS 1.2 | 是 | 继承 PG |
| QuestDB | 是 | TLS 1.2 | 是 (7.0+) | 6.6+ |
| Exasol | 是 | TLS 1.2 | 是 (7.1+) | 6.x+ |
| SAP HANA | 是 | TLS 1.2 | 是 (2.0 SPS 06+) | 1.0+ |
| Informix | 是 | TLS 1.2 | 是 (14.10+) | 11.x+ |
| Firebird | 是 (Wire Crypt + TLS) | TLS 1.2 | 是 (5.0+) | 3.0+ |
| H2 | 是 (JSSE) | JVM 决定 | 是 (JDK 11+) | 早期 |
| HSQLDB | 是 (JSSE) | JVM 决定 | 是 (JDK 11+) | 早期 |
| Derby | 是 (JSSE) | JVM 决定 | 是 (JDK 11+) | 早期 |
| Amazon Athena | 强制 (HTTPS) | TLS 1.2 | 是 | GA |
| Azure Synapse | 强制 | TLS 1.2 | 是 | GA |
| Google Spanner | 强制 (gRPC) | TLS 1.2 | 是 | GA |
| Materialize | 是 | TLS 1.2 | 是 | GA |
| RisingWave | 是 | TLS 1.2 | 是 (1.0+) | GA |
| InfluxDB (SQL) | 是 (HTTPS) | TLS 1.2 | 是 (3.0+) | 2.0+ |
| DatabendDB | 是 | TLS 1.2 | 是 | GA |
| Yellowbrick | 是 | TLS 1.2 | 是 | GA |
| Firebolt | 强制 (HTTPS) | TLS 1.2 | 是 | GA |

> 统计：48 个引擎中，47 个支持 TLS，唯一例外是纯嵌入式的 SQLite（连接本身不跨网络）。其中 9 个云托管引擎（Snowflake、BigQuery、Databricks、Athena、Synapse、Spanner、Firebolt、InfluxDB Cloud、部分 RisingWave Cloud 实例）**强制** TLS，没有"关闭加密"这个选项。

### mTLS、证书校验与密码套件控制

| 引擎 | mTLS（客户端证书） | 服务端证书校验 | 密码套件控制 | FIPS 模式 | ALPN | 可强制 TLS |
|------|-------------------|----------------|------------|-----------|------|-----------|
| PostgreSQL | 是（`sslcert`/`sslkey`） | 是（`verify-ca`/`verify-full`） | `ssl_ciphers` | FIPS OpenSSL 构建 | 否 | `hostssl` / `pg_hba.conf` |
| MySQL | 是（`REQUIRE X509`） | 是（`--ssl-mode=VERIFY_*`） | `--ssl-cipher` / `ssl_cipher` | FIPS 构建 | 否 | `require_secure_transport` |
| MariaDB | 是 | 是 | `ssl_cipher` | FIPS 构建 | 否 | `require_secure_transport` |
| Oracle | 是（wallet） | 是（DN 匹配） | `SSL_CIPHER_SUITES` | FIPS (`fips.ora`) | 否 | `TCPS` 监听 |
| SQL Server | 是 (2022+) | 是 (`TrustServerCertificate=false`) | 操作系统 SChannel | Windows FIPS | 否 | `Force Encryption` |
| DB2 | 是 | 是 | `SSL_CIPHERSPECS` | FIPS GSKit | 否 | `SSL_SVR_LABEL` |
| Snowflake | 是（SCIM/OAuth mTLS） | 强制 | 平台管理 | FedRAMP High | 是 | 强制 |
| BigQuery | 是 (gRPC client cert) | 强制 | 平台管理 | FedRAMP High | 是 | 强制 |
| Redshift | 是 | 是 (`verify-ca`/`verify-full`) | 平台管理 | FedRAMP High | -- | `require_SSL` |
| ClickHouse | 是（`<ssl_config>`） | 是 | `cipherList` | 构建时启用 | 否 | `tcp_port_secure` |
| Trino | 是 | 是 | `internal-communication.https.cipher-suites` | JVM FIPS | 是 | `http-server.https.enabled` |
| Spark SQL | 是 (Thrift SASL) | 是 | JSSE 配置 | JVM FIPS | 是 | `spark.ssl.enabled` |
| Databricks | 是 (客户端证书可选) | 强制 | 平台管理 | FedRAMP High | 是 | 强制 |
| Teradata | 是 | 是 | `CipherSuites` | FIPS 140-2 | -- | `TLSMODE=REQUIRE` |
| CockroachDB | 是（默认） | 是 | Go crypto/tls | -- | 是 | 默认强制 |
| TiDB | 是（`REQUIRE X509`） | 是 | Go crypto/tls | BoringCrypto | 是 | `require-secure-transport` |
| OceanBase | 是（`REQUIRE X509`） | 是 | `ssl_cipher` | 商业版 | -- | `require_secure_transport` |
| YugabyteDB | 是 | 是 | 继承 PG | -- | -- | `ysql_enable_auth` + TLS |
| SingleStore | 是 | 是 | 是 | 商业版 | -- | `require_secure_transport` |
| Vertica | 是 | 是 | `SSLCipherSuite` | FIPS 140-2 | -- | `EnableSSL=1` |
| Impala | 是 (Kerberos+TLS) | 是 | `--ssl_cipher_list` | FIPS (CDP) | 是 | `--ssl_server_certificate` |
| StarRocks | 是 | 是 | 是 | -- | -- | `ssl_force_secure` |
| SAP HANA | 是 (X.509/JWT) | 是 | `sslCipherSuites` | FIPS 140-2 | -- | `sslEnforce=true` |
| H2/HSQLDB/Derby | 是 (JSSE) | 是 | JSSE | JVM FIPS | 是 | 启动参数 |
| Materialize | 是 | 是 | 是 | -- | -- | 是 |
| RisingWave | 是 | 是 | 是 | -- | -- | 是 |
| 大多数云托管引擎 | 有限 (OIDC/SSO 优先) | 强制 | 平台管理 | 平台 FIPS | 是 | 强制 |

> 统计：约 35 个引擎支持完整的双向证书认证（mTLS）；TLS 1.3 在 45 个引擎中可用；近 20 个引擎提供原生 FIPS 模式或使用 FIPS 认证的加密模块。

### 证书校验模式对照

| 引擎 | 不加密 | 加密但不校验 | 校验 CA | 校验 CA + 主机名 |
|------|-------|-------------|---------|----------------|
| PostgreSQL | `disable` | `require` | `verify-ca` | `verify-full` |
| MySQL | `DISABLED` | `PREFERRED` / `REQUIRED` | `VERIFY_CA` | `VERIFY_IDENTITY` |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | 同 MySQL |
| SQL Server | `Encrypt=false` | `TrustServerCertificate=true` | N/A (CA 自动信任) | `TrustServerCertificate=false` |
| Oracle | 无 `TCPS` | `SSL_SERVER_CERT_DN=null` | CA wallet | `SSL_SERVER_DN_MATCH=TRUE` |
| Snowflake | 不支持 | 不支持 | 自动 | 自动（强制） |
| Redshift | `disable` | `allow` / `prefer` | `verify-ca` | `verify-full` |
| ClickHouse | HTTP/TCP 9000 | `sslmode=require` | `sslmode=verify-ca` | `sslmode=verify-full` |
| CockroachDB | `--insecure` | `sslmode=require` | `sslmode=verify-ca` | `sslmode=verify-full` |
| TiDB | `--ssl-mode=DISABLED` | `--ssl-mode=REQUIRED` | `VERIFY_CA` | `VERIFY_IDENTITY` |
| JDBC (JSSE 通用) | `useSSL=false` | `verifyServerCertificate=false` | `trustStore` | `verifyServerCertificate=true` |

> PostgreSQL 的 `sslmode` 命名已成为事实标准，CockroachDB、YugabyteDB、Redshift、Greenplum、TimescaleDB 全部沿用。MySQL 生态则偏向使用 `PREFERRED/REQUIRED/VERIFY_CA/VERIFY_IDENTITY` 的四档。

## PostgreSQL：sslmode 的教科书

PostgreSQL 从 8.0 (2005) 起就支持 TLS（当时还叫 SSL）。它的 `sslmode` 参数是业界最细粒度、被抄袭最多的设计：

```sql
-- libpq 连接字符串（6 档 sslmode）
-- 1. disable       不尝试加密
-- 2. allow         优先明文，服务器要求时才升级到 TLS
-- 3. prefer        优先 TLS，失败回退明文（默认值）
-- 4. require       必须 TLS，不校验证书（只防监听，不防中间人）
-- 5. verify-ca     必须 TLS + 校验服务器证书由可信 CA 签发
-- 6. verify-full   必须 TLS + 校验 CA + 校验证书 CN/SAN 与主机名匹配

postgres://alice@db.example.com:5432/mydb?sslmode=verify-full&sslrootcert=ca.pem
```

服务端配置 `postgresql.conf`：

```conf
ssl = on
ssl_cert_file = '/etc/ssl/certs/server.crt'
ssl_key_file  = '/etc/ssl/private/server.key'
ssl_ca_file   = '/etc/ssl/certs/root.crt'     -- 用于校验客户端证书 (mTLS)
ssl_ciphers   = 'HIGH:MEDIUM:+3DES:!aNULL'     -- OpenSSL 密码套件
ssl_min_protocol_version = 'TLSv1.2'           -- PG 12+
ssl_max_protocol_version = ''
ssl_prefer_server_ciphers = on
ssl_ecdh_curve = 'prime256v1'
```

`pg_hba.conf` 里强制 TLS 且要求客户端证书（mTLS）：

```conf
# TYPE      DATABASE  USER  ADDRESS           METHOD     OPTIONS
hostssl     all       all   0.0.0.0/0         scram-sha-256  clientcert=verify-full
hostnossl   all       all   0.0.0.0/0         reject
```

关键演进：
- PG 10 (2017) 引入 SCRAM-SHA-256，替代容易被离线破解的 MD5
- PG 12 (2019) 加入 `ssl_min_protocol_version`/`ssl_max_protocol_version`
- PG 13 (2020) 支持 TLS 1.3（依赖 OpenSSL 1.1.1）
- PG 16 (2023) 默认不再协商 TLS < 1.2

## MySQL：从 --ssl 到 ssl-mode

MySQL 5.5 就内置 OpenSSL/YaSSL，但直到 5.7 才算真正可用。2016 年 5.7.6 版本加入的 `require_secure_transport` 是一个里程碑——从那一刻起，DBA 才能真正**强制**所有连接加密。

```sql
-- 服务器 my.cnf
[mysqld]
ssl_ca       = /etc/mysql/ca.pem
ssl_cert     = /etc/mysql/server-cert.pem
ssl_key      = /etc/mysql/server-key.pem
tls_version  = TLSv1.2,TLSv1.3
ssl_cipher   = ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256
require_secure_transport = ON           -- 5.7.6+，拒绝所有非 TLS 连接
```

客户端使用 `--ssl-mode`（5.7.11 引入，替代老旧的布尔 `--ssl`）：

```bash
# 五档 ssl-mode
mysql --ssl-mode=DISABLED         # 不加密
mysql --ssl-mode=PREFERRED        # 能加密就加密（默认，8.0+）
mysql --ssl-mode=REQUIRED         # 必须加密，不校验证书
mysql --ssl-mode=VERIFY_CA        --ssl-ca=ca.pem
mysql --ssl-mode=VERIFY_IDENTITY  --ssl-ca=ca.pem    # 严格校验 CN/SAN
```

强制用户使用客户端证书（mTLS）：

```sql
-- 要求用户 alice 必须使用 TLS 且提供任意 X509 客户端证书
CREATE USER 'alice'@'%' IDENTIFIED BY 'secret' REQUIRE X509;

-- 要求具体的证书 DN
CREATE USER 'bob'@'%' IDENTIFIED BY 'secret'
  REQUIRE SUBJECT '/CN=bob/O=Corp/C=US'
      AND ISSUER '/CN=Internal CA/O=Corp'
      AND CIPHER 'ECDHE-RSA-AES256-GCM-SHA384';

-- 只要求 TLS（任何证书）
ALTER USER 'carol'@'%' REQUIRE SSL;
```

## SQL Server：Force Encryption 与 Azure 的强制 TLS 1.2

SQL Server 的 TLS 依赖 Windows SChannel（Linux 版使用 OpenSSL）：

```sql
-- ADO.NET / ODBC 连接字符串
Server=tcp:sql.example.com,1433;
Database=mydb;
Encrypt=true;                  -- 等同旧参数 Force Encryption
TrustServerCertificate=false;  -- 强制校验证书
HostNameInCertificate=sql.example.com;
```

服务器端通过 SQL Server Configuration Manager 启用 **Force Encryption**：

```powershell
# 注册表位置
HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL<ver>.<instance>\MSSQLServer\SuperSocketNetLib
#   ForceEncryption = 1
#   Certificate     = <thumbprint>
```

关键版本信息：
- SQL Server 2016+ 支持 TLS 1.2
- Azure SQL Database 自 2020 年起**强制** TLS 1.2，2024 年 Azure SQL 开始默认要求 TLS 1.3
- SQL Server 2022 首次支持 TLS 1.3（需 Windows Server 2022+）
- `Encrypt=Strict`（2022+ MSOLEDBSQL 19、microsoft.data.sqlclient 5.0+）强制使用 TDS 8.0，禁止明文 prelogin

## Oracle：Native Encryption 与 TCPS 并存

Oracle 的特殊之处是存在**两套**加密方案：

1. **Oracle Net Native Encryption**（1993 开始）：私有协议、对称加密、不涉及 X.509 证书。配置简单，但已被 NIST 视为"legacy"。
2. **TCPS (TCP over SSL)**：标准 TLS，从 11g (2007) 起稳定，12c 起推荐。

Native Encryption（`sqlnet.ora`）：

```conf
# 服务端与客户端同时配置
SQLNET.ENCRYPTION_SERVER         = REQUIRED
SQLNET.ENCRYPTION_TYPES_SERVER   = (AES256, AES192, AES128)
SQLNET.CRYPTO_CHECKSUM_SERVER    = REQUIRED
SQLNET.CRYPTO_CHECKSUM_TYPES_SERVER = (SHA256, SHA384, SHA512)
```

TCPS（`listener.ora` + `sqlnet.ora`）：

```conf
# listener.ora
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCPS)(HOST = db.example.com)(PORT = 2484))))
SSL_CLIENT_AUTHENTICATION = TRUE   -- 启用 mTLS

# sqlnet.ora
WALLET_LOCATION = (SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=/u01/wallet)))
SSL_SERVER_DN_MATCH = TRUE          -- 强制校验 CN
SSL_CIPHER_SUITES   = (TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
                       TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384)
SSL_VERSION = 1.2
```

19c 开始支持 TLS 1.3，21c 起 Native Encryption 与 TCPS 可以同时启用（按顺序尝试）。

## Snowflake、BigQuery、Databricks：云原生的强制加密

这三家云数据仓库的共同点：**没有关闭 TLS 的开关**。

**Snowflake**：所有连接通过 HTTPS (443)，Snowflake 的 JDBC/ODBC/Python 驱动底层也是 REST over HTTPS。不存在"unencrypted port"。2020 年起 TLS 1.2+ 强制。FedRAMP High 环境使用 FIPS 140-2 认证的加密模块。

```python
# Snowflake connector 示例 — 注意没有 sslmode 参数，因为只有 TLS 一种
snowflake.connector.connect(
    account='xy12345.us-east-1',
    user='alice',
    private_key=pkey,                   # 可用私钥+公钥注册实现 mTLS 等价功能
    insecure_mode=False                 # 默认 False，强烈不建议改为 True
)
```

**BigQuery**：客户端到 `bigquery.googleapis.com` 使用 HTTPS；后端存储层（Dremel + Colossus）内部用 gRPC over TLS + ALTS（Google 自研的应用层传输安全）。客户端证书通过 Workload Identity 或 Service Account Key 实现。

**Databricks**：JDBC 连接通过 `https://<workspace>/sql/1.0/endpoints/<id>`；SQL Warehouse 的 Thrift 协议封装在 HTTPS 内。Unity Catalog 的服务间调用 100% mTLS。

## ClickHouse：双端口模型

ClickHouse 对 TLS 的处理最直接——默认暴露**两个端口**：

| 协议 | 端口 | 加密 |
|------|-----|------|
| Native TCP | 9000 | 明文 |
| Native TCP + TLS | **9440** | TLS |
| HTTP | 8123 | 明文 |
| HTTPS | 8443 | TLS |

配置 `config.xml`：

```xml
<yandex>
  <openSSL>
    <server>
      <certificateFile>/etc/clickhouse/server.crt</certificateFile>
      <privateKeyFile>/etc/clickhouse/server.key</privateKeyFile>
      <caConfig>/etc/clickhouse/ca.pem</caConfig>
      <verificationMode>strict</verificationMode>         <!-- mTLS -->
      <disableProtocols>sslv2,sslv3,tlsv1,tlsv1_1</disableProtocols>
      <cipherList>ECDHE+AESGCM:ECDHE+CHACHA20</cipherList>
    </server>
  </openSSL>
  <tcp_port_secure>9440</tcp_port_secure>
  <https_port>8443</https_port>
</yandex>
```

强制只使用 TLS：把 `<tcp_port>` 和 `<http_port>` 注释掉即可。

客户端：

```bash
clickhouse-client --host ch.example.com --port 9440 --secure \
    --config /etc/clickhouse-client/config.xml
```

## CockroachDB：默认强制、不支持明文

Cockroach 是少数几个"默认安全"的数据库：启动 `cockroach start` 必须提供证书，除非显式 `--insecure`（生产环境强烈反对）：

```bash
# 生成证书（CA + 节点 + 客户端）
cockroach cert create-ca --certs-dir=certs --ca-key=ca.key
cockroach cert create-node localhost db.example.com --certs-dir=certs --ca-key=ca.key
cockroach cert create-client root --certs-dir=certs --ca-key=ca.key

# 连接必须 TLS
cockroach sql --certs-dir=certs --host=db.example.com
# 或
postgres://root@db.example.com:26257/defaultdb?sslmode=verify-full&sslrootcert=ca.crt&sslcert=client.root.crt&sslkey=client.root.key
```

## TiDB / OceanBase / StarRocks / Doris：MySQL 协议家族

由于它们都兼容 MySQL 协议，TLS 配置几乎照搬 MySQL：

```sql
-- TiDB (tidb.toml)
[security]
ssl-ca   = "/etc/tidb/ca.pem"
ssl-cert = "/etc/tidb/server-cert.pem"
ssl-key  = "/etc/tidb/server-key.pem"
require-secure-transport = true

-- TiDB 强制 X509 用户
CREATE USER 'audit'@'%' REQUIRE X509;

-- OceanBase
ALTER SYSTEM SET ssl_client_authentication = True;
ALTER USER 'app'@'%' REQUIRE X509;
```

TiDB 从 6.0 开始支持 TLS 1.3（基于 Go crypto/tls），OceanBase 从 4.0 起提供企业级 FIPS 模块。

## Spark SQL / Trino / Presto：JVM 生态

JVM 系引擎的 TLS 配置复用 JSSE，密码套件名称与 OpenSSL 不同：

```properties
# Trino coordinator config.properties
http-server.https.enabled=true
http-server.https.port=8443
http-server.https.keystore.path=/etc/trino/keystore.jks
http-server.https.keystore.key=changeit
http-server.https.truststore.path=/etc/trino/truststore.jks
http-server.https.cipher-suites=TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256
http-server.https.included-protocols=TLSv1.2,TLSv1.3
http-server.authentication.type=CERTIFICATE       # mTLS
```

```properties
# Spark (spark-defaults.conf) — Thrift Server / UI / RPC 共用 SSL 配置
spark.ssl.enabled=true
spark.ssl.protocol=TLSv1.3
spark.ssl.keyStore=/etc/spark/ssl/keystore.jks
spark.ssl.trustStore=/etc/spark/ssl/truststore.jks
spark.ssl.needClientAuth=true                     # mTLS
spark.ssl.enabledAlgorithms=TLS_AES_256_GCM_SHA384
```

Databricks Runtime 12.2+、Spark 3.4+ 默认启用 FIPS 模式（前提是 JDK 启用了 BouncyCastle FIPS 或 OpenJDK FIPS 构建）。

## SAP HANA：多层 TLS

HANA 对内部组件（nameserver/indexserver/xsengine）与外部连接分别有 TLS 配置：

```sql
-- 通过 JDBC
jdbc:sap://hana.example.com:30015/?encrypt=true
                                  &validateCertificate=true
                                  &hostNameInCertificate=hana.example.com
                                  &trustStore=/etc/hana/trust.pem
                                  &cryptoProvider=openssl

-- 服务端 (global.ini)
[communication]
ssl = systemPKI
sslEnforce = true
sslCipherSuites = TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
sslMinProtocolVersion = TLSv1.2
```

HANA 2.0 SPS 06 引入 TLS 1.3，SPS 07 支持 FIPS 140-2 L1 模块。

## Vertica / Teradata / Greenplum：MPP 数据仓库

```sql
-- Vertica
ALTER DATABASE mydb SET EnableSSL = 1;
ALTER DATABASE mydb SET SSLCipherSuite = 'HIGH:!aNULL:!MD5';
ALTER DATABASE mydb SET FIPSMode = 'on';

-- Teradata: tdgssconfig.xml + DBS Control
-- 强制模式
UPDATE DBC.SecurityLogV
  SET MechanismName = 'TD2_TLS'
  WHERE UserName = 'ETL_USER';

-- Greenplum (继承 PG 的 sslmode，但管理工具推荐 verify-full)
gpconfig -c ssl -v on
gpconfig -c ssl_ciphers -v 'ECDHE+AESGCM:ECDHE+CHACHA20'
```

## mTLS（双向 TLS）深入

mTLS 不止是"加密"，更是一种**强身份认证**手段。启用 mTLS 后，攻击者仅仅窃取密码仍无法登录——必须同时持有客户端私钥。

```
典型 mTLS 握手:
  Client  --ClientHello (ALPN=postgres, SNI=db.example.com)-->  Server
  Client  <--ServerHello, ServerCert, CertificateRequest-------  Server
  Client  --ClientCert, CertificateVerify(sig), Finished------>  Server
  Client  <--Finished, ApplicationData------------------------- Server
```

各引擎的 mTLS 身份映射模式：

| 引擎 | 证书中的字段 | 映射到 DB 用户的方式 |
|------|------------|--------------------|
| PostgreSQL | CN 或 SAN | `pg_hba.conf` + `pg_ident.conf` 做名称映射 |
| MySQL / MariaDB | Subject DN | `CREATE USER ... REQUIRE SUBJECT '...'` |
| SQL Server | Windows principal (AD 集成) | 登录映射到证书 |
| Oracle | Wallet DN | `ALTER USER ... IDENTIFIED EXTERNALLY AS 'CN=..'` |
| CockroachDB | CN | 证书 CN 必须等于 SQL 用户名 |
| TiDB / OceanBase | Subject DN | `REQUIRE SUBJECT` |
| Vertica | CN + Issuer | 创建 `AUTHENTICATION` 对象绑定 |
| SAP HANA | DN / SPN | `PSE` + `USER MAPPING` |
| ClickHouse | CN | `users.xml` 中 `<ssl_certificates>` |
| Snowflake / BigQuery | JWT/OIDC 优先 | 服务账号或 JWK 公钥注册 |

PostgreSQL mTLS 完整示例：

```conf
# pg_hba.conf
hostssl  app_db  app_user  0.0.0.0/0  cert  map=cert_map clientcert=verify-full

# pg_ident.conf
# MAPNAME     SYSTEM-USERNAME                 PG-USERNAME
cert_map      "CN=app-client,O=Corp,C=US"     app_user
cert_map      /^CN=prod-([a-z]+)$             \1
```

客户端：

```bash
PGSSLCERT=~/certs/app.crt \
PGSSLKEY=~/certs/app.key  \
PGSSLROOTCERT=~/certs/ca.crt \
psql "host=db.example.com sslmode=verify-full dbname=app_db user=app_user"
```

## FIPS 140-2 / 140-3 合规

美国联邦机构、金融行业、部分欧洲合规项目要求加密模块必须通过 NIST CMVP 认证（FIPS 140-2 已于 2026-09-22 完全过渡到 FIPS 140-3）。常见达成路径：

| 引擎 | FIPS 实现 | 启用方式 |
|------|----------|---------|
| PostgreSQL | 构建时链接 FIPS OpenSSL（RHEL FIPS、OpenSSL 3.0 FIPS provider） | OS 级启用 FIPS 模式 |
| MySQL | `--ssl_fips_mode=ON` (5.7.19+) | 变量配置 |
| Oracle | `fips.ora`: `FIPS_140=TRUE` | 文件配置 |
| SQL Server | Windows FIPS 策略（本地安全策略） | GPO |
| DB2 | GSKit FIPS-capable 模式 | `DB2_SSL_FIPS_MODE=YES` |
| Vertica | `FIPSMode='on'` | ALTER DATABASE |
| Teradata | TLS 1.2 + FIPS 140-2 认证的 TDGSS | `TDGSSCONFIG` |
| SAP HANA | SPS 07+ | `global.ini` `[cryptography] provider=fips` |
| Snowflake / BigQuery / Databricks (GovCloud) | 平台级 FedRAMP High | 选择 Gov 区域 |
| Trino / Spark / H2 等 JVM 系 | OpenJDK FIPS / BouncyCastle FIPS | JVM 启动参数 |
| TiDB | BoringCrypto 构建 | 编译开关 |
| CockroachDB | 支持 FIPS 构建（`cockroach-linux-3.7.19-gnu-amd64` FIPS 变体） | 下载对应版本 |

> **警告**：FIPS 模式会禁用大量"常用但非合规"的算法（如 3DES、RC4、MD5 签名、早期曲线）。启用前必须确认客户端与所有中间件都兼容限定的算法集。

## 强制 vs 可选 TLS

"已支持 TLS"≠"生产环境安全"——关键在于是否**拒绝**非 TLS 连接：

```sql
-- MySQL / MariaDB / TiDB / OceanBase
SET GLOBAL require_secure_transport = ON;

-- PostgreSQL: pg_hba.conf 使用 hostssl 而非 host
hostssl all all 0.0.0.0/0 scram-sha-256
hostnossl all all 0.0.0.0/0 reject

-- SQL Server
EXEC sp_configure 'Force Encryption', 1;

-- CockroachDB: 不加 --insecure 即默认强制

-- ClickHouse: 注释掉 <tcp_port> 和 <http_port>
-- Oracle: listener.ora 只声明 TCPS
-- DB2: DB2COMM=SSL (移除 TCPIP)
```

Snowflake、BigQuery、Athena、Synapse、Databricks、Firebolt、Google Spanner、Redshift（Serverless）这类 SaaS **不存在**可关闭 TLS 的配置——这是云时代的默认红线。

## 端口速查

| 引擎 | 明文端口 | TLS 端口 |
|------|---------|---------|
| PostgreSQL | 5432 | 5432（同端口，STARTTLS 升级） |
| MySQL | 3306 | 3306（STARTTLS） |
| SQL Server | 1433 | 1433（pre-login 内置协商） |
| Oracle | 1521 (TCP) | **2484** (TCPS) |
| ClickHouse | 9000 / 8123 | **9440** / **8443** |
| MongoDB | 27017 | 27017（协商） |
| Cassandra | 9042 | 9042（协商） |
| Redshift | 5439 | 5439 |
| Snowflake | — | 443 (HTTPS) |
| BigQuery | — | 443 |
| Trino / Presto | 8080 | 8443 |
| Spark Thrift | 10000 | 10001 (HTTPS) 或 10000 (STARTTLS) |
| DB2 | 50000 | 50001 |

> Oracle 与 ClickHouse 是少数使用**独立端口**区分加密与明文的引擎，其他大部分使用 STARTTLS（同端口升级）。

## 常见误区与反面教材

1. **`sslmode=require` 不是安全的**：它只验证"通道被加密"，不验证对端身份。中间人攻击者可以伪造证书。`verify-full` 才是生产级配置。
2. **`TrustServerCertificate=true` 等于没加密**：SQL Server 和 MySQL 的"信任所有证书"选项在出错时随手一加就变成了后门。
3. **TLS 1.2 仍然安全吗？** PCI-DSS 4.0、NIST SP 800-52 Rev.2 仍然允许 TLS 1.2，但要求禁用 CBC 模式 + 静态 RSA 密钥交换。TLS 1.3 强制前向保密。
4. **压缩漏洞**：启用 TLS 压缩（CRIME/BREACH 攻击向量）在现代数据库中应关闭。OpenSSL 默认已禁用。
5. **自签证书 + verify-full**：需要把自签 CA 放入客户端 truststore，不是 `TrustServerCertificate=true`。
6. **mTLS ≠ "更强的密码"**：证书过期后连接会彻底中断——必须建立证书自动轮换机制（cert-manager、HashiCorp Vault PKI 等）。
7. **内部网络就不用加密？** 零信任架构已经把这个假设打碎——AWS、GCP 等云厂商已经在 VPC 内部默认 mTLS。

## 关键发现

1. **47/48 引擎支持 TLS**，唯一例外是嵌入式 SQLite。这意味着"不加密"在今天已经是主动选择。
2. **TLS 1.3 普及率约 94%**：45/48 引擎支持 TLS 1.3，延迟比 TLS 1.2 握手减少一个 RTT。
3. **PostgreSQL 的 `sslmode` 成为事实标准**，被 Redshift、CockroachDB、YugabyteDB、Greenplum、TimescaleDB 等 PG 衍生品全盘继承。
4. **云托管引擎强制加密**：Snowflake、BigQuery、Databricks、Athena、Synapse、Spanner、Firebolt 等 9 款 SaaS 不提供关闭 TLS 的选项。
5. **mTLS 是合规项目的最低线**：金融、医疗、政府场景普遍要求 mTLS + FIPS；35 个引擎原生支持 mTLS。
6. **Oracle 与 ClickHouse 使用独立 TLS 端口**（2484 / 9440），其他引擎通过 STARTTLS 在同一端口升级。
7. **FIPS 140-2/3 模式覆盖不均**：Oracle、Teradata、Vertica、SAP HANA、SQL Server 原生支持；开源引擎通常依赖发行版（RHEL FIPS、OpenJDK FIPS）。
8. **`require`/`PREFERRED` 是伪安全**：它们只挡被动窃听，不防主动中间人攻击。生产必须 `verify-full` 或 `VERIFY_IDENTITY`。
9. **SCRAM-SHA-256 + TLS 是 PG 的现代默认**（PG 10, 2017）。仍然使用 `md5` 认证的 PG 应视为 Legacy。
10. **MySQL 8.0.16 起默认开启 TLS**：即便客户端未请求，握手失败也不会回退明文；这是从 5.7 到 8.0 的一项隐式安全升级。
11. **SQL Server 2022 的 `Encrypt=Strict`** 在 pre-login 阶段就要求 TDS 8.0，消除了 TLS 降级攻击面。
12. **可重复审计**：`pg_stat_ssl`（PG 9.5+）、`performance_schema.session_ssl_status`（MySQL 8.0.21+）、`sys.dm_exec_connections.encrypt_option`（SQL Server）让 DBA 能实时验证连接是否加密。

## 对引擎开发者的实现建议

1. **默认安全优于默认易用**：向 CockroachDB、Snowflake 看齐，让"不加密"成为需要显式开关的降级选项。
2. **握手过程最小化明文**：pre-login/prelogin 消息里不要泄漏数据库版本、用户名、认证方式清单。MySQL 8.0 / SQL Server 2022 已经做到这一点。
3. **ALPN 支持**：公布自己的 ALPN 标识（如 PostgreSQL 的 `postgresql`、SQL Server 2022 的 `tds/8.0`），避免被通用反向代理误识别。
4. **证书轮换的零停机**：让管理员可以通过 SQL/HTTP API 动态加载新证书（`pg_reload_conf()`、`ALTER SYSTEM RELOAD SSL`）。
5. **密码套件白名单而非黑名单**：OpenSSL 的 `HIGH:!aNULL:!MD5` 等写法在每次新漏洞曝光后都需要更新；改成"只允许 TLS 1.3 + 指定 AEAD"更可持续。
6. **TLS 1.3 的 0-RTT 谨慎使用**：数据库协议通常不是幂等的，0-RTT 重放可能导致写入重复。默认关闭 0-RTT，或只对只读查询启用。
7. **FIPS 可构建性**：提供官方 FIPS 认证的发行版（CockroachDB、TiDB BoringCrypto 已经做到），避免用户自己拼 OpenSSL FIPS provider。
8. **可观测性**：暴露每个会话的 TLS 版本、密码套件、客户端证书指纹，既便于审计，也便于出事时确定受影响范围。

## 参考资料

- RFC 8446: [The Transport Layer Security (TLS) Protocol Version 1.3](https://datatracker.ietf.org/doc/html/rfc8446)
- RFC 8996: [Deprecating TLS 1.0 and TLS 1.1](https://datatracker.ietf.org/doc/html/rfc8996)
- RFC 8705: [OAuth 2.0 Mutual-TLS Client Authentication](https://datatracker.ietf.org/doc/html/rfc8705)
- NIST SP 800-52 Rev.2: Guidelines for the Selection, Configuration, and Use of TLS Implementations
- NIST FIPS 140-3: Security Requirements for Cryptographic Modules
- PostgreSQL: [SSL Support](https://www.postgresql.org/docs/current/ssl-tcp.html)
- PostgreSQL: [libpq SSL Mode](https://www.postgresql.org/docs/current/libpq-ssl.html)
- MySQL: [Using Encrypted Connections](https://dev.mysql.com/doc/refman/8.0/en/encrypted-connection-protocols-ciphers.html)
- MariaDB: [Secure Connections Overview](https://mariadb.com/kb/en/secure-connections-overview/)
- SQL Server: [Encrypt Connections](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-sql-server-encryption)
- Oracle: [Database Security Guide - Network Encryption](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/)
- Snowflake: [Security - Encryption in Transit](https://docs.snowflake.com/en/user-guide/security-column-intro)
- BigQuery: [Encryption in Transit](https://cloud.google.com/docs/security/encryption-in-transit)
- Databricks: [Security and Compliance](https://docs.databricks.com/en/security/index.html)
- ClickHouse: [Server Settings - OpenSSL](https://clickhouse.com/docs/en/operations/server-configuration-parameters/settings#openssl)
- CockroachDB: [Authentication and Encryption](https://www.cockroachlabs.com/docs/stable/authentication)
- TiDB: [Enable TLS Between TiDB Clients and Servers](https://docs.pingcap.com/tidb/stable/enable-tls-between-clients-and-servers)
- SAP HANA: [Security Guide - TLS/SSL](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Trino: [Secure Internal Communication](https://trino.io/docs/current/security/internal-communication.html)
- Apache Spark: [Security - SSL Configuration](https://spark.apache.org/docs/latest/security.html)
