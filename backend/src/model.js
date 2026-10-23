// Enums (by name, same as the Flutter enums) and derived values of the entities.

const PARTY_LABEL = { customer: 'عميل', supplier: 'مورد' };
const METHOD_LABEL = { cash: 'نقدي', card: 'بطاقة', bank: 'تحويل بنكي' };
const methodAccount = (m) => (m === 'cash' ? 'cash' : 'bank');
const INVOICE = {
  sale: { label: 'فاتورة بيع', prefix: 'S', partyType: 'customer' },
  purchase: { label: 'فاتورة شراء', prefix: 'P', partyType: 'supplier' },
};
const TX = {
  sale: ['مبيعات', true],
  customerPayment: ['تحصيل من عميل', true],
  purchaseRefund: ['رد من مورد', true],
  cashIn: ['إيداع نقدي', true],
  deposit: ['إضافة رأس مال', true],
  purchase: ['مشتريات', false],
  supplierPayment: ['دفع لمورد', false],
  saleRefund: ['رد لعميل', false],
  expense: ['مصروف', false],
  withdrawal: ['سحب', false],
  cashOut: ['صرف نقدي', false],
};
const MANUAL_TX = ['cashIn', 'cashOut', 'expense', 'deposit', 'withdrawal'];
const txIsIn = (t) => TX[t][1];
const txLabel = (t) => TX[t][0];
const txSigned = (t) => (txIsIn(t.type) ? t.amount : -t.amount);

const ADJUST_REASON = {
  count: 'جرد / تصحيح عدد',
  damaged: 'تالف',
  expired: 'منتهي الصلاحية',
  lost: 'فقد',
  gift: 'هدية / عينة',
  other: 'أخرى',
};
const SEVERITY = ['info', 'warning', 'critical'];

// ───── Product ─────
const isOutOfStock = (p) => p.stock <= 0;
const isLowStock = (p) => p.stock > 0 && p.stock <= p.minStock;
const stockValue = (p) => (p.stock > 0 ? p.stock * p.purchasePrice : 0);
const priceFor = (p, tier) => (tier === 'wholesale' ? p.wholesalePrice : tier === 'halfWholesale' ? p.halfWholesalePrice : p.sellingPrice);

// ───── Party ─────
const isCustomer = (p) => p.type === 'customer';
const hasDebt = (p) => p.balance > 0.009;
const overLimit = (p) => p.creditLimit > 0 && p.balance > p.creditLimit;

// ───── Invoice ─────
const lineTotal = (l) => l.qty * l.unitPrice - (l.discount || 0);
const netUnitPrice = (l) => (l.qty === 0 ? 0 : lineTotal(l) / l.qty);
const returnableQty = (l) => l.qty - (l.returnedQty || 0);
const subtotal = (i) => i.lines.reduce((s, l) => s + lineTotal(l), 0);
const total = (i) => subtotal(i) - i.discount;
const due = (i) => {
  const d = total(i) - (i.returnedAmount || 0) - i.paid;
  return Math.abs(d) < 0.005 ? 0 : d;
};
const discountFactor = (i) => {
  const s = subtotal(i);
  return s === 0 ? 1 : total(i) / s;
};
const totalDiscount = (i) => i.lines.reduce((s, l) => s + (l.discount || 0), 0) + i.discount;
const cost = (i) => i.lines.reduce((s, l) => s + l.costPrice * l.qty, 0);
const profit = (i) => total(i) - cost(i);
const hasReturns = (i) => (i.returnedAmount || 0) > 0.009;
const paymentStatus = (i) => (due(i) <= 0.009 ? 'paid' : i.paid <= 0.009 ? 'unpaid' : 'partial');

// ───── Return ─────
const returnTotal = (r) => r.lines.reduce((s, l) => s + l.qty * l.unitPrice, 0);
const returnCost = (r) => r.lines.reduce((s, l) => s + l.costPrice * l.qty, 0);

const settlement = (inv, qtyByProduct) => {
  let t = 0;
  for (const l of inv.lines) t += (qtyByProduct[l.productId] || 0) * netUnitPrice(l) * discountFactor(inv);
  t = Math.round(t * 100) / 100;
  const d = Math.max(due(inv), 0);
  const credit = t < d ? t : d;
  return { total: t, creditApplied: credit, cashRefund: t - credit };
};

module.exports = {
  PARTY_LABEL, METHOD_LABEL, methodAccount, INVOICE, TX, MANUAL_TX, txIsIn, txLabel, txSigned, ADJUST_REASON, SEVERITY,
  isOutOfStock, isLowStock, stockValue, priceFor, isCustomer, hasDebt, overLimit,
  lineTotal, netUnitPrice, returnableQty, subtotal, total, due, discountFactor, totalDiscount, cost, profit, hasReturns, paymentStatus,
  returnTotal, returnCost, settlement,
};
