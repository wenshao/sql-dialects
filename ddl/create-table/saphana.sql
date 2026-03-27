-- SAP HANA: CREATE TABLE
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Column store (default, optimized for analytics)
CREATE COLUMN TABLE users (
    id         BIGINT        NOT NULL GENERATED ALWAYS AS IDENTITY,
    username   NVARCHAR(64)  NOT NULL,
    email      NVARCHAR(255) NOT NULL,
    age        INTEGER,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        NCLOB,
    created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE (username),
    UNIQUE (email)
);

-- Row store (optimized for OLTP point lookups)
CREATE ROW TABLE sessions (
    session_id NVARCHAR(128) PRIMARY KEY,
    user_id    BIGINT NOT NULL,
    data       NCLOB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

-- Partitioned table (hash partitioning)
CREATE COLUMN TABLE orders (
    order_id   BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    user_id    BIGINT NOT NULL,
    amount     DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id)
)
PARTITION BY HASH (user_id) PARTITIONS 8;

-- Range partitioning
CREATE COLUMN TABLE events (
    event_id   BIGINT NOT NULL,
    event_date DATE NOT NULL,
    event_type NVARCHAR(50),
    payload    NCLOB
)
PARTITION BY RANGE (event_date) (
    PARTITION '2020-01-01' <= VALUES < '2021-01-01',
    PARTITION '2021-01-01' <= VALUES < '2022-01-01',
    PARTITION '2022-01-01' <= VALUES < '2023-01-01',
    PARTITION OTHERS
);

-- Round-robin partitioning
CREATE COLUMN TABLE logs (
    log_id  BIGINT NOT NULL,
    message NVARCHAR(5000)
)
PARTITION BY ROUNDROBIN PARTITIONS 4;

-- Temporary table (global)
CREATE GLOBAL TEMPORARY TABLE temp_results (
    id    BIGINT,
    value DECIMAL(10,2)
);

-- Local temporary table (session-scoped, # prefix convention)
CREATE LOCAL TEMPORARY TABLE #my_temp (
    id    BIGINT,
    value DECIMAL(10,2)
);

-- CTAS
CREATE COLUMN TABLE users_copy AS (
    SELECT * FROM users
) WITH DATA;

-- Table with FUZZY SEARCH index
CREATE COLUMN TABLE documents (
    doc_id  BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    title   NVARCHAR(500),
    content NCLOB,
    PRIMARY KEY (doc_id)
);
-- Enable fuzzy search
CREATE FULLTEXT INDEX ft_content ON documents (content)
    FUZZY SEARCH INDEX ON;

-- History table (system-versioned temporal)
CREATE COLUMN TABLE employees (
    emp_id     BIGINT NOT NULL,
    emp_name   NVARCHAR(100),
    department NVARCHAR(50),
    valid_from TIMESTAMP NOT NULL GENERATED ALWAYS AS ROW START,
    valid_to   TIMESTAMP NOT NULL GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to),
    PRIMARY KEY (emp_id)
) WITH SYSTEM VERSIONING;

-- Series table (time series data)
CREATE COLUMN TABLE sensor_data (
    sensor_id  NVARCHAR(50),
    ts         TIMESTAMP,
    value      DECIMAL(10,4),
    PRIMARY KEY (sensor_id, ts)
)
SERIES (
    SERIES KEY (sensor_id)
    PERIOD FOR SERIES (ts)
    EQUIDISTANT INCREMENT BY INTERVAL 1 SECOND
);
