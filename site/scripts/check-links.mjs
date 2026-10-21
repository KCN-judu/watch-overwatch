// After `npm run build`: every internal link and image of the built site must lead to a
// file (and, for a link with an anchor, to an element with that id).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../dist');
const base = process.env.DOCS_BASE ?? '/watch-overwatch';

const html = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.html')) html.push(p);
  }
})(dist);

const ids = new Map();
const idsOf = (file) => {
  if (!ids.has(file)) {
    ids.set(file, new Set([...fs.readFileSync(file, 'utf8').matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])));
  }
  return ids.get(file);
};

let bad = 0;
for (const file of html) {
  const text = fs.readFileSync(file, 'utf8');
  for (const m of text.matchAll(/(?:href|src)="(\/[^"#?]*)(#[^"]*)?"/g)) {
    const [, target, hash] = m;
    if (target.startsWith('//') || !target.startsWith(base)) continue;
    const rel = decodeURIComponent(target.slice(base.length)) || '/';
    const candidates = [path.join(dist, rel), path.join(dist, rel, 'index.html')];
    const found = candidates.find((c) => fs.existsSync(c) && fs.statSync(c).isFile());
    if (!found) {
      console.error(`${path.relative(dist, file)}: no file for ${target}`);
      bad += 1;
    } else if (hash && found.endsWith('.html') && !idsOf(found).has(decodeURIComponent(hash.slice(1)))) {
      console.error(`${path.relative(dist, file)}: no anchor ${hash} in ${target}`);
      bad += 1;
    }
  }
}
if (bad) process.exit(1);
console.log(`checked ${html.length} pages`);
