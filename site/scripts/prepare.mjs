// Collects the site's pages from ../docs and ../CHANGELOG.md into src/content/docs, and
// the images and the JSON schema into public/. Run by `npm run dev` and `npm run build`;
// the generated files are not committed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ASSET_DIRS, ASSET_FILES, PAGES, describe, page, rewriteLinks, splitTitle } from './lib.mjs';

const site = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(site, '..');
const base = process.env.DOCS_BASE ?? '/watch-overwatch';
const out = path.join(site, 'src/content/docs');
const publicDir = path.join(site, 'public');

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

let problems = 0;
for (const p of PAGES) {
  const raw = fs.readFileSync(path.join(root, p.src), 'utf8').replace(/\r\n/g, '\n');
  const { title, body } = splitTitle(raw);
  const { text, broken } = rewriteLinks(body, p.src, base);
  for (const link of broken) {
    console.error(`${p.src}: link leaves the repository: ${link}`);
    problems += 1;
  }
  const heading = p.title ?? title;
  if (!heading) {
    console.error(`${p.src}: no "# title" line`);
    problems += 1;
    continue;
  }
  fs.writeFileSync(
    path.join(out, `${p.slug}.md`),
    page({ title: heading, description: describe(text), body: text }),
  );
}

for (const d of ASSET_DIRS) {
  const to = path.join(publicDir, d.to);
  fs.rmSync(to, { recursive: true, force: true });
  fs.cpSync(path.join(root, d.from), to, { recursive: true });
}
for (const f of ASSET_FILES) {
  fs.mkdirSync(publicDir, { recursive: true });
  fs.copyFileSync(path.join(root, f.from), path.join(publicDir, f.to));
}

// An image a page mentions must exist.
for (const p of PAGES) {
  const text = fs.readFileSync(path.join(out, `${p.slug}.md`), 'utf8');
  for (const m of text.matchAll(/!\[[^\]]*\]\(([^)\s]+)\)/g)) {
    const rel = m[1].startsWith(base) ? m[1].slice(base.length) : null;
    if (rel && !fs.existsSync(path.join(publicDir, rel))) {
      console.error(`${p.src}: missing image ${m[1]}`);
      problems += 1;
    }
  }
}

if (problems) process.exit(1);
console.log(`prepared ${PAGES.length} pages`);
