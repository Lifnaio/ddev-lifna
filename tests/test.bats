#!/usr/bin/env bats

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  export TESTDIR="${BATS_TMPDIR}/ddev-lifna-test"
  rm -rf "${TESTDIR}"
  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
}

teardown() {
  set +e
  cd "${TESTDIR}" 2>/dev/null || return 0
  ddev delete -Oy >/dev/null 2>&1
  rm -rf "${TESTDIR}"
}

@test "install from directory creates Lifna provider and command" {
  set -eu -o pipefail
  cd "${TESTDIR}"
  ddev config --project-type=drupal11 --docroot=web --create-docroot

  run ddev add-on get "${DIR}"
  [ "$status" -eq 0 ]

  [ -f .ddev/providers/lifna.yaml ]
  [ -f .ddev/commands/host/lifna ]
  [ -f .ddev/lifna/client.sh ]
  grep -q '#ddev-generated' .ddev/providers/lifna.yaml
  grep -q 'ddev lifna connect' .ddev/commands/host/lifna
}
