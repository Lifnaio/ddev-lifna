#!/usr/bin/env bash
#ddev-generated
set -euo pipefail

manifest=".lifna/environment.json"
env_file=".ddev/lifna/.env"
downloads=".ddev/.downloads"

if [ -f "${env_file}" ]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

json_value() {
  php -r '
    $path = explode(".", $argv[1]);
    $file = $argv[2];
    if (! is_file($file)) {
        echo "";
        exit(0);
    }
    $data = json_decode(file_get_contents($file), true);
    $value = $data;
    foreach ($path as $part) {
        if (! is_array($value) || ! array_key_exists($part, $value)) {
            echo "";
            exit(0);
        }
        $value = $value[$part];
    }
    echo is_scalar($value) ? $value : "";
  ' "$1" "$manifest"
}

lifna_site="${LIFNA_SITE:-$(json_value site.slug)}"
lifna_environment="${LIFNA_ENVIRONMENT:-$(json_value environment.slug)}"
lifna_base_url="${LIFNA_BASE_URL:-$(json_value lifna.base_url)}"
lifna_token="${LIFNA_TOKEN:-}"
lifna_environment_type="${LIFNA_ENVIRONMENT_TYPE:-$(json_value environment.type)}"
api_path="/api/ddev/v1/sites/${lifna_site}/environments/${lifna_environment}"

require_context() {
  if [ -z "${lifna_base_url}" ] || [ -z "${lifna_site}" ] || [ -z "${lifna_environment}" ]; then
    echo "Missing Lifna context. Run: ddev lifna connect --site=<site-slug> --environment=<env-slug> --base-url=<lifna-url>" >&2
    exit 64
  fi
}

validate_base_url() {
  local trusted_url="https://app.lifna.com"

  if [ "${LIFNA_DEV_MODE:-0}" = "1" ]; then
    case "${lifna_base_url}" in
      https://*|http://localhost:*|http://localhost|http://127.0.0.1:*|http://127.0.0.1|http://[::1]:*|http://[::1])
        return 0
        ;;
      *)
        echo "Dev mode allows HTTPS and local HTTP URLs only." >&2
        exit 64
        ;;
    esac
  fi

  if [ "${lifna_base_url}" != "${trusted_url}" ]; then
    echo "Refusing untrusted Lifna URL: ${lifna_base_url}" >&2
    echo "Expected ${trusted_url}. Set LIFNA_DEV_MODE=1 only for local Lifna development." >&2
    exit 64
  fi
}

require_token() {
  if [ -z "${lifna_token}" ]; then
    cat >&2 <<'TOKEN'
Missing LIFNA_TOKEN.

Create a Lifna DDEV token, then run:
  ddev lifna connect --site=<site-slug> --environment=<env-slug> --base-url=<lifna-url>

Do not commit tokens to Git.
TOKEN
    exit 64
  fi
}

curl_lifna() {
  require_context
  validate_base_url
  require_token
  curl --fail --silent --show-error \
    -H "Authorization: Bearer ${lifna_token}" \
    -H "Accept: application/json" \
    "$@"
}

post_lifna() {
  curl_lifna -X POST "${lifna_base_url}${api_path}/$1"
}

is_protected_environment() {
  local slug
  local type
  slug="$(printf '%s' "${lifna_environment}" | tr '[:upper:]' '[:lower:]')"
  type="$(printf '%s' "${lifna_environment_type}" | tr '[:upper:]' '[:lower:]')"

  case "${slug}" in
    main|live|prod|production) return 0 ;;
  esac

  case "${type}" in
    production|live|prod) return 0 ;;
  esac

  return 1
}

confirm_protected_push() {
  if ! is_protected_environment; then
    return 0
  fi

  local phrase="push ${lifna_site}/${lifna_environment}"
  local reply=""

  echo "This will upload your local database/files to protected Lifna environment ${lifna_site}/${lifna_environment}."
  echo "Type '${phrase}' to continue:"
  IFS= read -r reply

  if [ "${reply}" != "${phrase}" ]; then
    echo "Push cancelled." >&2
    exit 67
  fi
}

validate_tar_paths() {
  local archive="$1"

  tar -tzf "${archive}" | while IFS= read -r entry; do
    case "${entry}" in
      /*|../*|*/../*|..|*/..)
        echo "Unsafe path in Lifna files archive: ${entry}" >&2
        exit 1
        ;;
    esac
  done
}

case "${1:-status}" in
  info)
    require_context
    echo "${lifna_site}.${lifna_environment} @ ${lifna_base_url}"
    ;;
  doctor)
    require_context
    echo "Lifna site: ${lifna_site}"
    echo "Lifna environment: ${lifna_environment}"
    echo "Lifna base URL: ${lifna_base_url}"
    if [ -n "${lifna_token}" ]; then
      echo "Token: present"
    else
      echo "Token: missing"
    fi
    ;;
  auth)
    curl_lifna "${lifna_base_url}${api_path}" >/dev/null
    echo "Authenticated to Lifna as ${lifna_site}/${lifna_environment}."
    ;;
  login)
    require_context
    echo "Open Lifna and create a local access token for ${lifna_site}/${lifna_environment}:"
    echo "  ${lifna_base_url}/sites/${lifna_site}/export"
    ;;
  status)
    curl_lifna "${lifna_base_url}${api_path}"
    ;;
  spinup)
    post_lifna spinup
    ;;
  pause)
    post_lifna pause
    ;;
  open)
    require_context
    curl_lifna "${lifna_base_url}${api_path}" | php -r '
      $payload = json_decode(stream_get_contents(STDIN), true);
      echo $payload["environment"]["url"] ?? "";
      echo "\n";
    '
    ;;
  pull-db)
    mkdir -p "${downloads}"
    curl_lifna -L "${lifna_base_url}${api_path}/pull/database" -o "${downloads}/db.sql.gz"
    echo "Downloaded Lifna database to ${downloads}/db.sql.gz"
    ;;
  pull-files)
    mkdir -p "${downloads}"
    rm -rf "${downloads}/files"
    mkdir -p "${downloads}/files"
    curl_lifna -L "${lifna_base_url}${api_path}/pull/files" -o "${downloads}/files.tar.gz"
    validate_tar_paths "${downloads}/files.tar.gz"
    tar -xzf "${downloads}/files.tar.gz" -C "${downloads}/files"
    echo "Downloaded Lifna files to ${downloads}/files"
    ;;
  push-db)
    if [ ! -f "${downloads}/db.sql.gz" ]; then
      echo "DDEV did not provide ${downloads}/db.sql.gz for push." >&2
      exit 66
    fi
    confirm_protected_push
    curl_lifna -X POST -F "database=@${downloads}/db.sql.gz" "${lifna_base_url}${api_path}/push/database"
    ;;
  push-files)
    mkdir -p "${downloads}"
    if [ -d "web/sites/default/files" ]; then
      tar -czf "${downloads}/files-push.tar.gz" -C web/sites/default files
    elif [ -n "${DDEV_FILES_DIRS:-}" ]; then
      tar -czf "${downloads}/files-push.tar.gz" ${DDEV_FILES_DIRS}
    else
      echo "No Drupal files directory found to push." >&2
      exit 66
    fi
    validate_tar_paths "${downloads}/files-push.tar.gz"
    confirm_protected_push
    curl_lifna -X POST -F "files=@${downloads}/files-push.tar.gz" "${lifna_base_url}${api_path}/push/files"
    ;;
  *)
    echo "Unknown Lifna command: $1" >&2
    exit 64
    ;;
esac
