import { describe, expect, it, vi } from 'vitest'
import { loadPreview } from './loadPreview'
import { readFileSync } from 'node:fs'

describe('embedded preview loading', () => {
  it('loads Parquet metadata and pages through range requests', async () => {
    const bytes = readFileSync('../../vendor/office-viewer/office-viewer-app/samples/data.parquet')
    const requests: string[] = []
    const fetchWholeFile = vi.fn<typeof fetch>()
    vi.stubGlobal('fetch', vi.fn<typeof fetch>(async (_, init) => {
      const range = new Headers(init?.headers).get('Range')!
      requests.push(range)
      const [, start, end] = range.match(/^bytes=(\d+)-(\d+)$/)!
      return new Response(bytes.subarray(Number(start), Number(end) + 1), { status: 206, headers: { 'Content-Range': `bytes ${start}-${end}/${bytes.length}` } })
    }))
    try {
      const state = await loadPreview({ name: 'data.parquet', path: 'data.parquet', size: bytes.length, mime: 'application/octet-stream' }, 'http://127.0.0.1/token/file', new AbortController().signal, fetchWholeFile)
      expect(fetchWholeFile).not.toHaveBeenCalled()
      expect(requests.length).toBeGreaterThan(0)
      if (state.status !== 'ready' || state.content.kind !== 'parquet') throw new Error(JSON.stringify(state))
      expect(await state.content.readRows(1, 2)).toEqual([['乙', '2']])
    } finally { vi.unstubAllGlobals() }
  })
  it('does not download a multi-gigabyte video into a JavaScript byte buffer', async () => {
    const fetchFile = vi.fn<typeof fetch>()
    const metadata = { path: 'movie.mp4', name: 'movie.mp4', size: 4 * 1024 ** 3, mime: 'video/mp4' }
    const state = await loadPreview(metadata, 'http://127.0.0.1:1234/token/file', new AbortController().signal, fetchFile)
    expect(fetchFile).not.toHaveBeenCalled()
    expect(state).toMatchObject({ content: { kind: 'media', media: 'video', objectUrl: 'http://127.0.0.1:1234/token/file' } })
  })

  it('still reads complete bytes when the document parser needs them', async () => {
    const fetchFile = vi.fn<typeof fetch>().mockResolvedValue(new Response('中文文本'))
    const metadata = { path: 'file.norm', name: 'file.norm', size: 12, mime: 'application/octet-stream' }
    const state = await loadPreview(metadata, 'http://127.0.0.1:1234/token/file', new AbortController().signal, fetchFile)
    expect(fetchFile).toHaveBeenCalledTimes(1)
    expect(state).toMatchObject({ content: { kind: 'text', text: '中文文本' } })
  })

  it('stops before loading when its dialog has closed', async () => {
    const fetchFile = vi.fn<typeof fetch>()
    const controller = new AbortController()
    controller.abort()
    await expect(loadPreview({ path: 'file.txt', name: 'file.txt', size: 5, mime: 'text/plain' }, 'http://127.0.0.1:1234/token/file', controller.signal, fetchFile)).rejects.toThrow()
    expect(fetchFile).not.toHaveBeenCalled()
  })
})
