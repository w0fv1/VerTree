import { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { Preview } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/Preview'
import { resolveViewer } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/registry'
import { extensionOf } from '../../../vendor/office-viewer/office-viewer-app/src/lib/format'
import { objectUrlsFrom } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/previewResources'
import type { FilePayload } from '../../../vendor/office-viewer/office-viewer-app/src/types'
import type { LoadState } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/previewTypes'
import '../../../vendor/office-viewer/office-viewer-app/src/App.css'
import './style.css'

document.addEventListener('click', (event) => {
  if (event.target instanceof Element && event.target.closest('a')) event.preventDefault()
})

function App() {
  const [payload, setPayload] = useState<FilePayload | null>(null)
  const [state, setState] = useState<LoadState>({ status: 'loading' })

  useEffect(() => {
    const abort = new AbortController()
    let disposed = false
    let rendered: LoadState = { status: 'idle' }
    const release = () => objectUrlsFrom(rendered).forEach((url) => URL.revokeObjectURL(url))
    async function load() {
      try {
        const responses = await Promise.all([
          fetch('./metadata', { signal: abort.signal }),
          fetch('./file', { signal: abort.signal }),
        ])
        if (responses.some((response) => !response.ok)) throw new Error('文件读取失败，请关闭预览后重试。')
        const metadata = await responses[0].json() as Omit<FilePayload, 'bytes'>
        const file = { ...metadata, extension: extensionOf(metadata.name), bytes: new Uint8Array(await responses[1].arrayBuffer()) }
        if (disposed) return
        setPayload(file)
        rendered = await resolveViewer(file.name).load(file)
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
    <header className="preview-heading"><strong>{payload?.name ?? '文件预览'}</strong></header>
    <section className="preview-content">
      {state.status === 'error' ? <div className="error-view" role="alert">{state.message}</div>
        : state.status === 'loading' ? <div className="empty-view" role="status">正在加载预览…</div>
          : <Preview tab={tab} viewer={viewer} payload={payload} state={state} />}
    </section>
  </main>
}

createRoot(document.getElementById('root')!).render(<App />)
