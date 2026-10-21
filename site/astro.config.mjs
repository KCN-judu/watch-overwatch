import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';

const repo = 'https://github.com/KCN-judu/watch-overwatch';

export default defineConfig({
  site: 'https://kcn-judu.github.io',
  base: process.env.DOCS_BASE ?? '/watch-overwatch',
  integrations: [
    starlight({
      title: 'Watch Overwatch',
      favicon: '/favicon.png',
      description: '国服守望先锋的对局与数据分析桌面应用：使用指引、接口、算法和设计文档。',
      defaultLocale: 'root',
      locales: { root: { label: '简体中文', lang: 'zh-CN' } },
      social: [{ icon: 'github', label: 'GitHub', href: repo }],
      customCss: ['./src/styles/custom.css'],
      lastUpdated: false,
      pagination: true,
      sidebar: [
        { label: '概览', slug: 'index' },
        {
          label: '教程',
          items: [{ slug: 'getting-started' }, { slug: 'user-guide' }, { slug: 'credentials' }],
        },
        {
          label: '参考',
          items: [{ slug: 'http-api' }, { slug: 'cli' }, { slug: 'data-model' }, { slug: 'export' }],
        },
        {
          label: '设计',
          items: [
            { slug: 'architecture' },
            { slug: 'algorithms' },
            { slug: 'ui-design' },
            { slug: 'product-design' },
            { slug: 'game-data' },
            { slug: 'icon-audit' },
            { slug: 'reference-projects' },
            { slug: 'audit' },
          ],
        },
        { label: '更新记录', slug: 'changelog' },
      ],
    }),
  ],
});
