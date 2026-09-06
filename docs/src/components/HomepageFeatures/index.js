import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const features = [
  { title: '把文件历史画成树', emoji: '🌲', description: '主线、分支和备注都能直接查看。每个版本都是普通文件副本，可以继续用原来的软件打开。', to: '/docs/tutorial-usage/usage' },
  { title: '预览当前稿与旧版本', emoji: '📄', description: '查看文档、表格、幻灯片、图片、媒体和更多格式。文件在本机处理，打开新预览时自动关闭上一个。', to: '/docs/tutorial-usage/preview' },
  { title: '保存时自动留档', emoji: '⏱️', description: '监控单个文件的变化，按备份间隔保留副本，并按数量上限清理旧备份。重要节点还可以手动备份。', to: '/docs/tutorial-usage/usage#自动监控' },
  { title: '从熟悉的系统入口操作', emoji: '🖱️', description: 'Windows 右键菜单、macOS Services 和 Linux Files 集成，让备份与版本树操作靠近文件本身。', to: '/docs/tutorial-usage/entry-points' },
  { title: '把一个版本分享到局域网', emoji: '📡', description: '生成临时链接和二维码，让同一网络里的设备直接下载。文件由你的电脑提供，不上传到云端。', to: '/docs/tutorial-usage/sharing' },
  { title: '按需要接入自动化', emoji: '🔧', description: '用命令行调用常用操作，或启用带认证的本机 API 查询监控、备份和版本树。开发者可以控制热更新。', to: '/docs/tutorial-develop/local-api' },
];

export default function HomepageFeatures() {
  return (
    <section className={styles.features} aria-label="主要功能">
      <div className="container">
        <div className="row">
          {features.map(({ title, emoji, description, to }) => (
            <div key={to + title} className={clsx('col col--4', 'margin-bottom--lg')}>
              <div className="padding-horiz--md">
                <p style={{ fontSize: '2.4rem', marginBottom: '0.5rem' }} aria-hidden="true">{emoji}</p>
                <Heading as="h2" className="h3"><Link to={to}>{title}</Link></Heading>
                <p>{description}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
