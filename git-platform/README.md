# git-platform — SSH GitHub multi-identitas di satu akun server

Satu akun Linux dipakai bareng (satu gate), tiap orang punya akun GitHub
sendiri. Solusinya: **satu key + satu Host alias per orang**
(`github-<nama>`), bukan satu entry `github.com` bareng (itu menimpa —
siapa execute terakhir, key dia yang menang).

## Daftarkan orang baru (di server)

```bash
cd ~/stacks/devops/git-platform
chmod +x scripts/add-user.sh
./scripts/add-user.sh <nama>   # contoh: ./scripts/add-user.sh hafidz
```

Script: generate `~/.ssh/id_ed25519_<nama>` (skip bila sudah ada — key lama
tidak pernah ditimpa) + tambah blok `Host github-<nama>` (idempoten, aman
dijalankan ulang). Lalu:

1. Tempel public key yang dicetak ke GitHub orang itu
   (Settings > SSH and GPG keys).
2. Test: `ssh -T git@github-<nama>` → harap `Hi <nama>! ...`.
3. Clone SELALU pakai alias: `git clone git@github-<nama>:org/repo.git`.
   URL `git@github.com:...` (tanpa alias) = identitas salah/tidak jelas.

## Cabut akses orang

```bash
# 1. Hapus blok Host github-<nama> dari ~/.ssh/config
# 2. Hapus key-nya: rm ~/.ssh/id_ed25519_<nama>*
# 3. Hapus key di GitHub orang itu (Settings > SSH keys)
```

## Aturan keras

- **Private key tidak pernah masuk git.** Key hanya lahir di server via
  script. Yang boleh di-commit: script + README ini saja.
- Satu orang = satu key = satu alias. Jangan share key antar orang
  (kalau bocor, tidak ketahuan milik siapa).
- `IdentitiesOnly yes` wajib (sudah di script) — tanpa itu ssh menawarkan
  semua key berurutan dan GitHub mengautentikasi key pertama yang cocok,
  identitas bisa nyasar ke orang lain.
