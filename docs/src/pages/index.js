import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';

import Heading from '@theme/Heading';
import styles from './index.module.css';

function HomepageHeader() {
    const { siteConfig } = useDocusaurusContext();
    const heroImageUrl = useBaseUrl('/img/brand-home-page.png');
    return (
        <header className={clsx('hero hero--primary', styles.heroBanner)}>
            <div className={styles.heroContainer}>
                {/* 左侧内容 */}
                <div className={styles.heroText}>
                    <div className="margin-bottom--sm">
                        <strong>V2.0.0：版本与快照架构升级</strong>
                        <span> · 本地文件预览与更多格式支持</span>
                    </div>
                    <Heading as="h1" className="hero__title">
                        {siteConfig.title}
                    </Heading>
                    <p className="hero__subtitle">{siteConfig.tagline}</p>
                    <div className={styles.buttons}>
                        <Link className="button button--secondary button--lg" to="/docs/intro">
                            开始使用
                        </Link>
                        <Link className="button button--text button--lg" to="https://github.com/w0fv1/vertree/releases/latest">
                            下载
                        </Link>
                        <Link
                            className="button button--primary button--lg"
                            to="https://next.firco.cn/w0fv1?focusProduct=product-8283788fa5724d25ae65958d1b61b288"
                        >
                            捐助支持
                        </Link>
                    </div>
                </div>

                {/* 右侧图片 */}
                <img src={heroImageUrl} alt="Logo" className={styles.heroImage} />
            </div>
        </header>
    );
}


export default function Home() {
  return (
    <Layout
      title="文件版本管理与本地预览"
      description="用版本树保留文件历史，预览办公文档、图片和媒体，自动备份并通过局域网分享。支持 Windows、macOS 和 Linux。">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
