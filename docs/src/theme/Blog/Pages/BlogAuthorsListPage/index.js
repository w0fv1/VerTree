import React from 'react';
import Head from '@docusaurus/Head';
import Original from '@theme-original/Blog/Pages/BlogAuthorsListPage';
export default function Page(props) {
  return <><Original {...props}/><Head><meta name="description" content="了解 Vertree 更新与设计记录的作者，按作者查阅项目文章。"/></Head></>;
}
