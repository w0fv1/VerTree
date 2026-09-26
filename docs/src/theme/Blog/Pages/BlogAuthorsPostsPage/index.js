import React from 'react';
import Head from '@docusaurus/Head';
import Original from '@theme-original/Blog/Pages/BlogAuthorsPostsPage';
export default function Page(props) {
  return <><Original {...props}/><Head><meta name="description" content="查阅 Vertree 项目维护者发布的版本变化、开发进展与设计记录。"/></Head></>;
}
