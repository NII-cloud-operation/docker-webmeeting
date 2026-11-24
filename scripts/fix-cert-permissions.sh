#!/bin/sh
set -x

# Fix Let's Encrypt certificate permissions for nginx access
find /etc/letsencrypt/live -type d -exec chmod 755 {} \;
find /etc/letsencrypt/archive -type d -exec chmod 755 {} \;
find /etc/letsencrypt/live -name "*.pem" -exec chmod 644 {} \;
find /etc/letsencrypt/archive -name "*.pem" -exec chmod 644 {} \;

# Change ownership to allow nginx (www-data) to read certificates
chown -R root:root /etc/letsencrypt
chmod -R g+r /etc/letsencrypt