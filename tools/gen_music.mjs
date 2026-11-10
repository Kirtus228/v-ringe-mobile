// Генератор боевой музыки для РИНГ 3D → res://music/fight_loop.wav.
// Своя композиция: тёмный минорный грув на 100 BPM, 8 тактов, бесшовный луп.
// Никаких сэмплов и чужих мелодий — всё синтезируется здесь.
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RATE = 22050;
const BPM = 100;
const BEAT = 60 / BPM;             // 0.6 c
const BAR = BEAT * 4;              // 2.4 c
const BARS = 8;
const TOTAL = BAR * BARS;          // 19.2 c

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', 'music');
mkdirSync(outDir, { recursive: true });

const n = Math.floor(RATE * TOTAL);
const mix = new Float32Array(n);
const rnd = () => Math.random() * 2 - 1;
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);

function put(i, v) {
  if (i >= 0 && i < n) mix[i] += v;
}

// --- барабаны

function kick(at, amp = 1.0) {
  const start = Math.floor(at * RATE);
  const len = Math.floor(0.26 * RATE);
  let phase = 0;
  for (let k = 0; k < len; k++) {
    const t = k / RATE;
    const f = 46 + 130 * Math.exp(-28 * t);
    phase += (2 * Math.PI * f) / RATE;
    const e = Math.exp(-9 * t);
    put(start + k, Math.sin(phase) * e * 0.9 * amp);
    if (k < 60) put(start + k, rnd() * 0.10 * amp * e);
  }
}

function snare(at, amp = 1.0) {
  const start = Math.floor(at * RATE);
  const len = Math.floor(0.2 * RATE);
  for (let k = 0; k < len; k++) {
    const t = k / RATE;
    const e = Math.exp(-16 * t);
    const body = Math.sin(2 * Math.PI * 185 * t) * 0.22 * e;
    put(start + k, (rnd() * 0.55 + body) * amp);
  }
}

function hat(at, amp = 0.35) {
  const start = Math.floor(at * RATE);
  const len = Math.floor(0.05 * RATE);
  for (let k = 0; k < len; k++) {
    const t = k / RATE;
    put(start + k, rnd() * Math.exp(-55 * t) * amp);
  }
}

// --- бас: восьмые, тёмный квадрат с фильтром

let lp = 0;
function bass(at, freq, dur, amp = 1.0) {
  const start = Math.floor(at * RATE);
  const len = Math.floor(dur * RATE);
  const coef = 1 - Math.exp(-2 * Math.PI * 420 / RATE);
  let phase = 0;
  for (let k = 0; k < len; k++) {
    const t = k / RATE;
    phase += (2 * Math.PI * freq) / RATE;
    const raw = Math.tanh(Math.sin(phase) * 1.6 + Math.sin(phase * 2) * 0.35);
    lp += coef * (raw - lp);
    const e = Math.min(1, t / 0.008) * Math.exp(-3.4 * t);
    put(start + k, lp * e * 0.5 * amp);
  }
}

// --- мелодия и подложка

function tone(at, freq, dur, amp = 0.3, kind = 'tri') {
  const start = Math.floor(at * RATE);
  const len = Math.floor(dur * RATE);
  let phase = 0;
  for (let k = 0; k < len; k++) {
    const t = k / RATE;
    phase += (2 * Math.PI * freq) / RATE;
    let v;
    if (kind === 'tri') v = (2 / Math.PI) * Math.asin(Math.sin(phase));
    else if (kind === 'saw') v = ((phase / (2 * Math.PI)) % 1) * 2 - 1;
    else v = Math.sin(phase);
    const e = Math.min(1, t / 0.02) * Math.exp(-2.2 * t) * (1 - Math.min(1, t / dur));
    put(start + k, v * e * amp);
  }
}

// 8 тактов: аккорды и мелодия
const roots = [40, 40, 36, 36, 43, 43, 45, 47];       // E2 E2 C2 C2 G2 G2 A2 B2
const motif = [64, 64, 60, 60, 67, 67, 69, 71];       // E4 E4 C4 C4 G4 G4 A4 B4

for (let bar = 0; bar < BARS; bar++) {
  const t0 = bar * BAR;
  // бас: восьмые с акцентом на сильную долю
  for (let step = 0; step < 8; step++) {
    const at = t0 + step * (BEAT / 2);
    const accent = step % 2 === 0 ? 1.0 : 0.65;
    bass(at, midi(roots[bar]), BEAT * 0.5, accent);
  }
  // бочка 1 и 3, синкопы во второй половине
  kick(t0, 1.0);
  kick(t0 + BEAT * 2, 0.95);
  if (bar >= 3) kick(t0 + BEAT * 3.5, 0.7);
  // снейр 2 и 4
  snare(t0 + BEAT, 0.8);
  snare(t0 + BEAT * 3, 0.85);
  // хэты: восьмые, оффбит громче
  for (let step = 0; step < 8; step++) {
    hat(t0 + step * (BEAT / 2), step % 2 === 1 ? 0.42 : 0.22);
  }
  // мелодия: длинная нота в начале такта + отклик
  tone(t0 + 0.02, midi(motif[bar]), BEAT * 1.6, 0.26, 'tri');
  tone(t0 + BEAT * 2.5, midi(motif[bar] - 12), BEAT * 0.8, 0.16, 'sin');
  // низкая подложка — тревожный орган
  tone(t0 + 0.01, midi(roots[bar] - 12), BAR, 0.12, 'saw');
}

// мягкая компрессия и нормализация под луп
let peak = 0;
for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(mix[i]));
const gain = peak > 0 ? 0.82 / peak : 1;
for (let i = 0; i < n; i++) {
  mix[i] = Math.tanh(mix[i] * gain * 1.15) * 0.9;
}

function toWav(samples) {
  const N = samples.length;
  const data = Buffer.alloc(44 + N * 2);
  data.write('RIFF', 0);
  data.writeUInt32LE(36 + N * 2, 4);
  data.write('WAVE', 8);
  data.write('fmt ', 12);
  data.writeUInt32LE(16, 16);
  data.writeUInt16LE(1, 20);
  data.writeUInt16LE(1, 22);
  data.writeUInt32LE(RATE, 24);
  data.writeUInt32LE(RATE * 2, 28);
  data.writeUInt16LE(2, 32);
  data.writeUInt16LE(16, 34);
  data.write('data', 36);
  data.writeUInt32LE(N * 2, 40);
  for (let i = 0; i < N; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    data.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  return data;
}

const path = join(outDir, 'fight_loop.wav');
writeFileSync(path, toWav(mix));
console.log('ok', path, (TOTAL).toFixed(1) + 'c', Math.round(RATE * TOTAL * 2 / 1024) + 'КБ');
