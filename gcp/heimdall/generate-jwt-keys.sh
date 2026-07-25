#!/usr/bin/env bash
#
# Generate the RSA keypair heimdall signs JWTs with (RS256). heimdall gets the private key
# to sign; scorecard gets the public key to verify. Run this ONCE for the deployment — the
# keys become Secret Manager secrets in bootstrap-secrets.sh.
#
# Keys land in ./keys, which is git-ignored. Do not commit them; do not regenerate once
# tokens/sessions are live (it would invalidate every issued token).
#
#   ./generate-jwt-keys.sh
#
set -euo pipefail

OUT="${KEYS_DIR:-./keys}"
mkdir -p "$OUT"

if [[ -f "$OUT/jwt-private.pem" ]]; then
  echo "Refusing to overwrite existing $OUT/jwt-private.pem — remove it first to rotate." >&2
  exit 1
fi

openssl genrsa -out "$OUT/jwt-private.pem" 2048
openssl rsa -in "$OUT/jwt-private.pem" -pubout -out "$OUT/jwt-public.pem"

echo "Wrote $OUT/jwt-private.pem and $OUT/jwt-public.pem"
echo "Next: ./bootstrap-secrets.sh loads these into Secret Manager."
