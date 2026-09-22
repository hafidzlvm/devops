# NOTICE: NFS Server — perubahan di host ini

## Yang diubah
1. Install: `nfs-kernel-server` (ikut `nfs-common`, `rpcbind`, `keyutils`)
2. File: `/etc/exports` (isi di bawah)
3. UFW: allow `2049/tcp`, `111/tcp+udp` HANYA dari `172.16.0.0/12`
4. Service: `rpcbind` + `nfs-server` enabled & running
5. Data: `/home/devops/volumes` (`755 devops:devops`)

## /etc/exports
```
/home/devops/volumes 127.0.0.1(rw,sync,no_subtree_check) 172.16.0.0/12(rw,sync,no_subtree_check)
```

Maksud:
- `/home/devops/volumes` = direktori yang di-share.
- `127.0.0.1` = localhost (host itu sendiri) boleh mount. Untuk tes lokal.
- `172.16.0.0/12` = range Docker internal (172.16.x.x-172.31.x.x).
  Mencakup `docker0 172.17.0.1` dan bridge `172.18/19/22.0.1`.
  Container mount via gateway host (mis. `addr=172.17.0.1`), BUKAN `127.0.0.1`
  (loopback di container = container itu sendiri).
- `rw` = read-write. `sync` = tulis aman (jawab setelah masuk disk).
  `no_subtree_check` = standar modern, lebih cepat.
- Default implisit `root_squash`: `root` client -> `nobody`
  (tes tulis root = Permission denied, user `devops` = OK).
  Butuh container root bisa tulis? Tambahkan `no_root_squash` ke entry
  `172.16.0.0/12` lalu `exportfs -rav`. Risiko terkungkung di Docker nets.

## UFW (inbound ke host, BUKAN outbound)
```
2049/tcp  ALLOW  172.16.0.0/12   # nfsd (NFSv4, satu-satunya port wajib)
111/tcp   ALLOW  172.16.0.0/12   # rpcbind/portmapper
111/udp   ALLOW  172.16.0.0/12   # rpcbind/portmapper
```
- `2049` = port NFS. `111` = `rpcbind`, warisan SunRPC untuk NFSv2/v3
  (`mountd`/`statd` port dinamis) + `showmount`. NFSv4 murni tak butuh `111`.
- Scope hanya Docker nets. Public/internet tetap DENY ke 2049/111
  (tidak ada baris ALLOW Anywhere untuk port itu).
- Murni NFSv4 tanpa `showmount`? Rule `111` boleh dihapus.

## Compose — host berapa?
`localhost` juga bisa
<!--`127.0.0.1` JANGAN dipakai di compose. Pakai `172.17.0.1`-->
(gateway docker0, stabil) atau gateway network container
(`docker network inspect <net> | grep Gateway`).

```yaml
volumes:
  nginx_data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=172.17.0.1,rw,nfsvers=4
      device: ":/home/devops/volumes/devops/nginx"
```

## Verifikasi
```
exportfs -v
showmount -e localhost
mount -t nfs -o vers=4 127.0.0.1:/home/devops/volumes /mnt/test
sudo -u devops touch /mnt/test/.w && rm /mnt/test/.w
umount /mnt/test
```

## Jangan
- Jangan tambah `0.0.0.0/0` / `Anywhere` ke 2049/111 (membuka NFS ke internet).
- Jangan pakai `no_root_squash` ke public. Hanya untuk Docker nets bila perlu.
- File ini notice saja. Sumber kebenaran: `/etc/exports` + `ufw status`.