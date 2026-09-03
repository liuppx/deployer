#!/usr/bin/env bash
set -Eeuo pipefail
NODE_URL="${PASSPORT_NODE_URL:-http://localhost:8100}"; OUT_DIR="${PASSPORT_IDENTITY_TRUST_DIR:-/data/node}"

init_log_file() {
    local logfile_name=$1
    local logfile_dir="/opt/logs"

    LOGFILE="${logfile_dir}/${logfile_name}"
    mkdir -p "$logfile_dir"
    touch "$LOGFILE"

    local filesize=0
    filesize=$(stat -c "%s" "$LOGFILE" 2>/dev/null || echo 0)
    if [[ "$filesize" -ge 1048576 ]]; then
        printf 'clear old logs at %s to avoid log file too big\n' "$(date)" > "$LOGFILE"
    fi
}

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log_err() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >&2
}

die(){ log_err "ERROR: $*"; exit 1; }

init_log_file "sync-identity-trust.log"
command -v curl >/dev/null || die curl-required; command -v jq >/dev/null || die jq-required
[[ "$NODE_URL" == https://* || "$NODE_URL" == http://localhost:* || "$NODE_URL" == http://127.0.0.1:* ]] || die "PASSPORT_NODE_URL must use HTTPS, except for localhost"; NODE_URL="${NODE_URL%/}"; scheme="${NODE_URL%%:*}"; host="${NODE_URL#*://}"; host="${host%%/*}"; origin="${scheme}://${host}"
mkdir -p "$(dirname "$OUT_DIR")"; lock="${OUT_DIR}.lock"; mkdir "$lock" 2>/dev/null || { log 'another sync is running'; exit 0; }; tmp="$(mktemp -d "${OUT_DIR}.tmp.XXXXXX")"; trap 'rm -rf "$tmp"; rmdir "$lock" 2>/dev/null || true' EXIT; mkdir -p "$OUT_DIR"
curl --fail --silent --show-error --location --connect-timeout 10 --max-time 30 "$NODE_URL/.well-known/openid-credential-issuer" -o "$tmp/issuer-metadata.json" || die metadata-download
jq -e . "$tmp/issuer-metadata.json" >/dev/null || die metadata-json
jwks_uri="$(jq -r '.jwks_uri // empty' "$tmp/issuer-metadata.json")"; issuer="$(jq -r '.issuer // empty' "$tmp/issuer-metadata.json")"; [[ "$jwks_uri" == "$origin/"* ]] || die jwks-uri-origin; [[ "$issuer" == "did:web:${host}" ]] || die issuer-mismatch
curl --fail --silent --show-error --location --connect-timeout 10 --max-time 30 "$jwks_uri" -o "$tmp/jwks.json" || die jwks-download
jq -e '.keys | type == "array" and length > 0 and all(.[]; .kty == "OKP" and .crv == "Ed25519" and .alg == "EdDSA" and (.kid|type=="string" and length>0) and (.x|type=="string" and length>0))' "$tmp/jwks.json" >/dev/null || die jwks-invalid
sha(){ if command -v sha256sum >/dev/null; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }; ms="$(sha "$tmp/issuer-metadata.json")"; js="$(sha "$tmp/jwks.json")"; now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
jq -n --arg n "$NODE_URL" --arg i "$issuer" --arg t "$now" --arg m "$ms" --arg j "$js" '{version:1,nodeUrl:$n,issuer:$i,fetchedAt:$t,metadataSha256:$m,jwksSha256:$j}' > "$tmp/manifest.json"; chmod 644 "$tmp"/*.json
mv "$tmp/issuer-metadata.json" "$OUT_DIR/issuer-metadata.json"; mv "$tmp/jwks.json" "$OUT_DIR/jwks.json"; mv "$tmp/manifest.json" "$OUT_DIR/manifest.json"; log "identity trust bundle synchronized to $OUT_DIR"
