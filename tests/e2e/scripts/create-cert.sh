#!/usr/bin/env bash
# Creates a self-signed certificate for the names in tests/e2e/e2e.env.
set -euxo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/cert"
APP_FQDN="${APP_FQDN:-mtg.test}"

mkdir -p "${CERT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.crt" \
  -subj "/CN=${APP_FQDN}" \
  -addext "subjectAltName=DNS:${APP_FQDN},DNS:*.${APP_FQDN}"
