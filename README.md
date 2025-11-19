# AIBILL RADIUS - Sistem Billing untuk ISP RTRW.NET# AIBILL RADIUS - Sistem Billing untuk RTRW.NET

## ⚙️ Auto Install Ubuntu 22

- Skrip installer tersedia di `scripts/install-ubuntu22.sh` untuk menyiapkan dependency utama di Ubuntu 22.x.
- Komponen yang dapat dipasang: Node.js (18.x) + PNPM + PM2, MySQL 8, Nginx, Certbot, Redis, Docker, FreeRADIUS.

### Cara Pakai Cepat

```bash
# Salin repo ke server (atau salin hanya skripnya)
git clone <repo-anda> && cd <repo-anda>

# Jalankan semua instalasi + buat database/user MySQL
sudo bash scripts/install-ubuntu22.sh --all \
  --db-name aibill_radius --db-user aibill --db-pass 'GantiPasswordKuat123' \
  --domain yourdomain.com --app-port 3000 --email admin@yourdomain.com
```

### Opsi yang Tersedia

- `--all` memasang semua komponen.
- `--node` memasang Node.js LTS + PNPM + PM2.
- `--pm2` mengaktifkan PM2 startup (systemd).
- `--mysql` memasang MySQL 8 dan (opsional) membuat DB/user bila `--db-*` diisi.
- `--nginx` memasang Nginx dan reverse proxy ke `127.0.0.1:<app-port>` untuk `--domain`.
- `--ssl` mengaktifkan HTTPS via Certbot (butuh `--domain` dan `--email`).
- `--redis`, `--docker`, `--freeradius` memasang masing-masing komponen.
- `--db-name`, `--db-user`, `--db-pass` untuk membuat database dan user MySQL.
- `--domain`, `--app-port` untuk Nginx reverse proxy (default `3000`).
 - `--app-setup` otomatis setup aplikasi (generate `.env`, install deps, Prisma, build, PM2).
 - `--app-dir DIR` lokasi kode aplikasi di server (default: direktori skrip).
 - `--app-git URL` jika `DIR` belum ada, clone repo ke `DIR`.
 - `--app-branch BRANCH` pilih branch saat clone (opsional).

### Backup Otomatis MySQL

- Aktifkan backup harian ke `/var/backups/aibill-radius` pukul `03:00` dengan retensi default `14` hari:

```bash
sudo bash scripts/install-ubuntu22.sh --backup-cron \
  --db-name aibill_radius --db-user aibill --db-pass 'StrongPass123'
```

- Ubah retensi hari:

```bash
sudo bash scripts/install-ubuntu22.sh --backup-cron --backup-retain-days 7 \
  --db-name aibill_radius --db-user aibill --db-pass 'StrongPass123'
```

- Log: `
/var/log/aibill-db-backup.log
`

- File hasil: `
/var/backups/aibill-radius/<db>_YYYY-MM-DD_HHMMSS.sql.gz
`

### Contoh `.env`

Gunakan format dari `.env.example` dan sesuaikan kredensial:

```env
DATABASE_URL="mysql://aibill:YourStrongPass@localhost:3306/aibill_radius?connection_limit=10&pool_timeout=20"
TZ="Asia/Jakarta"
NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"
NEXT_PUBLIC_APP_NAME="AIBILL RADIUS"
NEXT_PUBLIC_APP_URL="https://yourdomain.com"
NEXTAUTH_SECRET=ubah-secret-anda
NEXTAUTH_URL=https://yourdomain.com
```

### PM2 Production

- Default: PM2 production aktif saat `--app-setup` dijalankan.
- Jalankan aplikasi dengan PM2 mode production menggunakan ecosystem dan logrotate.
- Opsi:
  - `--pm2-prod` aktifkan konfigurasi production (default aktif).
  - `--no-pm2-prod` nonaktifkan konfigurasi production (gunakan PM2 start sederhana).
  - `--pm2-cluster` gunakan mode cluster (multi CPU, default aktif).
  - `--pm2-fork` nonaktifkan cluster default (pakai mode fork).
  - `--pm2-instances N|max` tentukan jumlah instance (default `max` saat cluster).

Contoh:

```bash
# Setup app + PM2 production (fork mode default)
sudo bash scripts/install-ubuntu22.sh --app-setup --pm2-prod --pm2-fork --app-dir /opt/aibill-radius

# Cluster gunakan seluruh CPU (default)
sudo bash scripts/install-ubuntu22.sh --app-setup --pm2-prod --app-dir /opt/aibill-radius

# Cluster dengan 4 instance
sudo bash scripts/install-ubuntu22.sh --app-setup --pm2-prod --pm2-instances 4 --app-dir /opt/aibill-radius

# Otomatis clone repo saat `--app-dir` belum ada

Jika direktori aplikasi belum ada di server, gunakan opsi clone agar installer menyalin kode secara otomatis:

```bash
sudo bash scripts/install-ubuntu22.sh \
  --node --mysql --app-setup --pm2-prod \
  --db-name aibill_radius --db-user aibill --db-pass 'StrongPass123' \
  --domain yourdomain.com --app-port 3000 --email admin@yourdomain.com \
  --app-dir /opt/aibill-radius \
  --app-git https://github.com/yourorg/AIBILL-RADIUS.git \
  --app-branch main
```

Catatan:
- Installer memverifikasi `package.json` setelah clone. Jika tidak ditemukan, proses dihentikan dengan error.
- Jika `.env.example` tidak tersedia di repo, installer membuat `.env` minimal otomatis dengan `DATABASE_URL`, `NEXTAUTH_URL`, `NEXT_PUBLIC_APP_URL`, dan `NEXTAUTH_SECRET`.

# Nonaktifkan PM2 production (gunakan PM2 start sederhana)
sudo bash scripts/install-ubuntu22.sh --app-setup --no-pm2-prod --app-dir /opt/aibill-radius
```

Log PM2:
- File: `/var/log/aibill-radius/out.log` dan `/var/log/aibill-radius/error.log`
- Perintah: `pm2 logs aibill-radius --lines 100`

Operasional:
- Status: `pm2 status`
- Restart: `pm2 restart aibill-radius --update-env`
- Simpan untuk autostart: `pm2 save`

### Catatan FreeRADIUS

- Skrip hanya memasang paket `freeradius` dan `freeradius-mysql`.
- Anda perlu mengaktifkan modul `sql` dan menyesuaikan `/etc/freeradius/mods-available/sql` agar FreeRADIUS terhubung ke MySQL aplikasi.
- Pastikan skema tabel RADIUS kompatibel dengan definisi di `prisma/schema.prisma` (radacct, radcheck, radgroupreply, dll.).

#### Integrasi FreeRADIUS ke MySQL aplikasi

```bash
# Pasang FreeRADIUS + freeradius-mysql dan impor skema
sudo bash scripts/install-ubuntu22.sh --freeradius --radius-import-schema \
  --db-name aibill_radius --db-user aibill --db-pass 'StrongPass123'

# Setelah itu, aktifkan modul sql dan set kredensial MySQL
sudo nano /etc/freeradius/mods-available/sql
# Set driver = rlm_sql_mysql, db = aibill_radius, login = aibill, password = StrongPass123, server = localhost

# Enable modul sql bila belum
sudo ln -sf /etc/freeradius/mods-available/sql /etc/freeradius/mods-enabled/sql
sudo systemctl restart freeradius

# Dari aplikasi, Anda bisa trigger restart via API atau util
# src/lib/freeradius.ts -> reloadFreeRadius()
```



Sistem billing modern dan lengkap untuk ISP RTRW.NET dengan penanganan timezone WIB (Waktu Indonesia Barat) yang tepat dan integrasi FreeRADIUS.Sistem billing modern dan lengkap untuk ISP RTRW.NET dengan penanganan timezone WIB (Waktu Indonesia Barat) yang tepat.



## 🎯 Fitur Utama## 🎯 Fitur Utama



- ✅ **Penanganan Timezone WIB yang Benar** - Semua tanggal disimpan dalam UTC, ditampilkan dalam WIB- ✅ **Penanganan Timezone WIB** - Semua tanggal disimpan dalam UTC, ditampilkan dalam WIB

- 🎨 **UI Premium** - Desain responsif mobile-first dengan dark mode- 🎨 **UI Premium** - Desain responsif mobile-first dengan dark mode

- ⚡ **Stack Modern** - Next.js 15, TypeScript, Tailwind CSS, Prisma- ⚡ **Stack Modern** - Next.js 15, TypeScript, Tailwind CSS, Prisma

- 🔐 **Sistem Keamanan Lengkap** - Authentication dengan NextAuth.js dan permission system- 🔐 **Aman** - Struktur autentikasi built-in

- 📱 **SPA Experience** - Navigasi cepat dan smooth tanpa reload halaman- 📱 **SPA Experience** - Navigasi cepat dan smooth tanpa reload halaman

- 🔌 **Integrasi FreeRADIUS** - Terhubung langsung dengan FreeRADIUS server- 🔌 **Integrasi FreeRADIUS** - Terhubung langsung dengan FreeRADIUS server

- 💳 **Payment Gateway** - Mendukung Midtrans, Xendit, dan lainnya- 💳 **Payment Gateway** - Mendukung Midtrans, Xendit, dan lainnya

- 📊 **Laporan Lengkap** - Dashboard, statistik, dan export PDF/Excel- 📊 **Laporan Lengkap** - Dashboard, statistik, dan export PDF/Excel



## 🚀 Tech Stack## 🚀 Tech Stack



- **Framework**: Next.js 15 (App Router)- **Framework**: Next.js 15 (App Router)

- **Bahasa**: TypeScript- **Bahasa**: TypeScript

- **Styling**: Tailwind CSS v4- **Styling**: Tailwind CSS

- **Database**: MySQL dengan Prisma ORM- **Database**: MySQL dengan Prisma ORM

- **Icons**: Lucide React- **Icons**: Lucide React

- **Date Handling**: date-fns dengan dukungan timezone- **Date Handling**: date-fns dengan dukungan timezone

- **Authentication**: NextAuth.js- **Authentication**: NextAuth.js

- **RADIUS**: FreeRADIUS Integration- **RADIUS**: FreeRADIUS Integration

- **Charts**: Recharts

- **Maps**: React Leaflet## 📋 Fitur Lengkap



## 📋 Fitur Lengkap### Modul Admin Panel



### Modul Admin Panel1. **Dashboard** - Overview dengan statistik real-time

2. **Manajemen PPPoE** - User dan profile PPPoE

1. **Dashboard** - Overview dengan statistik real-time3. **Manajemen Hotspot** - Voucher, profile, dan template

2. **Manajemen PPPoE** - User dan profile PPPoE4. **Manajemen Agen** - Akun reseller

3. **Manajemen Hotspot** - Voucher, profile, dan template5. **Invoice** - Billing dan tracking pembayaran

4. **Manajemen Agen** - Akun reseller dengan sistem komisi6. **Payment Gateway** - Multiple metode pembayaran

5. **Invoice** - Billing dan tracking pembayaran7. **Keuangan** - Laporan keuangan

6. **Payment Gateway** - Multiple metode pembayaran (Midtrans, Xendit)8. **Sessions** - Monitoring koneksi aktif

7. **Keuangan** - Laporan keuangan dengan kategori9. **Integrasi WhatsApp** - Notifikasi otomatis

8. **Sessions** - Monitoring koneksi aktif (RADIUS accounting)10. **Manajemen Network** - Konfigurasi Router/NAS

9. **Integrasi WhatsApp** - Notifikasi otomatis via WhatsApp11. **Network Map** - Topologi jaringan visual

10. **Manajemen Network** - Konfigurasi Router/NAS12. **Settings** - Profil perusahaan, cron jobs, GenieACS

11. **Network Map** - Topologi jaringan visual dengan Leaflet

12. **Settings** - Profil perusahaan, cron jobs, GenieACS## 🕐 Penanganan Timezone (Solusi Kritis)



## 🛠️ Panduan InstalasiProject ini menyelesaikan masalah **UTC vs WIB timezone** yang sering menyebabkan error pada billing:



### Persyaratan Sistem### Cara Kerja:



- **OS**: Ubuntu 20.04 / 22.04 LTS (recommended)1. **Penyimpanan Database (UTC)**

- **Node.js**: v18 atau lebih baru   - Semua tanggal disimpan di MySQL sebagai UTC

- **MySQL**: 8.0 atau lebih baru   - Prisma menangani penyimpanan UTC secara otomatis

- **FreeRADIUS**: 3.0 atau lebih baru

- **PM2**: Untuk production deployment2. **Tampilan (WIB)**

   - Frontend mengkonversi UTC ke WIB menggunakan `date-fns-tz`

### 1. Persiapan Server   - Fungsi-fungsi di `src/lib/timezone.ts`:

     - `toWIB()` - Konversi UTC ke WIB untuk tampilan

```bash     - `toUTC()` - Konversi WIB ke UTC untuk penyimpanan

# Update sistem     - `formatWIB()` - Format tanggal dalam WIB

sudo apt update && sudo apt upgrade -y     - `isExpired()` - Cek expired dalam konteks WIB



# Install Node.js (v18+)3. **Konfigurasi Environment**

curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -   ```bash

sudo apt install -y nodejs   TZ="Asia/Jakarta"

   NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"

# Install MySQL Server   ```

sudo apt install -y mysql-server

### Contoh Penggunaan:

# Install FreeRADIUS

sudo apt install -y freeradius freeradius-mysql```typescript

import { formatWIB, isExpired, toUTC } from '@/lib/timezone';

# Install PM2 (untuk production)

sudo npm install -g pm2// Tampilkan tanggal dalam WIB

```const displayDate = formatWIB(user.createdAt, 'dd/MM/yyyy HH:mm');



### 2. Setup Database MySQL// Cek apakah expired (dalam WIB)

const expired = isExpired(user.expiredAt);

```bash

# Masuk ke MySQL// Konversi input user ke UTC sebelum disimpan

sudo mysql -u root -pconst utcDate = toUTC(userInputDate);

await prisma.user.create({ data: { expiredAt: utcDate } });

# Buat database dan user```

CREATE DATABASE aibill_radius CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'aibill'@'localhost' IDENTIFIED BY 'AiBill2024Secure';## 🛠️ Setup Instructions

GRANT ALL PRIVILEGES ON aibill_radius.* TO 'aibill'@'localhost';

FLUSH PRIVILEGES;### 1. Database Setup

EXIT;

```Create MySQL database:

```bash

### 3. Setup FreeRADIUSmysql -u root -p

CREATE DATABASE aibill_radius;

#### 3.1 Konfigurasi MySQL untuk RADIUSexit;

```

```bash

# Edit konfigurasi SQL module### 2. Environment Configuration

sudo nano /etc/freeradius/3.0/mods-available/sql

```Update `.env` with your database credentials:

```env

Ubah konfigurasi berikut:DATABASE_URL="mysql://root:YOUR_PASSWORD@localhost:3306/aibill_radius?connection_limit=10&pool_timeout=20"

TZ="Asia/Jakarta"

```confNEXT_PUBLIC_TIMEZONE="Asia/Jakarta"

sql {```

    driver = "rlm_sql_mysql"

    dialect = "mysql"### 3. Install Dependencies & Setup Database



    server = "localhost"```bash

    port = 3306npm install

    login = "aibill"npx prisma generate

    password = "AiBill2024Secure"npx prisma db push

    radius_db = "aibill_radius"```



    # Table names### 4. FreeRADIUS Integration Setup

    acct_table1 = "radacct"

    acct_table2 = "radacct"**Important**: This app integrates with FreeRADIUS and automatically restarts it when router/NAS configuration changes.

    postauth_table = "radpostauth"

    authcheck_table = "radcheck"#### Setup sudoers permission:

    groupcheck_table = "radgroupcheck"

    authreply_table = "radreply"```bash

    groupreply_table = "radgroupreply"# Run automated setup script

    usergroup_table = "radusergroup"bash scripts/setup-sudoers.sh

    

    read_clients = yes# Or manually:

    client_table = "nas"sudo visudo -f /etc/sudoers.d/freeradius-restart

}```

```

Add this line (replace `gnetid` with your PM2 user):

#### 3.2 Enable SQL Module```

gnetid ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart freeradius

```bashgnetid ALL=(ALL) NOPASSWD: /usr/bin/systemctl status freeradius

# Enable SQL module```

sudo ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

Save and test:

# Edit default site```bash

sudo nano /etc/freeradius/3.0/sites-available/defaultsudo systemctl restart freeradius

``````



Pastikan di section `authorize`, `accounting`, dan `post-auth` sudah ada `sql`:If no password is asked, setup is successful! ✅



```confSee [SUDOERS_SETUP.md](SUDOERS_SETUP.md) for detailed instructions.

authorize {

    preprocess### 5. Run Development Server

    sql

    # ... other modules```bash

}npm run dev

```

accounting {

    sqlOpen [http://localhost:3000](http://localhost:3000) - automatically redirects to `/admin`

    # ... other modules

}### 6. Production Deployment with PM2



post-auth {```bash

    sql# Build the app

    # ... other modulesnpm run build

}

```# Start with PM2

pm2 start npm --name "aibill-radius" -- start

#### 3.3 Restart FreeRADIUS

# Or use ecosystem file (recommended)

```bashpm2 start ecosystem.config.js

# Test konfigurasi```

sudo freeradius -X

## 📁 Project Structure

# Jika tidak ada error, restart service

sudo systemctl restart freeradius```

sudo systemctl enable freeradiussrc/

```├── app/

│   ├── admin/              # Admin panel routes

### 4. Clone dan Setup Project│   │   ├── layout.tsx      # Admin layout with sidebar

│   │   ├── page.tsx        # Dashboard

```bash│   │   ├── pppoe/          # PPPoE management

# Clone project (ganti dengan URL repo Anda)│   │   ├── hotspot/        # Hotspot management

git clone https://github.com/username/aibill-radius.git│   │   └── ...             # Other modules

cd aibill-radius│   └── page.tsx            # Root (redirects to /admin)

├── lib/

# Install dependencies│   ├── timezone.ts         # WIB timezone utilities ⭐

npm install│   └── utils.ts            # General utilities

```└── prisma/

    └── schema.prisma       # Database schema

### 5. Konfigurasi Environment```



```bash## 🎨 UI Components

# Copy file .env.example ke .env

cp .env.example .env- **Sidebar Navigation** - Collapsible, mobile-responsive

- **Stats Cards** - Real-time metrics display

# Edit file .env- **Data Tables** - Sortable, filterable tables

nano .env- **Forms** - With validation and error handling

```- **Modals** - For CRUD operations

- **Dark Mode** - Full dark mode support

Sesuaikan konfigurasi di `.env`:

## 🔒 Security

```env

# Database - MySQL with proper timezone handling- Environment variables for sensitive data

DATABASE_URL="mysql://aibill:AiBill2024Secure@localhost:3306/aibill_radius?connection_limit=10&pool_timeout=20"- Password hashing with bcryptjs

- SQL injection prevention via Prisma

# Timezone - CRITICAL for WIB handling- XSS protection built into Next.js

TZ="Asia/Jakarta"

NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"## 📊 Database Models



# App ConfigurationCore models included:

NEXT_PUBLIC_APP_NAME="AIBILL RADIUS"- Users (Admin, Agent, User roles)

NEXT_PUBLIC_APP_URL="https://billing.yourdomain.com"- PPPoE Users & Profiles

- Hotspot Vouchers & Profiles

# NextAuth- Sessions (RADIUS accounting)

NEXTAUTH_SECRET=aibill-radius-secret-change-in-production-ymQWx6HYvJ/ry9XsRBPkrPzvlCZ6HuNmPtJr/WRnZEw=- Invoices & Payments

NEXTAUTH_URL=https://billing.yourdomain.com- Payment Gateways

```- Routers/NAS

- WhatsApp Providers & Templates

**PENTING**: Generate `NEXTAUTH_SECRET` baru dengan:- Company Settings

```bash

openssl rand -base64 64## 🚧 TODO

```

- [ ] Implement authentication (NextAuth.js)

### 6. Setup Database & Migrasi- [ ] Add API routes for CRUD operations

- [ ] Integrate with RADIUS server

```bash- [ ] Connect payment gateways (Midtrans, Xendit)

# Generate Prisma Client- [ ] WhatsApp API integration

npx prisma generate- [ ] MikroTik API integration

- [ ] GenieACS integration for TR-069

# Push schema ke database (untuk development)- [ ] Add charts and analytics

npx prisma db push- [ ] Export reports (PDF, Excel)

- [ ] Multi-language support

# Atau jalankan migrasi (untuk production)

npx prisma migrate deploy## 🐛 Debugging Timezone Issues



# Seed data awal (admin user, permissions, dll)If you experience timezone issues:

npm run db:seed

```1. **Check environment variables**:

   ```bash

Setelah seeding, Anda bisa login dengan:   echo $TZ

- **Username**: `admin`   # Should output: Asia/Jakarta

- **Password**: `admin123`   ```



**PENTING**: Segera ganti password default setelah login pertama!2. **Verify in code**:

   ```typescript

### 7. Setup Sudoers untuk FreeRADIUS Auto-Restart   import { getTimezoneInfo } from '@/lib/timezone';

   console.log(getTimezoneInfo()); // Should show WIB info

AIBILL dapat otomatis restart FreeRADIUS saat ada perubahan konfigurasi NAS/Router.   ```



```bash3. **Check database timezone**:

# Edit sudoers   ```sql

sudo visudo -f /etc/sudoers.d/freeradius-restart   SELECT @@global.time_zone, @@session.time_zone;

```   ```



Tambahkan baris berikut (ganti `youruser` dengan username Linux Anda):## 📝 License



```Private - Proprietary software for AIBILL RADIUS

youruser ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart freeradius

youruser ALL=(ALL) NOPASSWD: /usr/bin/systemctl status freeradius## 👨‍💻 Development

```

Built with ❤️ for Indonesian ISPs with proper timezone handling.

Simpan dan test:

**Critical Note**: Always use `formatWIB()` and `toWIB()` functions when displaying dates to users. Never display raw UTC dates from database.

```bash
# Test restart tanpa password
sudo systemctl restart freeradius
```

### 8. Jalankan Development Server

```bash
npm run dev
```

Buka browser di [http://localhost:3000](http://localhost:3000)

### 9. Production Deployment dengan PM2

```bash
# Build aplikasi
npm run build

# Start dengan PM2
pm2 start npm --name "aibill-radius" -- start

# Setup auto-start saat reboot
pm2 startup
pm2 save

# Monitor aplikasi
pm2 monit
```

### 10. Setup Nginx (Reverse Proxy)

```bash
# Install Nginx
sudo apt install -y nginx

# Buat konfigurasi
sudo nano /etc/nginx/sites-available/aibill
```

Isi dengan:

```nginx
server {
    listen 80;
    server_name billing.yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/aibill /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 11. Setup SSL dengan Let's Encrypt (Opsional)

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Generate SSL certificate
sudo certbot --nginx -d billing.yourdomain.com

# Auto-renewal sudah setup otomatis oleh certbot
```

## 📁 Struktur Project

```
aibill-radius/
├── src/
│   ├── app/                    # Next.js App Router
│   │   ├── admin/              # Admin panel routes
│   │   ├── api/                # API routes
│   │   └── pay/                # Payment pages
│   ├── components/             # React components
│   │   ├── ui/                 # UI components (shadcn/ui)
│   │   └── ...                 # Feature components
│   ├── lib/                    # Utilities
│   │   ├── timezone.ts         # WIB timezone utilities ⭐
│   │   ├── auth.ts             # NextAuth configuration
│   │   └── prisma.ts           # Prisma client
│   └── middleware.ts           # Next.js middleware
├── prisma/
│   ├── schema.prisma           # Database schema
│   ├── migrations/             # Database migrations
│   └── seeds/                  # Seed data
├── public/                     # Static files
├── .env                        # Environment variables (jangan commit!)
├── .env.example                # Template environment
└── package.json                # Dependencies
```

## 🕐 Penanganan Timezone (Fitur Penting!)

Project ini menyelesaikan masalah **UTC vs WIB** yang sering menyebabkan error billing:

### Cara Kerja:

1. **Database menyimpan sebagai UTC**
   - Semua `DateTime` di Prisma otomatis disimpan sebagai UTC
   - Menghindari masalah timezone saat query

2. **Tampilan menggunakan WIB**
   - Helper functions di `src/lib/timezone.ts`
   - Konversi otomatis UTC → WIB untuk display

3. **Fungsi-fungsi Penting:**

```typescript
import { formatWIB, toWIB, toUTC, isExpired } from '@/lib/timezone';

// Format tanggal untuk tampilan
const tanggal = formatWIB(user.createdAt, 'dd/MM/yyyy HH:mm'); 

// Konversi UTC ke WIB
const wibDate = toWIB(user.createdAt);

// Konversi WIB ke UTC (sebelum simpan ke DB)
const utcDate = toUTC(inputDate);

// Cek expired (timezone-aware)
const isUserExpired = isExpired(user.expiredAt);
```

**PENTING**: Selalu gunakan fungsi-fungsi di atas saat menampilkan atau menyimpan tanggal!

## 🔐 Sistem Permission

AIBILL memiliki sistem permission lengkap:

- **Admin**: Full access
- **Agent**: Terbatas pada fitur reseller
- **User**: View only untuk data sendiri

Lihat dokumentasi lengkap di `docs/PERMISSION_SYSTEM.md`

## 🎨 UI Components

Menggunakan **shadcn/ui** components:

- Sidebar Navigation (collapsible, mobile-responsive)
- Data Tables (sortable, filterable, pagination)
- Forms dengan validation
- Modals & Dialogs
- Dark Mode support
- Toast notifications (SweetAlert2)

## 🔒 Keamanan

- ✅ Environment variables untuk data sensitif
- ✅ Password hashing dengan bcryptjs
- ✅ SQL injection prevention via Prisma
- ✅ XSS protection built-in Next.js
- ✅ CSRF protection
- ✅ Rate limiting pada API endpoints
- ✅ Session management

## 📊 Database Models

Model utama yang tersedia:

- **Users** - Admin, Agent, User roles
- **PppoeUsers & PppoeProfiles** - PPPoE management
- **Vouchers & VoucherProfiles** - Hotspot vouchers
- **Sessions (radacct)** - RADIUS accounting
- **Invoices & Payments** - Billing
- **PaymentGateways** - Gateway configuration
- **NAS/Routers** - Network devices
- **WhatsApp Integration** - Providers & templates
- **Keuangan** - Financial categories & transactions
- **Permissions** - Role-based access control

## 🧪 Testing

```bash
# Test koneksi database
npx prisma db pull

# Test RADIUS connection
radtest username password localhost 0 testing123

# Check logs
pm2 logs aibill-radius
```

## 🐛 Troubleshooting

### 1. Error koneksi database

```bash
# Cek MySQL service
sudo systemctl status mysql

# Cek credentials di .env
cat .env | grep DATABASE_URL
```

### 2. FreeRADIUS tidak terkoneksi

```bash
# Debug mode FreeRADIUS
sudo systemctl stop freeradius
sudo freeradius -X

# Cek table NAS
mysql -u aibill -p aibill_radius -e "SELECT * FROM nas"
```

### 3. Timezone issue

```bash
# Cek timezone server
timedatectl

# Set timezone ke WIB
sudo timedatectl set-timezone Asia/Jakarta

# Restart aplikasi
pm2 restart aibill-radius
```

### 4. Permission denied saat restart FreeRADIUS

```bash
# Cek sudoers
sudo cat /etc/sudoers.d/freeradius-restart

# Test manual
sudo systemctl restart freeradius
```

## 📚 Dokumentasi Tambahan

- [Setup Guide Lengkap](docs/SETUP.md)
- [Sistem Permission](docs/PERMISSION_SYSTEM.md)
- [FreeRADIUS Setup](docs/FREERADIUS-SETUP.md)
- [Isolir Management](docs/PPPOE_STATUS_MANAGEMENT.md)
- [Auto Isolir](docs/AUTO_ISOLIR.md)

## 🚀 Deployment Checklist

- [ ] Ganti password database default
- [ ] Generate NEXTAUTH_SECRET baru
- [ ] Setup domain dan SSL certificate
- [ ] Konfigurasi Nginx reverse proxy
- [ ] Setup PM2 auto-startup
- [ ] Ganti password admin default
- [ ] Konfigurasi payment gateway
- [ ] Setup backup database otomatis
- [ ] Monitoring dengan PM2
- [ ] Setup firewall (UFW)

## 📝 License

Proprietary - Untuk penggunaan pribadi atau komersial dengan lisensi.

## 👨‍💻 Support & Komunitas

Dibuat dengan ❤️ untuk ISP Indonesia dengan penanganan timezone WIB yang benar.

**Bergabung dengan Komunitas:**
- 💬 Telegram Group: [https://t.me/gnetid_aibill](https://t.me/gnetid_aibill)
- 🐛 Report bugs & request features di Telegram group
- 📖 Dokumentasi lengkap tersedia di folder `docs/`

**Catatan Penting**: 
- Selalu gunakan fungsi `formatWIB()` saat menampilkan tanggal
- Backup database secara berkala
- Monitor logs dengan `pm2 logs`
- Update dependencies secara berkala dengan `npm update`

---

**Happy Billing! 🚀**
