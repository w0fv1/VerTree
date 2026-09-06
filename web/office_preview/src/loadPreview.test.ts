import { describe, expect, it, vi } from 'vitest'
import { loadPreview } from './loadPreview'

describe('embedded preview loading', () => {
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
