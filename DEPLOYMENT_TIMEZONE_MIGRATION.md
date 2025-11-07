# Deployment: Timezone Migration (WIB → UTC)

## Pre-Deployment Status

### Production Server Discovery
- **Server**: 10.100.0.232
- **System Timezone**: Asia/Jakarta (WIB, +0700)
- **MySQL Timezone**: SYSTEM (= WIB)
- **Current Data**: Stored in WIB format

### Data Inventory
```
Invoices (unpaid):      36
Vouchers (WAITING):     264
Vouchers (ACTIVE):      13
PPPoE Users (active):   59
Agent Sales:            19
Cron History:           6992
```

### Critical Finding
⚠️ **Production DB stores dates in WIB, but our refactored code expects UTC!**

**Impact if deployed without migration:**
- All dates will display **+7 hours wrong**
- Example: Voucher expires at 23:45 WIB → will show 06:45 next day
- Invoice due Nov 6 → will show Nov 6 07:00 (wrong interpretation)

---

## Deployment Plan

### Step 1: Stop Application (Downtime Start)
```bash
ssh root@10.100.0.232
cd /root/aibill
pm2 stop ecosystem.config.js
```

**Expected downtime**: 5-10 minutes

---

### Step 2: Run Migration Script
```bash
# Upload migration script
rsync -avz --progress scripts/migrate-timezone-wib-to-utc.ts root@10.100.0.232:/root/aibill/scripts/

# Run migration
ssh root@10.100.0.232 "cd /root/aibill && npx tsx scripts/migrate-timezone-wib-to-utc.ts"
```

**What it does:**
1. ✅ Validates current timezone is WIB
2. 📸 Takes samples of existing data for validation
3. ⚙️ Sets MySQL timezone to UTC (`SET GLOBAL time_zone = '+00:00'`)
4. 🔄 Converts ALL DateTime columns: `CONVERT_TZ(datetime, '+07:00', '+00:00')`
   - invoices: createdAt, updatedAt, dueDate
   - hotspot_vouchers: createdAt, updatedAt, firstLoginAt, expiresAt
   - pppoe_users: createdAt, updatedAt, expiredAt, lastConnectedAt
   - customers: createdAt, updatedAt
   - users: createdAt, updatedAt
   - agent_sales: createdAt, saleDate
   - transactions: createdAt, updatedAt, transactionDate
   - cron_history: executedAt
   - notifications: createdAt, readAt
   - audit_logs: createdAt
   - radacct: acctstarttime, acctupdatetime, acctstoptime
   - radpostauth: authdate
5. ✅ Validates conversion succeeded
6. 📊 Shows summary report

**Expected output:**
```
======================================================================
  MIGRATION SUMMARY
======================================================================

✅ Migration completed successfully!

Next steps:
  1. Verify application behavior in production
  2. Deploy updated code with timezone refactor
  3. Monitor logs for any timezone-related issues
```

---

### Step 3: Deploy Refactored Code
```bash
# From local dev machine
cd /home/gnetid/Music/AIBILL-PROD/aibill

# Sync refactored files
rsync -avz --progress \
  --exclude 'node_modules' \
  --exclude '.next' \
  --exclude 'backups' \
  --exclude 'logs' \
  src/lib/timezone.ts \
  src/lib/utils/dateUtils.ts \
  src/app/api/agent/dashboard/route.ts \
  src/app/api/hotspot/agents/route.ts \
  src/app/api/dashboard/stats/route.ts \
  src/lib/cron/voucher-sync.ts \
  src/app/admin/pppoe/users/page.tsx \
  root@10.100.0.232:/root/aibill/
```

---

### Step 4: Install Dependencies (if needed)
```bash
ssh root@10.100.0.232 "cd /root/aibill && npm install date-fns date-fns-tz"
```

---

### Step 5: Rebuild Next.js
```bash
ssh root@10.100.0.232 "cd /root/aibill && npm run build"
```

**Expected**: Build should succeed with no errors

---

### Step 6: Start Application (Downtime End)
```bash
ssh root@10.100.0.232 "cd /root/aibill && pm2 start ecosystem.config.js"
```

---

### Step 7: Verification & Smoke Tests

#### Test 1: Check MySQL Timezone
```bash
ssh root@10.100.0.232 "mysql -uaibill -pAiBill2024Secure aibill_radius -e \"
SELECT @@global.time_zone, @@session.time_zone;
SELECT NOW(), UTC_TIMESTAMP();
\""
```

**Expected:**
```
global_tz    session_tz
+00:00       +00:00

NOW()                UTC_TIMESTAMP()
2025-11-03 16:55:09  2025-11-03 16:55:09  (same, both UTC)
```

#### Test 2: Check Sample Voucher Display
- Login to admin panel: https://your-domain.com/admin
- Go to Vouchers page
- Check voucher **QXVP** (or any ACTIVE voucher):
  - firstLoginAt should show **23:42 WIB** (not 06:42)
  - expiresAt should show correct WIB time

#### Test 3: Check Invoice Display
- Go to Invoices page
- Check unpaid invoices:
  - Due dates should display in WIB
  - Created dates should display in WIB

#### Test 4: Create New Voucher
- Create a new voucher
- Activate it immediately
- Check if createdAt and firstLoginAt show correct WIB time

#### Test 5: Check Dashboard Stats
- Go to Admin Dashboard
- Check monthly revenue/stats
- Numbers should match previous day (no data loss)

---

## Rollback Plan (If Issues Occur)

### Option A: Quick Rollback (Restore from backup)
```bash
ssh root@10.100.0.232

# Stop app
pm2 stop ecosystem.config.js

# Restore database
mysql -uaibill -pAiBill2024Secure aibill_radius < /path/to/backup.sql

# Verify timezone restored
mysql -uaibill -pAiBill2024Secure aibill_radius -e "SELECT @@global.time_zone;"

# Start app
pm2 start ecosystem.config.js
```

### Option B: Revert Code Only
```bash
# From local dev machine
cd /home/gnetid/Music/AIBILL-PROD/aibill

# Revert to old dateUtils.ts (if you kept backup)
rsync -avz --progress \
  src/lib/utils/dateUtils.ts.old \
  root@10.100.0.232:/root/aibill/src/lib/utils/dateUtils.ts

# Rebuild and restart
ssh root@10.100.0.232 "cd /root/aibill && npm run build && pm2 restart ecosystem.config.js"
```

---

## Success Criteria

✅ **Migration succeeded if:**
1. MySQL timezone = `+00:00` (UTC)
2. Sample voucher displays correct WIB time (not +7 hours off)
3. New vouchers created show correct WIB time
4. Dashboard stats match previous values
5. No errors in PM2 logs: `pm2 logs aibill --lines 50`

❌ **Migration failed if:**
1. Dates display +7 or -7 hours wrong
2. Build errors occur
3. Application crashes (check `pm2 logs`)
4. Database queries fail

---

## Post-Deployment Monitoring

### Check PM2 Logs
```bash
ssh root@10.100.0.232 "pm2 logs aibill --lines 100"
```

Look for:
- ✅ No timezone-related errors
- ✅ Cron jobs running successfully
- ✅ API responses successful

### Check Cron Jobs
```bash
ssh root@10.100.0.232 "mysql -uaibill -pAiBill2024Secure aibill_radius -e \"
SELECT * FROM cron_history ORDER BY executedAt DESC LIMIT 5;
\""
```

**Expected**: executedAt should be in UTC (7 hours behind WIB wall clock)

### Monitor for 24 Hours
- Check voucher expiration (should expire at correct time)
- Check invoice due date reminders (should trigger at correct time)
- Check agent dashboard stats (monthly boundaries should be correct)

---

## Files Modified

### New Files
- `src/lib/timezone.ts` - Core timezone utility library
- `scripts/migrate-timezone-wib-to-utc.ts` - Migration script

### Modified Files
- `src/lib/utils/dateUtils.ts` - Refactored to use timezone.ts
- `src/app/api/agent/dashboard/route.ts` - Use nowWIB()
- `src/app/api/hotspot/agents/route.ts` - Use nowWIB()
- `src/app/api/dashboard/stats/route.ts` - Use WIB boundaries
- `src/lib/cron/voucher-sync.ts` - Updated comments, NOW() → UTC_TIMESTAMP()
- `src/app/admin/pppoe/users/page.tsx` - Import fix

### Database Changes
- MySQL global timezone: SYSTEM → `+00:00`
- All DateTime columns: converted from WIB to UTC (-7 hours)

---

## Expected Timeline

```
00:00  Stop application (downtime starts)
00:01  Run migration script
00:03  Migration completes, validated
00:04  Deploy refactored code
00:05  Rebuild Next.js
00:07  Start application (downtime ends)
00:08  Run smoke tests
00:10  Monitor logs
00:15  Deployment complete ✅
```

**Total downtime**: ~7-10 minutes

---

## Contact & Support

**If issues occur:**
1. Check PM2 logs: `pm2 logs aibill`
2. Check migration summary output
3. Verify MySQL timezone: `SELECT @@global.time_zone`
4. Restore from backup if critical

**Migration script provides:**
- Automatic validation before/after
- Sample data comparison
- Rollback instructions
- Detailed error messages

---

## Sign-Off Checklist

Before deployment:
- [ ] VM backup completed
- [ ] Database backup completed
- [ ] Migration script tested on dev/staging
- [ ] Team notified of maintenance window
- [ ] Rollback plan reviewed

During deployment:
- [ ] Application stopped
- [ ] Migration script completed successfully
- [ ] Code deployed
- [ ] Dependencies installed
- [ ] Build succeeded
- [ ] Application started

After deployment:
- [ ] MySQL timezone verified (UTC)
- [ ] Sample data displays correctly (WIB)
- [ ] New voucher creation works
- [ ] Dashboard stats correct
- [ ] PM2 logs clean
- [ ] Cron jobs running

---

## Notes

- This is a **ONE-TIME migration** from WIB to UTC storage
- After migration, ALL new data will be stored in UTC automatically
- Frontend will continue to display in WIB (Asia/Jakarta)
- No code changes needed in the future for timezone handling
- Best practice achieved: UTC backend + WIB frontend ✅
