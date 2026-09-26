import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
export default function NotFound() {
  return <Layout title="没有找到这个页面" description="页面可能已移动，请从 Vertree 文档中心继续查找。"><main className="vt-empty"><p className="vt-eyebrow">404 · 页面不存在</p><h1>这条路径暂时没有记录</h1><p>页面可能已经移动，或链接没有复制完整。你的本地文件不受影响。</p><div className="vt-actions"><Link className="button button--primary" to="/docs/intro">前往文档中心</Link><Link className="button button--secondary" to="/">返回首页</Link></div></main></Layout>;
}
