# Tajer POS — Business & Architecture Analysis

This is the design reference for the prototype. Nothing in it depends on the UI.
When a backend exists, the backend takes over the role the `PosEngine` plays now.

---

## 1. Entities

| Entity | Key fields | Notes |
|---|---|---|
| **Product** | name, barcode, sku, category, unit, purchase / retail / half‑wholesale / wholesale price, stock, minStock, supplier, image, active | `stock` changes **only** through stock movements |
| **Category** | name | |
| **Party** | type (customer / supplier), name, phone, address, company, priceTier, creditLimit, **balance**, notes | Customers and suppliers share one model. Customer balance > 0 means the customer owes us. Supplier balance > 0 means we owe the supplier. |
| **Invoice** | type (sale / purchase), number, date, party, priceTier, lines, discount, total, **paid**, **returnedAmount**, payments, user | `due = total − returnedAmount − paid` |
| **InvoiceLine** | product snapshot (name, unit), qty, unitPrice, discount, costPrice, returnedQty | Snapshots keep old invoices correct after a product changes |
| **ReturnDoc** | type, invoice, lines, total, creditApplied, cashRefund, refund method, reason | |
| **PartyPayment** | party, amount, method, note, allocations | A receipt from a customer, or a payment to a supplier |
| **LedgerEntry** | party, kind (opening / invoice / payment / return / refund / adjustment), debit, credit, running balance, ref | The data behind the party statement |
| **StockMovement** | product, type (opening / purchase / sale / saleReturn / purchaseReturn / adjustment), signed qty, stockAfter, ref | The data behind stock history |
| **MoneyTx** | account (cash drawer / bank), type, direction, amount, ref, user, session, category | Every movement of money |
| **CashSession** | opening balance, opened/closed by, expected cash, counted cash, difference | The drawer shift; daily closing |
| **Settings / User** | permissions, thresholds, store info / role | |

## 2. Relationships

```
Category 1─* Product *─1 Supplier(Party)
Party 1─* Invoice 1─* InvoiceLine *─1 Product
Invoice 1─* ReturnDoc 1─* ReturnLine
Party 1─* PartyPayment ─allocates→ Invoice(s) (FIFO, oldest first)
Party 1─* LedgerEntry ─ref→ Invoice | ReturnDoc | PartyPayment
Product 1─* StockMovement ─ref→ Invoice | ReturnDoc | Adjustment
CashSession 1─* MoneyTx(account=cash) ─ref→ Invoice | ReturnDoc | PartyPayment | manual
```

## 3. Posting rules (the core business logic)

Every operation runs atomically inside `PosEngine`, and every side effect carries a reference number.

| Operation | Stock | Party ledger / balance | Money |
|---|---|---|---|
| **Sale** | − qty per line (`sale`) | named customer: debit total, credit paid → balance += due | + each payment (cash → drawer, card/bank → bank) |
| **Sale on credit** | same | balance += remaining (must respect credit limit) | + paid part only |
| **Customer payment** | — | credit amount → balance −= amount; allocated FIFO to open invoices | + amount (`customerPayment`) |
| **Sales return** | + qty (`saleReturn`) | credit return value; debit any cash refund | − cash refund (`saleRefund`) |
| **Purchase** | + qty (`purchase`); product purchase price = last cost | credit total, debit paid → balance += due | − each payment (`purchase`) |
| **Supplier payment** | — | debit amount → balance −= amount; FIFO allocation | − amount (`supplierPayment`) |
| **Purchase return** | − qty (`purchaseReturn`) | debit return value; credit any cash refund received | + refund (`purchaseRefund`) |
| **Stock adjustment** | ± qty (`adjustment`) with reason | — | — |
| **Balance adjustment** | — | debit or credit (`adjustment`) | — |
| **Expense / Cash out / Withdrawal** | — | — | − drawer |
| **Cash in / Deposit** | — | — | + drawer |

### How a return is settled
`R` = value of the returned qty (line net price after line discount, then the invoice discount shared out pro rata).

* `creditApplied = min(R, invoice.due)` reduces what the party still owes on that invoice.
* `cashRefund = R − creditApplied` is paid back in cash or by bank.
* `invoice.returnedAmount += R`, `invoice.paid −= cashRefund`, so `due` drops by exactly `creditApplied`.

Example: a sale of 10,000 with 4,000 paid (due 6,000). Returning 2,000 of goods makes the due 4,000, with no cash refund.
A sale of 1,000 paid in full: returning 300 refunds 300 in cash.

### Worked credit examples (from the brief)
* Sale 10,000, paid 4,000 → customer balance +6,000. A later payment of 2,000 → balance 4,000.
* Purchase 20,000, paid 5,000 → supplier payable 15,000. A payment of 5,000 → 10,000.
* Drawer: opening 5,000 + cash sales 10,000 + customer payments 2,000 − expenses 1,000 − supplier payment 3,000 = **13,000 expected**.

## 4. Business rules & edge cases

1. **Credit needs a named customer.** A walk‑in sale must be fully paid.
2. **Credit limit:** a new balance above the limit blocks a cashier. An admin can override after confirming.
3. **Stock:** a sale cannot exceed available stock unless *Allow negative stock* is on. A purchase return cannot exceed current stock or the qty bought less the qty already returned.
4. **Returns:** for each line, return qty ≤ qty − returnedQty. A fully returned invoice gets the status *Returned*.
5. **Cash drawer:** any cash movement needs an open session. The POS offers to open one inline. Cash out (expense, supplier payment, refund) cannot exceed the expected cash in the drawer.
6. **Permissions:** a cashier edits prices only if allowed and gives line or invoice discounts only up to the max discount %. An admin has no such limits.
7. **Product delete:** allowed only if the product has no movements other than opening. Otherwise the user is offered *Deactivate*.
8. **Party delete:** allowed only with no documents and a zero balance.
9. **Overpayment:** a customer may pay more than their balance after confirming. The balance goes negative, which means credit in the customer's favour.
10. **Large expense:** an amount above the configured threshold shows a warning and creates an alert.
11. **Daily closing:** counted cash is compared to expected cash, and any surplus or shortage is recorded on the session. The next opening suggests the last counted cash.
12. **Snapshots:** invoice lines keep the product name, unit and cost at the time of sale, so profit stays correct after prices change.

## 5. User flows

* **Sale:** POS → scan or search (tap adds 1, scanning again adds +1) → optional customer and price tier → cart (qty, price, discount) → Checkout (Cash / Card / Bank / Credit / Mixed) → invoice receipt (print, share, new sale).
* **Purchase:** Purchases → New → supplier → add products (scan or search) → qty, cost, discount → payment (cash / bank / credit / partial) → purchase invoice.
* **Returns:** Invoice details → Return → choose lines and qty → see the settlement → confirm.
* **Credit:** Party details → Add payment → amount and method → the balance updates. The statement shows each step.
* **Cash:** Cash → open drawer → movements (cash in/out, expense, deposit, withdrawal) → Daily closing (count cash, see the difference).

## 6. Code architecture

```
lib/
  app/        app widget, theme, DI (RepositoryProviders), session/settings cubits, shell navigation
  core/       formatters, errors, data-change bus, generic QueryCubit + AsyncView, reusable widgets
  domain/     models (entities + enums) and repository interfaces (contracts)
  data/local/ LocalStore (in-memory tables), PosEngine (posting rules), Seeder (30 days of history),
              Local*Repository (implements the contracts; adds latency and optional simulated errors)
  features/   one folder per module: screens, widgets, feature cubits
```

* **Swapping in a backend:** write `Api*Repository` classes that implement the same interfaces in `domain/repositories`, and change the bindings in `app/di.dart`. Screens and cubits depend only on the interfaces.
* **Reactivity:** repositories emit `DataTopic`s on a `DataBus` after each mutation. `QueryCubit`s subscribed to those topics reload, so every screen shows the change (stock, balances, cash) at once. A backend version can emit the same topics after a successful API call, or from push/websocket events.
* **State management:** Cubits (`flutter_bloc`). `QueryCubit<T, F>` covers every read screen (loading / empty / error / success, filters, silent refresh). Dedicated cubits handle stateful flows (cart, purchase draft).
