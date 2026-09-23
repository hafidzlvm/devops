### Log
```bash

export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y nfs-kernel-server && dpkg -l | grep nfs

ls -ld /home/devops/volumes; chown devops:devops /home/devops/volumes; chmod 755 /home/devops/volumes
cat /etc/exports
echo "---writing new exports---"
printf '%s\n' '/home/devops/volumes 127.0.0.1(rw,sync,no_subtree_check) 172.16.0.0/12(rw,sync,no_subtree_check)' > /etc/exports
cat /etc/exports
exportfs -rav; exportfs -v
systemctl enable --now rpcbind nfs-server 2>&1; systemctl is-active rpcbind nfs-server 2>&1

ufw allow from 172.16.0.0/12 to any port 2049 proto tcp comment 'NFSv4 docker nets' 2>&1
ufw allow from 172.16.0.0/12 to any port 111 proto tcp comment 'rpcbind docker nets' 2>&1
ufw allow from 172.16.0.0/12 to any port 111 proto udp comment 'rpcbind-udp docker nets' 2>&1
ufw status numbered 2>&1 | head -n 30
echo "---SHOWMOUNT---"; showmount -e localhost 2>&1; showmount -e 127.0.0.1 2>&1

mkdir -p /tmp/opencode/nfs-test
mount -t nfs -o vers=4 127.0.0.1:/home/devops/volumes /tmp/opencode/nfs-test 2>&1 && echo "MOUNT OK" || echo "MOUNT FAIL"
mount | grep nfs
touch /tmp/opencode/nfs-test/.nfs-write-test && ls -l /tmp/opencode/nfs-test/ && rm /tmp/opencode/nfs-test/.nfs-write-test && echo "RW OK"
umount /tmp/opencode/nfs-test && echo "UMOUNT OK"; rmdir /tmp/opencode/nfs-test 2>/dev/null; exportfs -v

mkdir -p /tmp/opencode/nfs-test
mount -t nfs -o vers=4 127.0.0.1:/home/devops/volumes /tmp/opencode/nfs-test 2>&1
sudo -u devops touch /tmp/opencode/nfs-test/.nfs-write-test-devops && echo "RW devops OK" && ls -l /tmp/opencode/nfs-test/ && sudo -u devops rm /tmp/opencode/nfs-test/.nfs-write-test-devops && echo "CLEAN OK"
umount /tmp/opencode/nfs-test; rmdir /tmp/opencode/nfs-test 2>/dev/null; echo DONE
```

### More
``` md
Fungsi dari menggunakan :
/home/devops/volumes 127.0.0.1(rw,sync,no_subtree_check) 172.16.0.0/12(rw,sync,no_subtree_check)

- /home/devops/volumes — direktori yang di-share via NFS.
- 127.0.0.1(...) — client localhost boleh mount (untuk tes + proses di host).
- 172.16.0.0/12(...) — range 172.16.x.x–172.31.x.x, mencakup semua Docker bridge (172.17.0.1 docker0, 172.18/19/22 br-* tadi). Container mount via gateway host. Public 194.233.79.99/22 sengaja tidak diberi akses.
- rw — read-write. Lawannya ro.
- sync — server jawab write setelah data masuk disk. Aman dari corrupt saat crash, sedikit lebih lambat dari async.
- no_subtree_check — skip cek subtree per-file. Standar modern, lebih cepat, hindari error saat subdir di-rename.
```