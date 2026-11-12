// Puts the screenshots of a tour run on contact sheets (8 per sheet, 4 x 2, in the order they
// were taken) so a whole run can be checked by eye in a few pictures.
//   node tool/demo/contact_sheet.mjs <folder with the png files> [per-sheet=8]
// Writes sheet_01.png, sheet_02.png ... into the same folder and prints which picture is where.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { PNG } from 'pngjs';

const dir = process.argv[2];
const per = Number(process.argv[3] ?? 8);
if (!dir) {
  console.error('usage: node contact_sheet.mjs <folder> [per-sheet]');
  process.exit(2);
}

// s01_1, s01_end, s02_1 ... : by chapter/beat number, then step (end last).
const key = (f) => {
  const m = /^(.*?)_(\d+|end)\.png$/.exec(f);
  if (!m) return [f, 0];
  return [m[1], m[2] === 'end' ? 9999 : Number(m[2])];
};
const files = readdirSync(dir)
  .filter((f) => f.endsWith('.png') && !f.startsWith('sheet_'))
  .sort((a, b) => {
    const [ka, na] = key(a);
    const [kb, nb] = key(b);
    return ka === kb ? na - nb : ka.localeCompare(kb, undefined, { numeric: true });
  });

const cols = 4;
const gap = 8;
let sheetNo = 0;
for (let i = 0; i < files.length; i += per) {
  const group = files.slice(i, i + per);
  const imgs = group.map((f) => PNG.sync.read(readFileSync(join(dir, f))));
  const w = Math.max(...imgs.map((p) => p.width));
  const h = Math.max(...imgs.map((p) => p.height));
  const rows = Math.ceil(group.length / cols);
  const out = new PNG({ width: cols * w + (cols + 1) * gap, height: rows * h + (rows + 1) * gap });
  out.data.fill(0x55); // grey background so the edges of each screen are visible
  imgs.forEach((p, n) => {
    const ox = gap + (n % cols) * (w + gap);
    const oy = gap + Math.floor(n / cols) * (h + gap);
    PNG.bitblt(p, out, 0, 0, p.width, p.height, ox, oy);
  });
  sheetNo++;
  const name = `sheet_${String(sheetNo).padStart(2, '0')}.png`;
  writeFileSync(join(dir, name), PNG.sync.write(out));
  console.log(`${name}: ${group.join('  ')}`);
}
console.log(`${files.length} pictures on ${sheetNo} sheet(s)`);
