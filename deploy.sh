#!/usr/bin/env bash
# deploy.sh
# Clean-builds all production Kafka modules (tests skipped) and copies every
# generated JAR into deploy/libs/ at the project root.
#
# Usage:
#   ./deploy.sh              # clean build + collect all JARs
#   ./deploy.sh --no-build   # skip the build, just re-collect already-built JARs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/deploy/libs"

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
SKIP_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --no-build) SKIP_BUILD=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# 2. Clean and build all production modules (no tests)
# ---------------------------------------------------------------------------
if [ "$SKIP_BUILD" = false ]; then
  echo "======================================================"
  echo " Cleaning and building Kafka (tests skipped)"
  echo "======================================================"
  cd "${SCRIPT_DIR}"

  # Clean every module first so stale JARs don't end up in deploy/
  ./gradlew clean --no-daemon

  # Build all production modules — explicit list excludes test-only, integration-
  # test, upgrade-system-test, and example modules that are not part of a broker
  # deployment. -x test skips unit tests for a fast turnaround.
  ./gradlew \
    :clients:jar \
    :server-common:jar \
    :storage:storage-api:jar \
    :storage:jar \
    :raft:jar \
    :metadata:jar \
    :coordinator-common:jar \
    :group-coordinator:group-coordinator-api:jar \
    :group-coordinator:jar \
    :transaction-coordinator:jar \
    :share-coordinator:jar \
    :server:jar \
    :core:jar \
    :tools:tools-api:jar \
    :tools:jar \
    :shell:jar \
    :trogdor:jar \
    :streams:jar \
    :streams:streams-scala:jar \
    :streams:test-utils:jar \
    :connect:api:jar \
    :connect:transforms:jar \
    :connect:json:jar \
    :connect:runtime:jar \
    :connect:file:jar \
    :connect:basic-auth-extension:jar \
    :connect:mirror:jar \
    :connect:mirror-client:jar \
    -x test \
    --no-daemon

  echo ""
  echo "Build complete."
fi

# ---------------------------------------------------------------------------
# 3. Collect JARs into deploy/libs/
#
# Rather than hardcoding every JAR path (which breaks when archive names change),
# we use `find` to discover all JARs produced under */build/libs/ and exclude:
#   - test JARs  (*-test.jar, *-tests.jar, names containing "test")
#   - sources    (*-sources.jar)
#   - javadoc    (*-javadoc.jar)
#   - upgrade-system-tests (large, not needed at runtime)
#   - integration-test JARs
#   - examples
#   - jmh-benchmarks
# ---------------------------------------------------------------------------
echo ""
echo "======================================================"
echo " Collecting JARs -> ${DEPLOY_DIR}"
echo "======================================================"

rm -rf "${DEPLOY_DIR}"
mkdir -p "${DEPLOY_DIR}"

COPIED=0

while IFS= read -r jar; do
  basename=$(basename "${jar}")
  # Skip test / sources / javadoc / excluded modules
  case "${jar}" in
    *integration-tests*|*upgrade-system-tests*|*examples*|*jmh-benchmarks*|*test-plugins*) continue ;;
  esac
  case "${basename}" in
    *-sources.jar|*-javadoc.jar|*-tests.jar|*-test.jar) continue ;;
    *test-common*|*integration-tests*) continue ;;
  esac

  cp "${jar}" "${DEPLOY_DIR}/"
  echo "  [OK]  ${jar#${SCRIPT_DIR}/}"
  COPIED=$((COPIED + 1))
done < <(find "${SCRIPT_DIR}" \
           -path "${SCRIPT_DIR}/deploy" -prune -o \
           -path "*/build/libs/*.jar" -print \
         | sort)

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================"
echo " Done. ${COPIED} JAR(s) copied to deploy/libs/"
echo "======================================================"
echo ""
echo " Contents:"
ls -1 "${DEPLOY_DIR}" | sed 's/^/   /'
