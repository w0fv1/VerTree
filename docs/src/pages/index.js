import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import SiteIcon from '@site/src/components/SiteIcon';
import styles from './index.module.css';

export default function Home() {
  return <Layout title="让每一次迭代都有迹可循" description="Vertree 用普通文件副本保留版本，通过版本树查看主线与分支，按需自动备份、本机预览和局域网分享。">
    <main>
      <header className={styles.hero}>
        <div className={`vt-shell ${styles.heroGrid}`}>
          <div className={styles.heroText}>
            <p className="vt-eyebrow">VERTREE 维树 · 开源桌面工具</p>
            <Heading as="h1">让每一次迭代<br/><span>都有迹可循</span></Heading>
            <p className={styles.lead}>文件还用原来的软件编辑，历史交给 Vertree 整理。<br className={styles.desktopBreak}/>保留阶段版本，看清分支，从容回到需要的那一版。</p>
            <div className="vt-actions"><Link className="button button--primary" to="/download">下载 Vertree</Link><Link className="button button--secondary" to="/docs/tutorial-usage/quick-start">完成第一次备份 <span aria-hidden="true">→</span></Link></div>
            <p className={styles.platforms}>Windows · macOS · Linux<span>MIT 开源许可</span></p>
          </div>
          <figure className={styles.preview}>
            <div className={styles.previewBar}><span className={styles.dot}/><span>版本树 · 同一份文件的不同方向</span></div>
            <img src={useBaseUrl('/img/version-tree-overview.png')} alt="Vertree 版本树，展示示例文件的主线、历史节点和分支" width="1280" height="800" fetchPriority="high"/>
            <figcaption>每个版本都是普通文件副本，不锁在专有数据库里。</figcaption>
          </figure>
        </div>
      </header>
      <div className={styles.principles}><div className="vt-shell"><span>文件副本直接可用</span><span>预览在本机处理</span><span>不改变原有编辑习惯</span></div></div>
      <HomepageFeatures/>
      <section className={styles.workflow} aria-labelledby="workflow-title"><div className="vt-shell">
        <div className="vt-section-heading"><p className="vt-eyebrow">先做好一件小事</p><Heading as="h2" id="workflow-title">给下一次修改，留一个起点</Heading><p>从一个常用文件开始，不必先整理整台电脑。</p></div>
        <div className={styles.steps}>{[
          ['01','保存当前文件','在原软件中保存。对需要留档的版本执行“备份文件”。'],
          ['02','给阶段写个备注','例如“客户确认”或“备选方向”，以后找回时少猜一步。'],
          ['03','在版本树里继续','预览历史节点，确认起点；需要另一种方案时创建分支。'],
        ].map(([n,t,d]) => <article key={n}><span>{n}</span><Heading as="h3">{t}</Heading><p>{d}</p></article>)}</div>
      </div></section>
      <section className="vt-shell vt-section" aria-labelledby="windows-tools-title"><div className={styles.tools}>
        <div><p className="vt-eyebrow">WINDOWS 文件工具 · 3.0.0</p><Heading as="h2" id="windows-tools-title">清理文件，与查看占用，分开处理</Heading><p>两个独立页面，从文件右键菜单进入。3.0.0 提供快速永久删除和本机占用诊断；执行删除或结束程序前明确确认。</p></div>
        <div className={styles.toolLinks}>
          <Link to="/docs/tutorial-usage/fast-delete"><SiteIcon name="bolt"/><strong>快速删除</strong><span>大文件与海量小文件；永久删除，先确认一次。</span><span aria-hidden="true">→</span></Link>
          <Link to="/docs/tutorial-usage/file-locks"><SiteIcon name="unlock"/><strong>解除占用</strong><span>查看占用进程，按需结束任务；本身不删除文件。</span><span aria-hidden="true">→</span></Link>
        </div>
      </div></section>
      <section className={styles.finalCta}><div className="vt-shell"><div><Heading as="h2">把重要的一版，留下来</Heading><p>从一次手动备份开始，按需要再启用监控。</p></div><Link className="button button--primary" to="/download">选择安装包 <span aria-hidden="true">→</span></Link></div></section>
    </main>
  </Layout>;
}
