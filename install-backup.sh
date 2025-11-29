#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "   MIKROTIK BACKUP RECEIVER INSTALLER"
echo "        FTP Version + GitHub Sync"
echo "=========================================="
echo ""

read -p "Masukkan user Linux untuk menerima backup (misal: backup): " LUSER
read -p "Masukkan URL repo GitHub: " REPO
read -p "Masukkan nama branch (default: main): " BRANCH
read -p "Masukkan Telegram Bot Token (opsional): " TG_TOKEN
read -p "Masukkan Telegram Chat ID (opsional): " TG_CHATID

BRANCH=${BRANCH:-main}

# IP VPS
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Password random
PASS=$(openssl rand -base64 12)

echo ""
echo "[✓] Membuat user $LUSER"

if ! id "$LUSER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$LUSER"
fi

echo "$LUSER:$PASS" | chpasswd

mkdir -p /home/$LUSER/mikrotik-upload
mkdir -p /home/$LUSER/mikrotik-repo
chown -R $LUSER:$LUSER /home/$LUSER

echo ""
echo "[✓] Install FTP Server (vsftpd)"
apt update -y
apt install -y vsftpd git curl

cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

cat <<EOF >/etc/vsftpd.conf
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
ftpd_banner=Welcome to FTP Backup Server
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_min_port=30000
pasv_max_port=30100
EOF

systemctl restart vsftpd
systemctl enable vsftpd

echo ""
echo "[✓] Clone / sync GitHub Repo"

cd /home/$LUSER

if [ ! -d "/home/$LUSER/mikrotik-repo/.git" ]; then
    sudo -u $LUSER git clone "$REPO" mikrotik-repo
else
    cd mikrotik-repo
    sudo -u $LUSER git pull
fi

echo ""
echo "[✓] Membuat script auto push GitHub"

cat << 'EOF' > /home/temp_push.sh
#!/bin/bash
set -euo pipefail

UPLOAD_DIR="/home/REPLACEUSER/mikrotik-upload"
REPO_DIR="/home/REPLACEUSER/mikrotik-repo"

DATE=$(date '+%Y-%m-%d %H:%M:%S')

cd "$REPO_DIR"
cp -r $UPLOAD_DIR/* . 2>/dev/null || true

git add .
git commit -m "Auto backup $DATE" || true
git push origin REPLACEBRANCH || true

EOF

sed -i "s/REPLACEUSER/$LUSER/g" /home/temp_push.sh
sed -i "s/REPLACEBRANCH/$BRANCH/g" /home/temp_push.sh

mv /home/temp_push.sh /home/$LUSER/push-github.sh
chmod +x /home/$LUSER/push-github.sh
chown $LUSER:$LUSER /home/$LUSER/push-github.sh

echo ""
echo "[✓] Aktifkan cron 1 menit"
(crontab -u $LUSER -l 2>/dev/null; echo "* * * * * /home/$LUSER/push-github.sh >/dev/null 2>&1") | crontab -u $LUSER -

# ======================================================
# === GENERATE SCRIPT MIKROTIK (FTP VERSION 100%) =====
# ======================================================

MT_SCRIPT="/home/$LUSER/mikrotik-script.rsc"

cat <<EOF > $MT_SCRIPT
# ===========================
# AUTO BACKUP MIKROTIK (FTP)
# ===========================

# --- PARAMETER VPS (ISI MANUAL DI MIKROTIK) ---
:local ftpServer "$IP"
:local ftpPort "21"
:local ftpUser "$LUSER"
:local ftpPass "$PASS"

# --- OPSIONAL TELEGRAM ---
:local telegramToken "$TG_TOKEN"
:local chatID "$TG_CHATID"

# --- Generate nama file ---
:local d [/system clock get date]
:local t [/system clock get time]
:local cleanT [:pick \$t 0 2][:pick \$t 3 5][:pick \$t 6 8]
:local cleanD [:pick \$d 7 11]"-"[:pick \$d 0 3]"-"[:pick \$d 4 6]
:local fname "backup-\$cleanD-\$cleanT"

# --- Buat backup ---
/system backup save name=\$fname
/export file=\$fname

# --- Upload via FTP (UNIVERSAL) ---
/tool fetch mode=ftp address=\$ftpServer port=\$ftpPort user=\$ftpUser password=\$ftpPass upload=yes src-path="\$fname.backup" dst-path="\$fname.backup"
/tool fetch mode=ftp address=\$ftpServer port=\$ftpPort user=\$ftpUser password=\$ftpPass upload=yes src-path="\$fname.rsc" dst-path="\$fname.rsc"

# --- Telegram Notif ---
:if (\$telegramToken != "" && \$chatID != "") do={
    :local msg "Backup Mikrotik OK %0AName: [/system identity get name] %0AFile: \$fname"
    /tool fetch url=("https://api.telegram.org/bot".\$telegramToken."/sendMessage?chat_id=". \$chatID ."&text=". \$msg) keep-result=no
}
EOF

chown $LUSER:$LUSER $MT_SCRIPT

echo ""
echo "=========================================="
echo " INSTALL SELESAI!"
echo ""
echo "=== PARAMETER LOGIN FTP UNTUK MIKROTIK ==="
echo "FTP Server : $IP"
echo "FTP Port   : 21"
echo "FTP User   : $LUSER"
echo "FTP Pass   : $PASS"
echo ""
echo "Folder penyimpanan: /home/$LUSER/mikrotik-upload"
echo ""
echo "=== Script untuk Mikrotik sudah dibuat ==="
echo "Lokasi: /home/$LUSER/mikrotik-script.rsc"
echo ""
echo "=========================================="
