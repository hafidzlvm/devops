#!/usr/bin/env bash
# add-user.sh — daftarkan satu identitas GitHub di server.
#
#   ./add-user.sh <nama>   # contoh: ./add-user.sh hafidz
#
# Yang dilakukan: generate key ed25519 ~/.ssh/id_ed25519_<nama> (skip bila
# sudah ada) + tulis blok `Host github-<nama>` di ~/.ssh/config (idempoten).
# Sesudahnya tempel public key yang dicetak ke GitHub > Settings > SSH keys,
# lalu clone pakai alias: git clone git@github-<nama>:org/repo.git
#
# ATURAN KERAS: private key tidak pernah masuk git. Key hanya lahir di server.
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" || ! "$NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Penggunaan: $0 <nama>   (huruf kecil, angka, - _)" >&2
    exit 1
fi

KEY_FILE="$HOME/.ssh/id_ed25519_$NAME"
ALIAS="github-$NAME"
CONFIG="$HOME/.ssh/config"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY_FILE" ]]; then
    echo "Key sudah ada, pakai yang lama: $KEY_FILE"
else
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "$NAME@$(hostname)"
    chmod 600 "$KEY_FILE"
fi

touch "$CONFIG"
chmod 600 "$CONFIG"
if ! grep -q "^Host $ALIAS$" "$CONFIG"; then
    cat >> "$CONFIG" <<EOF

Host $ALIAS
    HostName github.com
    User git
    IdentityFile $KEY_FILE
    IdentitiesOnly yes
EOF
    echo "Blok Host $ALIAS ditambahkan ke ~/.ssh/config"
else
    echo "Blok Host $ALIAS sudah ada, tidak diubah"
fi

echo ""
echo "=== Tempel public key ini ke GitHub ($NAME > Settings > SSH and GPG keys) ==="
cat "$KEY_FILE.pub"
echo "=== Test: ssh -T git@$ALIAS  (harap: Hi $NAME! ...) ==="
echo "=== Clone: git clone git@$ALIAS:org/repo.git ==="
