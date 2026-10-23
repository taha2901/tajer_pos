# Tajer POS — Backend (Node.js + MongoDB)

Local shop server. Runs on one PC in the shop and works **without internet**: phones and tablets
running the Tajer app connect to it over the shop's Wi-Fi.

## Requirements
- Node.js 18+
- MongoDB Community Server running locally (`mongodb://127.0.0.1:27017`)

## Run
```bash
cd backend
npm install
npm start
```
The server prints the address to use from the phones, e.g.:
```
→ on the shop network: http://192.168.1.14:3000/api
```
In the app: login screen → server icon (top) → enter that address → «اختبار» → «حفظ».
(Android emulator on the same PC: `http://10.0.2.2:3000/api`, the default.)

If phones can't connect, allow Node.js / port 3000 through Windows Firewall (private networks).

## Configuration (`.env`)
| Key | Default | |
|---|---|---|
| `PORT` | `3000` | |
| `MONGO_URL` | `mongodb://127.0.0.1:27017` | |
| `MONGO_DB` | `tajer` | |
| `SEED_DEMO` | `true` | Fill an empty database with 30 days of demo data on first start |

`npm run seed` wipes business data and regenerates the demo data (stop the server first).
Demo accounts: `admin / 1234`, `cashier / 0000`. New accounts are created from the app's register screen.

## Design
- `src/engine.js` — all business rules (stock, party ledger, cash drawer, invoices, returns, payments).
  Every operation validates first, then applies all side effects.
- `src/reads.js` — lists, statistics, reports, alerts, search.
- `src/store.js` — working set kept in memory and written through to MongoDB after each operation
  (one collection per entity: `products`, `invoices`, `parties`, `ledger`, `txs`, …; plus `meta`).
- `src/routes.js` — REST API under `/api`. All routes except `/health`, `/auth/login`,
  `/auth/register` and `GET /settings` need `Authorization: Bearer <token>`.
- All users have the same permissions.
