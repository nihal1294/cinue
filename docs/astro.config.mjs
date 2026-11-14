import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://nihal1294.github.io',
  base: '/cinue',
  publicDir: './media',
  integrations: [starlight({
    title: 'Cinue',
    favicon: '/cinue-icon.png',
    customCss: ['./stylesheets/extra.css'],
    sidebar: [
      { label: 'Overview', slug: '' },
      { label: 'Install and run', slug: 'installation' },
      { label: 'User guide', slug: 'user-guide' },
    ],
  })],
});
