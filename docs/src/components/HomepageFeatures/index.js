import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import SiteIcon from '../SiteIcon';
import styles from './styles.module.css';
const features = [
  {icon: 'tree', title: '把历史整理成版本树', description: '主线、分支和备注放在一起。先确认来路，再决定从哪个版本继续。', to: '/docs/tutorial-usage/version-tree'},
  {icon: 'clock', title: '在编辑过程中保留快照', description: '监听文件变化，按间隔自动留档。重要节点仍可手动备份，两种方式各有分工。', to: '/docs/tutorial-usage/monitoring'},
  {icon: 'preview', title: '先看内容，再打开编辑', description: '只读预览文档、图片与媒体；历史文件也能查看。不支持的格式交给原软件。', to: '/docs/tutorial-usage/preview'},
  {icon: 'menu', title: '操作就在文件旁边', description: '从系统菜单发起备份或查看版本。Windows 两套右键菜单分别配置。', to: '/docs/tutorial-usage/entry-points'},
  {icon: 'share', title: '把这一版分享出去', description: '生成临时链接与二维码，让能连通的局域网设备从你的电脑下载文件。', to: '/docs/tutorial-usage/sharing'},
  {icon: 'code', title: '也能交给脚本处理', description: '按需开启本机 API，用认证请求查询版本、快照与监控。不需要时保持关闭。', to: '/docs/tutorial-develop/local-api'},
];
export default function HomepageFeatures() {
  return <section className="vt-shell vt-section" aria-labelledby="features-title">
    <div className="vt-section-heading"><p className="vt-eyebrow">围绕文件，减少来回</p><Heading as="h2" id="features-title">从保存一份，到看清每一版</Heading><p>不替换你的编辑器，也不要求换一种文件格式。</p></div>
    <div className={styles.grid}>{features.map(item => <Link key={item.icon} to={item.to} className={styles.card}>
      <span className={styles.icon}><SiteIcon name={item.icon}/></span>
      <Heading as="h3">{item.title}</Heading><p>{item.description}</p><span className={styles.read}>了解用法 <span aria-hidden="true">↗</span></span>
    </Link>)}</div>
  </section>;
}
