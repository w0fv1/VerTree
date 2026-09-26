import React from 'react';
const paths = {
  tree: <><circle cx="6" cy="5" r="2"/><circle cx="18" cy="10" r="2"/><circle cx="18" cy="19" r="2"/><path d="M6 7v9a3 3 0 0 0 3 3h7M6 7v1a2 2 0 0 0 2 2h8"/></>,
  clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  preview: <><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M3 9h18M8 4v16"/></>,
  menu: <><path d="M5 5h14M5 12h14M5 19h8"/><circle cx="19" cy="19" r="2"/></>,
  share: <><rect x="2" y="6" width="12" height="10" rx="2"/><path d="M6 20h5M8 16v4"/><rect x="17" y="10" width="5" height="11" rx="1"/><path d="m16 3 4 3-4 2"/></>,
  code: <><path d="m8 7-5 5 5 5m8-10 5 5-5 5m-3-13-2 16"/></>,
  bolt: <path d="m14 2-9 12h6l-1 8 9-13h-6z"/>,
  unlock: <><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0m-4 9v2"/></>,
};
export default function SiteIcon({name, size = 24}) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name] || paths.tree}</svg>;
}
