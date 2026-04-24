#!/usr/bin/env bash
# One-time setup: create a self-signed codesigning identity "ZaDarkHelperDev"
# and trust it for code signing. Once Xcode uses this identity, TCC grants
# (App Management, etc.) persist across rebuilds — because TCC keys grants on
# the signing identity, not the rapidly-changing ad-hoc cdhash.
set -euo pipefail

IDENTITY="ZaDarkHelperDev"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "✓ Identity '$IDENTITY' already exists and is trusted."
  echo "  Verify: security find-identity -v -p codesigning"
  exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# --- 1. Generate key + self-signed cert with Code Signing EKU (required for codesign)
cat > "$TMP/config" <<'EOF'
[req]
default_bits       = 2048
default_md         = sha256
prompt             = no
distinguished_name = dn
x509_extensions    = ext
[dn]
CN = ZaDarkHelperDev
[ext]
basicConstraints  = critical, CA:FALSE
keyUsage          = critical, digitalSignature
extendedKeyUsage  = codeSigning
EOF

echo "==> Generating key + self-signed cert (10y validity)"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/config" >/dev/null 2>&1

# OpenSSL 3.x defaults export to AES-256-CBC which macOS `security` can't
# read. Use `-legacy` to fall back to the RC2/3DES format Keychain expects.
# Also use a non-empty password — some macOS versions reject empty PKCS#12.
P12_PASS="zadark-dev"

echo "==> Bundling as PKCS#12 (legacy compat)"
openssl pkcs12 -export -legacy \
  -in "$TMP/cert.pem" -inkey "$TMP/key.pem" \
  -name "$IDENTITY" \
  -out "$TMP/cert.p12" \
  -password "pass:$P12_PASS" >/dev/null 2>&1 || \
openssl pkcs12 -export \
  -in "$TMP/cert.pem" -inkey "$TMP/key.pem" \
  -name "$IDENTITY" \
  -out "$TMP/cert.p12" \
  -password "pass:$P12_PASS" >/dev/null

# --- 2. Import into login keychain; allow codesign + security tools to use it
echo "==> Importing into login keychain"
security import "$TMP/cert.p12" \
  -k "$LOGIN_KC" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

# --- 3. Trust the cert for code signing in System keychain (needs sudo)
echo "==> Trusting cert for code signing (sudo required)"
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain "$TMP/cert.pem"

# --- 4. Verify
echo ""
echo "==> Available codesigning identities now:"
security find-identity -v -p codesigning

echo ""
echo "✅ Done. Next: build the app — Xcode will auto-pick '$IDENTITY'."
echo "   If Xcode still uses '-', open project.yml and ensure:"
echo "     CODE_SIGN_STYLE: Manual"
echo "     CODE_SIGN_IDENTITY: $IDENTITY"
echo "   After rebuild, TCC grant ZaDarkHelper once — it will persist across rebuilds."
