import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
export default function Features() {
  return <Layout title="功能与使用场景" description="了解 Vertree 的版本树、自动快照、本机预览、系统菜单、分享，以及 Windows 文件工具的适用边界。"><main>
    <div className="vt-shell"><header className="vt-page-header"><p className="vt-eyebrow">功能与边界</p><Heading as="h1">记录变化，<br/>不改变你的工作方式</Heading><p>适合经常改稿的文档、设计文件和单个项目素材。每份版本独立保存在磁盘上，原软件仍负责编辑。</p></header>
      <div className="vt-grid">{[
        ['文档与方案','在提交、评审前手动备份并写备注。需要调整方向时，从已确认的一版创建分支。'],
        ['设计稿与素材','用普通文件副本留下阶段成果。能预览的格式先在树中确认，不支持的格式用原软件打开。'],
        ['脚本与配置','对单文件修改保留快照，必要时用本机 API 接入脚本。多人代码协作仍应使用 Git 等专门工具。'],
      ].map(([t,d])=><article className="vt-card" key={t}><Heading as="h2">{t}</Heading><p>{d}</p></article>)}</div>
    </div>
    <HomepageFeatures/>
    <section className="vt-shell" aria-labelledby="retention-title"><div className="vt-section-heading"><Heading as="h2" id="retention-title">阶段版本与自动快照，不是一回事</Heading></div>
      <div className="vt-doc-grid"><article className="vt-card"><Heading as="h3">手动版本：保留重要节点</Heading><p>版本号与备注进入文件名，主线和分支在版本树中查看。每一份都是完整副本，由你决定保留多久。</p><Link to="/docs/tutorial-usage/version-tree">查看版本树指南 →</Link></article><article className="vt-card"><Heading as="h3">自动快照：记录编辑过程</Heading><p>只在文件变化后按最小间隔备份，按任务数量上限清理已识别的旧快照。不是每一次按保存键都留一份。</p><Link to="/docs/tutorial-usage/monitoring">查看监控指南 →</Link></article></div>
      <div className="vt-callout"><strong>Windows 文件工具 · 3.0.0</strong><p><Link to="/docs/tutorial-usage/fast-delete">快速删除</Link>针对大文件与大量小文件设计，永久删除前需要确认；<Link to="/docs/tutorial-usage/file-locks">解除占用</Link>是独立的进程诊断页面。两个页面从 Windows 文件右键菜单进入，解除占用页面本身不删除文件。</p></div>
    </section>
    <section className="vt-shell vt-section"><div className="vt-section-heading"><Heading as="h2">提前知道这些限制</Heading><p>完整副本会占用磁盘空间；本地备份不能替代异地备份。Vertree 不提供云同步、多人合并，也不保证所有专有格式的预览与原软件完全一致。</p></div><div className="vt-actions"><Link className="button button--primary" to="/download">选择安装包</Link><Link className="button button--secondary" to="/docs/tutorial-usage/preview">查看格式与限制</Link></div></section>
  </main></Layout>;
}
