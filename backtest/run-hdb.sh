#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source ./qenv.conf

: "${HDB_PATH:?must set HDB_PATH in qenv.conf}"
: "${KDB_PORT:?must set KDB_PORT in qenv.conf}"

q hdb.q -hdb "$HDB_PATH" -port "$KDB_PORT"
