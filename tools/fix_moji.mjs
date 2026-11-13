import fs from 'node:fs';

const sus = /[\u0420\u0421][\u2019\u0406\u0455\u00b5\u00b0\u0402-\u040f\u0452-\u045f\u201a\u2018\u201c\u201d\u2013\u2014\u2026\u00ad]/g;

function buildMap(enc) {
  const dec = new TextDecoder(enc);
  const charToByte = new Map();
  for (let b = 0; b < 256; b++) charToByte.set(dec.decode(Uint8Array.from([b])), b);
  return charToByte;
}

function reverseOnce(text, charToByte) {
  const bytes = [];
  for (const ch of text) {
    if (charToByte.has(ch)) bytes.push(charToByte.get(ch));
    else bytes.push(...Buffer.from(ch, 'utf8'));
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(bytes));
  } catch {
    return null;
  }
}

const file = process.argv[2];
const target = process.argv[3];
const original = fs.readFileSync(file, 'utf8');
let best = original;
let bestScore = (original.match(sus) || []).length;
console.log('start suspect:', bestScore);
for (const enc of ['windows-1252', 'windows-1251']) {
  const map = buildMap(enc);
  let text = original;
  for (let round = 1; round <= 3; round++) {
    const out = reverseOnce(text, map);
    if (out == null) break;
    const score = (out.match(sus) || []).length;
    console.log(`${enc} round ${round}: suspect ${score}`);
    if (score < bestScore) {
      bestScore = score;
      best = out;
    }
    text = out;
    if (score === 0) break;
  }
}
fs.writeFileSync(target, best, 'utf8');
console.log('written', target, 'suspect now', bestScore);
