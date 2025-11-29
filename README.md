Siap, Hendri. Kita buat **metode nomor 2 (via VPS)** — ini yang **paling stabil**, karena MikroTik tinggal kirim file, dan VPS yang *push* ke GitHub.

Di bawah ini saya siapkan:

# ✅ **Bagian A — Script MikroTik (kirim backup ke VPS)**

# ✅ **Bagian B — Script di VPS (auto push ke GitHub)**

# ✅ **Bagian C — Instalasi otomatis (tinggal copy-paste)**

---

# 🅰 **A. Script MikroTik — Kirim file ke VPS**

Pastikan VPS punya **SFTP/SSH**, misal:

```
IP VPS   : 1.2.3.4
User     : backup
Password : mypass123
Folder   : /home/backup/mikrotik/
```

## **1. Buat backup & export config**

Letakkan script ini di MikroTik:

### **Script: backup-upload**

```mikrotik
:local date [/system clock get date]
:local time [/system clock get time]
:local name ("mt-" . [/system identity get name] . "-" . $date . "-" . $time)

# Hilangkan karakter spasi dan titik-koma
:set name ([:pick $name 0 [:len $name]])
:set name ([:gsub $name " " "_"])
:set name ([:gsub $name ":" "-"])

# Buat file backup dan export
/system backup save name=$name
/export file=$name

# Kirim ke VPS via SFTP
/tool fetch address="51.79.230.125" port=17123 user="root" password="rembulan" \
    src-path="$name.backup" dst-path="/home/backup/mikrotik/$name.backup" \
    upload=yes

/tool fetch address="51.79.230.125" port=17123 user="root" password="rembulan" \
    src-path="$name.rsc" dst-path="/home/backup/mikrotik/$name.rsc" \
    upload=yes

:put "Backup sukses di-upload ke VPS: $name"
```

---

# 🅱 **B. Script VPS — Auto Push ke GitHub**

Siapkan repo GitHub:

Misal:

```
https://github.com/username/mikrotik-backup
```

## **1. Clone repo dulu**

Login ke VPS:

```bash
git clone https://github.com/username/mikrotik-backup.git /home/backup/mikrotik-repo
```

Folder upload dari MikroTik tetap di tempat berbeda:

```
/home/backup/mikrotik/   ← MikroTik upload ke sini
/home/backup/mikrotik-repo/   ← Git repo
```

## **2. Buat skrip auto push**

Buat file:

```
nano /home/backup/push-github.sh
```

Isi:

```bash
#!/bin/bash
set -euo pipefail

UPLOAD_DIR="/home/backup/mikrotik"
REPO_DIR="/home/backup/mikrotik-repo"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

cd "$REPO_DIR"

# Salin file baru ke repo
cp -r $UPLOAD_DIR/* .

git add .
git commit -m "Auto backup $DATE"
git push origin main
```

Simpan → beri izin:

```bash
chmod +x /home/backup/push-github.sh
```

---

# 🅾 **C. Cronjob otomatis**

Agar setiap 1 menit repo dipush:

```
crontab -e
```

Tambahkan:

```
* * * * * /home/backup/push-github.sh >/dev/null 2>&1
```

---

# 🔥 **Kelebihan metode ini**

✔ MikroTik tidak perlu base64
✔ Aman
✔ Bisa multi router
✔ Bisa multi repo
✔ Bisa backup otomatis tiap har

Baik, Hendri. Berikut **link curl installer** sesuai repo yang kamu berikan:

### ✅ **One-line CURL Installer (jalankan di Linux/VPS)**

```
curl -o install-backup.sh https://raw.githubusercontent.com/heruhendri/Backup-MikroTik-ToGithub/main/install-backup.sh && chmod +x install-backup.sh && ./install-backup.sh
```

---

### Jika ingin dipakai di MikroTik sebagai downloader config:

```
/tool fetch url="https://raw.githubusercontent.com/heruhendri/Backup-MikroTik-ToGithub/main/install-backup.sh" dst-path="install-backup.sh"
```

---

Kalau file **install-backup.sh** belum ada di repo, saya bisa buatin isinya. Tinggal bilang:

> “Buatkan konten file install-backup.sh”

Dan saya akan isi lengkap:
✔ backup RouterOS 6 & 7
✔ kirim ke GitHub
✔ kirim ke Telegram
✔ kirim ke VPS via SCP/TCP
✔ jadwal otomatis
✔ auto-detect ROS6/ROS7

Tinggal bilang **"buatkan sekarang"**.
