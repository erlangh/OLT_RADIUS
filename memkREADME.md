# AIBILL RADIUS - Sistem Billing untuk RTRW.NET

Sistem billing modern dan lengkap untuk ISP RTRW.NET dengan penanganan timezone WIB (Waktu Indonesia Barat) yang tepat.

## 🎯 Fitur Utama

- ✅ **Penanganan Timezone WIB** - Semua tanggal disimpan dalam UTC, ditampilkan dalam WIB
- 🎨 **UI Premium** - Desain responsif mobile-first dengan dark mode
- ⚡ **Stack Modern** - Next.js 15, TypeScript, Tailwind CSS, Prisma
- 🔐 **Aman** - Struktur autentikasi built-in
- 📱 **SPA Experience** - Navigasi cepat dan smooth tanpa reload halaman
- 🔌 **Integrasi FreeRADIUS** - Terhubung langsung dengan FreeRADIUS server
- 💳 **Payment Gateway** - Mendukung Midtrans, Xendit, dan lainnya
- 📊 **Laporan Lengkap** - Dashboard, statistik, dan export PDF/Excel

## 🚀 Tech Stack

- **Framework**: Next.js 15 (App Router)
- **Bahasa**: TypeScript
- **Styling**: Tailwind CSS
- **Database**: MySQL dengan Prisma ORM
- **Icons**: Lucide React
- **Date Handling**: date-fns dengan dukungan timezone
- **Authentication**: NextAuth.js
- **RADIUS**: FreeRADIUS Integration

## 📋 Fitur Lengkap

### Modul Admin Panel

1. **Dashboard** - Overview dengan statistik real-time
2. **Manajemen PPPoE** - User dan profile PPPoE
3. **Manajemen Hotspot** - Voucher, profile, dan template
4. **Manajemen Agen** - Akun reseller
5. **Invoice** - Billing dan tracking pembayaran
6. **Payment Gateway** - Multiple metode pembayaran
7. **Keuangan** - Laporan keuangan
8. **Sessions** - Monitoring koneksi aktif
9. **Integrasi WhatsApp** - Notifikasi otomatis
10. **Manajemen Network** - Konfigurasi Router/NAS
11. **Network Map** - Topologi jaringan visual
12. **Settings** - Profil perusahaan, cron jobs, GenieACS

## 🕐 Penanganan Timezone (Solusi Kritis)

Project ini menyelesaikan masalah **UTC vs WIB timezone** yang sering menyebabkan error pada billing:

### Cara Kerja:

1. **Penyimpanan Database (UTC)**
   - Semua tanggal disimpan di MySQL sebagai UTC
   - Prisma menangani penyimpanan UTC secara otomatis

2. **Tampilan (WIB)**
   - Frontend mengkonversi UTC ke WIB menggunakan `date-fns-tz`
   - Fungsi-fungsi di `src/lib/timezone.ts`:
     - `toWIB()` - Konversi UTC ke WIB untuk tampilan
     - `toUTC()` - Konversi WIB ke UTC untuk penyimpanan
     - `formatWIB()` - Format tanggal dalam WIB
     - `isExpired()` - Cek expired dalam konteks WIB

3. **Konfigurasi Environment**
   ```bash
   TZ="Asia/Jakarta"
   NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"
   ```

### Contoh Penggunaan:

```typescript
import { formatWIB, isExpired, toUTC } from '@/lib/timezone';

// Tampilkan tanggal dalam WIB
const displayDate = formatWIB(user.createdAt, 'dd/MM/yyyy HH:mm');

// Cek apakah expired (dalam WIB)
const expired = isExpired(user.expiredAt);

// Konversi input user ke UTC sebelum disimpan
const utcDate = toUTC(userInputDate);
await prisma.user.create({ data: { expiredAt: utcDate } });
```

## 🛠️ Setup Instructions

### 1. Database Setup

Create MySQL database:
```bash
mysql -u root -p
CREATE DATABASE aibill_radius;
exit;
```

### 2. Environment Configuration

Update `.env` with your database credentials:
```env
DATABASE_URL="mysql://root:YOUR_PASSWORD@localhost:3306/aibill_radius?connection_limit=10&pool_timeout=20"
TZ="Asia/Jakarta"
NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"
```

### 3. Install Dependencies & Setup Database

```bash
npm install
npx prisma generate
npx prisma db push
```

### 4. FreeRADIUS Integration Setup

**Important**: This app integrates with FreeRADIUS and automatically restarts it when router/NAS configuration changes.

#### Setup sudoers permission:

```bash
# Run automated setup script
bash scripts/setup-sudoers.sh

# Or manually:
sudo visudo -f /etc/sudoers.d/freeradius-restart
```

Add this line (replace `gnetid` with your PM2 user):
```
gnetid ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart freeradius
gnetid ALL=(ALL) NOPASSWD: /usr/bin/systemctl status freeradius
```

Save and test:
```bash
sudo systemctl restart freeradius
```

If no password is asked, setup is successful! ✅

See [SUDOERS_SETUP.md](SUDOERS_SETUP.md) for detailed instructions.

### 5. Run Development Server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) - automatically redirects to `/admin`

### 6. Production Deployment with PM2

```bash
# Build the app
npm run build

# Start with PM2
pm2 start npm --name "aibill-radius" -- start

# Or use ecosystem file (recommended)
pm2 start ecosystem.config.js
```

## 📁 Project Structure

```
src/
├── app/
│   ├── admin/              # Admin panel routes
│   │   ├── layout.tsx      # Admin layout with sidebar
│   │   ├── page.tsx        # Dashboard
│   │   ├── pppoe/          # PPPoE management
│   │   ├── hotspot/        # Hotspot management
│   │   └── ...             # Other modules
│   └── page.tsx            # Root (redirects to /admin)
├── lib/
│   ├── timezone.ts         # WIB timezone utilities ⭐
│   └── utils.ts            # General utilities
└── prisma/
    └── schema.prisma       # Database schema
```

## 🎨 UI Components

- **Sidebar Navigation** - Collapsible, mobile-responsive
- **Stats Cards** - Real-time metrics display
- **Data Tables** - Sortable, filterable tables
- **Forms** - With validation and error handling
- **Modals** - For CRUD operations
- **Dark Mode** - Full dark mode support

## 🔒 Security

- Environment variables for sensitive data
- Password hashing with bcryptjs
- SQL injection prevention via Prisma
- XSS protection built into Next.js

## 📊 Database Models

Core models included:
- Users (Admin, Agent, User roles)
- PPPoE Users & Profiles
- Hotspot Vouchers & Profiles
- Sessions (RADIUS accounting)
- Invoices & Payments
- Payment Gateways
- Routers/NAS
- WhatsApp Providers & Templates
- Company Settings

## 🚧 TODO

- [ ] Implement authentication (NextAuth.js)
- [ ] Add API routes for CRUD operations
- [ ] Integrate with RADIUS server
- [ ] Connect payment gateways (Midtrans, Xendit)
- [ ] WhatsApp API integration
- [ ] MikroTik API integration
- [ ] GenieACS integration for TR-069
- [ ] Add charts and analytics
- [ ] Export reports (PDF, Excel)
- [ ] Multi-language support

## 🐛 Debugging Timezone Issues

If you experience timezone issues:

1. **Check environment variables**:
   ```bash
   echo $TZ
   # Should output: Asia/Jakarta
   ```

2. **Verify in code**:
   ```typescript
   import { getTimezoneInfo } from '@/lib/timezone';
   console.log(getTimezoneInfo()); // Should show WIB info
   ```

3. **Check database timezone**:
   ```sql
   SELECT @@global.time_zone, @@session.time_zone;
   ```

## 📝 License

Private - Proprietary software for AIBILL RADIUS

## 👨‍💻 Development

Built with ❤️ for Indonesian ISPs with proper timezone handling.

**Critical Note**: Always use `formatWIB()` and `toWIB()` functions when displaying dates to users. Never display raw UTC dates from database.
