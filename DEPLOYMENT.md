# Deployment Guide

## Database Setup

### Initial Setup
```bash
# Run Prisma migrations
npm run db:migrate

# Or use db:push for development
npm run db:push
```

**Note**: The custom `db:push` and `db:migrate` scripts automatically fix FreeRADIUS tables after migration.

### Manual Fix (if needed)
If you encounter accounting errors in FreeRADIUS, run:
```bash
./scripts/setup-radius-tables.sh
```

Or manually:
```bash
npm run db:fix-radius
```

## Common Issues

### FreeRADIUS Accounting Not Working
**Error**: `Field 'groupname' doesn't have a default value`

**Solution**: 
```bash
npm run db:fix-radius
sudo systemctl restart freeradius
```

### After Prisma Schema Changes
Always run the fix script after `prisma db push` or `prisma migrate`:
```bash
npm run db:push    # Already includes the fix
# OR
npm run db:migrate # Already includes the fix
```

## Production Deployment

1. Clone repository
2. Install dependencies: `npm install`
3. Setup environment variables (`.env`)
4. Run migrations: `npm run db:migrate`
5. Build application: `npm run build`
6. Start server: `npm start`

The migration scripts will automatically configure FreeRADIUS tables.
