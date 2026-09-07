import { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { Preview } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/Preview'
import { resolveViewer } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/registry'
import { objectUrlsFrom } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/previewResources'
import type { FileMetadata } from '../../../vendor/office-viewer/office-viewer-app/src/types'
import type { LoadState } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/previewTypes'
import '../../../vendor/office-viewer/office-viewer-app/src/App.css'
import './style.css'
import { loadPreview } from './loadPreview'
import { exportPreviewImage, type PreviewImageOptions } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/previewImage'

const imageMode = new URLSearchParams(location.search).has('image')
const imageApi = {
  async inspect() {
    const response = await fetch('./metadata')
    if (!response.ok) throw new Error('File metadata unavailable')
    const metadata = await response.json() as FileMetadata
    const state = await loadPreview(metadata, new URL('./file', location.href).href, AbortSignal.timeout(30000))
    try {
      return state.status === 'ready' ? { supported: state.content.kind !== 'unsupported', kind: state.content.kind, viewer: resolveViewer(metadata.name).id } : { supported: false, status: state.status, message: state.status === 'error' ? state.message : undefined }
    } finally { objectUrlsFrom(state).forEach((url) => URL.revokeObjectURL(url)) }
  },
  async render(options: PreviewImageOptions) {
    const response = await fetch('./metadata')
    if (!response.ok) throw new Error('File metadata unavailable')
    const metadata = await response.json() as FileMetadata
    const blob = await exportPreviewImage({ ...metadata, url: new URL('./file', location.href).href }, options)
    return await new Promise<string>((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve((reader.result as string).split(',')[1])
      reader.onerror = () => reject(reader.error)
      reader.readAsDataURL(blob)
    })
  },
}
Object.assign(window, { officePreviewImages: imageApi })

document.addEventListener('click', (event) => {
  if (event.target instanceof Element && event.target.closest('a')) event.preventDefault()
})

function App() {
  const [payload, setPayload] = useState<FileMetadata | null>(null)
  const [state, setState] = useState<LoadState>({ status: 'loading' })

  useEffect(() => {
    const report = () => {
      const bridge = (window as unknown as { flutter_inappwebview?: { callHandler(name: string, value: unknown): Promise<unknown> } }).flutter_inappwebview
      const error = document.querySelector('.error-view')
      const busy = document.querySelector('.empty-view, [data-preview-ready="false"]')
      const unsupported = state.status === 'ready' && state.content.kind === 'unsupported'
      const status = error ? 'error' : unsupported ? 'unsupported' : state.status === 'ready' && busy ? 'loading' : state.status
      void bridge?.callHandler('previewState', { status, message: error?.textContent ?? undefined })
    }
    const observer = new MutationObserver(report)
    observer.observe(document.getElementById('root')!, { childList: true, subtree: true, attributes: true })
    window.addEventListener('flutterInAppWebViewPlatformReady', report)
    report()
    return () => { observer.disconnect(); window.removeEventListener('flutterInAppWebViewPlatformReady', report) }
  }, [state])

  useEffect(() => {
    const abort = new AbortController()
    let disposed = false
    let rendered: LoadState = { status: 'idle' }
    const release = () => objectUrlsFrom(rendered).forEach((url) => URL.revokeObjectURL(url))
    async function load() {
      try {
        const response = await fetch('./metadata', { signal: abort.signal })
        if (!response.ok) throw new Error('文件读取失败，请关闭预览后重试。')
        const metadata = await response.json() as FileMetadata
        if (disposed) return
        setPayload(metadata)
        rendered = await loadPreview(metadata, new URL('./file', window.location.href).href, abort.signal)
        if (disposed) release()
        else setState(rendered)
      } catch (error) {
        if (!disposed) setState({ status: 'error', message: error instanceof Error ? error.message : String(error) })
      }
    }
    void load()
    return () => { disposed = true; abort.abort(); release() }
  }, [])

  const viewer = payload ? resolveViewer(payload.name) : undefined
  const tab = payload && viewer ? { path: payload.path, name: payload.name, viewerId: viewer.id } : undefined
  return <main data-status={state.status}>
    <section className="preview-content">
      {state.status === 'error' ? <div className="error-view" role="alert">{state.message}</div>
        : state.status === 'loading' ? <div className="empty-view" role="status">正在加载预览…</div>
          : <Preview tab={tab} viewer={viewer} payload={payload} state={state} />}
    </section>
  </main>
}

if (!imageMode) createRoot(document.getElementById('root')!).render(<App />)
