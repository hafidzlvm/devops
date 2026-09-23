#!/usr/bin/env bash

KEY_NAME="user"

if [ -z "$KEY_NAME" ]; then
    echo "Penggunaan: ./switch-key.sh <nama_file_key>"
    echo "Contoh: ./switch-key.sh hafidzlvm"
    exit 1
fi

cat << EOF > ~/.ssh/config
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/$KEY_NAME
    IdentitiesOnly yes
EOF

chmod 600 ~/.ssh/config
echo "SSH config berhasil diubah menggunakan key: ~/.ssh/$KEY_NAME"