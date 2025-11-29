#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "     MIKROTIK BACKUP RECEIVER INSTALLER"
echo "   Auto-push ke GitHub by Hendri (NATVPS)"
echo "=========================================="
echo ""

# === Input ===
read -p "Masukkan nama user Linux untuk menerima backup (misal: backup): " LUSER
read -p "Masukkan URL repo GitHub (misal: https://github.com/user/mikrotik-backup.git): " REPO
read -p "Masukkan nama branch (default: main): " BRANCH

BRANCH=${BRANCH:-main}

echo ""
echo "[✓] Membuat user $LUSER dan folder"
# Buat user jika belum ada
if ! id "$LUSER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$LUSER"
fi

mkdir -p /home/$LUSER/mikrotik-upload
mkdir -p /home/$LUSER/mikrotik-repo

chown -R $LUSER:$LUSER /home/$LUSER

echo ""
echo "[✓] Setup SSH untuk SFTP upload"
# Izinkan user ini pakai SFTP
if ! grep -q "Match User $LUSER" /etc/ssh/sshd_config; then
    cat <<EOF >> /etc/ssh/sshd_config

Match User $LUSER
    ForceCommand internal-sftp
    PasswordAuthentication yes
    ChrootDirectory /home/$LUSER
    PermitTunnel no
    AllowAgentForwarding no
    AllowTcpForwarding no
    X11Forwarding no
EOF
fi

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

cat <<'EOF' > /home/$LUSER/push-github.sh
#!/bin/bash
set -euo pipefail

UPLOAD_DIR="/home/REPLACEUSER/mikrotik-upload"
REPO_DIR="/home/REPLACEUSER/mikrotik-repo"

DATE=$(date '+%Y-%m-%d %H:%M:%S')

cd "$REPO_DIR"

cp -r $UPLOAD_DIR/* .

git add .
git commit -m "Auto backup $DATE" || true
git push origin REPLACEBRANCH || true
EOF

# Replace placeholder
sed -i "s/REPLACEUSER/$LUSER/g" /home/$LUSER/push-github.sh
sed -i "s/REPLACEBRANCH/$BRANCH/g" /home/$LUSER/push-github.sh

chmod +x /home/$LUSER/push-github.sh
chown $LUSER:$LUSER /home/$LUSER/push-github.sh

echo ""
echo "[✓] Menambahkan cronjob"
(crontab -u $LUSER -l 2>/dev/null; echo "* * * * * /home/$LUSER/push-github.sh >/dev/null 2>&1") | crontab -u $LUSER -

echo ""
echo "=========================================="
echo " INSTALL BERHASIL!"
echo " Folder upload MikroTik  : /home/$LUSER/mikrotik-upload"
echo " Folder repo GitHub      : /home/$LUSER/mikrotik-repo"
echo ""
echo " Copy script MikroTik berikut:"
echo ""
echo "  /tool fetch address=\"IP_VPS\" port=\"22/yourport\" user=\"$LUSER\" password=\"PASSWORD_LUSER\" \\"
echo "      src-path=\"filename.backup\" dst-path=\"/mikrotik-upload/filename.backup\" upload=yes"
echo ""
echo "=========================================="
