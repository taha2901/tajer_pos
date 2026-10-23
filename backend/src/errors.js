class BusinessError extends Error {
  constructor(message, code = null) {
    super(message);
    this.code = code;
    this.status = 422;
  }
}

class NotFoundError extends Error {
  constructor(message = 'العنصر غير موجود أو تم حذفه.') {
    super(message);
    this.status = 404;
  }
}

const Codes = {
  creditLimit: 'credit_limit',
  insufficientStock: 'insufficient_stock',
  drawerClosed: 'drawer_closed',
  insufficientCash: 'insufficient_cash',
  hasTransactions: 'has_transactions',
};

module.exports = { BusinessError, NotFoundError, Codes };
