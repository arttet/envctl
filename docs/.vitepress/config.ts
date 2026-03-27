import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: '/envctl/',

  title: "envctl",
  description: "Envctl docs",
  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/introduction' },
      { text: 'Reference', link: '/reference/commands' }
    ],

    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Introduction', link: '/guide/introduction' },
          { text: 'Installation', link: '/guide/installation' },
          { text: 'Quick Start', link: '/guide/getting-started' }
        ]
      },
      {
        text: 'Guide',
        items: [
          { text: 'Configuration', link: '/guide/configuration' },
          { text: 'Tokens & Grammar', link: '/guide/tokens' },
          { text: 'Profiles', link: '/guide/profiles' }
        ]
      },
      {
        text: 'Reference',
        items: [
          { text: 'Commands', link: '/reference/commands' },
          { text: 'Plugins (Providers & Backends)', link: '/reference/plugins' }
        ]
      },
      {
        text: 'Architecture',
        items: [
          { text: 'Overview', link: '/guide/architecture' }
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/arttet/envctl' }
    ]
  }
})
