// Compares the tour script with the coverage manifest: what the app has, and what the
// tour does not mention yet.
//   node tool/demo/coverage_check.mjs            (summary + every gap)
//   node tool/demo/coverage_check.mjs --strict   (exit 1 when anything is missing)
//
// Script format v1 (segments with "say") is checked by keywords, which is a generous
// upper bound. Script format v2 (beats with "covers": [ids]) is checked exactly.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const cov = JSON.parse(readFileSync(join(root, 'assets', 'demo', 'coverage.json'), 'utf8'));
const script = JSON.parse(readFileSync(join(root, 'assets', 'demo', 'tour.json'), 'utf8'));
const strict = process.argv.includes('--strict');

const beats = [];
const chapterFilter = process.argv.find((a) => a.startsWith('--only='))?.slice(7)?.split(',');
if (script.chapters) {
  for (const ch of script.chapters) for (const b of ch.beats) beats.push({ ...b, chapter: ch.id });
} else {
  for (const s of script.segments) beats.push({ id: s.id, say: s.say, cap: s.cap, covers: s.covers });
}
const exact = beats.some((b) => Array.isArray(b.covers));
const text = beats.map((b) => `${b.say ?? ''} ${b.cap ?? ''}`.toLowerCase()).join(' \n ');
const covered = new Set(beats.flatMap((b) => b.covers ?? []));

let total = 0;
let hit = 0;
const gaps = [];
const perChapter = [];
for (const ch of cov.chapters) {
  let ct = 0;
  let ch_hit = 0;
  for (const sc of ch.screens) {
    for (const [id, kw, kind] of sc.els) {
      total++;
      ct++;
      const ok = exact ? covered.has(id) : kw.split('|').some((k) => text.includes(k.trim()));
      if (ok) {
        hit++;
        ch_hit++;
      } else {
        gaps.push({ chapter: ch.name, screen: sc.id, id, kind, kw });
      }
    }
  }
  perChapter.push([ch.name, ch_hit, ct]);
}

// beats that claim to cover an element that does not exist
const known = new Set(cov.chapters.flatMap((c) => c.screens.flatMap((s) => s.els.map((e) => e[0]))));
const unknown = [...covered].filter((id) => !known.has(id));

console.log(`mode: ${exact ? 'exact (beats cover ids)' : 'keywords (upper bound)'}`);
console.log(`beats/segments: ${beats.length}`);
console.log(`coverage: ${hit}/${total} (${Math.round((100 * hit) / total)}%)\n`);
for (const [n, h, t] of perChapter) console.log(`  ${String(h).padStart(3)}/${String(t).padEnd(3)} ${n}`);
if (unknown.length) console.log(`\nunknown ids in the script: ${unknown.join(', ')}`);
if (gaps.length) {
  console.log(`\nNOT MENTIONED (${gaps.length}):`);
  let last = '';
  for (const g of gaps) {
    if (g.screen !== last) {
      console.log(`\n  [${g.chapter} / ${g.screen}]`);
      last = g.screen;
    }
    console.log(`    ${g.kind} ${g.id}   (${g.kw})`);
  }
}
if (strict && (gaps.length || unknown.length)) process.exit(1);
