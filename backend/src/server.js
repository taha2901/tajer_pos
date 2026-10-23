require('dotenv').config();
const os = require('os');
const express = require('express');
const cors = require('cors');
const { Store } = require('./store');
const { Engine } = require('./engine');
const { Reads } = require('./reads');
const { Seeder } = require('./seeder');
const { buildRouter } = require('./routes');

const PORT = Number(process.env.PORT || 3000);
const MONGO_URL = process.env.MONGO_URL || 'mongodb://127.0.0.1:27017';
const MONGO_DB = process.env.MONGO_DB || 'tajer';

function lanAddresses() {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal)
    .map((i) => i.address);
}

async function main() {
  const db = new Store();
  await db.connect(MONGO_URL, MONGO_DB);
  const engine = new Engine(db);
  const reads = new Reads(db, engine);

  const seeder = new Seeder(db, engine);
  // Starts empty: the owner registers and enters everything. Set SEED_DEMO=true for demo data.
  if (db.isEmpty && process.env.SEED_DEMO === 'true') {
    console.log('Empty database — generating demo data...');
    seeder.run();
  }
  await db.flush();

  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '5mb' }));
  // Logs every request so you can watch the app talking to the server.
  app.use((req, res, next) => {
    const t = Date.now();
    res.on('finish', () => {
      const time = new Date().toLocaleTimeString('en-GB');
      console.log(`[${time}] ${req.ip.replace('::ffff:', '')} ${req.method} ${req.originalUrl} → ${res.statusCode} (${Date.now() - t}ms)`);
    });
    next();
  });
  app.use('/api', buildRouter({ db, engine, reads }));
  app.use((err, _req, res, _next) => {
    const status = err.status || 500;
    if (status === 500) console.error(err);
    res.status(status).json({ message: status === 500 ? 'حدث خطأ في الخادم.' : err.message, code: err.code || null });
  });

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Tajer backend running on port ${PORT} (MongoDB: ${MONGO_URL}/${MONGO_DB})`);
    for (const ip of lanAddresses()) console.log(`  → on the shop network: http://${ip}:${PORT}/api`);
  });
}

main().catch((e) => {
  console.error('Failed to start:', e.message);
  process.exit(1);
});
