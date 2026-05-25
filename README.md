# Aurora PostgreSQL CA Buildpack

Classic Cloud Foundry supply buildpack for Aurora PostgreSQL service bindings
that expose `credentials.certificate_authority_url` in `VCAP_SERVICES`.

## Usage

Use this buildpack before the application buildpack:

```bash
cf push APP_NAME -b aurora-ca-buildpack -b java_buildpack
```

The buildpack is non-final. It does not provide a start command and should not
be the last buildpack unless another buildpack or a Procfile supplies the app
start command.

## Behavior

During staging, `bin/supply`:

1. Parses `VCAP_SERVICES`.
2. Finds Aurora PostgreSQL bindings.
3. Reads unique `credentials.certificate_authority_url` values.
4. Downloads each CA bundle with `curl`.
5. Validates each bundle with `openssl`.
6. Stores a combined bundle under `deps/<index>/aurora-ca-certificates`.
7. Writes `deps/<index>/config.yml` for the Cloud Foundry buildpack contract.
8. Writes `deps/<index>/profile.d/aurora-ca-certificates.sh`.

At launch, the profile script:

1. Exports `SSL_CERT_FILE`, `SSL_CERT_DIR`, `REQUESTS_CA_BUNDLE`, and
   `CURL_CA_BUNDLE` pointing at the staged CA bundle.
2. Attempts to copy the CA bundle to
   `/usr/local/share/ca-certificates/aurora-postgresql-ca.crt` and run
   `update-ca-certificates` when the container allows it.
3. Logs a warning and keeps the environment-variable fallback when the system
   truststore is not writable.

## Service Matching

A binding is treated as Aurora PostgreSQL when any of these are true:

- `label` is `csb-aws-aurora-postgresql`.
- `name` is `csb-aws-aurora-postgresql`.
- `tags` include `aurora` and either `postgres` or `postgresql`.

Bindings without `credentials.certificate_authority_url` are ignored.

## Requirements

The staging container must provide:

- `bash`
- `jq`
- `curl`
- `openssl`

## Limitations

Classic non-final buildpacks are constrained to write under `deps/<index>`
during staging. This buildpack therefore cannot guarantee a real mutation of
`/etc/ssl/certs` at staging time. It performs a launch-time system truststore
install only when the runtime container permits it, and otherwise relies on the
exported CA bundle variables.

The final app buildpack must honor supplied `profile.d` scripts from earlier
buildpacks, which is the contract used by Cloud Foundry core buildpacks.

## Tests

Run:

```bash
bash tests/run
```
