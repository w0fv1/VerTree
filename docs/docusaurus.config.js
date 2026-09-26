// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Vertree 维树',
  tagline: '让每一次迭代都有迹可循',
  favicon: 'logo.ico',
  staticDirectories: ['static', '../assets/img/logo'],
  url: 'https://vertree.w0fv1.dev',
  baseUrl: '/',
  organizationName: 'w0fv1',
  projectName: 'vertree',
  onBrokenLinks: 'throw',
  markdown: {hooks: {onBrokenMarkdownLinks: 'throw', onBrokenMarkdownImages: 'throw'}},
  i18n: {defaultLocale: 'zh', locales: ['zh']},
  presets: [['classic', {
    docs: {
      sidebarPath: './sidebars.js',
      editUrl: 'https://github.com/w0fv1/VerTree/tree/main/docs/',
      showLastUpdateTime: false,
    },
    blog: {
      blogTitle: '更新与设计记录',
      blogDescription: '版本变化、升级说明与 Vertree 的设计取舍。',
      blogSidebarTitle: '更新与设计记录',
      blogSidebarCount: 'ALL',
      showReadingTime: true,
      feedOptions: {type: ['rss', 'atom'], xslt: true},
      editUrl: 'https://github.com/w0fv1/VerTree/tree/main/docs/',
      onInlineTags: 'warn', onInlineAuthors: 'warn', onUntruncatedBlogPosts: 'throw',
    },
    theme: {customCss: './src/css/custom.css'},
  }]],
  themeConfig: {
    image: 'img/brand-home-page.png',
    colorMode: {defaultMode: 'light', respectPrefersColorScheme: true},
    metadata: [{name: 'theme-color', content: '#f6f7f3'}],
    navbar: {
      title: 'Vertree 维树',
      logo: {alt: 'Vertree 首页', src: 'logo.png', width: 28, height: 28},
      items: [
        {to: '/features', label: '功能', position: 'left'},
        {type: 'docSidebar', sidebarId: 'tutorialSidebar', label: '使用文档', position: 'left'},
        {to: '/blog', label: '更新记录', position: 'left'},
        {href: 'https://github.com/w0fv1/VerTree', label: 'GitHub', position: 'right'},
        {to: '/download', label: '下载', position: 'right', className: 'nav-download'},
      ],
    },
    footer: {
      style: 'light',
      links: [
        {title: '开始使用', items: [
          {label: '下载与安装', to: '/download'},
          {label: '完成第一次备份', to: '/docs/tutorial-usage/quick-start'},
          {label: '功能概览', to: '/features'},
        ]},
        {title: '查阅指南', items: [
          {label: '预览与格式支持', to: '/docs/tutorial-usage/preview'},
          {label: '右键菜单与命令行', to: '/docs/tutorial-usage/entry-points'},
          {label: '常见问题', to: '/docs/tutorial-usage/troubleshooting'},
        ]},
        {title: '参与项目', items: [
          {label: '源代码 · MIT', href: 'https://github.com/w0fv1/VerTree'},
          {label: '反馈问题', href: 'https://github.com/w0fv1/VerTree/issues'},
          {label: '捐助支持', href: 'https://next.firco.cn/w0fv1?focusProduct=product-8283788fa5724d25ae65958d1b61b288'},
        ]},
      ],
      copyright: `© ${new Date().getFullYear()} Vertree · 让每一次迭代都有迹可循`,
    },
    tableOfContents: {minHeadingLevel: 2, maxHeadingLevel: 3},
    prism: {
      // Explicit palettes avoid low-contrast comments and PowerShell variables.
      theme: {
        plain: {color: '#24352a', backgroundColor: '#f1f4ef'},
        styles: [
          {types: ['comment','prolog','doctype','cdata'], style: {color:'#596758'}},
          {types: ['punctuation','operator'], style: {color:'#3d5143'}},
          {types: ['property','tag','constant','symbol','deleted','number','boolean'], style: {color:'#7c3459'}},
          {types: ['selector','attr-name','string','char','builtin','inserted'], style: {color:'#276137'}},
          {types: ['entity','url','variable','parameter'], style: {color:'#146065'}},
          {types: ['atrule','attr-value','keyword','function','class-name'], style: {color:'#644594'}},
        ],
      },
      darkTheme: {
        plain: {color:'#e7eede', backgroundColor:'#1d2720'},
        styles: [
          {types: ['comment','prolog','doctype','cdata'], style: {color:'#a7b4a6'}},
          {types: ['punctuation','operator'], style: {color:'#cfddcb'}},
          {types: ['property','tag','constant','symbol','deleted','number','boolean'], style: {color:'#f0b4cc'}},
          {types: ['selector','attr-name','string','char','builtin','inserted'], style: {color:'#b9dba1'}},
          {types: ['entity','url','variable','parameter'], style: {color:'#9dcbd0'}},
          {types: ['atrule','attr-value','keyword','function','class-name'], style: {color:'#cfc0ee'}},
        ],
      },
      additionalLanguages: ['powershell', 'dart', 'bash', 'json'],
    },
  },
};
export default config;
