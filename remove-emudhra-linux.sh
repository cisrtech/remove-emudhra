#!/usr/bin/env bash
###############################################################################
# distrust-emudhra.sh
#
# Identifies and removes eMudhra / emSign certificates from:
#   - the Debian system trust store (/etc/ssl/certs)
#   - NSS application databases (Firefox, Thunderbird, Chromium/Chrome)
#   - every Java "cacerts" keystore on disk
#   - the Python "certifi" bundle (if present)
#
# It also writes blacklist entries into /etc/ca-certificates.conf so the
# certificates stay removed across future ca-certificates package upgrades.
#
# Target: Debian 13 (trixie). Fully offline - no network access required.
# Optional packages: libnss3-tools (certutil), a JRE (keytool).
# Run as root.
###############################################################################

set -euo pipefail

PATTERN='eMudhra|emSign'
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/emudhra-removal-${STAMP}"
CONF="/etc/ca-certificates.conf"

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root." >&2; exit 1; }

mkdir -p "$BACKUP"
log() { echo "[*] $*" | tee -a "$BACKUP/actions.log"; }

#######################################
# Phase 1 - backup
#######################################
log "Backing up trust configuration to $BACKUP"
cp -a "$CONF" "$BACKUP/ca-certificates.conf.bak" 2>/dev/null || true
tar -czf "$BACKUP/etc-ssl-certs.tar.gz" -C / etc/ssl/certs 2>/dev/null || true

#######################################
# Phase 2 - system trust store (OpenSSL)
#######################################
log "Scanning system CA sources for eMudhra/emSign..."
found=0
shopt -s nullglob

for f in /usr/share/ca-certificates/mozilla/*.crt; do
    if openssl x509 -in "$f" -noout -subject -issuer 2>/dev/null | grep -qiE "$PATTERN"; then
        found=1
        rel="${f#/usr/share/ca-certificates/}"
        log "  MATCH: $rel  ($(openssl x509 -in "$f" -noout -subject))"
        cp -a "$f" "$BACKUP/"                      # keep a copy for reference
        sed -i "s|^${rel}$|!${rel}|" "$CONF"       # turn enable-entry into blacklist-entry
        grep -qxF "!${rel}" "$CONF" || echo "!${rel}" >> "$CONF"
    fi
done

# Locally installed roots are always enabled -> remove the file itself
for f in /usr/local/share/ca-certificates/*.crt; do
    if openssl x509 -in "$f" -noout -subject -issuer 2>/dev/null | grep -qiE "$PATTERN"; then
        found=1
        log "  MATCH (local override): $f -> moved to backup"
        mv "$f" "$BACKUP/"
    fi
done
[[ $found -eq 0 ]] && log "  no matches in system bundle."

log "Rebuilding system trust store (this also triggers the jks-keystore hook)..."
update-ca-certificates --fresh >/dev/null

#######################################
# Phase 3 - NSS databases (Firefox / Thunderbird / Chromium)
#######################################
if command -v certutil >/dev/null 2>&1; then
    log "Scanning NSS databases..."
    while IFS= read -r db; do
        dir="$(dirname "$db")"
        fmt=sql; [[ $db == *cert8.db ]] && fmt=dbm
        # certutil -L output: "nickname    <spaces>    trustflags" - strip the flags column
        certutil -L -d "${fmt}:${dir}" 2>/dev/null \
          | grep -iE "$PATTERN" \
          | sed -E 's/[[:space:]]+[A-Za-z,]+[[:space:]]*$//' \
          | while IFS= read -r nick; do
                log "  removing NSS entry '${nick}' from ${dir}"
                certutil -D -d "${fmt}:${dir}" -n "$nick" >>"$BACKUP/actions.log" 2>&1 || true
            done
    done < <(find /home /root -maxdepth 6 \( -name cert9.db -o -name cert8.db \) 2>/dev/null)
else
    log "certutil not found - install libnss3-tools to clean NSS databases."
fi

#######################################
# Phase 4 - Java keystores
#######################################
if command -v keytool >/dev/null 2>&1; then
    log "Scanning Java keystores..."
    while IFS= read -r ks; do
        keytool -list -keystore "$ks" -storepass changeit 2>/dev/null \
          | grep -iE "$PATTERN" | cut -d, -f1 \
          | while IFS= read -r alias; do
                log "  deleting alias '${alias}' from ${ks}"
                keytool -delete -noprompt -keystore "$ks" -storepass changeit \
                        -alias "$alias" >>"$BACKUP/actions.log" 2>&1 || true
            done
    done < <(find / -xdev -type f -name cacerts 2>/dev/null)
else
    log "keytool not found - skipping Java keystores."
fi

#######################################
# Phase 5 - Python certifi bundle
#######################################
CERTIFI="$(python3 -c 'import certifi; print(certifi.where())' 2>/dev/null || true)"
if [[ -n "${CERTIFI:-}" && -f $CERTIFI ]]; then
    log "Filtering eMudhra blocks out of certifi bundle: $CERTIFI"
    cp -a "$CERTIFI" "$BACKUP/certifi-cacert.pem.bak"
    tmpdir="$(mktemp -d)"
    awk -v d="$tmpdir" 'BEGIN{n=0} /-----BEGIN CERTIFICATE-----/{n++} {print > (d "/block-" n ".pem")}' "$CERTIFI"
    : > "$CERTIFI.new"
    for b in "$tmpdir"/block-*.pem; do
        if grep -q "BEGIN CERTIFICATE" "$b" \
           && openssl x509 -in "$b" -noout -subject -issuer 2>/dev/null | grep -qiE "$PATTERN"; then
            log "  dropped certifi entry: $(openssl x509 -in "$b" -noout -subject)"
            continue
        fi
        cat "$b" >> "$CERTIFI.new"
    done
    cat "$CERTIFI.new" > "$CERTIFI" && rm -f "$CERTIFI.new"
    rm -rf "$tmpdir"
fi

#######################################
# Phase 6 - verification
#######################################

log "Verifying rebuilt system bundle..."
if openssl crl2pkcs7 -nocrl -certfile /etc/ssl/certs/ca-certificates.crt 2>/dev/null \
     | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -qiE "$PATTERN"; then
    log "  WARNING: eMudhra/emSign still present in the system bundle."
    exit 1
fi
log "  system bundle is clean."
log "Done. Backup and full log: $BACKUP"

cat <<'EOF'

Next steps:
  - Restart browsers and long-running services so they reload the trust store.
  - Point Python tooling at the system store where possible:
        SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
        REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
  - Node.js ships its own bundled roots. On Node 22+ launch with:
        NODE_OPTIONS=--use-system-ca
  - Go binaries built before Go 1.26.10 / 1.27.3 carry an unpatched
    crypto/x509 - rebuild them with a fixed toolchain.
  - Containers: rebuild images from an updated base and redeploy; scripts
    like this one cannot reach inside images.
EOF
