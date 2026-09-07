import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description='Run a local Vertree preview-image demo')
    parser.add_argument('--exe', type=Path, default=ROOT / 'build/windows/x64/runner/Release/vertree.exe')
    parser.add_argument('--port', type=int, default=32510)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    exe = args.exe.resolve(strict=True)
    token = secrets.token_urlsafe(32)
    http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    folder = ROOT / '.dart_tool/local-preview-demo'
    folder.mkdir(parents=True, exist_ok=True)
    text_file = folder / 'text.norm'
    binary_file = folder / 'binary.norm'
    text_file.write_text('Unknown extension, readable text.\n\nVertree uses Office-Viewer to render this file.\n', encoding='utf-8')
    binary_file.write_bytes(bytes(range(256)) * 4)
    sample_dir = ROOT / 'vendor/office-viewer/office-viewer-app/samples'
    samples = [{'name': name, 'path': str(sample_dir / name)} for name in ['brief.pdf', 'visual-slides.pptx', 'report.docx', 'formats.xlsx', 'notes.md', 'mind.xmind', 'pixel.png']]
    samples += [{'name': '未知扩展名：文本', 'path': str(text_file)}, {'name': '未知扩展名：二进制（应返回不支持）', 'path': str(binary_file)}]
    api_base = None

    def call(route, data=None, timeout=65):
        request = urllib.request.Request(api_base + route, data=data, headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        try:
            response = http.open(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, response.headers.get('Content-Type', 'application/json'), response.read()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def reply(self, status, mime, body):
            self.send_response(status)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(body)

        def allowed(self):
            host = f'127.0.0.1:{server.server_port}'
            return self.headers.get('Host') == host and self.headers.get('Origin') in (None, 'http://' + host)

        def do_GET(self):
            if not self.allowed():
                return self.reply(403, 'text/plain', b'Forbidden')
            if self.path == '/':
                return self.reply(200, 'text/html; charset=utf-8', (ROOT / 'tools/preview_demo.html').read_bytes())
            if self.path == '/state':
                return self.reply(200, 'application/json', json.dumps({'api': api_base, 'samples': samples, 'exe': str(exe)}, ensure_ascii=False).encode())
            self.reply(404, 'text/plain', b'Not found')

        def do_POST(self):
            if not self.allowed() or self.headers.get('X-Preview-Demo') != '1':
                return self.reply(403, 'text/plain', b'Forbidden')
            if self.path == '/stop':
                self.reply(200, 'application/json', b'{"stopped":true}')
                threading.Thread(target=server.shutdown, daemon=True).start()
                return
            if self.path != '/render':
                return self.reply(404, 'text/plain', b'Not found')
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if size < 1 or size > 65536:
                    return self.reply(400, 'text/plain', b'Invalid request size')
                data = self.rfile.read(size)
                json.loads(data)
                self.reply(*call('/preview-images', data))
            except (ValueError, OSError) as error:
                self.reply(502, 'application/json', json.dumps({'message': str(error)}).encode())

    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    process = None
    with (folder / 'app.log').open('w', encoding='utf-8') as log:
        try:
            env = os.environ | {'VERTREE_LOCAL_API_ENABLED': '1', 'VERTREE_LOCAL_API_TOKEN': token}
            process = subprocess.Popen([str(exe), '--startup', '--no-announcement'], cwd=exe.parent, env=env, stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError('Test app exited. Close the other Vertree instance before starting this demo.')
                for port in range(31414, 31614):
                    api_base = f'http://127.0.0.1:{port}/api/v1'
                    try:
                        if call('/health', timeout=.05)[0] == 200:
                            break
                    except OSError:
                        continue
                else:
                    time.sleep(.2)
                    continue
                break
            else:
                raise RuntimeError('Vertree API did not become ready; see ' + str(folder / 'app.log'))
            url = f'http://127.0.0.1:{server.server_port}'
            (folder / 'state.json').write_text(json.dumps({'url': url, 'api': api_base, 'pid': process.pid}), encoding='utf-8')
            print('Local preview demo: ' + url, flush=True)
            if not args.no_browser:
                webbrowser.open(url)
            server.serve_forever()
        finally:
            server.server_close()
            if process and process.poll() is None:
                try:
                    call('/app/quit', b'{}')
                    process.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == '__main__':
    main()
