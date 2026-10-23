// Formatting helpers matching the app's Fmt (used in messages and labels).

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const WEEKDAYS = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت']; // JS getDay() order

const r2 = (v) => Math.round(v * 100) / 100;

const num = (v) => {
  const [i, f] = (Math.round(v * 100) / 100).toFixed(2).split('.');
  const neg = i.startsWith('-');
  const int = (neg ? i.slice(1) : i).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const frac = f.replace(/0+$/, '');
  return (neg ? '-' : '') + int + (frac ? '.' + frac : '');
};

const money = (v) => `${num(v)} ج.م`;
const qty = (v) => (v === Math.round(v) ? String(Math.round(v)) : v.toFixed(2));
const shortDate = (d) => `${d.getDate()}/${d.getMonth() + 1}`;
const dayMonth = (d) => `${d.getDate()} ${MONTHS[d.getMonth()]}`;
const date = (d) => `${dayMonth(d)} ${d.getFullYear()}`;
const monthYear = (d) => `${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
const weekday = (d) => WEEKDAYS[d.getDay()];

const time = (d) => {
  const h = d.getHours() % 12 === 0 ? 12 : d.getHours() % 12;
  return `${h}:${String(d.getMinutes()).padStart(2, '0')} ${d.getHours() < 12 ? 'ص' : 'م'}`;
};

const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const endOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());
const daysBetween = (a, b) => Math.round((startOfDay(a) - startOfDay(b)) / 86400000);

const relative = (d) => {
  const diff = daysBetween(new Date(), d);
  if (diff === 0) return `اليوم ${time(d)}`;
  if (diff === 1) return `أمس ${time(d)}`;
  if (diff < 7) return `${weekday(d)} ${time(d)}`;
  return date(d);
};

const dayLabel = (d) => {
  const diff = daysBetween(new Date(), d);
  if (diff === 0) return 'اليوم';
  if (diff === 1) return 'أمس';
  return `${weekday(d)} ${dayMonth(d)}`;
};

module.exports = { r2, money, qty, shortDate, dayMonth, date, monthYear, weekday, time, relative, dayLabel, startOfDay, endOfDay, addDays, daysBetween };
