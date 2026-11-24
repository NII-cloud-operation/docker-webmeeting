#!/usr/bin/env bash
set -euxo pipefail

LOGIN_URL="${LOGIN_URL:-https://admin.mtg.test/login}"
PROXY_ADDRESS="${PROXY_ADDRESS:-127.0.0.1}"
MAX_RETRIES=60
SLEEP_SECONDS=5

host="${LOGIN_URL#https://}"
host="${host%%/*}"

for attempt in $(seq 1 "${MAX_RETRIES}"); do
  if curl --silent --show-error --fail --insecure --resolve "${host}:443:${PROXY_ADDRESS}" "${LOGIN_URL}" -o /dev/null; then
    echo "WebMeeting is accepting connections at ${LOGIN_URL}"
    exit 0
  fi
  echo "Waiting for WebMeeting... attempt ${attempt}/${MAX_RETRIES}" >&2
  sleep "${SLEEP_SECONDS}"
done

docker compose ps >&2 || true
>&2 echo "Timed out waiting for WebMeeting at ${LOGIN_URL}"
exit 1
