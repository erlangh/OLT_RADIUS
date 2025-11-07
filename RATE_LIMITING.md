# WhatsApp Rate Limiting Implementation

## 📋 Overview

Sistem rate limiting untuk mencegah WhatsApp API banned saat mengirim pesan broadcast dalam jumlah banyak (ratusan/ribuan user).

**Default Config:**
- **5 messages per 10 seconds** = 30 msg/minute = 1800 msg/hour
- Untuk 1000 user: ~33 menit
- Untuk 100 user: ~3.3 menit

---

## 🎯 Fitur

### 1. **Batch Processing**
- Otomatis split messages menjadi batch (5 msg/batch)
- Delay 10 detik antar batch
- Delay 0.5 detik antar message dalam 1 batch

### 2. **Progress Tracking**
- Real-time console logging
- Progress counter: "15/100 messages sent"
- Batch counter: "Batch 3/20"

### 3. **Error Handling**
- Individual message error tidak stop keseluruhan proses
- Detailed error reporting per message
- Retry logic di level provider (WhatsAppService failover)

### 4. **Time Estimation**
- Estimasi waktu sebelum mulai kirim
- Format human-readable: "33 menit", "1 jam 15 menit"

---

## 📁 Files Modified

### 1. **`src/lib/utils/rateLimiter.ts`** (NEW)
Core rate limiting utility dengan:
- `sendWithRateLimit()` - Main function untuk batch sending
- `estimateSendTime()` - Calculate estimated time
- `formatEstimatedTime()` - Format ke human-readable
- Configurable parameters

### 2. **`src/lib/cron/voucher-sync.ts`**
Function: `sendInvoiceReminders()`
- Replace direct loop dengan `sendWithRateLimit()`
- Add progress logging
- Batch processing untuk invoice reminders

### 3. **`src/app/api/whatsapp/broadcast/route.ts`**
Endpoint: `POST /api/whatsapp/broadcast`
- Replace hardcoded delay dengan rate limiter
- Better error handling
- Return estimated time di response

---

## 🚀 Usage Examples

### Example 1: Invoice Reminder (Automatic)
```typescript
// Cron job setiap jam
// Otomatis kirim reminder dengan rate limiting
await sendInvoiceReminders()

// Console output:
// [RateLimiter] Starting batch send: 150 messages in 30 batches
// [RateLimiter] Estimated time: 5 menit
// [RateLimiter] Batch 1/30: Processing 5 messages
// [Invoice Reminder] Progress: 5/150 (Batch 1/30)
// [RateLimiter] ⏳ Waiting 10000ms before next batch...
```

### Example 2: Manual Broadcast (Admin)
```typescript
// POST /api/whatsapp/broadcast
{
  "userIds": ["id1", "id2", ... "id1000"],
  "message": "Halo {{customerName}}..."
}

// Response:
{
  "success": true,
  "total": 1000,
  "successCount": 998,
  "failCount": 2,
  "estimatedTime": "33 menit",
  "results": [...]
}
```

---

## ⚙️ Configuration

### Default Settings
```typescript
const DEFAULT_CONFIG = {
  messagesPerBatch: 5,        // 5 messages per batch
  delayBetweenBatches: 10000, // 10 seconds between batches
  delayBetweenMessages: 500,   // 0.5 seconds between messages in batch
}
```

### Custom Configuration
```typescript
// Override default config
await sendWithRateLimit(
  messages,
  sendFunction,
  {
    messagesPerBatch: 10,       // Send 10 per batch (faster)
    delayBetweenBatches: 5000,  // 5 seconds delay (faster but risky)
    delayBetweenMessages: 200,  // 0.2 seconds (faster)
  }
)
```

### ⚠️ Recommended Limits by Provider

| Provider | Safe Rate | Risky Rate | Note |
|----------|-----------|------------|------|
| **Fonnte** | 5/10sec | 10/10sec | Free plan limited |
| **WAHA** | 10/10sec | 20/10sec | Self-hosted, more flexible |
| **MPWA** | 5/10sec | 10/10sec | Official API |
| **Wablas** | 10/10sec | 15/10sec | Paid plan |

**Default 5/10sec** adalah safe untuk semua provider.

---

## 🔍 Testing

### Test dengan Invoice Kecil
```bash
# 1. Buat test invoices (5-10 invoice)
# 2. Set reminder schedule
# 3. Trigger cron manual
npm run cron:test

# Expected output:
# [Invoice Reminder] Found 10 invoices for H-7
# [RateLimiter] Starting batch send: 10 messages in 2 batches
# [RateLimiter] Estimated time: 10 detik
# [Invoice Reminder] Progress: 5/10 (Batch 1/2)
# [RateLimiter] ⏳ Waiting 10000ms before next batch...
# [Invoice Reminder] Progress: 10/10 (Batch 2/2)
# [RateLimiter] ✅ Completed: 10 sent, 0 failed
```

### Test Broadcast Manual
```bash
# Di admin dashboard:
# 1. WhatsApp → Send Message → Broadcast
# 2. Pilih 10-20 users
# 3. Ketik message dan send
# 4. Monitor console log di terminal
```

---

## 📊 Performance Comparison

### Before Rate Limiting
```
1000 users = langsung kirim semua
Duration: 2-5 menit (depending on API response)
Risk: HIGH - banned potential
Error rate: Variable
```

### After Rate Limiting
```
1000 users = 200 batches × 10sec
Duration: ~33 menit (predictable)
Risk: LOW - safe rate
Error rate: Lower (dengan failover)
```

---

## 🛡️ Safety Features

### 1. **Tidak Ganggu Single Message**
Rate limiter **HANYA** untuk bulk sending:
- ✅ Invoice reminder cron (ratusan invoice)
- ✅ Manual broadcast (banyak user)

Tetap **INSTANT** untuk:
- ✅ Payment success notification (1 user)
- ✅ Manual send reminder (1 invoice)
- ✅ Admin create user (1 user)
- ✅ Voucher purchase (1 transaksi)

### 2. **Failover Protection**
- WhatsAppService tetap try multiple providers
- Jika provider1 gagal → auto try provider2
- Rate limiting di level batch, bukan provider

### 3. **Error Isolation**
- 1 message gagal tidak stop batch
- Detailed error logging per message
- Return success/fail count

---

## 📝 Monitoring

### Console Logs
```bash
# Invoice reminder cron
[Invoice Reminder] Processing 3 reminder schedules...
[Invoice Reminder] Found 150 invoices for H-7
[RateLimiter] Starting batch send: 150 messages in 30 batches
[RateLimiter] Estimated time: 5 menit
[Invoice Reminder] Progress: 5/150 (Batch 1/30)
[RateLimiter] ✅ Sent 1/150: 628123456789
[RateLimiter] ⏳ Waiting 10000ms before next batch...
[Invoice Reminder] Batch H-7 completed: 148 sent, 2 failed

# Broadcast API
[Broadcast] Sending to 1000 users (5 skipped - no phone)
[Broadcast] Estimated time: 33 menit
[Broadcast] Progress: 50/1000 (Batch 10/200)
```

### Database Logs
Check `cron_history` table:
```sql
SELECT * FROM cronHistory 
WHERE jobType = 'invoice_reminder' 
ORDER BY startedAt DESC 
LIMIT 10;
```

---

## 🔧 Troubleshooting

### Issue: Masih kena banned
**Solution:** Turunkan rate
```typescript
{
  messagesPerBatch: 3,        // 3 msg per batch (lebih aman)
  delayBetweenBatches: 15000, // 15 seconds delay
}
```

### Issue: Terlalu lambat
**Solution:** Naikkan rate (hati-hati!)
```typescript
{
  messagesPerBatch: 10,       // 10 msg per batch
  delayBetweenBatches: 5000,  // 5 seconds delay
}
```

### Issue: Stuck di tengah jalan
**Solution:** Cek console logs
- Pastikan tidak ada error di WhatsAppService
- Cek provider API status
- Restart PM2 jika perlu

---

## 🎯 Best Practices

1. **Gunakan Default Config** (5/10sec) untuk production
2. **Test dengan user kecil** (10-20) sebelum deploy
3. **Monitor console logs** saat broadcast besar
4. **Jangan override config** tanpa testing
5. **Backup WhatsApp provider** (minimum 2 provider aktif)

---

## 📈 Future Improvements

- [ ] Queue system dengan Redis untuk distributed processing
- [ ] Pause/Resume functionality untuk long-running batch
- [ ] Web dashboard untuk monitor progress real-time
- [ ] Per-provider rate limit config
- [ ] Retry failed messages automatically
- [ ] Schedule broadcast untuk waktu tertentu

---

## 📞 Support

Jika ada issue atau pertanyaan:
1. Cek console logs di terminal
2. Cek `cron_history` di database
3. Cek `whatsapp_logs` table untuk detail message
4. Test dengan user kecil dulu

---

## ✅ Summary

**What Changed:**
- ✅ Added rate limiter utility (5 msg/10sec)
- ✅ Updated invoice reminder cron with batch processing
- ✅ Updated broadcast API with rate limiting
- ✅ Added progress tracking and time estimation
- ✅ Better error handling and logging

**What Didn't Change:**
- ✅ Single message sending (tetap instant)
- ✅ WhatsAppService failover logic
- ✅ Payment notifications (tetap real-time)
- ✅ Manual single invoice reminder (tetap instant)

**Result:**
- 🚀 **Safe** - No more banned risk
- ⏱️ **Predictable** - Know estimated time upfront
- 📊 **Monitored** - Real-time progress tracking
- 🛡️ **Robust** - Error isolation + failover
