#!/usr/bin/env bash
set -euo pipefail

# OLT-RADIUS Ubuntu 22.04 Auto Installer
# This script installs common dependencies for deploying this app on Ubuntu 22.x
# Components (opt-in via flags): Node.js + PNPM + PM2, MySQL 8, Nginx, Certbot, Redis, Docker, FreeRADIUS
# Usage:
#   sudo bash scripts/install-ubuntu22.sh --all \
#     --db-name aibill_radius --db-user aibill --db-pass 'StrongPass123' \
#     --domain example.com --app-port 3000 --email admin@example.com
#
# Flags:
#   --all                 Install everything (node, pm2, mysql, nginx, redis, docker, freeradius)
#   --node                Install Node.js LTS + PNPM + PM2
#   --pm2                 Ensure PM2 is installed and systemd startup is configured
#   --mysql               Install MySQL 8 and optionally create DB/user (requires --db-*)
#   --nginx               Install Nginx and configure reverse proxy
#   --ssl                 Issue TLS with Certbot for Nginx (requires --domain and --email)
#   --redis               Install Redis server
#   --docker              Install Docker Engine
#   --freeradius          Install FreeRADIUS + MySQL driver (no DB binding configured)
#   --radius-import-schema Import skema standar FreeRADIUS ke MySQL (opsional)
#   --app-setup           Setup aplikasi (env, dependencies, prisma, build, PM2)
#   --app-dir DIR         Direktori aplikasi (default: direktori skrip dieksekusi)
#   --app-git URL         Repo git aplikasi untuk di-clone ke --app-dir jika kosong
#   --app-branch BRANCH   Branch git untuk clone (default: repo default)
#   --backup-cron         Aktifkan backup otomatis MySQL harian (03:00) ke /var/backups/olt-radius
#   --backup-retain-days N Jumlah hari retensi backup (default: 14)
#   --pm2-prod            Konfigurasi PM2 untuk production dengan ecosystem & logrotate (default: aktif)
#   --no-pm2-prod         Nonaktifkan PM2 production default
#   --pm2-cluster         Jalankan PM2 dalam mode cluster (default: aktif)
#   --pm2-fork            Nonaktifkan cluster default (gunakan mode fork)
#   --pm2-instances N|max Jumlah instance cluster (default: max saat cluster)
#   --set-timezone        Set timezone sistem (default Asia/Jakarta)
#   --timezone ZONE       Zona waktu, contoh: Asia/Jakarta
#   --ufw                 Konfigurasi firewall UFW (SSH, HTTP/HTTPS, RADIUS)
#   --db-fix-radius       Jalankan fix migrasi radacct groupname menggunakan kredensial --db-*
#   --yes                 Non-interactive where possible
#   --db-name NAME        MySQL database name to create
#   --db-user USER        MySQL user to create
#   --db-pass PASS        MySQL password for the user
#   --domain DOMAIN       Domain for Nginx reverse proxy
#   --app-port PORT       App port to proxy (default 3000)
#   --email EMAIL         Email for Certbot (required with --ssl)
#   --help                Show help

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

COLOR_RESET='\033[0m'
COLOR_INFO='\033[1;34m'
COLOR_WARN='\033[1;33m'
COLOR_ERROR='\033[1;31m'
COLOR_OK='\033[1;32m'

info() { echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_WARN}[WARN]${COLOR_RESET} $*"; }
error() { echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $*"; }
ok() { echo -e "${COLOR_OK}[OK]${COLOR_RESET} $*"; }

run() {
  info "Running: $*"
  eval "$*"
}

NODE=false
PM2=false
MYSQL=false
NGINX=false
SSL=false
REDIS=false
DOCKER=false
RADIUS=false
YES=false
SET_TIMEZONE=false
TZ_REGION="Asia/Jakarta"
CONFIG_UFW=false
RUN_DB_FIX_RADIUS=false
RADIUS_IMPORT_SCHEMA=false
APP_SETUP=false
APP_DIR=""
APP_GIT=""
APP_BRANCH=""
PM2_PROD=true
PM2_CLUSTER=true
PM2_INSTANCES="max"
SETUP_BACKUP_CRON=false
BACKUP_RETAIN_DAYS=14

DB_NAME=""
DB_USER=""
DB_PASS=""
DOMAIN=""
APP_PORT="3000"
EMAIL=""

usage() {
  sed -n '1,60p' "$0"
}

detect_ubuntu_22() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID}" != "ubuntu" ]]; then
      error "Distro bukan Ubuntu (detected: ${ID})."
      exit 1
    fi
    if [[ "${VERSION_ID}" != 22.* ]]; then
      error "Versi Ubuntu bukan 22.x (detected: ${VERSION_ID})."
      exit 1
    fi
    ok "Detected Ubuntu ${VERSION_ID}."
  else
    error "/etc/os-release tidak ditemukan; tidak bisa memastikan versi OS."
    exit 1
  fi
}

update_base() {
  info "Update apt index dan base tools"
  if [[ "${YES}" == true ]]; then
    export DEBIAN_FRONTEND=noninteractive
  fi
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y ca-certificates curl gnupg lsb-release git build-essential ufw
}

install_node() {
  info "Install Node.js LTS (18.x), PNPM, PM2"
  local NODE_MAJOR=18
  if [[ -n "${SUDO}" ]]; then
    run "curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | ${SUDO} -E bash -"
  else
    run "curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -"
  fi
  ${SUDO} apt-get install -y nodejs
  if command -v corepack >/dev/null 2>&1; then
    run "${SUDO} corepack enable"
  fi
  run "${SUDO} npm i -g pnpm pm2"
  ok "Node.js $(node -v) terpasang; PNPM dan PM2 siap."
}

configure_pm2() {
  info "Konfigurasi PM2 startup (systemd)"
  if ! command -v pm2 >/dev/null 2>&1; then
    warn "PM2 belum terpasang; memasang terlebih dahulu"
    run "${SUDO} npm i -g pm2"
  fi
  # Use systemd startup
  if [[ -n "${SUDO}" ]]; then
    run "${SUDO} pm2 startup systemd -u ${SUDO_USER:-$(whoami)} --hp /home/${SUDO_USER:-$(whoami)} || true"
  else
    run "pm2 startup systemd || true"
  fi
  ok "PM2 startup dikonfigurasi. Jalankan 'pm2 save' setelah menambahkan proses."
}

install_mysql() {
  info "Install MySQL Server"
  ${SUDO} apt-get install -y mysql-server mysql-client
  ok "MySQL terpasang."

  if [[ -n "${DB_NAME}" && -n "${DB_USER}" && -n "${DB_PASS}" ]]; then
    info "Membuat database dan user: ${DB_NAME} / ${DB_USER}"
    ${SUDO} mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    ${SUDO} mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    ${SUDO} mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';"
    ${SUDO} mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    ${SUDO} mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';"
    ${SUDO} mysql -e "FLUSH PRIVILEGES;"
    ok "Database dan user MySQL dikonfigurasi."
  else
    warn "Lewati konfigurasi DB/user MySQL karena parameter --db-* tidak lengkap."
  fi
}

# Setup automatic MySQL backup via cron (daily at 03:00)
setup_backup_cron() {
  if [[ -z "${DB_NAME}" || -z "${DB_USER}" || -z "${DB_PASS}" ]]; then
    warn "Backup cron membutuhkan --db-name, --db-user, dan --db-pass. Lewati setup."
    return 0
  fi

  local BK_DIR="/var/backups/olt-radius"
  local BK_SCRIPT="/usr/local/sbin/olt-db-backup.sh"
  local BK_CRON="/etc/cron.d/olt-db-backup"

  info "Menyiapkan backup otomatis MySQL ke ${BK_DIR} (retensi ${BACKUP_RETAIN_DAYS} hari)"
  ${SUDO} mkdir -p "${BK_DIR}"
  ${SUDO} chown root:root "${BK_DIR}"
  ${SUDO} chmod 750 "${BK_DIR}"

  # Buat skrip backup
  cat <<'SH' | ${SUDO} tee "${BK_SCRIPT}" >/dev/null
#!/usr/bin/env bash
set -euo pipefail

DB_USER="__DB_USER__"
DB_PASS="__DB_PASS__"
DB_NAME="__DB_NAME__"
DB_HOST="localhost"
RETENTION_DAYS=__RETENTION_DAYS__
OUT_DIR="/var/backups/olt-radius"

# Timestamp
TS=$(date +%F_%H%M%S)
OUT_FILE="${OUT_DIR}/${DB_NAME}_${TS}.sql.gz"

echo "[Backup] $(date) Starting mysqldump to ${OUT_FILE}" || true

# Use MYSQL_PWD to avoid exposing password in process list
export MYSQL_PWD="${DB_PASS}"
mysqldump -u "${DB_USER}" -h "${DB_HOST}" --single-transaction --routines --triggers "${DB_NAME}" | gzip -c > "${OUT_FILE}"

echo "[Backup] $(date) Backup completed: ${OUT_FILE}" || true

# Retention: delete files older than RETENTION_DAYS
find "${OUT_DIR}" -type f -name "${DB_NAME}_*.sql.gz" -mtime +"${RETENTION_DAYS}" -print -delete || true
echo "[Backup] $(date) Retention applied: ${RETENTION_DAYS} days" || true
SH

  # Inject variables into script
  ${SUDO} sed -i "s|__DB_USER__|${DB_USER}|g" "${BK_SCRIPT}"
  ${SUDO} sed -i "s|__DB_PASS__|${DB_PASS}|g" "${BK_SCRIPT}"
  ${SUDO} sed -i "s|__DB_NAME__|${DB_NAME}|g" "${BK_SCRIPT}"
  ${SUDO} sed -i "s|__RETENTION_DAYS__|${BACKUP_RETAIN_DAYS}|g" "${BK_SCRIPT}"

  ${SUDO} chmod 750 "${BK_SCRIPT}"

  # Cron entry: run daily at 03:00
  cat <<CRON | ${SUDO} tee "${BK_CRON}" >/dev/null
# OLT-RADIUS MySQL backup (daily)
0 3 * * * root ${BK_SCRIPT} >/var/log/olt-db-backup.log 2>&1
CRON
  ${SUDO} chmod 644 "${BK_CRON}"

  ok "Backup otomatis MySQL terpasang. Cek log di /var/log/olt-db-backup.log"
}

install_redis() {
  info "Install Redis Server"
  ${SUDO} apt-get install -y redis-server
  # Supervised by systemd
  ${SUDO} sed -i 's/^#*\s*supervised\s.*/supervised systemd/' /etc/redis/redis.conf || true
  ${SUDO} systemctl enable redis-server
  ${SUDO} systemctl restart redis-server
  ok "Redis terpasang dan berjalan."
}

install_nginx() {
  info "Install Nginx"
  ${SUDO} apt-get install -y nginx
  ${SUDO} systemctl enable nginx
  ${SUDO} systemctl start nginx
  if [[ -n "${DOMAIN}" ]]; then
    info "Membuat konfigurasi reverse proxy untuk domain ${DOMAIN} -> 127.0.0.1:${APP_PORT}"
    local CFG="/etc/nginx/sites-available/olt-radius.conf"
    cat <<CONF | ${SUDO} tee "${CFG}" >/dev/null
server {
  listen 80;
  server_name ${DOMAIN};

  location / {
    proxy_pass http://127.0.0.1:${APP_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
  }
}
CONF
    ${SUDO} ln -sf "${CFG}" /etc/nginx/sites-enabled/olt-radius.conf
    ${SUDO} nginx -t
    ${SUDO} systemctl reload nginx
    ok "Nginx reverse proxy dikonfigurasi."
  else
    warn "Lewati konfigurasi Nginx reverse proxy karena --domain tidak diset."
  fi
}

install_ssl() {
  if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
    error "--ssl memerlukan --domain dan --email"
    exit 1
  fi
  info "Mengaktifkan HTTPS via Certbot untuk ${DOMAIN}"
  ${SUDO} apt-get install -y certbot python3-certbot-nginx
  local ARGS="--nginx -d ${DOMAIN} --non-interactive --agree-tos -m ${EMAIL}"
  if [[ "${YES}" == true ]]; then
    run "${SUDO} certbot ${ARGS} || true"
  else
    run "${SUDO} certbot ${ARGS} || true"
  fi
  ok "Certbot dijalankan. Pastikan DNS mengarah ke server ini."
}

install_docker() {
  info "Install Docker Engine"
  ${SUDO} install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io
  ${SUDO} systemctl enable docker
  ${SUDO} systemctl start docker
  ok "Docker terpasang."
}

install_freeradius() {
  info "Install FreeRADIUS + MySQL driver"
  ${SUDO} apt-get install -y freeradius freeradius-mysql
  ${SUDO} systemctl enable freeradius
  ${SUDO} systemctl start freeradius
  ok "FreeRADIUS terpasang."
}

configure_freeradius_mysql() {
  local SQL_AVAIL="/etc/freeradius/3.0/mods-available/sql"
  local SQL_ENABLED_DIR="/etc/freeradius/3.0/mods-enabled"
  local DEFAULT_SITE="/etc/freeradius/3.0/sites-available/default"

  if [[ ! -f "${SQL_AVAIL}" ]]; then
    error "File konfigurasi tidak ditemukan: ${SQL_AVAIL}"
    return 1
  fi

  info "Konfigurasi FreeRADIUS SQL (MySQL localhost:3306)"
  ${SUDO} cp "${SQL_AVAIL}" "${SQL_AVAIL}.bak" || true
  cat <<CONF | ${SUDO} tee "${SQL_AVAIL}" >/dev/null
sql {
  driver = "rlm_sql_mysql"
  dialect = "mysql"

  # Koneksi database
  server = "localhost"
  port = 3306
  login = "${DB_USER}"
  password = "${DB_PASS}"
  radius_db = "${DB_NAME}"

  # Opsional: aktifkan read_clients bila menyimpan clients di DB
  read_clients = yes

  # Path queries default
  # file = "/etc/freeradius/3.0/mods-config/sql/main/mysql/queries.conf"
}
CONF

  # Enable module sql
  ${SUDO} ln -sf "${SQL_AVAIL}" "${SQL_ENABLED_DIR}/sql"

  # Aktifkan 'sql' di default site untuk authorize, accounting, session
  if [[ -f "${DEFAULT_SITE}" ]]; then
    ${SUDO} cp "${DEFAULT_SITE}" "${DEFAULT_SITE}.bak" || true
    ${SUDO} sed -i 's/^\s*#\s*sql/sql/' "${DEFAULT_SITE}" || true
  else
    warn "Default site tidak ditemukan: ${DEFAULT_SITE}. Lewati update situs."
  fi

  ${SUDO} systemctl restart freeradius
  ok "FreeRADIUS dikonfigurasi menggunakan MySQL di localhost."
}

setup_env() {
  local DIR="${APP_DIR:-$(pwd)}"
  local ENV_EXAMPLE="${DIR}/.env.example"
  local ENV_FILE="${DIR}/.env"
  if [[ ! -f "${ENV_EXAMPLE}" ]]; then
    warn ".env.example tidak ditemukan di ${DIR}; membuat .env minimal"
    ${SUDO} bash -c "cat > '${ENV_FILE}' <<'ENV'
NODE_ENV=production
DATABASE_URL=
NEXTAUTH_URL=
NEXT_PUBLIC_APP_URL=
NEXTAUTH_SECRET=
ENV" || true
  else
    if [[ ! -f "${ENV_FILE}" ]]; then
      info "Membuat .env dari .env.example di ${DIR}"
      ${SUDO} cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    else
      info ".env sudah ada; akan disesuaikan jika perlu"
    fi
  fi

  if [[ -n "${DB_NAME}" && -n "${DB_USER}" && -n "${DB_PASS}" ]]; then
    local NEW_DB_URL="mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}?connection_limit=10&pool_timeout=20"
    ${SUDO} sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"${NEW_DB_URL}\"|" "${ENV_FILE}" || true
  fi

  if [[ -n "${DOMAIN}" ]]; then
    local URL="https://${DOMAIN}"
    ${SUDO} sed -i "s|^NEXT_PUBLIC_APP_URL=.*|NEXT_PUBLIC_APP_URL=\"${URL}\"|" "${ENV_FILE}" || true
    ${SUDO} sed -i "s|^NEXTAUTH_URL=.*|NEXTAUTH_URL=${URL}|" "${ENV_FILE}" || true
  fi
  # Generate NEXTAUTH_SECRET jika kosong
  if command -v openssl >/dev/null 2>&1; then
    if [[ -f "${ENV_FILE}" ]] && ! grep -q "^NEXTAUTH_SECRET=" "${ENV_FILE}"; then
      ${SUDO} bash -c "echo NEXTAUTH_SECRET=\"$(openssl rand -hex 32)\" >> '${ENV_FILE}'" || true
    fi
  fi
  ok "File .env disiapkan."
}

setup_app() {
  local DIR="${APP_DIR:-$(pwd)}"
  # Pastikan direktori aplikasi tersedia; clone jika perlu
  if [[ ! -d "${DIR}" ]]; then
    if [[ -n "${APP_GIT}" ]]; then
      info "APP_DIR belum ada; clone repo ${APP_GIT} ke ${DIR}"
      ${SUDO} mkdir -p "${DIR}"
      if [[ -n "${APP_BRANCH}" ]]; then
        run "git clone --depth 1 -b '${APP_BRANCH}' '${APP_GIT}' '${DIR}'"
      else
        run "git clone --depth 1 '${APP_GIT}' '${DIR}'"
      fi
    else
      error "Direktori aplikasi ${DIR} tidak ditemukan. Gunakan --app-git untuk clone atau buat direktori dan salin kode aplikasi."
      exit 1
    fi
  fi
  # Validasi package.json
  if [[ ! -f "${DIR}/package.json" ]]; then
    error "package.json tidak ditemukan di ${DIR}. Pastikan repo aplikasi sudah benar."
    exit 1
  fi
  info "Setup aplikasi di ${DIR}"
  ( cd "${DIR}" && \
    if command -v pnpm >/dev/null 2>&1; then pnpm install; else ${SUDO} npm install; fi && \
    npx prisma generate && \
    ( npx prisma migrate deploy || npx prisma db push ) && \
    ( npm run db:seed || true ) && \
    npm run build )

  # Jalankan dengan PM2
  if command -v pm2 >/dev/null 2>&1; then
    if [[ "${PM2_PROD}" == true ]]; then
      setup_pm2_production
    else
      ( cd "${DIR}" && pm2 start npm --name olt-radius -- start )
      pm2 save || true
      ok "Aplikasi dijalankan via PM2 sebagai 'olt-radius'."
    fi
  else
    warn "PM2 tidak ditemukan; jalankan manual dengan 'npm run start' di ${DIR}"
  fi
}

import_radius_schema() {
  local SCHEMA="/etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql"
  if [[ ! -f "${SCHEMA}" ]]; then
    warn "Schema SQL standar FreeRADIUS tidak ditemukan: ${SCHEMA}."
    return 0
  fi

  info "Impor skema standar FreeRADIUS ke MySQL (${DB_NAME})"
  # Cek apakah tabel radcheck sudah ada
  local TABLE_EXISTS
  TABLE_EXISTS=$( ${SUDO} mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='radcheck';" || echo 0 )
  if [[ "${TABLE_EXISTS}" -eq 0 ]]; then
    info "Tabel radcheck belum ada, menjalankan impor skema standar."
    ${SUDO} mysql "${DB_NAME}" < "${SCHEMA}"
    ok "Skema standar FreeRADIUS diimpor."
  else
    warn "Skema tampak sudah ada (radcheck ditemukan). Lewati impor."
  fi
}

set_system_timezone() {
  info "Set timezone sistem ke ${TZ_REGION}"
  if command -v timedatectl >/dev/null 2>&1; then
    ${SUDO} timedatectl set-timezone "${TZ_REGION}" || warn "Gagal set timezone via timedatectl"
  else
    warn "timedatectl tidak tersedia; lewati set timezone"
  fi
  ok "Timezone sistem diperbarui (jika didukung)."
}

configure_ufw() {
  info "Konfigurasi firewall UFW"
  ${SUDO} ufw allow OpenSSH || true
  ${SUDO} ufw allow 80/tcp || true
  ${SUDO} ufw allow 443/tcp || true
  # FreeRADIUS ports
  ${SUDO} ufw allow 1812/udp || true
  ${SUDO} ufw allow 1813/udp || true
  # App port jika ditentukan
  if [[ -n "${APP_PORT}" ]]; then
    ${SUDO} ufw allow "${APP_PORT}/tcp" || true
  fi
  echo y | ${SUDO} ufw enable || true
  ${SUDO} ufw status
  ok "UFW diaktifkan dan aturan dasar diterapkan."
}

run_db_fix_radius() {
  local DIR="${APP_DIR:-$(pwd)}"
  local MIG="${DIR}/prisma/migrations/fix_radacct_groupname/migration.sql"
  if [[ ! -f "${MIG}" ]]; then
    warn "File migrasi tidak ditemukan: ${MIG}"
    return 0
  fi
  if [[ -z "${DB_NAME}" || -z "${DB_USER}" || -z "${DB_PASS}" ]]; then
    warn "Lewati db-fix-radius karena kredensial --db-* belum lengkap"
    return 0
  fi
  info "Menjalankan perbaikan radacct groupname menggunakan ${DB_USER}@localhost ke DB ${DB_NAME}"
  ${SUDO} sh -c "mysql -u '${DB_USER}' -p'${DB_PASS}' '${DB_NAME}' < '${MIG}'" || error "Gagal menjalankan db-fix-radius"
  ok "Perbaikan radacct groupname berhasil dijalankan."
}

setup_pm2_production() {
  local DIR="${APP_DIR:-$(pwd)}"
  local ECO="${DIR}/ecosystem.config.js"
  local LOG_DIR="/var/log/olt-radius"
  local INSTANCES
  local EXEC_MODE

  info "Konfigurasi PM2 untuk production"
  if ! command -v pm2 >/dev/null 2>&1; then
    warn "PM2 belum terpasang; memasang terlebih dahulu"
    run "${SUDO} npm i -g pm2"
  fi

  # Pastikan startup systemd sudah dikonfigurasi
  if [[ -n "${SUDO}" ]]; then
    run "${SUDO} pm2 startup systemd -u ${SUDO_USER:-$(whoami)} --hp /home/${SUDO_USER:-$(whoami)} || true"
  else
    run "pm2 startup systemd || true"
  fi

  # Install dan konfigurasi pm2-logrotate
  pm2 install pm2-logrotate || true
  pm2 set pm2-logrotate:max_size 10M || true
  pm2 set pm2-logrotate:retain 10 || true
  pm2 set pm2-logrotate:compress true || true
  pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss || true

  # Siapkan direktori log
  ${SUDO} mkdir -p "${LOG_DIR}"
  ${SUDO} chown ${SUDO_USER:-$(whoami)}:"${SUDO_USER:-$(whoami)}" "${LOG_DIR}" || true

  # Tentukan mode eksekusi
  if [[ "${PM2_CLUSTER}" == true ]]; then
    INSTANCES="${PM2_INSTANCES}"
    EXEC_MODE="cluster"
  else
    INSTANCES="1"
    EXEC_MODE="fork"
  fi

  # Buat ecosystem config
  info "Membuat ecosystem.config.js di ${DIR}"
  cat <<ECO > "${ECO}"
module.exports = {
  apps: [
    {
      name: 'olt-radius',
      cwd: '${DIR}',
      script: 'node_modules/.bin/next',
      args: 'start -p ${APP_PORT}',
      instances: ${INSTANCES},
      exec_mode: '${EXEC_MODE}',
      env: {
        NODE_ENV: 'production',
        PORT: '${APP_PORT}',
        TZ: 'Asia/Jakarta'
      },
      max_memory_restart: '512M',
      out_file: '${LOG_DIR}/out.log',
      error_file: '${LOG_DIR}/error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss'
    }
  ]
}
ECO

  # Jalankan aplikasi via ecosystem
  ( cd "${DIR}" && pm2 start "${ECO}" )
  pm2 save || true
  ok "PM2 production dikonfigurasi dan aplikasi berjalan."
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) NODE=true; PM2=true; MYSQL=true; NGINX=true; REDIS=true; DOCKER=true; RADIUS=true; shift ;;
    --node) NODE=true; shift ;;
    --pm2) PM2=true; shift ;;
    --mysql) MYSQL=true; shift ;;
    --nginx) NGINX=true; shift ;;
    --ssl) SSL=true; shift ;;
    --redis) REDIS=true; shift ;;
    --docker) DOCKER=true; shift ;;
    --freeradius) RADIUS=true; shift ;;
    --radius-import-schema) RADIUS_IMPORT_SCHEMA=true; shift ;;
    --app-setup) APP_SETUP=true; shift ;;
    --app-dir) APP_DIR="$2"; shift 2 ;;
    --app-git) APP_GIT="$2"; shift 2 ;;
    --app-branch) APP_BRANCH="$2"; shift 2 ;;
    --pm2-prod) PM2_PROD=true; shift ;;
    --pm2-fork) PM2_CLUSTER=false; PM2_INSTANCES="1"; shift ;;
    --no-pm2-prod) PM2_PROD=false; shift ;;
    --pm2-cluster) PM2_CLUSTER=true; PM2_INSTANCES="max"; shift ;;
    --pm2-instances) PM2_INSTANCES="$2"; PM2_CLUSTER=true; shift 2 ;;
    --set-timezone) SET_TIMEZONE=true; shift ;;
    --timezone) TZ_REGION="$2"; shift 2 ;;
    --ufw) CONFIG_UFW=true; shift ;;
    --db-fix-radius) RUN_DB_FIX_RADIUS=true; shift ;;
    --yes) YES=true; shift ;;
    --db-name) DB_NAME="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-pass) DB_PASS="$2"; shift 2 ;;
    --backup-cron) SETUP_BACKUP_CRON=true; shift ;;
    --backup-retain-days) BACKUP_RETAIN_DAYS="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --app-port) APP_PORT="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) error "Argumen tidak dikenal: $1"; usage; exit 1 ;;
  esac
done

detect_ubuntu_22
update_base

if [[ "${NODE}" == true ]]; then install_node; fi
if [[ "${PM2}" == true ]]; then configure_pm2; fi
if [[ "${MYSQL}" == true ]]; then install_mysql; fi
if [[ "${SETUP_BACKUP_CRON}" == true ]]; then setup_backup_cron; fi
if [[ "${REDIS}" == true ]]; then install_redis; fi
if [[ "${NGINX}" == true ]]; then install_nginx; fi
if [[ "${SSL}" == true ]]; then install_ssl; fi
if [[ "${DOCKER}" == true ]]; then install_docker; fi
if [[ "${RADIUS}" == true ]]; then
  install_freeradius
  # Jika kredensial DB tersedia, konfigurasikan FreeRADIUS ke MySQL lokal
  if [[ -n "${DB_NAME}" && -n "${DB_USER}" && -n "${DB_PASS}" ]]; then
    configure_freeradius_mysql
    if [[ "${RADIUS_IMPORT_SCHEMA}" == true ]]; then
      import_radius_schema
    fi
  else
    warn "Lewati konfigurasi FreeRADIUS ke MySQL karena --db-* belum lengkap."
  fi
fi

# Perbaikan skema radacct bila diminta
if [[ "${RUN_DB_FIX_RADIUS}" == true ]]; then
  run_db_fix_radius
fi

# Set timezone sistem bila diminta
if [[ "${SET_TIMEZONE}" == true ]]; then
  set_system_timezone
fi

# UFW konfigurasi dasar
if [[ "${CONFIG_UFW}" == true ]]; then
  configure_ufw
fi

# Siapkan aplikasi (opsional)
if [[ "${APP_SETUP}" == true ]]; then
  setup_env
  setup_app
fi

# Jika diminta, lakukan konfigurasi PM2 production meski tanpa --app-setup
if [[ "${PM2_PROD}" == true && "${APP_SETUP}" != true ]]; then
  setup_pm2_production
fi

ok "Semua task selesai."
echo
info "Contoh DATABASE_URL untuk .env (MySQL):"
echo "  mysql://<db_user>:<db_pass>@localhost:3306/<db_name>?connection_limit=10&pool_timeout=20"
echo
info "Langkah lanjut (manual):"
echo "  1) Salin file .env.example menjadi .env dan sesuaikan kredensial."
echo "  2) Jalankan 'pnpm install' lalu 'pnpm build' dan 'pnpm start' (atau gunakan PM2)."
echo "  3) Jika memakai Nginx, pastikan domain telah mengarah ke server dan SSL aktif."