import fs from 'node:fs';
import path from 'node:path';

const root = 'games/boxing3d/scripts';
const patterns = [
  ['CP1251-double', /[\u0420\u2019\u0406\u0455\u00b5\u00b0][\u0402-\u203a]/g],
  ['mojibake-Cyr', /Р[\u0400-\u04ff]/g],
  ['times-broken', /Р’В/g],
];
function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (e.name.endsWith('.gd')) out.push(p);
  }
  return out;
}
let total = 0;
for (const f of walk(root)) {
  const text = fs.readFileSync(f, 'utf8');
  let bad = 0;
  for (const [, re] of patterns) bad += (text.match(re) || []).length;
  if (bad > 0) {
    total += bad;
    console.log(`${f} : ${bad}`);
  }
}
console.log('TOTAL bad patterns:', total);
