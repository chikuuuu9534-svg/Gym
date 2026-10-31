#!/usr/bin/env bash
# ============================================================
#  IRONPEAK FITNESS — one-command installer for Ubuntu 22.04/24.04
#  Run from the unzipped folder:  sudo bash install-ubuntu.sh
# ============================================================
set -euo pipefail

# ---------- EDIT THESE 3 LINES (defaults work fine to start) ----------
DOMAIN="_"                      # "_" = serve on any IP. Later: "yourdomain.com www.yourdomain.com"
DB_NAME="ironpeak_production"   # database name for form inquiries
CORS_ORIGINS="*"                # tighten to "https://yourdomain.com" after you get HTTPS
# ----------------------------------------------------------------------

APP_DIR="/opt/ironpeak"
WEB_DIR="/var/www/ironpeak"

if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; else SUDO=""; fi
$SUDO true 2>/dev/null || { echo "Run with sudo: sudo bash install-ubuntu.sh"; exit 1; }

[ -d "frontend" ] && [ -d "backend" ] || { echo "Run this from the unzipped ironpeak-fitness-deploy folder."; exit 1; }

echo "==> [1/7] Installing system packages (nginx, python, tools)"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y nginx python3 python3-venv python3-pip gnupg curl ca-certificates lsb-release

echo "==> [2/7] Installing MongoDB (skip if already present)"
if ! command -v mongod >/dev/null 2>&1; then
  CODENAME=$(lsb_release -cs)
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | $SUDO gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/8.0 multiverse" | $SUDO tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
  $SUDO apt-get update -y && $SUDO apt-get install -y mongodb-org
  $SUDO systemctl enable --now mongod
else
  echo "    MongoDB already installed."
fi

echo "==> [3/7] Setting up the backend (inquiry form service)"
$SUDO rm -rf "${APP_DIR}/backend"
$SUDO mkdir -p "${APP_DIR}/backend"
$SUDO cp backend/server.py backend/requirements.txt "${APP_DIR}/backend/"
$SUDO python3 -m venv "${APP_DIR}/backend/venv"
$SUDO "${APP_DIR}/backend/venv/bin/pip" install --upgrade pip -q
$SUDO "${APP_DIR}/backend/venv/bin/pip" install -r "${APP_DIR}/backend/requirements.txt" -q
printf 'MONGO_URL="mongodb://localhost:27017"\nDB_NAME="%s"\nCORS_ORIGINS="%s"\n' "$DB_NAME" "$CORS_ORIGINS" | $SUDO tee "${APP_DIR}/backend/.env" >/dev/null
$SUDO cp systemd/ironpeak-backend.service /etc/systemd/system/
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now ironpeak-backend

echo "==> [4/7] Publishing the website files"
$SUDO mkdir -p "${WEB_DIR}"
$SUDO cp -r frontend/. "${WEB_DIR}/"

echo "==> [5/7] Configuring nginx"
$SUDO tee /etc/nginx/sites-available/ironpeak >/dev/null <<NGINX
server {
    listen 80 default_server;
    server_name ${DOMAIN};
    root ${WEB_DIR};
    index index.html;
    client_max_body_size 10M;

    location /api/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / { try_files \$uri \$uri/ /index.html; }

    location /static/ { expires 30d; add_header Cache-Control "public, immutable"; }
}
NGINX
$SUDO rm -f /etc/nginx/sites-enabled/default
$SUDO ln -sf /etc/nginx/sites-available/ironpeak /etc/nginx/sites-enabled/ironpeak
$SUDO nginx -t
$SUDO systemctl reload nginx

echo "==> [6/7] Opening firewall port 80 (if ufw is active)"
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
  $SUDO ufw allow 'Nginx Full'
fi

echo "==> [7/7] Health checks"
sleep 2
curl -fs http://127.0.0.1:8001/api/ >/dev/null && echo "    backend: OK"
curl -fs http://127.0.0.1/index.html >/dev/null && echo "    website: OK"

SERVER_IP=$(curl -fs --max-time 3 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
echo ""
echo "=============================================="
echo "  DONE! Your website is live at:  http://${SERVER_IP}"
echo "  (or http://${DOMAIN} once DNS points here)"
echo ""
echo "  Test the form, then check saved leads with:"
echo "    curl http://127.0.0.1/api/inquiries"
echo ""
echo "  When you have a domain, run these for HTTPS:"
echo "    sudo apt install -y certbot python3-certbot-nginx"
echo "    sudo certbot --nginx -d ${DOMAIN}"
echo "=============================================="
