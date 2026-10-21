import assert from 'node:assert/strict';
import test from 'node:test';
import { describe, page, rewriteLinks, route, splitTitle } from './lib.mjs';

const base = '/watch-overwatch';

test('the first heading becomes the title and leaves the text', () => {
  const { title, body } = splitTitle('# 使用指引\n\n## 第一次使用\n\n正文');
  assert.equal(title, '使用指引');
  assert.equal(body, '## 第一次使用\n\n正文');
  assert.equal(splitTitle('没有标题').title, null);
});

test('the description is the first plain paragraph, without markup', () => {
  const body = '![图](images/a.png)\n\n| a | b |\n|---|---|\n\n这是 **第一段** 和 [链接](x.md)，还有 `code`。\n\n第二段';
  assert.equal(describe(body), '这是 第一段 和 链接，还有 code。');
  assert.equal(describe('```\ncode\n```\n'), '');
});

test('links to other pages, images and repository files are rewritten', () => {
  const src = 'docs/user-guide.md';
  const body = [
    '[a](credentials.md)',
    '[b](algorithms.md#4-对局强度)',
    '![c](images/matches.png)',
    '[d](../crates/watch-core/src/ir.rs)',
    '[e](../CHANGELOG.md)',
    '[f](https://example.com/x.md)',
    '[g](#本页)',
    '[h](watch-overwatch.schema.json)',
  ].join('\n');
  const { text, broken } = rewriteLinks(body, src, base);
  assert.deepEqual(broken, []);
  assert.equal(
    text,
    [
      '[a](/watch-overwatch/credentials/)',
      '[b](/watch-overwatch/algorithms/#4-对局强度)',
      '![c](/watch-overwatch/images/matches.png)',
      '[d](https://github.com/KCN-judu/watch-overwatch/blob/main/crates/watch-core/src/ir.rs)',
      '[e](/watch-overwatch/changelog/)',
      '[f](https://example.com/x.md)',
      '[g](#本页)',
      '[h](/watch-overwatch/watch-overwatch.schema.json)',
    ].join('\n'),
  );
});

test('the changelog links to the docs from the repository root', () => {
  const { text } = rewriteLinks('[审计](docs/audit-2026-10.md)', 'CHANGELOG.md', base);
  assert.equal(text, '[审计](/watch-overwatch/audit/)');
});

test('code blocks are left as they are, and a link out of the repository is reported', () => {
  const body = '```\n[x](a.md)\n```\n\n[y](../../outside.md)';
  const { text, broken } = rewriteLinks(body, 'docs/a.md', base);
  assert.ok(text.includes('[x](a.md)'));
  assert.deepEqual(broken, ['../../outside.md']);
});

test('the home page is the root route', () => {
  assert.equal(route(base, 'index'), '/watch-overwatch/');
  assert.equal(route(base, 'cli'), '/watch-overwatch/cli/');
});

test('front matter is quoted so a colon in a title cannot break it', () => {
  const p = page({ title: 'a: b', description: '说明 "引号"', body: '正文\n' });
  assert.ok(p.startsWith('---\ntitle: "a: b"\ndescription: "说明 \\"引号\\""\n---'));
});
