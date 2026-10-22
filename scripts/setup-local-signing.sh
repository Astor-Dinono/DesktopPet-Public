#!/bin/bash
set -euo pipefail
umask 077
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$PROJECT_DIR/.local-signing"
MODE="${1:---prepare}"
if [[ "$MODE" != --prepare && "$MODE" != --install ]]; then
    echo 'Usage: bash scripts/setup-local-signing.sh [--prepare|--install]' >&2
    exit 2
fi
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
CERT="$SIGNING_DIR/certificate.pem"
if [[ ! -f "$CERT" ]]; then
    if [[ -e "$SIGNING_DIR/identity.p12" || -e "$SIGNING_DIR/password" ]]; then
        echo 'Incomplete signing identity; refusing to replace existing key material.' >&2
        exit 1
    fi
    TEMP_DIR="$(mktemp -d "$SIGNING_DIR/.prepare.XXXXXX")"
    trap 'rm -rf "$TEMP_DIR"' EXIT
    /usr/bin/openssl rand -base64 48 > "$TEMP_DIR/password"
    cat > "$TEMP_DIR/certificate.conf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions
[subject]
CN = DesktopPet Local Development
O = DesktopPet Local Only
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
    /usr/bin/openssl req -new -x509 -newkey rsa:3072 -sha256 -days 3650 \
        -config "$TEMP_DIR/certificate.conf" -keyout "$TEMP_DIR/key.pem" \
        -out "$TEMP_DIR/certificate.pem" -passout "file:$TEMP_DIR/password" 2> "$TEMP_DIR/generation.log"
    cp "$TEMP_DIR/password" "$TEMP_DIR/export-password"
    /usr/bin/openssl pkcs12 -export -name 'DesktopPet Local Development' \
        -inkey "$TEMP_DIR/key.pem" -in "$TEMP_DIR/certificate.pem" \
        -out "$TEMP_DIR/identity.p12" -passin "file:$TEMP_DIR/password" -passout "file:$TEMP_DIR/export-password"
    mv "$TEMP_DIR/certificate.pem" "$CERT"
    mv "$TEMP_DIR/identity.p12" "$SIGNING_DIR/identity.p12"
    mv "$TEMP_DIR/password" "$SIGNING_DIR/password"
fi
/usr/bin/openssl x509 -in "$CERT" -noout -checkend 0 > /dev/null
IDENTITY="$(/usr/bin/openssl x509 -in "$CERT" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
[[ "$IDENTITY" =~ ^[A-Fa-f0-9]{40}$ ]]
printf '%s\n' "$IDENTITY" > "$SIGNING_DIR/identity.sha1"
chmod 600 "$CERT" "$SIGNING_DIR/identity.p12" "$SIGNING_DIR/password" "$SIGNING_DIR/identity.sha1"
if [[ "$MODE" == --prepare ]]; then
    echo 'Prepared locally; no keychain import or trust changes made.'
    /usr/bin/openssl x509 -in "$CERT" -noout -subject -dates -fingerprint -sha256
    exit 0
fi
# Run only after the user approves adding this local signing credential.
# Restrict private-key access to codesign; never use security import -A.
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" | /usr/bin/grep -Fq "$IDENTITY"; then
    echo 'Local signing identity is already installed and valid.'
    exit 0
fi
if ! /usr/bin/security find-identity -p codesigning "$KEYCHAIN" | /usr/bin/grep -Fq "$IDENTITY"; then
    /usr/bin/security import "$SIGNING_DIR/identity.p12" -k "$KEYCHAIN" \
        -P "$(cat "$SIGNING_DIR/password")" -T /usr/bin/codesign
fi
# User domain, code-signing policy only. No system or SSL trust changes.
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT"
if ! /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" | /usr/bin/grep -Fq "$IDENTITY"; then
    echo 'Local identity is not usable yet. Existing app has not been replaced.' >&2
    exit 1
fi
echo 'Local signing identity installed. Build with bash scripts/build-app.sh.'
