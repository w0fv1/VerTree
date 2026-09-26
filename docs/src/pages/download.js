import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
const release='https://github.com/w0fv1/VerTree/releases';
const version='3.0.0';
const asset=(name)=>`${release}/download/V${version}/${name}`;
export default function Download() {
  return <Layout title="下载与安装" description="按平台选择 Vertree 安装包：Windows x64、macOS Apple Silicon、Linux x64。查看安装要求、版本边界与校验方法。"><main className="vt-shell">
    <header className="vt-page-header"><p className="vt-eyebrow">下载 VERTREE</p><Heading as="h1">选对安装包，<br/>从一次备份开始</Heading><p>下列链接对应正式版 <strong>{version}</strong>。普通使用不需要 Flutter、Node.js 或独立 Office-Viewer。</p><Link to={`${release}/latest`}>在 GitHub 查看最新发布与全部附件 ↗</Link></header>
    <div className="vt-grid">
      <article className="vt-card"><p className="vt-eyebrow">WINDOWS · X64</p><Heading as="h2">日常使用，选 EXE</Heading><p>完整安装程序，包含应用与预览资源。预览需要 WebView2 Runtime；Windows 11 新菜单还需成功注册包身份。</p><Link className="button button--primary" to={asset(`vertree-windows-x64-${version}-setup.exe`)}>下载 Windows 安装包</Link><p style={{marginTop:16}}><Link to={asset(`vertree-windows-x64-${version}.zip`)}>ZIP 便携版</Link> · <Link to={asset(`vertree-windows-x64-${version}.msi`)}>MSI</Link></p><Link to="/docs/tutorial-usage/install#windows">Windows 安装说明 →</Link></article>
      <article className="vt-card"><p className="vt-eyebrow">MACOS · APPLE SILICON</p><Heading as="h2">拖入应用程序</Heading><p>此版本提供 arm64 构建，预览使用系统 WKWebView。当前发布流程未进行 Apple 公证，首次打开可能需要系统确认。</p><Link className="button button--secondary" to={asset(`vertree-macos-arm64-${version}.dmg`)}>下载 macOS DMG</Link><p style={{marginTop:16}}><Link to={asset(`vertree-macos-arm64-${version}.zip`)}>ZIP 应用归档</Link></p><Link to="/docs/macos">macOS 使用说明 →</Link></article>
      <article className="vt-card"><p className="vt-eyebrow">LINUX · X64</p><Heading as="h2">按发行版选择</Heading><p>Debian / Ubuntu 选 DEB，Fedora 等系统选 RPM。交互预览使用本机浏览器，菜单与托盘依赖桌面环境。</p><Link className="button button--secondary" to={asset(`vertree-linux-x64-${version}.deb`)}>下载 Linux DEB</Link><p style={{marginTop:16}}><Link to={asset(`vertree-linux-x64-${version}.rpm`)}>RPM</Link> · <Link to={asset(`vertree-linux-x64-${version}.tar.gz`)}>TAR.GZ 便携版</Link></p><Link to="/docs/linux">Linux 使用说明 →</Link></article>
    </div>
    <aside className="vt-callout"><strong>3.0.0：文件工具与体验更新</strong><p>此版本包含 Windows 快速删除、解除占用、两套菜单逐项设置与新版首页。删除为永久删除，不进入回收站，并可能结束可处理的占用程序；确认前请保存工作。<Link to={`${release}/tag/V${version}`}>查看完整发布说明</Link>。</p></aside>
    <section className="vt-section" style={{paddingTop:16}}><div className="vt-section-heading"><Heading as="h2">安装前，再确认三件事</Heading></div><div className="vt-grid">
      <article><Heading as="h3">保留完整资源</Heading><p className="vt-muted">便携版需要整体解压，不要只拷贝一个 EXE。菜单注册后移动目录，需要重新应用菜单设置。</p></article>
      <article><Heading as="h3">先退出旧实例</Heading><p className="vt-muted">保存编辑内容，退出正在运行的 Vertree 再升级。不要同时用多个安装目录注册右键菜单。</p></article>
      <article><Heading as="h3">核对下载完整性</Heading><p className="vt-muted">使用发布页的 <Link to={asset('SHA256SUMS.txt')}>SHA256SUMS.txt</Link>核对同名文件。符号包与 Win11 开发包不用于普通安装。</p></article>
    </div><div className="vt-actions" style={{marginTop:24}}><Link className="button button--secondary" to="/docs/tutorial-usage/install">安装与升级指南</Link><Link to="/docs/tutorial-usage/quick-start">安装后做什么 →</Link></div></section>
  </main></Layout>;
}
