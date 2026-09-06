import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { resolveViewer } from '../../../vendor/office-viewer/office-viewer-app/src/viewers/registry'
import { extensionOf } from '../../../vendor/office-viewer/office-viewer-app/src/lib/format'

describe('embedded upstream viewers', () => {
  it.each([
    ['report.docx', 'word'], ['formats.xlsx', 'sheet'], ['slides.pptx', 'presentation'],
    ['article.odt', 'word'], ['memo.rtf', 'word'], ['formats.ods', 'sheet'],
    ['notes.md', 'html'], ['data.csv', 'sheet'], ['config.json', 'text'],
    ['bundle.zip', 'archive'], ['unknown.bin', 'unsupported'],
  ])('renders %s as %s', async (name, kind) => {
    const bytes = new Uint8Array(readFileSync(resolve('../../vendor/office-viewer/office-viewer-app/samples', name)))
    const state = await resolveViewer(name).load({ name, path: name, extension: extensionOf(name), mime: 'application/octet-stream', size: bytes.length, bytes })
    expect(state.status, JSON.stringify(state)).toBe('ready')
    if (state.status === 'ready') expect(state.content.kind).toBe(kind)
  })

  it('sanitizes active HTML while retaining document text', async () => {
    const bytes = new TextEncoder().encode('<h1>Visible heading</h1><script>alert(1)</script><img src=x onerror="alert(1)">')
    const state = await resolveViewer('unsafe.html').load({ name: 'unsafe.html', path: 'unsafe.html', extension: 'html', mime: 'text/html', size: bytes.length, bytes })
    expect(state.status).toBe('ready')
    if (state.status === 'ready' && state.content.kind === 'html') {
      expect(state.content.html).toContain('Visible heading')
      expect(state.content.html).not.toMatch(/<script|onerror/)
    }
  })

  it.each([
    ['notes.norm', '中文正文\n第二行', 'text'],
    ['notes.fodt', '<o:document xmlns:o="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:t="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><o:body><o:text><t:p>正文</t:p></o:text></o:body></o:document>', 'word'],
    ['message.eml', 'From: sender@example.com\r\nSubject: Preview\r\n\r\nMessage body', 'email'],
    ['book.fb2', '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><body><section><p>正文</p></section></body></FictionBook>', 'book'],
  ])('embeds the new %s viewer', async (name, source, kind) => {
    const bytes = new TextEncoder().encode(source)
    const state = await resolveViewer(name).load({ name, path: name, extension: extensionOf(name), mime: 'application/octet-stream', size: bytes.length, bytes })
    expect(state.status, JSON.stringify(state)).toBe('ready')
    if (state.status === 'ready') expect(state.content.kind).toBe(kind)
  })
})
