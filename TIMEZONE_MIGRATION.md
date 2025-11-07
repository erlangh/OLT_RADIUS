# Timezone Migration Strategy

## 🎯 Goal
Convert entire codebase to use **UTC in backend/database** and **WIB (Asia/Jakarta) in frontend**.

## 📋 Migration Phases

### Phase 1: Setup ✅
- [x] Install `date-fns` and `date-fns-tz`
- [x] Copy timezone utility library to `src/lib/timezone.ts`
- [x] Create migration documentation

### Phase 2: Database Schema (DO NOTHING)
- Schema stays the same: All `DateTime` fields in Prisma
- MySQL will store as UTC when server timezone is UTC
- NO schema changes needed

### Phase 3: Backend Refactoring
Priority files to refactor:

#### High Priority (Critical Business Logic):
1. `src/lib/cron/voucher-sync.ts` - Voucher expiration logic
2. `src/app/api/agent/dashboard/route.ts` - Agent monthly sales
3. `src/app/api/hotspot/agents/route.ts` - Agent stats
4. `src/app/api/dashboard/stats/route.ts` - Admin dashboard stats
5. `src/app/api/invoices/*` - Invoice due date handling

#### Medium Priority:
6. `src/app/api/hotspot/vouchers/validate/route.ts` - Voucher validation
7. `src/app/api/customer/invoices/route.ts` - Customer invoice list
8. `src/app/api/payment/webhook/route.ts` - Payment callbacks
9. All other API routes with date filtering

### Phase 4: Frontend Refactoring
1. `src/app/customer/page.tsx` - Customer dashboard
2. `src/app/pay/[token]/page.tsx` - Payment page
3. `src/app/admin/**/page.tsx` - Admin pages with date display
4. All components displaying dates

### Phase 5: Testing
- [ ] Unit tests for timezone functions
- [ ] Test voucher expiration at midnight WIB
- [ ] Test invoice due date calculations
- [ ] Test agent commission monthly cutoff
- [ ] Test payment webhook timezone handling

## 🔧 Refactoring Patterns

### Pattern 1: Date Display (Frontend/API Response)
```typescript
// BEFORE
const date = new Date(invoice.createdAt);
return date.toLocaleDateString('id-ID');

// AFTER
import { formatWIB } from '@/lib/timezone';
return formatWIB(invoice.createdAt, 'dd MMM yyyy HH:mm');
```

### Pattern 2: Date Comparison (Backend)
```typescript
// BEFORE
const now = new Date();
const currentMonth = now.getMonth();
const isCurrentMonth = saleDate.getMonth() === currentMonth;

// AFTER
import { toWIB, nowWIB } from '@/lib/timezone';
const now = nowWIB();
const currentMonth = now.getMonth();
const saleDate = toWIB(sale.createdAt);
const isCurrentMonth = saleDate.getMonth() === currentMonth;
```

### Pattern 3: Date Range Queries (Backend)
```typescript
// BEFORE
const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
WHERE createdAt >= startOfMonth

// AFTER
import { startOfDayWIBtoUTC, endOfDayWIBtoUTC } from '@/lib/timezone';
const startOfMonth = startOfDayWIBtoUTC(new Date(year, month, 1));
const endOfMonth = endOfDayWIBtoUTC(new Date(year, month + 1, 0));
WHERE createdAt >= startOfMonth AND createdAt <= endOfMonth
```

### Pattern 4: Saving Dates to DB
```typescript
// BEFORE
const dueDate = new Date(input.dueDate);
await prisma.invoice.create({ data: { dueDate } });

// AFTER
import { toUTC } from '@/lib/timezone';
// If input is already in WIB string/Date, convert to UTC
const dueDate = toUTC(input.dueDate);
await prisma.invoice.create({ data: { dueDate } });

// OR if using Prisma @default(now()), it's already UTC
// Just let Prisma handle it
```

### Pattern 5: Expiration Check
```typescript
// BEFORE
const now = new Date();
const isExpired = voucher.expiresAt < now;

// AFTER
import { isExpiredWIB } from '@/lib/timezone';
const isExpired = isExpiredWIB(voucher.expiresAt);
```

### Pattern 6: Raw SQL Queries
```typescript
// BEFORE
WHERE expiresAt < NOW()

// AFTER
// MySQL NOW() returns server timezone, use UTC_TIMESTAMP()
WHERE expiresAt < UTC_TIMESTAMP()

// OR convert to specific timezone
WHERE expiresAt < CONVERT_TZ(NOW(), 'SYSTEM', 'UTC')
```

## ⚠️ Critical Areas

### Voucher Expiration Logic
- File: `src/lib/cron/voucher-sync.ts`
- Issue: Vouchers expire at wrong time if timezone mixed
- Fix: Use UTC for all calculations, convert to WIB for display

### Agent Commission Calculation
- Files: `src/app/api/agent/dashboard/route.ts`, `src/app/api/hotspot/agents/route.ts`
- Issue: Monthly cutoff at wrong time (already fixed in agent dashboard)
- Fix: Get current month in WIB, filter sales by WIB month

### Invoice Due Date
- Files: `src/app/api/invoices/*`, `src/lib/cron/voucher-sync.ts` (invoice reminders)
- Issue: Invoice marked overdue at wrong time
- Fix: Compare due date (UTC) with current WIB time

### RADIUS Accounting
- Table: `radacct` (acctstarttime, acctstoptime)
- Issue: FreeRADIUS stores in server timezone
- Fix: Treat as UTC, convert to WIB for display

## 🗄️ Data Migration (Future)

**Note:** We're doing clean slate - data inconsistency accepted for now.

If needed to fix existing data:
```sql
-- Check server timezone
SELECT @@system_time_zone, @@time_zone;

-- Convert existing WIB data to UTC (if stored as WIB)
UPDATE hotspot_vouchers 
SET expiresAt = CONVERT_TZ(expiresAt, '+07:00', '+00:00')
WHERE expiresAt IS NOT NULL;

UPDATE invoices
SET dueDate = CONVERT_TZ(dueDate, '+07:00', '+00:00'),
    paidAt = CONVERT_TZ(paidAt, '+07:00', '+00:00')
WHERE dueDate IS NOT NULL;

-- Or just re-input data manually for critical records
```

## 📝 Testing Checklist

### Voucher Tests
- [ ] Create voucher → Check createdAt stored as UTC
- [ ] Activate voucher at 23:50 WIB → Check firstLoginAt
- [ ] Voucher expires at midnight WIB → Verify cron marks as EXPIRED at correct time
- [ ] Check voucher list in admin → All dates display in WIB

### Invoice Tests
- [ ] Create invoice with due date → Stored as UTC
- [ ] Due date today (WIB) → Shows correct status
- [ ] Due date tomorrow → Not marked overdue
- [ ] Invoice reminder cron → Sends at correct WIB time

### Agent Tests
- [ ] Agent sells voucher → Recorded with UTC timestamp
- [ ] Check monthly revenue → Calculated in WIB month boundaries
- [ ] Cross midnight test → Sale at 23:59 vs 00:01 WIB different months

### Customer Tests
- [ ] Customer views invoice → Due date shows in WIB
- [ ] Customer pays → paidAt stored as UTC, displayed as WIB
- [ ] Session history → Times shown in WIB

## 🚀 Rollout Plan

1. **Local Development** (1-2 weeks)
   - Refactor all files
   - Test thoroughly
   - Fix bugs

2. **Staging Test** (3-5 days)
   - Deploy to test environment
   - Run parallel with production
   - Compare outputs

3. **Production Deploy** (D-Day)
   - Maintenance window announcement
   - Deploy new code
   - Monitor logs closely
   - Quick rollback plan ready

4. **Post-Deploy** (1 week)
   - Monitor for timezone bugs
   - Fix edge cases
   - Document lessons learned

## 📚 Resources

- Timezone utility: `src/lib/timezone.ts`
- date-fns docs: https://date-fns.org/
- date-fns-tz docs: https://github.com/marnusw/date-fns-tz
- MySQL timezone docs: https://dev.mysql.com/doc/refman/8.0/en/time-zone-support.html

## ✅ Success Criteria

- [ ] No timezone-related bugs in production for 1 week
- [ ] All dates display correctly in WIB for users
- [ ] Voucher expiration works correctly at midnight WIB
- [ ] Invoice reminders sent at correct WIB time
- [ ] Agent commission calculated correctly by WIB month
- [ ] Code is maintainable and consistent
