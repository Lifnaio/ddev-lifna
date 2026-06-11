#!/usr/bin/env bats

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="lifna-addon-${BATS_TEST_NUMBER:-0}-${RANDOM:-0}"
  export TESTDIR="${BATS_TMPDIR}/${PROJNAME}"
  export TEST_BASH="${BASH:-bash}"
  rm -rf "${TESTDIR}"
  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
}

teardown() {
  set +e
  if command -v ddev >/dev/null 2>&1; then
    ddev stop --unlist "${PROJNAME}" >/dev/null 2>&1
    ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  fi
  rm -rf "${TESTDIR}"
}

create_fake_curl() {
  mkdir -p "${TESTDIR}/bin"
  cat > "${TESTDIR}/bin/curl" <<'SH'
#!/usr/bin/env bash
set -eu

out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "${out}" ]; then
  cp "${FAKE_CURL_ARCHIVE}" "${out}"
else
  printf '{"environment":{"url":"https://example.com"}}\n'
fi
SH
  chmod +x "${TESTDIR}/bin/curl"
}

create_tar() {
  local archive="$1"
  local entry="$2"
  command -v python3 >/dev/null 2>&1 || skip "python3 is required for tar fixture creation"

  python3 - "$archive" "$entry" <<'PY'
import io
import sys
import tarfile

archive, entry = sys.argv[1], sys.argv[2]
payload = b"fixture"
info = tarfile.TarInfo(entry)
info.size = len(payload)

with tarfile.open(archive, "w:gz") as tar:
    tar.addfile(info, io.BytesIO(payload))
PY
}

@test "generated files carry ddev-generated markers" {
  grep -q '#ddev-generated' "${DIR}/providers/lifna.yaml"
  grep -q '#ddev-generated' "${DIR}/commands/host/lifna"
  grep -q '#ddev-generated' "${DIR}/lifna/client.sh"
  grep -q '#ddev-generated' "${DIR}/lifna/.gitignore"
}

@test "connect writes scoped manifest and local token file from environment token" {
  run env DDEV_APPROOT="${TESTDIR}" DDEV_SITENAME="unit" LIFNA_TOKEN="lft_test_secret" \
    "${DIR}/commands/host/lifna" connect \
    --site=dream-site \
    --environment=main \
    --base-url=https://app.lifna.com

  [ "$status" -eq 0 ]
  [ -f "${TESTDIR}/.lifna/environment.json" ]
  [ -f "${TESTDIR}/.ddev/lifna/.env" ]
  grep -q '"base_url": "https://app.lifna.com"' "${TESTDIR}/.lifna/environment.json"
  grep -q '"slug": "dream-site"' "${TESTDIR}/.lifna/environment.json"
  grep -q "LIFNA_TOKEN='lft_test_secret'" "${TESTDIR}/.ddev/lifna/.env"
}

@test "connect rejects command-line tokens" {
  run env DDEV_APPROOT="${TESTDIR}" DDEV_SITENAME="unit" \
    "${DIR}/commands/host/lifna" connect \
    --site=dream-site \
    --environment=main \
    --base-url=https://app.lifna.com \
    --token=lft_leaky

  [ "$status" -eq 64 ]
  [[ "$output" == *"Do not pass Lifna tokens"* ]]
  [ ! -f "${TESTDIR}/.ddev/lifna/.env" ]
}

@test "connect rejects untrusted production base URLs" {
  run env DDEV_APPROOT="${TESTDIR}" DDEV_SITENAME="unit" LIFNA_TOKEN="lft_test_secret" \
    "${DIR}/commands/host/lifna" connect \
    --site=dream-site \
    --environment=main \
    --base-url=https://evil.example

  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing untrusted Lifna URL"* ]]
}

@test "connect allows localhost only when dev mode is explicit" {
  run env DDEV_APPROOT="${TESTDIR}" DDEV_SITENAME="unit" LIFNA_TOKEN="lft_test_secret" \
    "${DIR}/commands/host/lifna" connect \
    --site=dream-site \
    --environment=main \
    --base-url=http://127.0.0.1:8080 \
    --dev

  [ "$status" -eq 0 ]
  grep -q '"base_url": "http://127.0.0.1:8080"' "${TESTDIR}/.lifna/environment.json"
}

@test "doctor reports token presence without printing token value" {
  run env LIFNA_SITE=dream-site LIFNA_ENVIRONMENT=main LIFNA_ENVIRONMENT_TYPE=production LIFNA_BASE_URL=https://app.lifna.com LIFNA_TOKEN=lft_super_secret \
    "${TEST_BASH}" "${DIR}/lifna/client.sh" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"Token: present"* ]]
  [[ "$output" != *"lft_super_secret"* ]]
}

@test "client refuses untrusted base URL before making a request" {
  run env LIFNA_SITE=dream-site LIFNA_ENVIRONMENT=main LIFNA_ENVIRONMENT_TYPE=production LIFNA_BASE_URL=https://evil.example LIFNA_TOKEN=lft_test_secret \
    "${TEST_BASH}" "${DIR}/lifna/client.sh" status

  [ "$status" -eq 64 ]
  [[ "$output" == *"Refusing untrusted Lifna URL"* ]]
}

@test "protected database push requires typed confirmation before network call" {
  mkdir -p .ddev/.downloads
  printf 'fake-db' > .ddev/.downloads/db.sql.gz

  run "${TEST_BASH}" -c "printf 'nope\n' | LIFNA_SITE=dream-site LIFNA_ENVIRONMENT=main LIFNA_ENVIRONMENT_TYPE=production LIFNA_BASE_URL=https://app.lifna.com LIFNA_TOKEN=lft_test_secret '${TEST_BASH}' '${DIR}/lifna/client.sh' push-db"

  [ "$status" -eq 67 ]
  [[ "$output" == *"Push cancelled"* ]]
}

@test "pull-files rejects tar archives with traversal paths" {
  create_fake_curl
  create_tar "${TESTDIR}/malicious.tar.gz" "../evil.txt"

  run env PATH="${TESTDIR}/bin:${PATH}" FAKE_CURL_ARCHIVE="${TESTDIR}/malicious.tar.gz" \
    LIFNA_SITE=dream-site LIFNA_ENVIRONMENT=develop LIFNA_ENVIRONMENT_TYPE=development LIFNA_BASE_URL=https://app.lifna.com LIFNA_TOKEN=lft_test_secret \
    "${TEST_BASH}" "${DIR}/lifna/client.sh" pull-files

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsafe path in Lifna files archive"* ]]
  [ -z "$(find .ddev/.downloads/files -mindepth 1 -print -quit 2>/dev/null)" ]
}

@test "pull-files extracts safe tar archives" {
  create_fake_curl
  create_tar "${TESTDIR}/safe.tar.gz" "files/example.txt"

  run env PATH="${TESTDIR}/bin:${PATH}" FAKE_CURL_ARCHIVE="${TESTDIR}/safe.tar.gz" \
    LIFNA_SITE=dream-site LIFNA_ENVIRONMENT=develop LIFNA_ENVIRONMENT_TYPE=development LIFNA_BASE_URL=https://app.lifna.com LIFNA_TOKEN=lft_test_secret \
    "${TEST_BASH}" "${DIR}/lifna/client.sh" pull-files

  [ "$status" -eq 0 ]
  [ -f .ddev/.downloads/files/files/example.txt ]
}

@test "install from directory creates Lifna provider and command" {
  command -v ddev >/dev/null 2>&1 || skip "DDEV is not available"

  mkdir -p web
  ddev config --project-name="${PROJNAME}" --project-type=drupal11 --docroot=web

  run ddev add-on get "${DIR}"

  [ "$status" -eq 0 ]
  [ -f .ddev/providers/lifna.yaml ]
  [ -f .ddev/commands/host/lifna ]
  [ -x .ddev/commands/host/lifna ]
  [ -f .ddev/lifna/client.sh ]
  [ -x .ddev/lifna/client.sh ]
  grep -q '#ddev-generated' .ddev/providers/lifna.yaml
  grep -q 'ddev lifna connect' .ddev/commands/host/lifna
}
