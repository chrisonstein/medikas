#!/usr/bin/env bash
# Eenmalig: maakt een lokaal, zelfondertekend certificaat "MediKas Local Signing" in je login-sleutelhanger.
# build.sh ondertekent daarmee, zodat elke versie dezelfde identiteit heeft (updates blijven vertrouwd).
#
# Weer verwijderen met: security delete-identity -c "MediKas Local Signing" ~/Library/Keychains/login.keychain-db
set -euo pipefail

NAME="MediKas Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
  echo "\"$NAME\" bestaat al — niets te doen."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/id.p12" -passout "pass:$PASS" >/dev/null 2>&1

# -T lets codesign use the private key without prompting on every build.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "\"$NAME\" aangemaakt. Bouw opnieuw met ./build.sh."
