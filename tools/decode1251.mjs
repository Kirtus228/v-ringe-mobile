import fs from 'node:fs';

const dec = new TextDecoder('windows-1251');
const charToByte = new Map();
for (let b = 0; b < 256; b++) charToByte.set(dec.decode(Uint8Array.from([b])), b);

const text = fs.readFileSync(process.argv[2], 'utf8');
const bytes = [];
let unmapped = 0;
for (const ch of text) {
  if (charToByte.has(ch)) bytes.push(charToByte.get(ch));
  else {
    unmapped++;
    bytes.push(...Buffer.from(ch, 'utf8'));
  }
}
const buf = Buffer.from(bytes);
const out = new TextDecoder('utf-8', { fatal: false }).decode(buf);
const bad = (out.match(/\uFFFD/g) || []).length;
console.log('unmapped chars:', unmapped, 'replacement chars:', bad, 'out length:', out.length);
fs.writeFileSync(process.argv[3], out, 'utf8');
if (bad > 0) {
  // показать первое место
  const idx = out.indexOf('\uFFFD');
  console.log('first bad context:', JSON.stringify(out.slice(Math.max(0, idx - 40), idx + 40)));
}
