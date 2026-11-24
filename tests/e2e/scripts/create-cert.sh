#!/usr/bin/env bash
# Creates a certificate authority for the tests, and a certificate signed by it for the names in tests/e2e/e2e.env.
set -euxo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/cert"
APP_FQDN="${APP_FQDN:-mtg.test}"

mkdir -p "${CERT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "${CERT_DIR}/ca.key" -out "${CERT_DIR}/ca.crt" \
  -subj "/CN=WebMeeting E2E CA"
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.csr" \
  -subj "/CN=${APP_FQDN}"
openssl x509 -req -days 1 -in "${CERT_DIR}/server.csr" \
  -CA "${CERT_DIR}/ca.crt" -CAkey "${CERT_DIR}/ca.key" -CAcreateserial \
  -out "${CERT_DIR}/server.crt" \
  -extfile <(printf "subjectAltName=DNS:%s,DNS:*.%s\nextendedKeyUsage=serverAuth\n" "${APP_FQDN}" "${APP_FQDN}")
