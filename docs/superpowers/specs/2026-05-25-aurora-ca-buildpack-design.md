# Aurora CA Buildpack Design

## Goal

Build a classic Cloud Foundry supply buildpack that reads Aurora PostgreSQL
`certificate_authority_url` values from `VCAP_SERVICES`, downloads the referenced
CA bundle, and makes that bundle trusted by application processes.

## External References

- Cloud Foundry classic buildpack scripts: `bin/detect`, `bin/supply`,
  `bin/finalize`, and `bin/release`.
- Cloud Foundry trusted system certificates: cflinuxfs app instances expose
  system certificates through `/etc/ssl/certs`, with administrator configured
  certificates also exposed by `CF_SYSTEM_CERT_PATH`.

## Architecture

The buildpack is a non-final supply buildpack. It is intended to be pushed before
the app buildpack, for example:

```bash
cf push APP -b aurora-ca-buildpack -b java_buildpack
```

`bin/supply` writes only to `deps/<index>`, which keeps it within the classic
multi-buildpack contract. It downloads and validates the CA bundle during staging,
writes `deps/<index>/config.yml`, then writes launch-time environment scripts
under `deps/<index>/profile.d`.

Because a non-final buildpack cannot safely mutate `/etc/ssl/certs` during
staging, the launch script attempts a real system truststore installation only
when the runtime container permits writes to `/usr/local/share/ca-certificates`
and `update-ca-certificates` is available. If the container does not allow this,
the script exports `SSL_CERT_FILE`, `SSL_CERT_DIR`, `REQUESTS_CA_BUNDLE`, and
`CURL_CA_BUNDLE` pointing at the staged bundle so common TLS libraries can still
use the downloaded CA.

## Components

- `bin/detect`: always returns success and identifies the buildpack.
- `bin/supply`: validates arguments, reads `VCAP_SERVICES`, extracts unique
  Aurora PostgreSQL CA URLs, downloads each bundle, validates the PEM with
  `openssl`, combines them, writes `config.yml`, and writes launch-time profile
  scripts.
- `lib/aurora_ca_supply.sh`: shell functions for download, validation, and
  profile script generation. It uses `jq` to parse `VCAP_SERVICES`.
- `tests/run`: dependency-free shell test harness.

## Aurora Service Matching

A service binding is considered Aurora PostgreSQL when at least one of these is
true:

- `label` is `csb-aws-aurora-postgresql`.
- `name` is `csb-aws-aurora-postgresql`.
- `tags` include both `aurora` and one of `postgres`, `postgresql`.

Only bindings with a non-empty
`credentials.certificate_authority_url` value are used.

## Error Handling

- Missing `VCAP_SERVICES` or no matching CA URLs: skip installation and exit
  successfully.
- Malformed `VCAP_SERVICES`: fail staging with a clear error.
- Missing required tools: fail staging when `jq`, `curl`, or `openssl` is
  unavailable.
- Download failure or invalid PEM: fail staging.
- Runtime truststore is not writable: log a warning and use environment-variable
  trust bundle fallback.

## Testing

The test harness exercises parser and supply behavior without Cloud Foundry:

- CA URLs are extracted from the sample Aurora service.
- Non-Aurora services are ignored.
- Duplicate URLs are de-duplicated.
- Malformed JSON fails.
- `bin/supply` downloads a local PEM URL, validates it, and creates profile
  scripts.
- `bin/supply` succeeds when no Aurora CA URL is present.
