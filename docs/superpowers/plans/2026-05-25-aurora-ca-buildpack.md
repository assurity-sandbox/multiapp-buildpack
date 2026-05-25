# Aurora CA Buildpack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a classic Cloud Foundry supply buildpack that installs Aurora PostgreSQL CA trust from `VCAP_SERVICES`.

**Architecture:** A Bash `bin/supply` script coordinates staging work, a small Ruby
parser extracts CA URLs from `VCAP_SERVICES`, and launch-time profile scripts
expose the staged CA bundle to application processes. The buildpack stays
non-final so it can be used before the real application buildpack.

**Tech Stack:** Bash, Ruby standard `json`, `curl`, `openssl`, dependency-free shell tests.

---

## File Structure

- `bin/detect`: buildpack detection entry point.
- `bin/supply`: classic supply entry point.
- `lib/aurora_ca_supply.sh`: shell functions used by `bin/supply`, including
  `jq` parsing for Aurora CA URLs.
- `tests/run`: shell test harness.
- `test/fixtures/aurora-vcap.json`: Aurora VCAP fixture.
- `README.md`: usage and behavior notes.

### Task 1: Parser Tests

**Files:**
- Create: `tests/run`
- Create: `test/fixtures/aurora-vcap.json`
- Modify: `lib/aurora_ca_supply.sh`

- [ ] **Step 1: Write parser tests**

Add tests that call the `aurora_ca_extract_urls` shell function with Aurora,
non-Aurora, duplicate, unicode-escaped, and malformed JSON inputs.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run`

Expected: failure because `aurora_ca_extract_urls` does not exist.

- [ ] **Step 3: Implement parser**

Implement `aurora_ca_extract_urls` with `jq`, matching
`csb-aws-aurora-postgresql` by label/name or Aurora plus Postgres tags, and
printing unique non-empty CA URLs.

- [ ] **Step 4: Run tests to verify parser passes**

Run: `bash tests/run`

Expected: parser tests pass.

### Task 2: Supply Buildpack

**Files:**
- Create: `bin/detect`
- Create: `bin/supply`
- Create: `lib/aurora_ca_supply.sh`
- Modify: `tests/run`

- [ ] **Step 1: Write supply tests**

Add tests for local CA download, PEM validation, generated `config.yml`,
generated profile scripts, and no-URL skip behavior.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run`

Expected: supply tests fail because `bin/supply` does not exist.

- [ ] **Step 3: Implement buildpack scripts**

Implement `bin/detect`, `bin/supply`, and `lib/aurora_ca_supply.sh` with required
tool checks, download, validation, combined bundle creation, `config.yml`, and
launch profile generation.

- [ ] **Step 4: Run tests to verify supply behavior passes**

Run: `bash tests/run`

Expected: all tests pass.

### Task 3: Documentation and Verification

**Files:**
- Create: `README.md`
- Modify: executable bits for `bin/detect`, `bin/supply`, and `tests/run`

- [ ] **Step 1: Document usage**

Document `cf push APP -b aurora-ca-buildpack -b app-buildpack`, service matching,
runtime truststore behavior, fallback variables, and limitations.

- [ ] **Step 2: Run verification**

Run: `bash tests/run`

Expected: all tests pass.

- [ ] **Step 3: Inspect repository state**

Run: `git status --short`

Expected: only intended files are changed.
