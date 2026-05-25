#!/usr/bin/env bash

aurora_ca_log() {
  echo "Aurora CA Buildpack: $*"
}

aurora_ca_fail() {
  echo "Aurora CA Buildpack: ERROR: $*" >&2
  exit 1
}

aurora_ca_require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    aurora_ca_fail "Required command '${command_name}' is not available"
  fi
}

aurora_ca_download() {
  local url="$1"
  local output_path="$2"

  curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 \
    --output "${output_path}" \
    "${url}"
}

aurora_ca_validate_pem_bundle() {
  local bundle_path="$1"

  if [[ ! -s "${bundle_path}" ]]; then
    aurora_ca_fail "Downloaded CA bundle is empty: ${bundle_path}"
  fi

  if ! grep -q -- "-----BEGIN CERTIFICATE-----" "${bundle_path}" ||
     ! grep -q -- "-----END CERTIFICATE-----" "${bundle_path}"; then
    aurora_ca_fail "Downloaded CA bundle does not contain a PEM certificate: ${bundle_path}"
  fi

  if ! openssl crl2pkcs7 -nocrl -certfile "${bundle_path}" >/dev/null 2>&1; then
    aurora_ca_fail "Downloaded CA bundle is not a valid PEM certificate bundle: ${bundle_path}"
  fi
}

aurora_ca_extract_urls() {
  local vcap_services="${VCAP_SERVICES:-}"
  local jq_output

  if [[ -z "${vcap_services//[[:space:]]/}" ]]; then
    return 0
  fi

  if ! jq_output="$(jq --raw-output '
    def aurora_postgres_binding:
      (.label // "") == "csb-aws-aurora-postgresql"
      or (.name // "") == "csb-aws-aurora-postgresql"
      or (
        ((.tags // []) | map(tostring | ascii_downcase)) as $tags
        | ($tags | index("aurora")) != null
          and (($tags | index("postgres")) != null or ($tags | index("postgresql")) != null)
      );

    [
      to_entries[]
      | .value[]
      | select(type == "object")
      | select(aurora_postgres_binding)
      | .credentials.certificate_authority_url? // empty
      | select(type == "string" and length > 0)
    ]
    | unique
    | .[]
  ' <<<"${vcap_services}" 2>/dev/null)"; then
    echo "Invalid VCAP_SERVICES JSON" >&2
    return 1
  fi

  printf "%s\n" "${jq_output}"
}

aurora_ca_write_profile_script() {
  local index="$1"
  local profile_dir="$2"
  local script_path="${profile_dir}/aurora-ca-certificates.sh"

  mkdir -p "${profile_dir}"

  cat >"${script_path}" <<PROFILE
#!/usr/bin/env bash

aurora_ca_dir="/home/vcap/deps/${index}/aurora-ca-certificates"
aurora_ca_bundle="\${aurora_ca_dir}/aurora-ca-bundle.pem"
aurora_ca_cert="\${aurora_ca_dir}/aurora-ca-bundle.crt"

if [[ ! -s "\${aurora_ca_bundle}" ]]; then
  echo "Aurora CA Buildpack: CA bundle is missing at \${aurora_ca_bundle}" >&2
  return 0
fi

export SSL_CERT_FILE="\${aurora_ca_bundle}"
export REQUESTS_CA_BUNDLE="\${aurora_ca_bundle}"
export CURL_CA_BUNDLE="\${aurora_ca_bundle}"
export SSL_CERT_DIR="\${aurora_ca_dir}\${SSL_CERT_DIR:+:\${SSL_CERT_DIR}}"

if command -v update-ca-certificates >/dev/null 2>&1 &&
   [[ -d /usr/local/share/ca-certificates && -w /usr/local/share/ca-certificates ]]; then
  cp "\${aurora_ca_cert}" /usr/local/share/ca-certificates/aurora-postgresql-ca.crt &&
    update-ca-certificates >/dev/null 2>&1 &&
    echo "Aurora CA Buildpack: installed Aurora PostgreSQL CA into system truststore"
else
  echo "Aurora CA Buildpack: system truststore is not writable; using CA bundle environment variables"
fi
PROFILE

  chmod +x "${script_path}"
}

aurora_ca_write_config() {
  local deps_index_dir="$1"

  cat >"${deps_index_dir}/config.yml" <<'YAML'
---
name: aurora-ca-buildpack
config:
  certificate_bundle: aurora-ca-certificates/aurora-ca-bundle.pem
  profile_script: profile.d/aurora-ca-certificates.sh
YAML
}

aurora_ca_install() {
  local build_dir="$1"
  local deps_dir="$2"
  local index="$3"
  local buildpack_dir="$4"
  local install_dir="${deps_dir}/${index}/aurora-ca-certificates"
  local deps_index_dir="${deps_dir}/${index}"
  local profile_dir="${deps_dir}/${index}/profile.d"
  local urls

  aurora_ca_require_command jq
  aurora_ca_require_command curl
  aurora_ca_require_command openssl

  mkdir -p "${install_dir}"

  if ! urls="$(aurora_ca_extract_urls)"; then
    aurora_ca_fail "Could not parse VCAP_SERVICES"
  fi

  if [[ -z "${urls}" ]]; then
    aurora_ca_log "No Aurora PostgreSQL CA URL found in VCAP_SERVICES; skipping"
    return 0
  fi

  : >"${install_dir}/aurora-ca-bundle.pem"

  local count=0
  local url
  while IFS= read -r url; do
    [[ -z "${url}" ]] && continue
    count=$((count + 1))

    local cert_path="${install_dir}/aurora-ca-${count}.pem"
    aurora_ca_log "Downloading Aurora PostgreSQL CA bundle ${count}"
    aurora_ca_download "${url}" "${cert_path}" || aurora_ca_fail "Failed to download CA bundle from ${url}"
    aurora_ca_validate_pem_bundle "${cert_path}"
    cat "${cert_path}" >>"${install_dir}/aurora-ca-bundle.pem"
    printf "\n" >>"${install_dir}/aurora-ca-bundle.pem"
  done <<<"${urls}"

  cp "${install_dir}/aurora-ca-bundle.pem" "${install_dir}/aurora-ca-bundle.crt"
  aurora_ca_write_config "${deps_index_dir}"
  aurora_ca_write_profile_script "${index}" "${profile_dir}"

  aurora_ca_log "Installed ${count} Aurora PostgreSQL CA bundle(s) for launch-time trust configuration"
}
