# AIBILL RADIUS - Core Modules Documentation

## 📋 Overview
AIBILL RADIUS adalah sistem billing berbasis FreeRADIUS untuk manajemen ISP dengan fokus pada PPPoE dan Hotspot.

**Tech Stack:**
- **Frontend:** Next.js 16, React 19, TailwindCSS 4
- **Backend:** Next.js API Routes (Serverless)
- **Database:** MySQL + Prisma ORM
- **RADIUS:** FreeRADIUS 3.x
- **Network:** MikroTik RouterOS API (node-routeros)

---

## 🎯 Core Modules

### 1. PPPoE Management Module

#### **Features:**
✅ User management dengan customer data lengkap (nama, telpon, alamat, GPS)
✅ Profile-based billing (speed, harga, validity period)
✅ Static IP & MAC binding support
✅ Auto-sync ke FreeRADIUS tables
✅ Expiry date management
✅ Router/NAS assignment per user
✅ Session tracking & accounting

#### **Database Schema:**

**PppoeUser:**
```prisma
- username, password (credentials)
- profile (relation to PppoeProfile)
- router (optional NAS assignment)
- name, phone, email, address (customer info)
- latitude, longitude (GPS mapping)
- status (active/suspended/expired)
- ipAddress, macAddress (optional binding)
- syncedToRadius, lastSyncAt (sync status)
- expiredAt (subscription expiry)
```

**PppoeProfile:**
```prisma
- name, description
- groupName (RADIUS group - must match MikroTik profile)
- price (IDR)
- downloadSpeed, uploadSpeed (Mbps)
- validityValue, validityUnit (duration)
- syncedToRadius, lastSyncAt
```

#### **API Endpoints:**

**GET /api/pppoe/users**
- List semua PPPoE users dengan profile & router info
- Include relations: `profile`, `router`

**POST /api/pppoe/users**
- Create user baru
- Auto-calculate expiry date
- Auto-sync ke FreeRADIUS:
  - `radcheck`: Cleartext-Password
  - `radusergroup`: username → groupName
  - `radreply`: Framed-IP-Address (jika static IP)
- Return status sync

**PUT /api/pppoe/users**
- Update user data & credentials
- Re-sync ke RADIUS jika password/profile berubah

**POST /api/pppoe/users/bulk**
- Bulk create users (batch import)

**POST /api/pppoe/users/status**
- Toggle status (active/suspended)
- Update RADIUS accordingly

**POST /api/pppoe/users/bulk-status**
- Bulk status update

#### **RADIUS Integration:**
```
User Creation Flow:
1. Insert ke `pppoe_users` (aplikasi)
2. Insert ke `radcheck` (password)
3. Insert ke `radusergroup` (assign group)
4. Insert ke `radreply` (optional: static IP)
5. Mark syncedToRadius = true
```

---

### 2. Hotspot Management Module

#### **Features:**
✅ Voucher generation (bulk/single)
✅ Profile-based pricing (cost, reseller fee, selling price)
✅ Multi-validity (minutes/hours/days/months)
✅ Batch management
✅ Auto-sync ke RADIUS per voucher
✅ Status tracking (WAITING/ACTIVE/EXPIRED)
✅ Agent/reseller support
✅ WhatsApp integration untuk kirim voucher
✅ Template voucher (HTML/PDF)

#### **Database Schema:**

**HotspotVoucher:**
```prisma
- code (unique voucher code)
- batchCode (group identifier)
- profile (relation to HotspotProfile)
- status (WAITING/ACTIVE/EXPIRED)
- firstLoginAt (first use timestamp)
- expiresAt (calculated expiry)
- lastUsedBy (MAC/IP tracking)
```

**HotspotProfile:**
```prisma
- name
- costPrice, resellerFee, sellingPrice
- speed (format: "5M/5M")
- groupProfile (MikroTik user profile name)
- sharedUsers (concurrent users limit)
- validityValue, validityUnit
- agentAccess, eVoucherAccess (permissions)
```

**VoucherTemplate:**
```prisma
- name (template name)
- htmlTemplate (Smarty syntax template)
- isDefault, isActive
```

**Agent & AgentSale:**
```prisma
Agent:
  - name, phone, email, address
  - isActive
  
AgentSale:
  - agent (relation)
  - voucherCode, profileName
  - amount (sale price)
  - createdAt (sale timestamp)
```

#### **API Endpoints:**

**GET /api/hotspot/voucher**
- List vouchers dengan filter (profileId, batchCode, status)
- Include profile info
- Return unique batch codes
- Limit 1000 records

**POST /api/hotspot/voucher**
- Generate vouchers (max 500 per batch)
- Auto-generate batch code: `BATCH-YYYYMMDD-HHMM`
- Customizable: quantity, profileId, codeLength, prefix
- Auto-sync ke RADIUS setelah generate
- Return: count, batchCode, message

**DELETE /api/hotspot/voucher**
- Delete single voucher atau batch
- Hanya delete status WAITING
- Auto-remove dari RADIUS

**POST /api/hotspot/voucher/resync**
- Re-sync vouchers ke RADIUS
- Useful setelah RADIUS crash

**POST /api/hotspot/voucher/send-whatsapp**
- Kirim voucher via WhatsApp
- Include voucher details & template

**POST /api/hotspot/voucher/delete-expired**
- Bulk delete expired vouchers
- Cron job endpoint

**GET /api/hotspot/profiles**
- List hotspot profiles
- Include price calculation

**POST /api/hotspot/profiles**
- Create profile baru

**GET /api/hotspot/agents**
- List agents dengan sales history

**POST /api/hotspot/agents**
- Create agent baru

**GET /api/hotspot/agents/[id]/history**
- Sales history per agent

**POST /api/agent/generate-voucher**
- Agent endpoint untuk generate voucher
- Auto-record ke AgentSale

**POST /api/evoucher/purchase**
- Public endpoint untuk beli voucher (e-commerce)

#### **RADIUS Integration (Unique Per Voucher):**

```
Voucher Sync Flow:
1. Insert ke `hotspot_vouchers`
2. Per voucher generate unique group: `hotspot-{profile}-{code}`
3. Insert ke `radcheck`: 
   - username: {code}
   - attribute: Cleartext-Password
   - value: {code}
4. Insert ke `radusergroup`:
   - username: {code}
   - groupname: {unique_group}
5. Insert ke `radgroupreply` (3 attributes):
   - Mikrotik-Group: {mikrotik_profile}
   - Mikrotik-Rate-Limit: {speed}
   - Session-Timeout: {validity_in_seconds}

Advantages:
- Setiap voucher punya group sendiri
- Session timeout per voucher (auto-disconnect)
- Easy tracking & management
```

#### **Voucher Code Generator:**
```typescript
function generateVoucherCode(length: number, prefix: string = ''): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // Exclude: 0, O, I, 1
  let code = prefix
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return code
}
```

---

### 3. Network Management Module

#### **Features:**
✅ Router/NAS management (MikroTik focus)
✅ Connection testing via RouterOS API
✅ Auto-sync ke FreeRADIUS `nas` table
✅ VPN Server management (L2TP/SSTP/PPTP)
✅ VPN Client management dengan auto-assign ke Router
✅ Status monitoring
✅ Auto-isolir setup (disable user di MikroTik)

#### **Database Schema:**

**Router (mapped to `nas` table):**
```prisma
- name, shortname
- nasname (IP for RADIUS - sama dengan ipAddress)
- type (mikrotik/cisco/etc)
- ipAddress, username, password
- port (API), apiPort, secret (RADIUS shared secret)
- ports (RADIUS auth port: 1812)
- server (RADIUS server IP)
- vpnClient (optional VPN relation)
- isActive
```

**VpnServer:**
```prisma
- host, username, password, port
- l2tpEnabled, sstpEnabled, pptpEnabled
- isConfigured (setup status)
```

**VpnClient:**
```prisma
- name, vpnIp, username, password
- vpnType (L2TP/SSTP/PPTP)
- isActive
- isRadiusServer (flag untuk central RADIUS)
- router (reverse relation)
```

#### **API Endpoints:**

**GET /api/network/routers**
- List semua routers/NAS

**POST /api/network/routers**
- Add router baru
- Test connection via RouterOS API
- Auto-generate shortname dari name
- Get router identity dari MikroTik
- Auto-restart FreeRADIUS untuk reload NAS

**PUT /api/network/routers**
- Update router config
- Test connection jika credentials berubah
- Auto-restart FreeRADIUS

**DELETE /api/network/routers**
- Remove router
- Auto-restart FreeRADIUS

**GET /api/network/routers/status**
- Check online status semua routers
- Test connection via RouterOS API

**POST /api/network/routers/[id]/setup-isolir**
- Setup/remove isolir (suspend) user di MikroTik
- Disable secret via API
- Use case: auto-isolir expired users

**GET /api/network/vpn-server**
- Get VPN server config

**POST /api/network/vpn-server**
- Setup VPN server (first time)

**PUT /api/network/vpn-server**
- Update VPN config

**POST /api/network/vpn-server/setup**
- Configure VPN via RouterOS API
- Enable L2TP/SSTP/PPTP server
- Setup IP pools, profiles, secrets

**POST /api/network/vpn-server/test**
- Test VPN connection

**GET /api/network/vpn-clients**
- List VPN clients

**POST /api/network/vpn-clients**
- Create VPN client

**GET /api/network/vpn-clients/status**
- Check active VPN sessions

#### **MikroTik API Integration:**

```typescript
// Connection example
const RouterOSAPI = require('node-routeros').RouterOSAPI;

const conn = new RouterOSAPI({
  host: ipAddress,
  user: username,
  password: password,
  port: 8728,
  timeout: 5,
});

await conn.connect();
const identity = await conn.write('/system/identity/print');
conn.close();
```

**Common Commands:**
- `/system/identity/print` - Get router name
- `/ppp/secret/print` - List PPPoE users
- `/ppp/secret/disable` - Isolir user
- `/ppp/secret/enable` - Enable user
- `/ppp/active/print` - Active sessions
- `/interface/l2tp-server/server/set enabled=yes` - Enable L2TP

#### **FreeRADIUS Auto-Restart:**
```typescript
// lib/freeradius.ts
export async function reloadFreeRadius(): Promise<void> {
  // Restart via sudo
  await execAsync('sudo systemctl restart freeradius');
  
  // Cooldown: 3 detik (prevent concurrent restarts)
}
```

**Sudoers config required:**
```bash
# /etc/sudoers.d/aibill
pm2_user ALL=(ALL) NOPASSWD: /bin/systemctl restart freeradius
```

---

## 🔧 Supporting Systems

### 1. FreeRADIUS Tables Integration

**radcheck** - User authentication
```sql
username | attribute            | op | value
---------|---------------------|----|---------
user1    | Cleartext-Password  | := | pass123
```

**radusergroup** - User to group mapping
```sql
username | groupname           | priority
---------|--------------------|---------
user1    | 10Mbps            | 0
voucher1 | hotspot-3jam-ABC  | 1
```

**radgroupreply** - Group attributes (reply)
```sql
groupname          | attribute           | op | value
-------------------|-------------------|----|---------
10Mbps            | Mikrotik-Rate-Limit | := | 10M/10M
hotspot-3jam-ABC  | Mikrotik-Group     | := | AIBILL
hotspot-3jam-ABC  | Session-Timeout    | := | 10800
```

**radreply** - User-specific reply
```sql
username | attribute         | op | value
---------|------------------|----|-----------
user1    | Framed-IP-Address | := | 10.0.0.5
```

**nas** - NAS/Router list
```sql
nasname    | shortname | secret    | ports
-----------|-----------|-----------|------
10.0.0.1  | rb1       | secret123 | 1812
```

**radacct** - Accounting (sessions)
```sql
username | acctstarttime | acctstoptime | acctinputoctets | acctoutputoctets
---------|---------------|--------------|-----------------|------------------
user1    | 2025-10-28... | NULL         | 1048576        | 2097152
```

**radpostauth** - Authentication log
```sql
username | pass    | reply      | authdate
---------|---------|------------|------------
user1    | pass123 | Access-Accept | 2025-10-28...
```

### 2. Session & Accounting

**Session model:**
```prisma
- username, userId (link to PppoeUser)
- nasIpAddress, sessionId
- startTime, stopTime
- uploadBytes, downloadBytes
```

**Flow:**
1. FreeRADIUS log session ke `radacct`
2. App sync data dari `radacct` ke `sessions`
3. Dashboard display sessions dengan user info

### 3. Invoice & Payment

**Invoice:**
```prisma
- invoiceNumber (unique)
- user (relation to PppoeUser)
- amount, status (PENDING/PAID/OVERDUE)
- dueDate, paidAt
- payments (relation)
```

**Payment:**
```prisma
- invoice (relation)
- amount, method
- gateway (relation to PaymentGateway)
- status, paidAt
```

**PaymentGateway:**
```prisma
- name, type
- apiKey, apiSecret
- isActive
```

### 4. WhatsApp Integration

**WhatsAppProvider:**
```prisma
- name, type (fonnte/wablas)
- apiKey, apiUrl
- isActive
```

**WhatsAppTemplate:**
```prisma
- name, type (invoice/payment/expiry)
- message (with variables)
- isActive
```

**WhatsAppHistory:**
```prisma
- phone, message
- status, response
- sentAt
```

### 5. Company Settings

**Company:**
```prisma
- name, address, phone, email
- baseUrl, adminPhone
- logo
```

---

## 🔄 Data Flow Examples

### PPPoE User Creation
```
1. User input form (username, password, profile, customer info)
2. POST /api/pppoe/users
3. Validate & check duplicate username
4. Calculate expiry date from profile validity
5. Create pppoe_users record
6. Sync to RADIUS:
   - radcheck (password)
   - radusergroup (assign profile group)
   - radreply (static IP if specified)
7. Mark syncedToRadius = true
8. Return success + sync status
```

### Hotspot Voucher Generation
```
1. User select profile, quantity, options
2. POST /api/hotspot/voucher
3. Generate unique codes (avoid duplicates)
4. Create batch code (BATCH-YYYYMMDD-HHMM)
5. Bulk insert to hotspot_vouchers
6. For each voucher:
   - Generate unique group name
   - Sync to RADIUS (radcheck, radusergroup, radgroupreply)
7. Return batch info + sync result
```

### Router Management
```
1. User input router credentials
2. POST /api/network/routers
3. Test connection via RouterOS API
4. Get router identity
5. Save to database (nas table)
6. Restart FreeRADIUS (reload NAS config)
7. Return success + router identity
```

---

## 📊 Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                     Next.js Application                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Frontend   │  │  API Routes  │  │   Services   │     │
│  │  (React 19)  │→ │ (Serverless) │→ │  (ts files)  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         │                  │                  │             │
│         └──────────────────┴──────────────────┘             │
│                            ↓                                │
│                    ┌───────────────┐                        │
│                    │ Prisma Client │                        │
│                    └───────────────┘                        │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
         ┌─────────────────────────────────┐
         │      MySQL Database             │
         │  ┌──────────┬───────────────┐  │
         │  │ App DB   │  RADIUS DB    │  │
         │  │(aibill)  │  (FreeRADIUS) │  │
         │  └──────────┴───────────────┘  │
         └────────────┬────────────────────┘
                      ↓
         ┌──────────────────────┐
         │   FreeRADIUS Server  │
         │   (Port 1812/1813)   │
         └──────────┬───────────┘
                    ↓
         ┌──────────────────────┐
         │  MikroTik Router(s)  │
         │  (PPPoE + Hotspot)   │
         │  API Port: 8728      │
         └──────────────────────┘
```

---

## 🚀 Development Roadmap Suggestions

### Short Term (Completed ✅)
- [x] PPPoE user & profile management
- [x] Hotspot voucher generation & sync
- [x] Router/NAS management
- [x] FreeRADIUS integration
- [x] MikroTik API integration
- [x] Basic dashboard

### Medium Term (Next Steps 📝)
- [ ] Invoice generation automation
- [ ] Payment gateway integration (Midtrans, Xendit)
- [ ] WhatsApp notification system
- [ ] Session monitoring dashboard (real-time)
- [ ] Bandwidth usage analytics
- [ ] Customer portal (self-service)
- [ ] Mobile app (React Native)

### Long Term (Future 🔮)
- [ ] Multi-tenant support
- [ ] GenieACS integration (CPE management)
- [ ] Advanced network mapping
- [ ] AI-based network optimization
- [ ] Automated ticketing system
- [ ] Advanced reporting & BI

---

## 💡 Best Practices

### 1. RADIUS Sync
- Always verify sync status (`syncedToRadius` flag)
- Use transactions untuk atomic operations
- Handle sync errors gracefully
- Log sync errors untuk debugging

### 2. MikroTik API
- Always use timeout (prevent hanging)
- Close connection after use
- Handle network errors
- Validate credentials before operations

### 3. Security
- Never expose RADIUS secret di frontend
- Encrypt sensitive data (passwords, API keys)
- Use environment variables
- Implement rate limiting
- Add CORS protection

### 4. Performance
- Use database indexes (username, status, dates)
- Limit query results (pagination)
- Cache frequently accessed data
- Use bulk operations when possible
- Optimize FreeRADIUS restart (cooldown)

### 5. Monitoring
- Log all RADIUS sync operations
- Track session data
- Monitor router status
- Alert on sync failures
- Track payment status

---

## 🛠️ Troubleshooting

### RADIUS Sync Issues
1. Check FreeRADIUS service status: `systemctl status freeradius`
2. Verify database connectivity
3. Check `syncedToRadius` flags
4. Review sync logs
5. Manual resync via API

### MikroTik Connection
1. Verify IP & port accessibility
2. Check API service enabled: `/ip service print`
3. Test credentials
4. Check firewall rules
5. Verify API port (default: 8728)

### Session Not Tracking
1. Check NAS secret match
2. Verify `radacct` table
3. Check FreeRADIUS accounting config
4. Verify router accounting enabled
5. Check session sync cron job

---

## 📚 Key Files Reference

### API Routes
```
src/app/api/
├── pppoe/
│   ├── users/route.ts          (CRUD users)
│   ├── users/bulk/route.ts     (Bulk operations)
│   ├── users/status/route.ts   (Status toggle)
│   └── profiles/route.ts       (Profile management)
├── hotspot/
│   ├── voucher/route.ts        (Generate vouchers)
│   ├── profiles/route.ts       (Profile management)
│   └── agents/route.ts         (Agent management)
└── network/
    ├── routers/route.ts        (NAS management)
    ├── vpn-server/route.ts     (VPN server)
    └── vpn-clients/route.ts    (VPN clients)
```

### Libraries
```
src/lib/
├── prisma.ts                   (Prisma client)
├── freeradius.ts              (RADIUS restart)
├── hotspot-radius-sync.ts     (Voucher sync)
└── timezone.ts                (WIB timezone utils)
```

### Database
```
prisma/
├── schema.prisma              (Complete schema)
└── migrations/                (Migration files)
```

---

## 📞 Support

Untuk pengembangan lebih lanjut:
1. Review schema Prisma untuk data structure
2. Study API routes untuk business logic
3. Analyze RADIUS sync mechanism
4. Test MikroTik API integration
5. Plan features based on existing structure

**Core sudah solid, tinggal develop fitur tambahan! 🚀**
