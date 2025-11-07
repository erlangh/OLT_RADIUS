# FreeRADIUS Sudoers Setup

Untuk mengizinkan aplikasi (running di PM2) restart FreeRADIUS tanpa password, tambahkan konfigurasi sudoers.

## Setup Steps

### 1. Cek user PM2
```bash
whoami
# Contoh output: gnetid
```

### 2. Buat file sudoers untuk FreeRADIUS
```bash
sudo visudo -f /etc/sudoers.d/freeradius-restart
```

### 3. Tambahkan konfigurasi (ganti `gnetid` dengan user PM2 Anda)
```
# Allow PM2 user to restart FreeRADIUS without password
gnetid ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart freeradius
gnetid ALL=(ALL) NOPASSWD: /usr/bin/systemctl status freeradius
```

### 4. Set permission file sudoers
```bash
sudo chmod 440 /etc/sudoers.d/freeradius-restart
```

### 5. Test restart tanpa password
```bash
sudo systemctl restart freeradius
sudo systemctl status freeradius
```

Jika tidak diminta password, setup sudah berhasil! ✅

## Verifikasi

Setelah deploy aplikasi dengan PM2, coba operasi router (create/update/delete) dan cek log:

```bash
pm2 logs aibill-radius --lines 50
```

Harusnya muncul log:
```
FreeRADIUS restarted successfully
```

## Troubleshooting

### Error: "sudo: no tty present and no askpass program specified"
- File sudoers belum dibuat atau permission salah
- Cek ulang langkah 2-4

### Error: "Failed to restart freeradius"
- FreeRADIUS belum terinstall
- Service name salah (coba `radiusd` atau `freeradius.service`)

### Cek service name FreeRADIUS
```bash
sudo systemctl list-units --type=service | grep -i radius
```

Jika service name berbeda (misalnya `radiusd`), update file:
`src/lib/freeradius.ts` pada baris 27:
```typescript
const { stdout, stderr } = await execAsync('sudo systemctl restart radiusd', {
```

## Security Note

Setup ini **HANYA** mengizinkan restart FreeRADIUS, bukan full sudo access. Ini aman untuk production.
