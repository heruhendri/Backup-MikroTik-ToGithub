#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "   MIKROTIK BACKUP RECEIVER INSTALLER"
echo " Auto-Push GitHub + Auto Script Mikrotik"
echo "=========================================="
echo ""

read -p "Masukkan user Linux untuk menerima backup (misal: backup): " LUSER
read -p "Masukkan URL repo GitHub: " REPO
read -p "Masukkan nama branch (default: main): " BRANCH
read -p "Masukkan Telegram Bot Token (opsional, Enter lewati): " TG_TOKEN
read -p "Masukkan Telegram Chat ID (opsional, Enter lewati): " TG_CHATID

BRANCH=${BRANCH:-main}

# Ambil IP VPS otomatis
IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Generate password random
PASS=$(openssl rand -base64 12)

echo ""
echo "[✓] Membuat user $LUSER dan folder"

if ! id "$LUSER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$LUSER"
fi

echo "$LUSER:$PASS" | chpasswd

mkdir -p /home/$LUSER/mikrotik-upload
mkdir -p /home/$LUSER/mikrotik-repo
chown -R $LUSER:$LUSER /home/$LUSER

echo ""
echo "[✓] Instalasi FTP server (vsftpd)"
apt update -y
apt install -y vsftpd git curl

systemctl enable vsftpd
systemctl restart vsftpd

echo ""
echo "[✓] Setup SFTP jail user"
if ! grep -q "Match User $LUSER" /etc/ssh/sshd_config; then
cat <<EOF >> /etc/ssh/sshd_config

Match User $LUSER
    ForceCommand internal-sftp
    PasswordAuthentication yes
    ChrootDirectory /home/$LUSER
    PermitTunnel no
    AllowAgentForwarding no
    AllowTcpForwarding no
EOF
fi

chmod 755 /home/$LUSER
systemctl restart ssh

echo ""
echo "[✓] Clone atau sync repository GitHub"

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
echo "[✓] Cronjob aktif setiap 1 menit"
(crontab -u $LUSER -l 2>/dev/null; echo "* * * * * /home/$LUSER/push-github.sh >/dev/null 2>&1") | crontab -u $LUSER -

# ===============================
# Generate SCRIPT MIKROTIK FIX
# ===============================

echo ""
echo "[✓] Membuat script Mikrotik otomatis..."

MT_SCRIPT="/home/$LUSER/mikrotik-script.rsc"

cat <<EOF > $MT_SCRIPT
# ============================
# AUTO BACKUP MIKROTIK UNIVERSAL
# ROS6/ROS7 (SFTP/SCP AUTO)
# Kirim ke VPS
# ============================

:local vpsAddress "$IP"
:local vpsPort "22"
:local vpsUser "$LUSER"
:local vpsPass "$PASS"

# === TELEGRAM OPSIONAL ===
:local telegramToken "$TG_TOKEN"
:local chatID "$TG_CHATID"

# === tanggal filename ===
:local d [/system clock get date]
:local t [/system clock get time]
:local cleanT [:pick \$t 0 2][:pick \$t 3 5][:pick \$t 6 8]
:local cleanD [:pick \$d 0 3][:pick \$d 4 6][:pick \$d 7 11]

:local fname "auto-\$cleanD-\$cleanT"

# BUAT FILE BACKUP
/system backup save name=\$fname
/export file=\$fname

# DETEKSI ROS6 / ROS7
:local ver [/system resource get version]

:if ([:find \$ver "6."] != nil) do={
    :local opt ""
} else={
    :local opt "mode=scp"
}

# Upload BACKUP
/tool fetch address=\$vpsAddress port=\$vpsPort user=\$vpsUser password=\$vpsPass \$opt upload=yes \\
    src-path="\$fname.backup" dst-path="/mikrotik-upload/\$fname.backup"

/tool fetch address=\$vpsAddress port=\$vpsPort user=\$vpsUser password=\$vpsPass \$opt upload=yes \\
    src-path="\$fname.rsc" dst-path="/mikrotik-upload/\$fname.rsc"

# Telegram Notify
:if (\$telegramToken != "" && \$chatID != "") do={
    :local msg "Backup Mikrotik OK %0AName: [/system identity get name] %0AFile: \$fname %0AVersion: \$ver"
    /tool fetch url=("https://api.telegram.org/bot" . \$telegramToken . "/sendMessage?chat_id=" . \$chatID . "&text=" . \$msg) keep-result=no
}

EOF

chown $LUSER:$LUSER $MT_SCRIPT

echo ""
echo "=========================================="
echo " INSTALL BERHASIL!"
echo ""
echo " === Login SFTP ==="
echo "User      : $LUSER"
echo "Password  : $PASS"
echo "IP VPS    : $IP"
echo "Port      : 22"
echo ""
echo " Folder upload MikroTik  : /home/$LUSER/mikrotik-upload"
echo " Folder repo GitHub      : /home/$LUSER/mikrotik-repo"
echo ""
echo "=== Copy script Mikrotik berikut: ==="
echo ""
cat $MT_SCRIPT
echo ""
echo "=========================================="
