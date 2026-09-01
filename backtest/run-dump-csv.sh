#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source ./qenv.conf

: "${PROD_HOST:?must set PROD_HOST in qenv.conf}"
: "${PROD_PORT:?must set PROD_PORT in qenv.conf}"
: "${CSV_PATH:?must set CSV_PATH in qenv.conf}"
: "${START_DATE:?must set START_DATE in qenv.conf (e.g. 2026.05.01)}"
: "${END_DATE:?must set END_DATE in qenv.conf (e.g. 2026.05.20)}"

mkdir -p "$CSV_PATH"

# Optional: restrict to a subset of .bt.pulls.tables, e.g.
#   ./run-dump-csv.sh obTob,bookAsymMicroSignalBinance
TABLES="${1:-}"

q dump-csv.q \
    -prodhost "$PROD_HOST" \
    -prodport "$PROD_PORT" \
    -csv "$CSV_PATH" \
    -start "$START_DATE" \
    -end "$END_DATE" \
    ${TABLES:+-tables "$TABLES"}
