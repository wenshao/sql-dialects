# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses date-based version identifiers.

## [Unreleased]

## [2026-03-28] - Infrastructure improvements

### Added
- Missing `_comparison.md` for `ddl/users-databases/` module
- Missing `_comparison.md` for `types/array-map-struct/` module
- `.gitignore` file
- CI workflow (`.github/workflows/ci.yml`) with automated validation
- Unified CLI tool (`tools/cli.py`) consolidating `convert.py` and `expand_tables.py`
- GitHub Issue templates (syntax error report, new dialect request, new module request)
- GitHub Pull Request template
- `CHANGELOG.md`

## [2026-03-22] - Bulk SQL-to-MD conversion (batch 2)

### Added
- Convert 408 SQL files to Markdown: TiDB, OceanBase, CockroachDB, Spanner, YugabyteDB, Trino, Flink, DuckDB (1,181 files changed)
- Convert 408 SQL files to Markdown: Databricks, Redshift, Synapse, Greenplum, MariaDB, Impala, Vertica, Teradata

### Changed
- Audit round 2: cross-consistency, format, completeness fixes
- Verify and enrich all people pages with source citations

## [2026-03-15] - People, SQL standards, modern SQL features

### Added
- Key people pages for database founders (22 dialect pages updated)
- SQL standard version pages and evolution history (SQL-86 through SQL:2023)
- `docs/people/` section (20 pages on database founders/key people)
- `docs/sql-standards/` section (11 pages on SQL standard evolution)
- `docs/modern-sql-features/` section (51 articles on modern SQL features)

### Changed
- Deep rewrites of all 51 Snowflake and Hive SQL files
- Enrichment of dialect module tables (batch updates)

## [2026-03-01] - Bulk SQL-to-MD conversion (batch 1)

### Added
- Convert 255 SQL files to Markdown for MySQL, PostgreSQL, Oracle, SQL Server, SQLite
- Missing engine-level features added for multiple dialects

## [2026-02-15] - Initial release

### Added
- Initial release with 2,295 SQL files covering 45 dialects × 51 modules
- 47 comparison tables (`_comparison.md`)
- 11 real-world scenario modules
- `INDEX.md` global navigation index
- `REFERENCES.md` official documentation links
- `CONTRIBUTING.md` contribution guidelines
- `docs/` documentation section with migration guides and feature design checklist
- `convert.py` SQL-to-Markdown conversion tool
- `expand_tables.py` dialect page enrichment tool
