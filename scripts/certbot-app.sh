#!/bin/sh
set -x

trap exit TERM

while :; do
    certbot certonly --webroot --webroot-path=/var/www/certbot \
        --email "${CERTBOT_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        -d "${APP_FQDN},${ADMIN_SUBDOMAIN}.${APP_FQDN},${SAMPLE_TENANT}.${APP_FQDN}"

    # Fix certificate permissions for nginx access
    sh /scripts/fix-cert-permissions.sh

    sleep 12h & wait ${!}
done