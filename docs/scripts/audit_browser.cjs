#!/usr/bin/env node
/* Production-route audit. Launches its own browser; never attaches to user tabs.
 * Private LAN endpoints are intercepted in the protocol check, never contacted.
 */
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const {default: AxeBuilder} = require('@axe-core/playwright');
const base = process.env.VERTREE_DOCS_URL || 'http://127.0.0.1:33030';
const out = path.resolve(process.env.VERTREE_AUDIT_DIR || path.join(__dirname, '../../build/site-audit'));
const staticReport = path.resolve(process.env.VERTREE_STATIC_AUDIT || path.join(__dirname, '../../build/site-audit/static.json'));
const pages = JSON.parse(fs.readFileSync(staticReport, 'utf8')).pages;
fs.mkdirSync(path.join(out, 'screenshots'), {recursive:true});
const reports = [], failures = [];
const presets = [
  {name:'desktop-light',width:1440,height:1000,theme:'light'},
  {name:'mobile-light',width:390,height:844,theme:'light'},
  {name:'desktop-dark',width:1440,height:1000,theme:'dark'},
  {name:'mobile-dark',width:390,height:844,theme:'dark'},
];
const slug = value => value.replace(/[^a-zA-Z0-9\u3400-\u9fff-]+/g,'_').slice(0,130) || 'home';
function persist() {
  fs.writeFileSync(path.join(out,'browser.json'), JSON.stringify({checkedAt:new Date().toISOString(),
    base, checks:reports.length, failureCount:failures.length, reports, failures},null,2));
}
(async () => {
  const channel = process.env.VERTREE_BROWSER_CHANNEL || (process.platform === 'win32' ? 'msedge' : 'chromium');
  if (!['localhost','127.0.0.1','[::1]'].includes(new URL(base).hostname)) throw new Error('Audit only a controlled loopback preview.');
  const browser = await chromium.launch({...(channel === 'chromium' ? {} : {channel}), headless:true});
  try {
    await Promise.all(presets.map(async preset => {
      const context=await browser.newContext({viewport:{width:preset.width,height:preset.height},colorScheme:preset.theme,reducedMotion:'reduce'});
      await context.addInitScript(theme=>localStorage.setItem('theme',theme),preset.theme);
      const page=await context.newPage();
      let jsErrors=[];
      page.on('pageerror',e=>jsErrors.push(e.message));
      for (const entry of pages) {
        jsErrors=[];
        const record={route:entry.route,preset:preset.name,issues:[]};
        try {
          const response=await page.goto(base+entry.route,{waitUntil:'networkidle',timeout:25000});
          await page.evaluate(()=>document.fonts.ready);
          if (!response || response.status()!==200) record.issues.push({type:'http',status:response?.status()});
          const state=await page.evaluate(()=>({
            title:document.title,
            theme:document.documentElement.dataset.theme,
            width:innerWidth, scrollWidth:document.documentElement.scrollWidth,
            main:document.querySelectorAll('main').length,
            brokenImages:[...document.querySelectorAll('img')].filter(i=>!i.complete || !i.naturalWidth).map(i=>i.getAttribute('src')),
            overflow:[...document.querySelectorAll('main *')].filter(e=>{
              const r=e.getBoundingClientRect(),s=getComputedStyle(e);
              if(r.width<1 || s.visibility==='hidden' || s.position==='fixed') return false;
              // Local table/code scroll is intentional, document-level scrolling is not.
              return r.right>innerWidth+2 && !e.closest('table, pre, .prism-code');
            }).slice(0,5).map(e=>({tag:e.tagName,cls:e.className})),
          }));
          record.state=state;
          if(state.scrollWidth>state.width+1) record.issues.push({type:'horizontal-overflow',...state});
          if(state.theme!==preset.theme) record.issues.push({type:'theme',actual:state.theme});
          if(state.brokenImages.length) record.issues.push({type:'images',items:state.brokenImages});
          if(jsErrors.length) record.issues.push({type:'javascript',messages:[...jsErrors]});
          if(preset.name==='desktop-light' || preset.name==='desktop-dark') {
            const axe=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa']).analyze();
            const violations=axe.violations.map(v=>({id:v.id,impact:v.impact,help:v.help,nodes:v.nodes.slice(0,4).map(n=>({target:n.target,summary:n.failureSummary}))}));
            record.accessibility=violations;
            if(violations.length) record.issues.push({type:'accessibility',violations});
          }
          if(preset.theme==='light' || entry.route==='/') {
            record.screenshot=`screenshots/${preset.name}-${slug(entry.route)}.png`;
            await page.screenshot({path:path.join(out,record.screenshot),fullPage:true,animations:'disabled'});
          }
        } catch(error) {record.issues.push({type:'exception',message:String(error)});}
        reports.push(record);
        if(record.issues.length) failures.push(record);
        persist();
        console.log(`${preset.name} ${entry.route}: ${record.issues.length?'FAIL':'OK'}`);
      }
      await context.close();
    }));
    // Mobile menu can actually open and navigate, not merely fit the viewport.
    const mobile=await browser.newContext({viewport:{width:390,height:844},reducedMotion:'reduce'});
    const mp=await mobile.newPage();
    const menuCheck={route:'/',preset:'mobile-navigation',issues:[]};
    try {
      await mp.goto(base,{waitUntil:'networkidle'});
      await mp.locator('button.navbar__toggle').click();
      await mp.locator('.navbar-sidebar').getByRole('link',{name:'下载',exact:true}).click();
      await mp.waitForURL(/\/download\/?$/);
    } catch(error) {menuCheck.issues.push(String(error));}
    reports.push(menuCheck);if(menuCheck.issues.length)failures.push(menuCheck);
    await mobile.close();
    // A synthetic capability uses documentation-reserved private addresses; all
    // matching requests are fulfilled locally to avoid scanning the real network.
    const ctx=await browser.newContext(); const p=await ctx.newPage();
    const lanCheck={route:'/f',preset:'mocked-share-route',issues:[]};
    let attempted=0;
    try {
      await ctx.route('http://192.168.0.1:*/**',async route=>{
        attempted++;
        const url=route.request().url();
        if(url.includes('/info/')) return route.fulfill({status:200,contentType:'application/json',headers:{'Access-Control-Allow-Origin':'*'},body:JSON.stringify({success:true,data:{fileName:'audit-fixture.txt',fileSize:128}})});
        return route.fulfill({status:200,contentType:'text/html',headers:{'Access-Control-Allow-Origin':'*'},body:'<!doctype html><title>Local route fixture</title><h1>Local test download</h1>'});
      });
      await p.goto(base+'/f',{waitUntil:'networkidle'});
      await p.getByRole('heading',{name:'还没有分享链接'}).waitFor();
      if(attempted!==0) throw new Error('Missing share link unexpectedly probed the network');
      await p.goto(base+'/f#invalid!');
      await p.getByRole('heading',{name:'分享链接不完整或已损坏'}).waitFor();
      if(attempted!==0) throw new Error('Invalid share link unexpectedly probed the network');
      const alphabet='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
      let value=BigInt('0b1'+'00000000'+'00000001'+(1).toString(2).padStart(25,'0'));
      let encoded='';do {encoded=alphabet[Number(value%62n)]+encoded;value/=62n;}while(value);
      const fragment='0A'+encoded; // one-character key A, protocol v0, one RFC1918 address
      await p.goto(base+'/f#'+fragment);
      await p.waitForURL('http://192.168.0.1:31424/file-share/page/A',{timeout:15000});
      if(!attempted) throw new Error('Valid share link was not parsed');
      lanCheck.interceptedRequests=attempted;
    } catch(error) {lanCheck.issues.push(String(error));}
    reports.push(lanCheck);if(lanCheck.issues.length)failures.push(lanCheck);
    await ctx.close();
    persist();
  } finally {await browser.close();}
  console.log(`Browser audit: ${reports.length} checks, ${failures.length} failures. ${out}`);
  process.exitCode=failures.length?1:0;
})().catch(error=>{console.error(error);process.exitCode=1;});
