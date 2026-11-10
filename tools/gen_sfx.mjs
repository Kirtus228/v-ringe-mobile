// Генератор процедурных звуков для РИНГ 3D → res://sfx/*.wav (16-bit PCM, 22.05 кГц, моно).
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RATE = 22050;
const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', 'sfx');
mkdirSync(outDir, { recursive: true });

const rnd = () => Math.random() * 2 - 1;
const env = (t, dur, decay = 4) => Math.exp(-decay * t / dur);

function buf(seconds) {
  return new Float32Array(Math.floor(RATE * seconds));
}

function lowpass(sec, cutoff, wobble = 0) {
  const out = buf(sec.length / RATE);
  let y = 0;
  const dt = 1 / RATE;
  for (let i = 0; i < sec.length; i++) {
    const t = i * dt;
    const c = cutoff * (1 + wobble * Math.sin(t * 40));
    const a = 1 - Math.exp(-2 * Math.PI * c * dt);
    y += a * (sec[i] - y);
    out[i] = y;
  }
  return out;
}

const sounds = {};

// удар: низкий тон + шум
{
  const dur = 0.24;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const thump = Math.sin(2 * Math.PI * (74 - 20 * t) * t) * env(t, dur, 7);
    s[i] = thump * 0.85 + rnd() * env(t, dur, 14) * 0.55;
  }
  sounds['hit'] = lowpass(s, 3200);
}

// свист мимо / замах
{
  const dur = 0.17;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const e = Math.sin(Math.PI * Math.min(1, t / dur));
    s[i] = rnd() * e * 0.6;
  }
  sounds['whoosh'] = lowpass(s, 1600, 0.7);
}

// блок: короткий щелчок
{
  const dur = 0.1;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    s[i] = (Math.sin(2 * Math.PI * 1180 * t) * 0.5 + rnd() * 0.5) * env(t, dur, 12);
  }
  sounds['block'] = lowpass(s, 5200);
}

// гонг
{
  const dur = 1.1;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const a = Math.sin(2 * Math.PI * 880 * t) * Math.exp(-3.2 * t);
    const b = Math.sin(2 * Math.PI * 1320 * t) * Math.exp(-3.6 * t) * 0.55;
    const c = Math.sin(2 * Math.PI * 2640 * t) * Math.exp(-6.0 * t) * 0.22;
    s[i] = (a + b + c) * 0.55;
  }
  sounds['bell'] = s;
}

// нокдаун
{
  const dur = 0.9;
  const s = buf(dur);
  let phase = 0;
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const f = 230 * Math.exp(-1.6 * t) + 55;
    phase += (2 * Math.PI * f) / RATE;
    s[i] = (Math.sin(phase) * 0.7 + rnd() * 0.12 * Math.exp(-6 * t)) * Math.exp(-2.2 * t);
  }
  sounds['ko'] = lowpass(s, 2800);
}

// шаг по настилу
{
  const dur = 0.17;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const thud = Math.sin(2 * Math.PI * (120 - 40 * t) * t) * Math.exp(-18 * t);
    s[i] = thud * 0.8 + rnd() * Math.exp(-22 * t) * 0.45;
  }
  sounds['step'] = lowpass(s, 900);
}

// толчок корпусом
{
  const dur = 0.3;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const rumble = Math.sin(2 * Math.PI * (72 - 18 * t) * t) * Math.exp(-7 * t);
    const cloth = rnd() * Math.exp(-9 * t) * 0.5;
    s[i] = rumble * 0.7 + cloth;
  }
  sounds['shove'] = lowpass(s, 1400);
}

// толпа ликует на нокдаун
{
  const dur = 2.4;
  const s = buf(dur);
  let phase = 0;
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const rise = Math.min(1, t / 0.25);
    const tail = Math.exp(-1.1 * Math.max(0, t - 0.35));
    const wob = 0.75 + 0.25 * Math.sin(t * 17 + Math.sin(t * 5.5) * 3);
    const crowd = (rnd() * 0.5 + Math.sin(phase) * 0.35) * rise * tail * wob;
    phase += (2 * Math.PI * (240 + 60 * Math.sin(t * 3.1))) / RATE;
    s[i] = crowd;
  }
  sounds['cheer'] = lowpass(s, 2600);
}

// вздох трибун на пропущенный удар
{
  const dur = 0.9;
  const s = buf(dur);
  for (let i = 0; i < s.length; i++) {
    const t = i / RATE;
    const e = Math.sin(Math.PI * Math.min(1, t / dur)) * Math.exp(-0.8 * t);
    s[i] = (rnd() * 0.7 + Math.sin(2 * Math.PI * 320 * t) * 0.15) * e;
  }
  sounds['gasp'] = lowpass(s, 1800);
}

function toWav(samples) {
  const n = samples.length;
  const data = Buffer.alloc(44 + n * 2);
  data.write('RIFF', 0);
  data.writeUInt32LE(36 + n * 2, 4);
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
  data.writeUInt32LE(n * 2, 40);
  let peak = 0;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(samples[i]));
  const gain = peak > 0 ? 0.85 / peak : 1;
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i] * gain));
    data.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  return data;
}

for (const [name, samples] of Object.entries(sounds)) {
  const path = join(outDir, name + '.wav');
  writeFileSync(path, toWav(samples));
  console.log('ok', path, Math.round(samples.length / RATE * 1000) + 'ms');
}
