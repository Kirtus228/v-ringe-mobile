import fs from 'node:fs';

const files = ['games/boxing3d/scripts/training/training_mode.gd', 'games/boxing3d/scripts/lang.gd'];
const sus = /[\u0420\u0421][\u2019\u0406\u0455\u00b5\u00b0\u0402-\u040f\u0452-\u045f]/g;
for (const f of files) {
  const text = fs.readFileSync(f, 'utf8');
  const lines = text.split('\n');
  let shown = 0;
  const counts = {};
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(sus);
    if (m) {
      for (const s of m) counts[s] = (counts[s] || 0) + 1;
      if (shown < 6) {
        console.log(`${f}:${i + 1}: ${lines[i].slice(0, 160)}`);
        shown++;
      }
    }
  }
  console.log(f, 'suspect chars:', JSON.stringify(counts).slice(0, 400));
}
