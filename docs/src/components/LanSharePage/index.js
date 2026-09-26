import React, {useEffect, useMemo, useState} from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import styles from './index.module.css';

const DEFAULT_LAN_SHARE_PORT = 31424;
const DEFAULT_LAN_SHARE_PORT_SCAN_SPAN = 100;
const PRIORITY_PORT_SCAN_SPAN = 12;
const MAX_ROUTE_IPS = 16;
const MAX_PROBE_CANDIDATES = 240;
const BASE62_ALPHABET =
  '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const BASE62_LOOKUP = Object.fromEntries(
  [...BASE62_ALPHABET].map((char, index) => [char, index]),
);

const BASE62 = 62;
const PAYLOAD_VERSION = 0;
const PRIVATE_192168_SPAN = 1 << 16;
const PRIVATE_172_SPAN = 16 << 16;
const PRIVATE_10_SPAN = 1 << 24;
const PRIVATE_172_OFFSET = PRIVATE_192168_SPAN;
const PRIVATE_10_OFFSET = PRIVATE_172_OFFSET + PRIVATE_172_SPAN;
const PRIVATE_TOTAL_SPAN = PRIVATE_10_OFFSET + PRIVATE_10_SPAN;
const FIRST_ID_BIT_WIDTH = 25;
const MAX_VISIBLE_FAILED_CANDIDATES = 18;

function big(value) {
  return BigInt(value);
}

function logShareDebug(level, message) {
  // A share URL is a capability: never log its fragment, key or candidate URLs.
  const logger = console[level] || console.log;
  logger(`[Vertree share] ${message}`);
}

function stripRetrySuffix(hash) {
  const retryIndex = hash.indexOf('&retry=');
  return retryIndex >= 0 ? hash.slice(0, retryIndex) : hash;
}

function isBase62(value) {
  return Boolean(value) && [...value].every((char) => BASE62_LOOKUP[char] !== undefined);
}

function decodeBase62Fixed(value) {
  let result = 0;
  for (const char of value) {
    const digit = BASE62_LOOKUP[char];
    if (digit === undefined) {
      throw new Error(`Invalid Base62 character: ${char}`);
    }
    result = result * BASE62 + digit;
  }
  return result;
}

function mapOrdinalToRfc1918Ipv4(ordinal) {
  if (ordinal < big(0) || ordinal >= big(PRIVATE_TOTAL_SPAN)) {
    throw new Error(`Compact IPv4 ordinal is outside RFC1918 private space: ${ordinal}`);
  }

  if (ordinal < big(PRIVATE_172_OFFSET)) {
    return `192.168.${Number((ordinal >> big(8)) & big(0xff))}.${Number(ordinal & big(0xff))}`;
  }

  if (ordinal < big(PRIVATE_10_OFFSET)) {
    const value = ordinal - big(PRIVATE_172_OFFSET);
    return `172.${16 + Number((value >> big(16)) & big(0x0f))}.${Number((value >> big(8)) & big(0xff))}.${Number(value & big(0xff))}`;
  }

  const value = ordinal - big(PRIVATE_10_OFFSET);
  return `10.${Number((value >> big(16)) & big(0xff))}.${Number((value >> big(8)) & big(0xff))}.${Number(value & big(0xff))}`;
}

function decodeBase62BigInt(value) {
  let result = big(0);
  for (const char of value) {
    const digit = BASE62_LOOKUP[char];
    if (digit === undefined) {
      throw new Error(`Invalid Base62 character: ${char}`);
    }
    result = result * big(BASE62) + BigInt(digit);
  }
  return result;
}

class BitReader {
  constructor(bits) {
    this.bits = bits;
    this.offset = 0;
  }

  get remaining() {
    return this.bits.length - this.offset;
  }

  get isAtEnd() {
    return this.offset >= this.bits.length;
  }

  readBit() {
    if (this.offset >= this.bits.length) {
      throw new Error('Bitstream ended unexpectedly');
    }
    const bit = this.bits[this.offset];
    this.offset += 1;
    if (bit === '0') {
      return big(0);
    }
    if (bit === '1') {
      return big(1);
    }
    throw new Error('Bitstream contains a non-binary character');
  }
}

function readFixedWidthBits(reader, width) {
  if (reader.remaining < width) {
    throw new Error('Bitstream ended unexpectedly');
  }
  let value = big(0);
  for (let index = 0; index < width; index += 1) {
    value = (value << big(1)) | reader.readBit();
  }
  return value;
}

function readUleb128Bits(reader) {
  let value = big(0);
  let shift = big(0);
  while (true) {
    const byte = readFixedWidthBits(reader, 8);
    value |= (byte & big(0x7f)) << shift;
    if ((byte & big(0x80)) === big(0)) {
      return value;
    }
    shift += big(7);
    if (shift > big(63)) {
      throw new Error('ULEB128 value is too large');
    }
  }
}

function decodeCompactIpv4ListPayload(payload) {
  if (!payload || !isBase62(payload)) {
    throw new Error('Compact route IPv4 payload must be a non-empty Base62 string');
  }
  const value = decodeBase62BigInt(payload);
  const binary = value.toString(2);
  if (!binary || binary[0] !== '1') {
    throw new Error('Compact route IPv4 payload is missing sentinel bit');
  }

  const reader = new BitReader(binary.slice(1));
  const version = Number(readUleb128Bits(reader));
  if (version !== PAYLOAD_VERSION) {
    throw new Error(`Unsupported compact route version: ${version}`);
  }

  const count = Number(readUleb128Bits(reader));
  if (count <= 0) {
    throw new Error('Compact route must contain at least one LAN IP');
  }
  if (count > MAX_ROUTE_IPS) {
    throw new Error(`Compact route contains too many LAN IPs: ${count}`);
  }

  const ids = [];
  ids.push(readFixedWidthBits(reader, FIRST_ID_BIT_WIDTH));
  for (let index = 1; index < count; index += 1) {
    const delta = readUleb128Bits(reader);
    ids.push(ids[ids.length - 1] + delta);
  }

  if (!reader.isAtEnd) {
    throw new Error('Compact route IPv4 payload contains unexpected trailing bits');
  }

  return [...new Set(ids.map(mapOrdinalToRfc1918Ipv4))];
}

function parseCompactRoute(hash) {
  const normalizedHash = stripRetrySuffix(hash);
  if (!normalizedHash.startsWith('#')) {
    return null;
  }

  try {
    const payload = decodeURIComponent(normalizedHash.slice(1).trim());
    if (!payload || !isBase62(payload)) {
      return null;
    }

    const shareKeyLengthDigit = BASE62_LOOKUP[payload[0]];
    const shareKeyLength = (shareKeyLengthDigit ?? -1) + 1;
    const shareRef = payload.slice(1, 1 + shareKeyLength).trim();
    const routePayload = payload.slice(1 + shareKeyLength);
    if (!isBase62(shareRef) || !routePayload) {
      logShareDebug('error', 'Share key must be a non-empty Base62 string.', {
        hash: normalizedHash,
        shareRef,
      });
      return null;
    }

    const ips = decodeCompactIpv4ListPayload(routePayload);

    if (ips.length === 0) {
      logShareDebug('error', 'Share route did not produce any candidate LAN IP.', {
        hash: normalizedHash,
        payload,
      });
      return null;
    }

    return {
      shareRef,
      ips,
      fileName: '',
      fileSize: 0,
      expiresAt: '',
      networkName: '',
    };
  } catch (error) {
    logShareDebug('error', 'Failed to parse compact share route.', {
      hash: normalizedHash,
      error,
    });
    return null;
  }
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '-';
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatTime(value) {
  if (!value) {
    return '-';
  }

  let date;
  const numericValue =
    typeof value === 'number' ? value : (/^\d+$/.test(String(value)) ? Number(value) : NaN);
  if (Number.isFinite(numericValue)) {
    date = new Date(numericValue);
  } else {
    date = new Date(value);
  }

  if (Number.isNaN(date.getTime())) {
    return '-';
  }
  return new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function buildPortRange() {
  const ports = Array.from(
    {length: DEFAULT_LAN_SHARE_PORT_SCAN_SPAN},
    (_, index) => DEFAULT_LAN_SHARE_PORT + index,
  );
  const priority = ports.slice(0, PRIORITY_PORT_SCAN_SPAN);
  const fallback = ports.slice(PRIORITY_PORT_SCAN_SPAN);
  return [...priority, ...fallback].map(String);
}

function buildCandidates(params) {
  const shareRef = params.shareRef || '';
  const ports = buildPortRange();
  const ips = [...new Set((params.ips || []).filter(Boolean))].slice(0, MAX_ROUTE_IPS);

  if (!shareRef || ports.length === 0 || ips.length === 0) {
    return [];
  }

  const candidates = [];
  const seen = new Set();
  ports.forEach((port) => {
    ips.forEach((ip) => {
      const id = `${ip}:${port}`;
      if (seen.has(id) || candidates.length >= MAX_PROBE_CANDIDATES) {
        return;
      }
      seen.add(id);
      candidates.push({
        id,
        ip,
        port,
        label: `${ip}:${port}`,
        pageUrl: `http://${ip}:${port}/file-share/page/${shareRef}`,
        infoUrl: `http://${ip}:${port}/file-share/info/${shareRef}`,
        downloadUrl: `http://${ip}:${port}/file-share/download/${shareRef}`,
        probeUrl: `http://${ip}:${port}/file-share/probe/${shareRef}`,
        pixelProbeUrl: `http://${ip}:${port}/file-share/pixel/${shareRef}`,
      });
    });
  });
  return candidates;
}

function supportsLanSharePage() {
  return (
    typeof BigInt === 'function' &&
    typeof fetch === 'function' &&
    typeof AbortController === 'function' &&
    typeof Image === 'function' &&
    typeof Intl === 'object' &&
    typeof Intl.DateTimeFormat === 'function'
  );
}

function isLikelyLocalNetworkPermissionError(error) {
  const text = String(error?.message || error || '').toLowerCase();
  return (
    text.includes('failed to fetch') ||
    text.includes('networkerror') ||
    text.includes('network access') ||
    text.includes('err_network_access_denied') ||
    text.includes('load failed') ||
    text.includes('image probe failed')
  );
}

async function fetchShareInfo(candidate, timeoutMs = 2400) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${candidate.infoUrl}?ts=${Date.now()}`, {
      method: 'GET',
      mode: 'cors',
      cache: 'no-store',
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`info failed: ${response.status}`);
    }
    const payload = await response.json();
    if (!payload?.success || !payload?.data) {
      throw new Error('info payload missing success/data');
    }
    return payload.data;
  } finally {
    window.clearTimeout(timeout);
  }
}

function probeWithFetch(candidate, timeoutMs = 2400) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs);
  return fetch(`${candidate.probeUrl}?ts=${Date.now()}`, {
    method: 'GET',
    mode: 'cors',
    cache: 'no-store',
    signal: controller.signal,
  })
    .then((response) => {
      if (!response.ok) {
        throw new Error(`probe failed: ${response.status}`);
      }
      return response;
    })
    .finally(() => window.clearTimeout(timeout));
}

function probeWithImage(candidate, timeoutMs = 2400) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    const timeout = window.setTimeout(() => {
      cleanup();
      reject(new Error('timeout'));
    }, timeoutMs);

    function cleanup() {
      window.clearTimeout(timeout);
      image.onload = null;
      image.onerror = null;
    }

    image.onload = () => {
      cleanup();
      resolve(candidate);
    };
    image.onerror = () => {
      cleanup();
      reject(new Error('image probe failed'));
    };
    image.src = `${candidate.pixelProbeUrl}?ts=${Date.now()}`;
  });
}

async function probeCandidate(candidate) {
  try {
    await probeWithFetch(candidate);
    return candidate;
  } catch (error) {
    await probeWithImage(candidate);
    return candidate;
  }
}

export default function FileSharePage() {
  const [fragment, setFragment] = useState(() =>
    typeof window === 'undefined' ? '' : window.location.hash || '',
  );
  const browserSupported = useMemo(
    () => typeof window !== 'undefined' && supportsLanSharePage(),
    [],
  );
  const [status, setStatus] = useState('idle');
  const [selectedCandidate, setSelectedCandidate] = useState(null);
  const [candidateStates, setCandidateStates] = useState({});
  const [resolvedInfo, setResolvedInfo] = useState(null);
  const [showAllFailedCandidates, setShowAllFailedCandidates] = useState(false);
  const [needsLocalNetworkPermission, setNeedsLocalNetworkPermission] = useState(false);
  const [probeAttempt, setProbeAttempt] = useState(0);

  useEffect(() => {
    const onHashChange = () => setFragment(window.location.hash || '');
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  const shareParams = useMemo(() => {
    if (!browserSupported) {
      return {
        shareRef: '',
        ips: [],
        fileName: '',
        fileSize: 0,
        expiresAt: '',
        networkName: '',
      };
    }
    const compactRoute = parseCompactRoute(fragment);
    if (!compactRoute && stripRetrySuffix(fragment)) {
      logShareDebug('error', 'Unable to resolve share params from fragment.', {
        fragment: stripRetrySuffix(fragment),
      });
    }
    return compactRoute ?? {
      shareRef: '',
      ips: [],
      fileName: '',
      fileSize: 0,
      expiresAt: '',
      networkName: '',
    };
  }, [browserSupported, fragment]);

  const candidates = useMemo(() => buildCandidates(shareParams), [shareParams]);
  const candidateIds = useMemo(
    () => candidates.map((candidate) => candidate.id).join('|'),
    [candidates],
  );
  const visibleCandidates = useMemo(() => {
    if (status !== 'failed' || candidates.length <= MAX_VISIBLE_FAILED_CANDIDATES) {
      return candidates;
    }
    return showAllFailedCandidates
      ? candidates
      : candidates.slice(0, MAX_VISIBLE_FAILED_CANDIDATES);
  }, [candidates, showAllFailedCandidates, status]);
  const displayFileName = resolvedInfo?.fileName || shareParams.fileName;
  const displayFileSize = resolvedInfo?.fileSize ?? shareParams.fileSize;
  const displayExpiresAt = resolvedInfo?.expiresAt || shareParams.expiresAt;
  const displayNetworkName = resolvedInfo?.networkName || shareParams.networkName;

  useEffect(() => {
    setResolvedInfo(null);
    setShowAllFailedCandidates(false);
    setNeedsLocalNetworkPermission(false);
  }, [fragment]);

  useEffect(() => {
    if (!browserSupported) {
      return undefined;
    }
    if (candidates.length === 0) {
      return undefined;
    }

    let cancelled = false;

    const hydrateInfo = async () => {
      for (const candidate of candidates) {
        try {
          const info = await fetchShareInfo(candidate, 1800);
          if (cancelled) {
            return;
          }
          setResolvedInfo(info);
          logShareDebug('log', 'Resolved share info from LAN endpoint.', {
            candidate,
            info,
          });
          return;
        } catch (error) {
          logShareDebug('warn', 'Failed to hydrate share info from candidate.', {
            candidate,
            error,
          });
        }
      }
    };

    hydrateInfo();

    return () => {
      cancelled = true;
    };
  }, [browserSupported, candidateIds, candidates]);

  useEffect(() => {
    if (!browserSupported) {
      setStatus('unsupported');
      return undefined;
    }
    if (candidates.length === 0) {
      logShareDebug('error', 'No candidate routes resolved from current share params.', {
        fragment: stripRetrySuffix(fragment),
        shareParams,
      });
      setStatus('invalid');
      return undefined;
    }

    let cancelled = false;
    const probeErrors = [];

    setStatus('probing');
    setSelectedCandidate(null);
    setNeedsLocalNetworkPermission(false);
    setShowAllFailedCandidates(false);
    setCandidateStates(
      Object.fromEntries(candidates.map((candidate) => [candidate.id, 'pending'])),
    );

    const runProbeSequence = async () => {
      for (const candidate of candidates) {
        try {
          await probeCandidate(candidate);
          if (cancelled) {
            return;
          }
          setSelectedCandidate(candidate);
          setCandidateStates(
            Object.fromEntries(
              candidates.map((item) => [
                item.id,
                item.id === candidate.id ? 'success' : 'stopped',
              ]),
            ),
          );
          setStatus('redirecting');
          window.setTimeout(() => {
            window.location.replace(candidate.pageUrl);
          }, 350);
          return;
        } catch (error) {
          if (cancelled) {
            return;
          }
          probeErrors.push(error);
          logShareDebug('warn', 'Candidate probe failed.', {
            candidate,
            error,
          });
          setCandidateStates((previous) => ({
            ...previous,
            [candidate.id]: 'failed',
          }));
        }
      }

      if (cancelled) {
        return;
      }

      logShareDebug('error', 'All candidate probes failed.', {
        fragment: stripRetrySuffix(fragment),
        candidates,
        probeErrors,
      });
      setNeedsLocalNetworkPermission(
        probeErrors.length > 0 &&
          probeErrors.every((error) => isLikelyLocalNetworkPermissionError(error)),
      );
      setStatus('failed');
    };

    runProbeSequence();

    return () => {
      cancelled = true;
    };
  }, [browserSupported, candidateIds, candidates, fragment, probeAttempt, shareParams]);

  const headline = {
    idle: '正在准备连接',
    probing: '正在连接分享者的电脑',
    redirecting: '已连接，即将打开下载页',
    failed: '暂时无法连接分享者',
    invalid: '分享链接无效',
    unsupported: '当前浏览器不受支持',
  }[status];

  if (status === 'invalid' || status === 'unsupported') {
    return <Layout title="局域网文件分享" description="打开分享者提供的完整链接，在局域网中接收文件。">
      <main className="vt-empty"><p className="vt-eyebrow">VERTREE · 局域网分享</p>
        <h1>{status === 'unsupported' ? '请使用支持此功能的浏览器' : fragment ? '分享链接不完整或已损坏' : '还没有分享链接'}</h1>
        <p>{status === 'unsupported' ? '请在较新的系统浏览器中重新打开完整分享链接。' : '请让分享者在 Vertree 中选择“分享到局域网”，再发送完整链接或二维码。单独打开这个页面不能找到文件。'}</p>
        <p>接收期间保持两台设备网络可达，分享者需要保持 Vertree 运行。文件直接来自分享者的电脑。</p>
        <div className="vt-actions"><Link className="button button--primary" to="/docs/tutorial-usage/sharing">查看分享指南</Link><Link className="button button--secondary" to="/">返回首页</Link></div>
      </main></Layout>;
  }

  return (
    <Layout
      title="Vertree 文件分享"
      description="Vertree 局域网文件分享页"
    >
      <main className={styles.page}>
        <section className={styles.hero}>
          <div className={styles.badge}>Vertree · 局域网分享</div>
          <h1 aria-live="polite">{headline}</h1>
          <p className={styles.description}>
            请保持两台设备网络可达，并让分享者保持 Vertree 运行。连接成功后会打开下载页，文件不会经过官网服务器。
          </p>
        </section>

        <section className={styles.grid}>
          <article className={styles.card}>
            <h2>文件信息</h2>
            <div className={styles.metaList}>
              <div>
                <span>文件名</span>
                <strong>{displayFileName || '正在获取'}</strong>
              </div>
              <div>
                <span>文件大小</span>
                <strong>{formatBytes(displayFileSize)}</strong>
              </div>
              <div>
                <span>失效时间</span>
                <strong>{formatTime(displayExpiresAt)}</strong>
              </div>
              {displayNetworkName ? (
                <div>
                  <span>分享网络</span>
                  <strong>{displayNetworkName}</strong>
                </div>
              ) : null}
            </div>
          </article>

          <article className={styles.card}>
            <h2>状态</h2>
            <p className={styles.statusText}>
              {status === 'redirecting' && selectedCandidate
                ? `已选中 ${selectedCandidate.label}，即将开始下载。`
                : status === 'unsupported'
                  ? '当前浏览器缺少解析局域网分享页所需的现代能力。请改用较新的 Chrome、Edge、Firefox 或 Safari 打开这个链接。'
                : status === 'failed'
                  ? (needsLocalNetworkPermission
                    ? '连接可能被浏览器的本地网络权限限制。请检查权限提示，也可以手动打开下面的下载页；网络或防火墙也可能导致连接失败。'
                    : '浏览器没有自动探测到可用地址。你可以手动点击下面的候选下载页，并先确认是否和分享者连接在同一个网络。')
                  : status === 'invalid'
                    ? '当前链接不是有效的局域网分享链接，请让分享者重新生成。'
                    : '正在后台按顺序测试候选地址和端口，请稍候。'}
            </p>
            <p className={styles.note}>
              提示：某些浏览器或企业网络会限制从 HTTPS 页面直接探测 HTTP 局域网地址。如果自动跳转失败，手动打开下面的候选下载页通常仍然可以完成下载。
            </p>
            {status === 'failed' || status === 'unsupported' ? (
              <div className={styles.failureHint}>
                {status === 'unsupported'
                  ? '这个分享页需要现代浏览器能力来解析短链接和探测局域网地址。请升级浏览器后重试。'
                  : needsLocalNetworkPermission
                    ? '如果浏览器顶部弹出了“访问本地网络中的其他设备”或类似提示，请点击允许，然后再点“重新探测”。'
                  : '没有探测到任何可用候选地址。请先确认接收方和分享方是否连接在同一个网络；'}
                {status !== 'unsupported' && !needsLocalNetworkPermission
                  ? (displayNetworkName
                    ? `当前分享网络是“${displayNetworkName}”。`
                    : '如果分享方使用的是 Wi‑Fi，也请确认两端连接的是同一个 Wi‑Fi。')
                  : null}
              </div>
            ) : null}
          </article>
        </section>

        <section className={styles.card}>
          <div className={styles.sectionHeader}>
            <h2>可尝试的连接地址</h2>
            <button
              className={styles.retryButton}
              type="button"
              disabled={status === 'probing' || status === 'redirecting' || candidates.length === 0}
              onClick={() => setProbeAttempt((current) => current + 1)}
            >
              重新探测
            </button>
          </div>
          <div className={styles.candidateList}>
            {visibleCandidates.map((candidate) => (
              <div className={styles.candidateCard} key={candidate.id}>
                <div>
                  <div className={styles.candidateIp}>{candidate.label}</div>
                  <div className={styles.candidateUrl}>{candidate.pageUrl}</div>
                </div>
                <div className={styles.candidateActions}>
                  <span
                    className={`${styles.candidateState} ${styles[candidateStates[candidate.id] || 'pending']}`}
                  >
                    {{
                      pending: '探测中',
                      success: '可用',
                      stopped: '已停止',
                      failed: '失败',
                    }[candidateStates[candidate.id] || 'pending']}
                  </span>
                  <a
                    className={styles.downloadButton}
                    href={candidate.pageUrl}
                  >
                    打开下载页
                  </a>
                </div>
              </div>
            ))}
          </div>
          {status === 'failed' && candidates.length > MAX_VISIBLE_FAILED_CANDIDATES ? (
            <div className={styles.moreCandidates}>
              <button
                className={styles.retryButton}
                type="button"
                onClick={() => setShowAllFailedCandidates((current) => !current)}
              >
                {showAllFailedCandidates
                  ? '收起更多候选地址'
                  : `显示全部 ${candidates.length} 个候选地址`}
              </button>
            </div>
          ) : null}
        </section>
      </main>
    </Layout>
  );
}
