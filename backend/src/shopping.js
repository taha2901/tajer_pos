const { BusinessError, NotFoundError } = require('./errors');

/// Shortages list: things to order from suppliers. An item is either a known
/// product or a free-text name; the supplier is optional.
class ShoppingList {
  constructor(db) {
    this.db = db;
  }

  /// Current product name/unit/stock and the supplier name are joined at read time.
  _view(it) {
    const p = it.productId ? this.db.products.get(it.productId) : null;
    const s = it.supplierId ? this.db.parties.get(it.supplierId) : null;
    return {
      ...it,
      name: p ? p.name : it.name,
      unit: p ? p.unit : it.unit,
      stock: p ? p.stock : null,
      supplierId: s ? s.id : null,
      supplierName: s ? s.name : null,
    };
  }

  list({ supplierId } = {}) {
    let items = [...this.db.shopping.values()].map((it) => this._view(it));
    // Items with no supplier show under every supplier.
    if (supplierId) items = items.filter((it) => !it.supplierId || it.supplierId === supplierId);
    return items.reverse();
  }

  _fields(body) {
    const productId = body.productId || null;
    if (productId && !this.db.products.has(productId)) throw new NotFoundError('المنتج غير موجود.');
    const name = String(body.name || '').trim();
    if (!productId && !name) throw new BusinessError('اكتب اسم الصنف.');
    const qty = Number(body.qty || 0);
    if (!(qty > 0)) throw new BusinessError('الكمية يجب أن تكون أكبر من صفر.');
    const supplierId = body.supplierId || null;
    if (supplierId && !this.db.parties.has(supplierId)) throw new NotFoundError('المورد غير موجود.');
    return { productId, name, unit: String(body.unit || '').trim(), qty, supplierId, note: String(body.note || '').trim() };
  }

  add(body, user) {
    const f = this._fields(body);
    // Same product already on the list: add to its quantity instead of a duplicate row.
    const existing = f.productId && [...this.db.shopping.values()].find((it) => it.productId === f.productId);
    if (existing) {
      existing.qty += f.qty;
      if (f.supplierId) existing.supplierId = f.supplierId;
      if (f.note) existing.note = f.note;
      return this._view(this.db.put('shopping', existing));
    }
    const it = { id: this.db.id('sh'), ...f, addedBy: user ? user.name : '', createdAt: new Date().toISOString() };
    return this._view(this.db.put('shopping', it));
  }

  update(id, body) {
    const it = this.db.shopping.get(id);
    if (!it) throw new NotFoundError();
    return this._view(this.db.put('shopping', { ...it, ...this._fields({ ...it, ...body }) }));
  }

  remove(ids) {
    for (const id of ids) if (this.db.shopping.has(id)) this.db.remove('shopping', id);
  }
}

module.exports = { ShoppingList };
