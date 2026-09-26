#!/usr/bin/env python3
"""Audit every generated HTML route using only Python's standard library.

Run after `npm run build`. No external requests, credentials or application data.
"""
from __future__ import annotations
import argparse
import json
import sys
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit

class Page(HTMLParser):
    def __init__(self, text: str):
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.assets: list[str] = []
        self.title = ''
        self.description = ''
        self.h1 = 0
        self.main = 0
        self.bad_images = 0
        self.language = ''
        self._title = False
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get('id'): self.ids.add(a['id'])
        if tag == 'a' and a.get('name'): self.ids.add(a['name'])
        if tag == 'html': self.language = a.get('lang', '')
        if tag == 'title': self._title = True
        if tag == 'meta' and a.get('name') == 'description': self.description = a.get('content','')
        if tag == 'h1': self.h1 += 1
        if tag == 'main': self.main += 1
        if tag == 'a' and a.get('href'): self.links.append(a['href'])
        if tag in ('img','script') and a.get('src'): self.assets.append(a['src'])
        if tag == 'link' and a.get('rel') in ('stylesheet','icon','preload') and a.get('href'): self.assets.append(a['href'])
        if tag == 'img' and 'alt' not in a: self.bad_images += 1
    def handle_endtag(self, tag):
        if tag == 'title': self._title = False
    def handle_data(self, data):
        if self._title: self.title += data

def route_for(file: Path, build: Path) -> str:
    value = file.relative_to(build).as_posix()
    if value == 'index.html': return '/'
    if value == '404.html': return '/404.html'
    if value.endswith('/index.html'): return '/' + value[:-10]
    return '/' + value[:-5]

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, default=Path(__file__).resolve().parents[1]/'build')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2]/'build/site-audit/static.json')
    args=parser.parse_args(); build=args.build.resolve()
    files=sorted(build.rglob('*.html'))
    if not files: raise SystemExit('No generated HTML: run npm run build first.')
    pages={p:Page(p.read_text(encoding='utf-8')) for p in files}
    issues=[]; rows=[]
    def resolve(value, base):
        uri=urlsplit(urljoin('https://vertree.w0fv1.dev'+base, value))
        if uri.scheme not in ('https','http') or uri.netloc not in ('vertree.w0fv1.dev',''): return None
        path=unquote(uri.path)
        f=build/path.lstrip('/')
        for candidate in (f, f/'index.html', Path(str(f)+'.html')):
            if candidate.is_file(): return candidate.resolve(), unquote(uri.fragment)
        return f.resolve(), unquote(uri.fragment)
    for file,page in pages.items():
        route=route_for(file,build); local=[]
        def error(kind, detail):
            issue={'route':route,'kind':kind,'detail':detail}; issues.append(issue); local.append(issue)
        if not page.title.strip(): error('title','Missing page title')
        if not page.description.strip(): error('description','Missing page description')
        if not page.language.startswith('zh'): error('language',page.language)
        if not page.main: error('main','No main landmark')
        # Blog listings intentionally contain linked article headings; feeds are not HTML.
        if route.startswith('/docs/') or route in ('/','/features','/features/','/download','/download/'):
            if page.h1 != 1: error('h1',f'Expected one h1, found {page.h1}')
        if page.bad_images: error('image-alt',str(page.bad_images))
        for value in page.links:
            result=resolve(value,route)
            if result is None: continue
            dest,fragment=result
            if not dest.is_file(): error('broken-link',value)
            elif fragment and not fragment.startswith(':~:') and dest in pages and fragment not in pages[dest].ids:
                error('broken-anchor',value)
        for value in page.assets:
            result=resolve(value,route)
            if result is not None and not result[0].is_file(): error('missing-asset',value)
        rows.append({'route':route,'file':file.relative_to(build).as_posix(),'title':page.title,
            'description':page.description,'h1':page.h1,'links':len(page.links),'assets':len(page.assets),'issues':local})
    report={'checkedAt':datetime.now(timezone.utc).isoformat(),'routes':len(rows),'issueCount':len(issues),'pages':rows,'issues':issues}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Static audit: {len(rows)} HTML routes, {len(issues)} issues. Report: {args.output}')
    for issue in issues[:30]: print(json.dumps(issue,ensure_ascii=False))
    return 1 if issues else 0
if __name__=='__main__': sys.exit(main())
