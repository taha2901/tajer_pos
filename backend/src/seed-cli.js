// Wipes business data and regenerates the demo dataset: `npm run seed`.
require('dotenv').config();
const { Store } = require('./store');
const { Engine } = require('./engine');
const { Seeder } = require('./seeder');

(async () => {
  const db = new Store();
  await db.connect(process.env.MONGO_URL || 'mongodb://127.0.0.1:27017', process.env.MONGO_DB || 'tajer');
  new Seeder(db, new Engine(db)).run();
  await db.flush();
  console.log(`Seeded: ${db.products.size} products, ${db.invoices.size} invoices, ${db.parties.size} parties.`);
  await db.client.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
