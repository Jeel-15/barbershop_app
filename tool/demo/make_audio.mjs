// Makes one mp3 per beat of assets/demo/tour.json with a Canadian English neural voice.
//   node tool/demo/make_audio.mjs            (from the project root, or from tool/demo)
// Only the beats whose sentence (or voice) changed are made again; mp3 files of beats that no
// longer exist are removed. Needs internet (Microsoft's free Edge text-to-speech service);
// the mp3 files are then bundled in the app (assets/demo/audio).
import { EdgeTTS } from 'node-edge-tts';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const scriptPath = join(root, 'assets', 'demo', 'tour.json');
const outDir = join(root, 'assets', 'demo', 'audio');
const manifestPath = join(outDir, 'manifest.json');

const script = JSON.parse(readFileSync(scriptPath, 'utf8'));
const voice = script.voice ?? 'en-CA-ClaraNeural';
const beats = script.chapters.flatMap((c) => c.beats);
mkdirSync(outDir, { recursive: true });
const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : {};

const wanted = new Set(beats.map((b) => `${b.id}.mp3`));
for (const f of readdirSync(outDir)) {
  if (f.endsWith('.mp3') && !wanted.has(f)) {
    rmSync(join(outDir, f));
    delete manifest[f.replace('.mp3', '')];
    console.log('removed', f);
  }
}

let made = 0;
for (const b of beats) {
  const file = join(outDir, `${b.id}.mp3`);
  const hash = createHash('sha1').update(`${voice}|${b.say}`).digest('hex');
  if (existsSync(file) && manifest[b.id] === hash) continue;
  const tts = new EdgeTTS({
    voice,
    lang: 'en-CA',
    outputFormat: 'audio-24khz-96kbitrate-mono-mp3',
    rate: '-3%',
    timeout: 60000,
  });
  let ok = false;
  for (let attempt = 1; attempt <= 3 && !ok; attempt++) {
    try {
      await tts.ttsPromise(b.say, file);
      ok = true;
    } catch (e) {
      console.log(`  retry ${b.id} (${e.message ?? e})`);
    }
  }
  if (!ok) throw new Error(`could not make ${b.id}`);
  manifest[b.id] = hash;
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 1));
  made++;
  console.log('made', b.id);
}
console.log(`done: ${made} made, ${beats.length} beats, voice ${voice}`);
