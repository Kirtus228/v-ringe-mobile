import fs from 'node:fs';

const dec = new TextDecoder('windows-1251');
const charToByte = new Map();
for (let b = 0; b < 256; b++) charToByte.set(dec.decode(Uint8Array.from([b])), b);

const sus = /[\u0420\u0421][\u2019\u0406\u0455\u00b5\u00b0\u0402-\u040f\u0452-\u045f\u201a\u00ad]/;

const text = fs.readFileSync(process.argv[2], 'utf8');
const lines = text.split('\n');
let fixed = 0;
let failed = 0;
const outLines = lines.map((line) => {
  if (!sus.test(line)) return line;
  const bytes = [];
  let ok = true;
  for (const ch of line) {
    if (charToByte.has(ch)) bytes.push(charToByte.get(ch));
    else { ok = false; break; }
  }
  if (!ok) { failed++; return line; }
  const decoded = new TextDecoder('utf-8', { fatal: false }).decode(Buffer.from(bytes));
  if (decoded.includes('\uFFFD')) { failed++; return line; }
  fixed++;
  return decoded;
});
fs.writeFileSync(process.argv[3], outLines.join('\n'), 'utf8');
const still = outLines.filter((l) => sus.test(l)).length;
console.log('lines fixed:', fixed, 'failed:', failed, 'still suspicious lines:', still);
