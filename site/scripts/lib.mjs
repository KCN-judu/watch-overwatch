// Turns the plain Markdown in ../docs into pages of the site. The docs stay readable on
// GitHub as they are (relative links, no front matter); this is where they become routes.
import path from 'node:path';

export const REPO = 'https://github.com/KCN-judu/watch-overwatch';
export const BRANCH = 'main';

/** The pages, in the order of the sidebar. `src` is relative to the repository root. */
export const PAGES = [
  { src: 'docs/overview.md', slug: 'index', title: '概览' },
  { src: 'docs/getting-started.md', slug: 'getting-started' },
  { src: 'docs/user-guide.md', slug: 'user-guide' },
  { src: 'docs/credentials.md', slug: 'credentials' },
  { src: 'docs/http-api.md', slug: 'http-api' },
  { src: 'docs/cli.md', slug: 'cli' },
  { src: 'docs/data-model.md', slug: 'data-model' },
  { src: 'docs/export.md', slug: 'export' },
  { src: 'docs/architecture.md', slug: 'architecture' },
  { src: 'docs/algorithms.md', slug: 'algorithms' },
  { src: 'docs/ui-design.md', slug: 'ui-design' },
  { src: 'docs/product-design.md', slug: 'product-design' },
  { src: 'docs/game-data.md', slug: 'game-data' },
  { src: 'docs/icon-audit.md', slug: 'icon-audit' },
  { src: 'docs/reference-projects.md', slug: 'reference-projects' },
  { src: 'docs/audit-2026-10.md', slug: 'audit' },
  { src: 'CHANGELOG.md', slug: 'changelog' },
];

/** Files that are served as they are, keyed by their path in the repository. */
export const ASSET_DIRS = [{ from: 'docs/images', to: 'images' }];
export const ASSET_FILES = [{ from: 'docs/watch-overwatch.schema.json', to: 'watch-overwatch.schema.json' }];

/** The route of a page under `base` (no trailing slash in `base`). */
export function route(base, slug) {
  return slug === 'index' ? `${base}/` : `${base}/${slug}/`;
}

/** First `# heading` and the text without it. */
export function splitTitle(markdown) {
  const lines = markdown.split('\n');
  const i = lines.findIndex((l) => /^# /.test(l));
  if (i < 0) return { title: null, body: markdown };
  const title = lines[i].replace(/^# /, '').trim();
  lines.splice(i, 1);
  return { title, body: lines.join('\n').replace(/^\s*\n/, '') };
}

/** A one-sentence description for the page head: the first plain paragraph. */
export function describe(body) {
  let inCode = false;
  for (const para of body.split(/\n\s*\n/)) {
    const lines = para.split('\n');
    if (lines[0].startsWith('```')) inCode = !inCode;
    if (inCode || /^(#|\||>|!\[|[-*] |\d+\. |```)/.test(para.trim())) continue;
    const text = para
      .replace(/`([^`]*)`/g, '$1')
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/[*_]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
    if (text) return text.length > 120 ? `${text.slice(0, 118)}…` : text;
  }
  return '';
}

/**
 * Rewrites the relative links and images of the page whose source is `src`.
 * Returns the new text and the links that lead nowhere.
 */
export function rewriteLinks(body, src, base, pages = PAGES) {
  const bySrc = new Map(pages.map((p) => [path.posix.normalize(p.src), p]));
  const broken = [];
  const one = (whole, bang, label, target) => {
    if (/^([a-z][a-z0-9+.-]*:|#|\/)/i.test(target)) return whole;
    const [file, anchor] = target.split('#');
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(src), file));
    const hash = anchor ? `#${anchor}` : '';
    const page = bySrc.get(resolved);
    if (page) return `${bang}[${label}](${route(base, page.slug)}${hash})`;
    for (const d of ASSET_DIRS) {
      if (resolved.startsWith(`${d.from}/`)) {
        return `${bang}[${label}](${base}/${d.to}/${resolved.slice(d.from.length + 1)}${hash})`;
      }
    }
    for (const f of ASSET_FILES) {
      if (resolved === f.from) return `${bang}[${label}](${base}/${f.to})`;
    }
    if (resolved.startsWith('..')) {
      broken.push(target);
      return whole;
    }
    return `${bang}[${label}](${REPO}/blob/${BRANCH}/${resolved}${hash})`;
  };
  // Code blocks are left alone: odd segments between ``` fences.
  const text = body
    .split(/^(```.*)$/m)
    .map((chunk, i, all) => {
      const fences = all.slice(0, i).filter((c) => c.startsWith('```')).length;
      return fences % 2 === 1 || chunk.startsWith('```')
        ? chunk
        : chunk.replace(/(!?)\[([^\]]*)\]\(([^)\s]+)\)/g, one);
    })
    .join('');
  return { text, broken };
}

/** The page file: front matter, then the text. */
export function page({ title, description, body }) {
  return `---\ntitle: ${JSON.stringify(title)}\ndescription: ${JSON.stringify(description)}\n---\n\n${body.trimEnd()}\n`;
}
