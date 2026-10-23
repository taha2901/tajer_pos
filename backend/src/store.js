const { MongoClient } = require('mongodb');

/// Tables persisted as one MongoDB collection each (document _id = entity id).
const TABLES = ['categories', 'products', 'parties', 'invoices', 'returns', 'payments', 'ledger', 'stockMoves', 'txs', 'sessions', 'users'];

const DEFAULT_SETTINGS = {
  storeName: 'سوبر ماركت التاجر',
  storePhone: '01001234567',
  storeAddress: 'القاهرة - مدينة نصر - شارع عباس العقاد',
  invoiceFooter: 'شكراً لزيارتكم • البضاعة المباعة تُرد خلال 14 يوماً',
  allowNegativeStock: false,
  largeExpenseThreshold: 2000,
  debtDueDays: 30,
  closingReminderHour: 22,
  themeMode: 'light',
};

/// Working set kept in memory (a single shop fits easily) and written through
/// to MongoDB after every successful operation. Only the engine mutates it.
class Store {
  constructor() {
    for (const t of TABLES) this[t] = new Map();
    this.settings = { ...DEFAULT_SETTINGS };
    this.readAlerts = new Set();
    this.recentSearches = [];
    this.pins = {}; // username -> pin
    this.tokens = {}; // token -> userId
    this.seq = {};
    this._dirty = new Map(); // table -> Set(id)
    this._removed = new Map();
    this._metaDirty = false;
  }

  // ───────── mutation helpers (track what to persist) ─────────

  put(table, obj) {
    this[table].set(obj.id, obj);
    if (!this._dirty.has(table)) this._dirty.set(table, new Set());
    this._dirty.get(table).add(obj.id);
    return obj;
  }

  remove(table, id) {
    this[table].delete(id);
    if (!this._removed.has(table)) this._removed.set(table, new Set());
    this._removed.get(table).add(id);
  }

  touchMeta() {
    this._metaDirty = true;
  }

  _next(key) {
    this.seq[key] = (this.seq[key] || 0) + 1;
    this._metaDirty = true;
    return this.seq[key];
  }

  id(prefix) {
    return `${prefix}${this._next('id_' + prefix)}`;
  }

  number(prefix, { pad = 5, start = 0 } = {}) {
    const n = this._next('no_' + prefix) + start;
    return `${prefix}-${String(n).padStart(pad, '0')}`;
  }

  get openSession() {
    const all = [...this.sessions.values()];
    for (let i = all.length - 1; i >= 0; i--) if (!all[i].closedAt) return all[i];
    return null;
  }

  clearBusiness() {
    for (const t of TABLES) {
      if (t === 'users') continue;
      for (const id of this[t].keys()) this.remove(t, id);
    }
    this.readAlerts.clear();
    this.recentSearches = [];
    for (const k of Object.keys(this.seq)) if (!k.endsWith('_u')) delete this.seq[k];
    this._metaDirty = true;
  }

  // ───────── persistence ─────────

  async connect(url, dbName) {
    this.client = new MongoClient(url);
    await this.client.connect();
    this.mdb = this.client.db(dbName);
    for (const t of TABLES) {
      const docs = await this.mdb.collection(t).find().sort({ _ord: 1 }).toArray();
      for (const d of docs) {
        const { _id, _ord, ...rest } = d;
        this[t].set(rest.id, rest);
      }
    }
    const meta = await this.mdb.collection('meta').findOne({ _id: 'meta' });
    if (meta) {
      this.settings = { ...DEFAULT_SETTINGS, ...meta.settings };
      this.readAlerts = new Set(meta.readAlerts || []);
      this.recentSearches = meta.recentSearches || [];
      this.pins = meta.pins || {};
      this.tokens = meta.tokens || {};
      this.seq = meta.seq || {};
    }
    this._ord = Date.now();
  }

  get isEmpty() {
    return this.products.size === 0 && this.invoices.size === 0;
  }

  /// Writes are serialised so two quick requests never interleave on disk.
  flush() {
    const dirty = this._dirty;
    const removed = this._removed;
    const metaDirty = this._metaDirty;
    this._dirty = new Map();
    this._removed = new Map();
    this._metaDirty = false;
    const job = async () => {
      for (const [t, ids] of removed) {
        await this.mdb.collection(t).deleteMany({ _id: { $in: [...ids] } });
      }
      for (const [t, ids] of dirty) {
        const ops = [];
        for (const id of ids) {
          const obj = this[t].get(id);
          if (!obj) continue;
          ops.push({ replaceOne: { filter: { _id: id }, replacement: { ...obj, _id: id, _ord: this._ord++ }, upsert: true } });
        }
        // Preserve original insertion order for already-stored docs.
        if (ops.length) {
          const existing = await this.mdb.collection(t).find({ _id: { $in: ops.map((o) => o.replaceOne.filter._id) } }, { projection: { _ord: 1 } }).toArray();
          const ord = new Map(existing.map((e) => [e._id, e._ord]));
          for (const o of ops) {
            const prev = ord.get(o.replaceOne.filter._id);
            if (prev !== undefined) o.replaceOne.replacement._ord = prev;
          }
          await this.mdb.collection(t).bulkWrite(ops, { ordered: false });
        }
      }
      if (metaDirty) {
        await this.mdb.collection('meta').replaceOne(
          { _id: 'meta' },
          {
            settings: this.settings,
            readAlerts: [...this.readAlerts],
            recentSearches: this.recentSearches,
            pins: this.pins,
            tokens: this.tokens,
            seq: this.seq,
          },
          { upsert: true },
        );
      }
    };
    this._queue = (this._queue || Promise.resolve()).then(job, job);
    return this._queue;
  }
}

module.exports = { Store, DEFAULT_SETTINGS };
