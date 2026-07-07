#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source ./qenv.conf

: "${PROD_HOST:?must set PROD_HOST in qenv.conf}"
: "${PROD_PORT:?must set PROD_PORT in qenv.conf}"
: "${HDB_PATH:?must set HDB_PATH in qenv.conf}"
: "${START_DATE:?must set START_DATE in qenv.conf (e.g. 2026.05.01)}"
: "${END_DATE:?must set END_DATE in qenv.conf (e.g. 2026.05.20)}"

mkdir -p "$HDB_PATH"

q seed.q \
    -prodhost "$PROD_HOST" \
    -prodport "$PROD_PORT" \
    -hdb "$HDB_PATH" \
    -start "$START_DATE" \
    -end "$END_DATE"
