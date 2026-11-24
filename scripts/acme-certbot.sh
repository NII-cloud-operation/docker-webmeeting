#!/bin/sh
set -eu

ACME_ROOT=${ACME_ROOT:-/var/lib/acme}
ACME_WEBROOT=${ACME_WEBROOT:-/var/www/acme}
ACME_STATE_NAME=${ACME_STATE_NAME:-letsencrypt-production}
ACME_DIRECTORY=${ACME_DIRECTORY:-https://acme-v02.api.letsencrypt.org/directory}
ACME_EMAIL=${ACME_EMAIL:-}
ACME_KEY_TYPE=${ACME_KEY_TYPE:-rsa}
ACME_EAB_REQUIRED=${ACME_EAB_REQUIRED:-false}
ACME_EAB_DIR=${ACME_EAB_DIR:-/run/secrets/acme-eab}
ACME_NGINX_GID=${ACME_NGINX_GID:-101}
ACME_RENEW_INTERVAL=${ACME_RENEW_INTERVAL:-12h}

log() {
    printf '%s\n' "acme-certbot: $*"
}

fail() {
    log "ERROR: $*" >&2
    exit 1
}

domain_for_role() {
    case "$1" in
        app) printf '%s\n' "${APP_FQDN:?Set APP_FQDN}" ;;
        admin) printf '%s.%s\n' "${ADMIN_SUBDOMAIN:?Set ADMIN_SUBDOMAIN}" "${APP_FQDN:?Set APP_FQDN}" ;;
        sample) printf '%s.%s\n' "${SAMPLE_TENANT_SUBDOMAIN:?Set SAMPLE_TENANT_SUBDOMAIN}" "${APP_FQDN:?Set APP_FQDN}" ;;
        sfu) printf '%s\n' "${SFU_FQDN:?Set SFU_FQDN}" ;;
        turn) printf '%s\n' "${TURN_FQDN:?Set TURN_FQDN}" ;;
        *) fail "unknown certificate role: $1" ;;
    esac
}

key_type_for_role() {
    case "$1" in
        app) printf '%s\n' "${ACME_KEY_TYPE_APP:-$ACME_KEY_TYPE}" ;;
        admin) printf '%s\n' "${ACME_KEY_TYPE_ADMIN:-$ACME_KEY_TYPE}" ;;
        sample) printf '%s\n' "${ACME_KEY_TYPE_SAMPLE:-$ACME_KEY_TYPE}" ;;
        sfu) printf '%s\n' "${ACME_KEY_TYPE_SFU:-$ACME_KEY_TYPE}" ;;
        turn) printf '%s\n' "${ACME_KEY_TYPE_TURN:-$ACME_KEY_TYPE}" ;;
        *) fail "unknown certificate role: $1" ;;
    esac
}

role_root() {
    printf '%s/%s/%s\n' "$ACME_ROOT" "$ACME_STATE_NAME" "$1"
}

has_account() {
    config_dir=$(role_root "$1")/config
    [ -d "$config_dir/accounts" ] &&
        find "$config_dir/accounts" -type f -name regr.json -print -quit | grep -q .
}

read_credential() {
    role=$1
    kind=$2
    case "$role:$kind" in
        app:kid) credential_name=${ACME_EAB_APP_KID_FILE:?Set ACME_EAB_APP_KID_FILE} ;;
        app:hmac) credential_name=${ACME_EAB_APP_HMAC_KEY_FILE:?Set ACME_EAB_APP_HMAC_KEY_FILE} ;;
        admin:kid) credential_name=${ACME_EAB_ADMIN_KID_FILE:?Set ACME_EAB_ADMIN_KID_FILE} ;;
        admin:hmac) credential_name=${ACME_EAB_ADMIN_HMAC_KEY_FILE:?Set ACME_EAB_ADMIN_HMAC_KEY_FILE} ;;
        sample:kid) credential_name=${ACME_EAB_SAMPLE_KID_FILE:?Set ACME_EAB_SAMPLE_KID_FILE} ;;
        sample:hmac) credential_name=${ACME_EAB_SAMPLE_HMAC_KEY_FILE:?Set ACME_EAB_SAMPLE_HMAC_KEY_FILE} ;;
        sfu:kid) credential_name=${ACME_EAB_SFU_KID_FILE:?Set ACME_EAB_SFU_KID_FILE} ;;
        sfu:hmac) credential_name=${ACME_EAB_SFU_HMAC_KEY_FILE:?Set ACME_EAB_SFU_HMAC_KEY_FILE} ;;
        turn:kid) credential_name=${ACME_EAB_TURN_KID_FILE:?Set ACME_EAB_TURN_KID_FILE} ;;
        turn:hmac) credential_name=${ACME_EAB_TURN_HMAC_KEY_FILE:?Set ACME_EAB_TURN_HMAC_KEY_FILE} ;;
        *) fail "unknown EAB credential: role=$role kind=$kind" ;;
    esac
    case "$credential_name" in
        */* | . | ..) fail "EAB credential must be a file name: $credential_name" ;;
    esac
    credential_file=$ACME_EAB_DIR/$credential_name
    [ -r "$credential_file" ] || fail "missing EAB credential file: $credential_file"
    credential=$(tr -d '\r\n' < "$credential_file")
    [ -n "$credential" ] || fail "empty EAB credential file: $credential_file"
    printf '%s' "$credential"
}

register_account() {
    role=$1
    root=$(role_root "$role")

    if has_account "$role"; then
        return
    fi

    log "registering isolated ACME account for role=$role"
    set -- register --non-interactive \
        --config-dir "$root/config" \
        --work-dir "$root/work" \
        --logs-dir "$root/logs" \
        --server "$ACME_DIRECTORY" \
        --email "$ACME_EMAIL" \
        --agree-tos \
        --no-eff-email

    if [ "$ACME_EAB_REQUIRED" = true ]; then
        eab_kid=$(read_credential "$role" kid)
        eab_hmac=$(read_credential "$role" hmac)
        set -- "$@" --eab-kid "$eab_kid" --eab-hmac-key "$eab_hmac"
    fi
    certbot "$@"
}

issue_certificate() {
    role=$1
    domain=$(domain_for_role "$role")
    key_type=$(key_type_for_role "$role")
    root=$(role_root "$role")

    if [ -s "$root/config/live/$role/fullchain.pem" ] && [ -s "$root/config/live/$role/privkey.pem" ]; then
        return
    fi

    log "issuing certificate role=$role domain=$domain"
    certbot certonly --non-interactive \
        --config-dir "$root/config" \
        --work-dir "$root/work" \
        --logs-dir "$root/logs" \
        --server "$ACME_DIRECTORY" \
        --webroot \
        --webroot-path "$ACME_WEBROOT" \
        --cert-name "$role" \
        --key-type "$key_type" \
        -d "$domain"
}

deploy_certificate() {
    role=$1
    root=$(role_root "$role")
    source_dir=$root/config/live/$role
    deploy_dir=$ACME_ROOT/$ACME_STATE_NAME/certificates/$role

    [ -s "$source_dir/fullchain.pem" ] || fail "missing issued certificate for role=$role"
    [ -s "$source_dir/privkey.pem" ] || fail "missing issued private key for role=$role"

    mkdir -p \
        "$ACME_ROOT/$ACME_STATE_NAME" \
        "$ACME_ROOT/$ACME_STATE_NAME/certificates" \
        "$deploy_dir"
    chown root:"$ACME_NGINX_GID" \
        "$ACME_ROOT/$ACME_STATE_NAME" \
        "$ACME_ROOT/$ACME_STATE_NAME/certificates" \
        "$deploy_dir"
    chmod 0750 \
        "$ACME_ROOT/$ACME_STATE_NAME" \
        "$ACME_ROOT/$ACME_STATE_NAME/certificates" \
        "$deploy_dir"

    umask 027
    cp -L "$source_dir/fullchain.pem" "$deploy_dir/.fullchain.pem.new"
    cp -L "$source_dir/privkey.pem" "$deploy_dir/.privkey.pem.new"
    chown root:"$ACME_NGINX_GID" "$deploy_dir/.fullchain.pem.new" "$deploy_dir/.privkey.pem.new"
    chmod 0644 "$deploy_dir/.fullchain.pem.new"
    chmod 0640 "$deploy_dir/.privkey.pem.new"
    mv -f "$deploy_dir/.fullchain.pem.new" "$deploy_dir/fullchain.pem"
    mv -f "$deploy_dir/.privkey.pem.new" "$deploy_dir/privkey.pem"
}

initialize_all() {
    [ -n "$ACME_EMAIL" ] || fail "set ACME_EMAIL"
    [ -n "${ACME_CERTIFICATE_ROLES:-}" ] || fail "set ACME_CERTIFICATE_ROLES"
    mkdir -p "$ACME_WEBROOT"

    for role in $ACME_CERTIFICATE_ROLES; do
        root=$(role_root "$role")
        mkdir -p "$root/config" "$root/work" "$root/logs"
        chmod 0700 "$root/config" "$root/work" "$root/logs"
        register_account "$role"
        issue_certificate "$role"
        deploy_certificate "$role"
    done
}

renew_all() {
    status=0
    for role in $ACME_CERTIFICATE_ROLES; do
        root=$(role_root "$role")
        log "checking renewal role=$role domain=$(domain_for_role "$role")"
        if certbot renew --non-interactive \
            --config-dir "$root/config" \
            --work-dir "$root/work" \
            --logs-dir "$root/logs"; then
            deploy_certificate "$role"
        else
            log "ERROR: renewal failed for role=$role" >&2
            status=1
        fi
    done
    return "$status"
}

renew_loop() {
    trap 'exit 0' TERM INT
    while :; do
        if ! renew_all; then
            log "renewal check failed; retrying after $ACME_RENEW_INTERVAL" >&2
        fi
        sleep "$ACME_RENEW_INTERVAL" &
        wait "$!"
    done
}

case "${1:-}" in
    init) initialize_all ;;
    renew-once) renew_all ;;
    renew-loop) renew_loop ;;
    *) fail "usage: $0 {init|renew-once|renew-loop}" ;;
esac
