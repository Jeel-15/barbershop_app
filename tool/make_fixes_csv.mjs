// Turns docs/WEB_DEV_FIXES.md into docs/web_dev_fixes.csv for the web developer.
// Table rows (sections 1-3) become one row each; the later "Q53+" sections
// become one row per bullet / numbered item.
import fs from 'node:fs';

const md = fs.readFileSync('docs/WEB_DEV_FIXES.md', 'utf8').split(/\r?\n/);
const clean = (s) =>
  s
    .replace(/<br\s*\/?>/g, ' ')
    .replace(/\*\*/g, '')
    .replace(/`/g, '')
    .replace(/\s+/g, ' ')
    .trim();
const esc = (s) => `"${String(s).replace(/"/g, '""')}"`;

const rows = [];
let sev = '';
let section = '';
for (const line of md) {
  if (/^## 1\./.test(line)) { sev = 'High (security)'; continue; }
  if (/^## 2\./.test(line)) { sev = 'Medium/High (wrong money or data)'; continue; }
  if (/^## 3\./.test(line)) { sev = 'Low (cleanup)'; continue; }
  const h = line.match(/^## (Q\d+)\s*[—-]\s*(.*)$/);
  if (h) { sev = ''; section = `${h[1]} ${h[2]}`; continue; }
  if (/^## /.test(line)) { sev = ''; section = ''; continue; }

  if (sev && line.startsWith('| Q')) {
    const c = line.split('|').slice(1, -1).map((x) => clean(x));
    rows.push([c[0], sev, c[1], c[2], c[3]]);
  } else if (section && /^(- |\d+\. )/.test(line)) {
    const text = clean(line.replace(/^(- |\d+\. )/, ''));
    if (text.length < 25) continue;
    const m = text.match(/^([^:.]{3,70}?)[:.] (.*)$/);
    const sv = /Fix first|🔴/.test(line) ? 'High' : 'See section';
    rows.push([section.split(' ')[0], sv, m ? m[1] : section, text, '']);
  }
}

// Rows that are not web bugs (our own API notes, cosmetic, duplicates): see the json.
const skip = new Set(JSON.parse(fs.readFileSync('tool/fixes_csv_exclude.json', 'utf8')));
const kept = rows.filter((r) => !skip.has(r[0] + '|' + r[3].slice(0, 40)));

const head = ['Id', 'Priority', 'Where', 'Problem', 'Suggested fix', 'Status', 'Web dev notes'];
const out = [head, ...kept.map((r) => [...r, 'Open', ''])]
  .map((r) => r.map(esc).join(','))
  .join('\r\n');
fs.writeFileSync('docs/web_dev_fixes.csv', '﻿' + out + '\r\n');
console.log(`${kept.length} rows -> docs/web_dev_fixes.csv`);
