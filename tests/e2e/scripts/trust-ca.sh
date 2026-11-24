#!/usr/bin/env bash
# Adds the certificate authority of create-cert.sh to the NSS database of the user, which Chromium trusts.
set -euxo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/cert"
NSSDB="${HOME}/.pki/nssdb"

if [ ! -f "${NSSDB}/cert9.db" ]; then
  mkdir -p "${NSSDB}"
  certutil -d "sql:${NSSDB}" -N --empty-password
fi
certutil -d "sql:${NSSDB}" -A -t "C,," -n webmeeting-e2e-ca -i "${CERT_DIR}/ca.crt"
