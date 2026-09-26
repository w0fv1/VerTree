"""Windows file-tools integration and opt-in benchmark runner.

Only newly created tempfile.TemporaryDirectory fixtures are modified. Process
termination tests address only the dedicated child fixture started by this run.
No existing files, applications, registry settings or security policies change.
"""
from __future__ import annotations
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any

Json = dict[str, Any]
ROOT = Path(__file__).resolve().parent.parent


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class Worker:
    def __init__(self, executable: Path):
        self.executable = executable

    def request(self, request: Json, *, timeout: float = 90, controls=None,
                failures: Path | None = None) -> Json:
        process = subprocess.Popen([str(self.executable), '--stdio'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        events: queue.Queue = queue.Queue()
        errors: list[str] = []
        started = time.perf_counter()
        def read_output() -> None:
            try:
                for line in process.stdout:
                    if len(line) > 4 * 1024 * 1024:
                        raise ValueError('Oversized output frame')
                    events.put(json.loads(line))
            except BaseException as error:
                events.put(error)
            finally:
                events.put(None)
        def read_errors() -> None:
            value = process.stderr.read(8192)
            errors.append(value.decode('utf-8', errors='replace'))
        output_thread = threading.Thread(target=read_output, daemon=True)
        error_thread = threading.Thread(target=read_errors, daemon=True)
        output_thread.start(); error_thread.start()
        terminal = None
        progress = None
        first_progress = None
        seen_processes: dict[int, Json] = {}
        failed = 0
        report = failures.open('w', encoding='utf-8') if failures else None
        def send(value: Json) -> None:
            process.stdin.write((json.dumps({'v': 1, **value}, ensure_ascii=False) + '\n').encode('utf-8'))
            process.stdin.flush()
        try:
            send({'hostPid': os.getpid(), **request})
            if controls:
                controls(send)
            while time.perf_counter() - started < timeout:
                try:
                    event = events.get(timeout=0.1)
                except queue.Empty:
                    continue
                if isinstance(event, BaseException):
                    raise event
                if event is None:
                    break
                check(event.get('v') == 1, 'Unversioned native event')
                kind = event.get('type')
                if kind == 'progress':
                    progress = event['progress']
                    if first_progress is None and progress.get('deletedFiles', 0):
                        first_progress = time.perf_counter() - started
                elif kind == 'failure':
                    failed += 1
                    if report:
                        report.write(json.dumps(event, ensure_ascii=False) + '\n')
                elif kind == 'process':
                    seen_processes[event['process']['pid']] = event['process']
                elif kind in ('result', 'error'):
                    check(terminal is None, 'Multiple terminal native messages')
                    terminal = event
            process.stdin.close()
            process.wait(timeout=12)
            output_thread.join(timeout=2); error_thread.join(timeout=2)
            check(terminal is not None, f'No terminal result; exit={process.returncode}; stderr={errors}')
            if terminal['type'] == 'result':
                check(process.returncode == 0, 'Successful result with failing process exit')
            else:
                check(process.returncode != 0, 'Native error with successful process exit')
            return {'terminal': terminal, 'wallSeconds': time.perf_counter() - started,
                    'lastProgress': progress, 'firstDeletedProgressSeconds': first_progress,
                    'failureEvents': failed, 'incrementalProcesses': list(seen_processes.values())}
        finally:
            if report:
                report.close()
            if process.poll() is None:
                process.kill()  # Only this test's own file-worker child.
                process.wait(timeout=12)
            if process.stdin and not process.stdin.closed:
                process.stdin.close()
            process.stdout.close(); process.stderr.close()

    def prepare(self, paths: list[Path]) -> Json:
        response = self.request({'op': 'prepare', 'paths': [str(path) for path in paths]})['terminal']
        check(response['type'] == 'result', json.dumps(response))
        return response['result']

    def delete(self, plan: Json, **kwargs) -> Json:
        request = {'op': 'delete', 'confirmed': True, **plan, **kwargs.pop('options', {})}
        return self.request(request, **kwargs)


def native_result(response: Json) -> Json:
    terminal = response['terminal']
    check(terminal['type'] == 'result', json.dumps(terminal, ensure_ascii=False))
    return terminal['result']


def run_integration(worker: Worker, holder: Path, output: dict) -> None:
    tests: list[dict] = []
    def run(name: str, function) -> None:
        start = time.perf_counter()
        try:
            function()
            row = {'name': name, 'outcome': 'passed', 'seconds': time.perf_counter() - start}
        except BaseException as error:
            row = {'name': name, 'outcome': 'failed', 'error': str(error),
                   'seconds': time.perf_counter() - start}
        tests.append(row)
        print(f"{row['outcome'].upper()}: {name}", flush=True)
        if row['outcome'] == 'failed':
            print(row['error'], flush=True)

    with tempfile.TemporaryDirectory(prefix='VerTree-FileTools-Integration-') as temporary:
        root = Path(temporary)
        (root / '.vertree-test-fixture').write_text('Created only for this test run', encoding='utf-8')

        def protocol() -> None:
            response = worker.request({'op': 'delete', 'paths': [str(root)]})['terminal']
            check(response.get('code') == 'CONFIRMATION_REQUIRED', 'Deletion lacked explicit confirmation guard')
            response = worker.request({'op': 'not-an-operation'})['terminal']
            check(response.get('code') == 'UNKNOWN_OPERATION', 'Unknown operation was accepted')
            for path in ('C:\\', '..\\unrelated', 'C:\\Windows', 'C:\\Windows\\System32'):
                response = worker.request({'op': 'prepare', 'paths': [path]})['terminal']
                check(response['type'] == 'error', f'Unsafe path accepted: {path}')
        run('versioned protocol, explicit deletion consent and protected roots', protocol)

        def long_paths() -> None:
            target = root / '长路径-空格-emoji-😀'
            child = target
            for index in range(12):
                child = child / ('directory-with-spaces-' + str(index))
            extended = '\\\\?\\' + str(child)
            os.makedirs(extended)
            with open(extended + '\\中文 文档.txt', 'wb') as file:
                file.write(b'test contents')
            plan = worker.prepare([target, target])
            check(len(plan['targets']) == 1, 'Duplicate roots were not removed')
            response = native_result(worker.delete(plan))
            check(response['outcome'] == 'succeeded' and not target.exists(), 'Unicode/long-path tree was not removed')
        run('Unicode, spaces, >260-character paths and duplicate selection', long_paths)

        def pause_cancel() -> None:
            target = root / 'paused'
            target.mkdir(); (target / 'keep').write_bytes(b'not deleted')
            plan = worker.prepare([target])
            def control(send):
                time.sleep(0.25)
                check((target / 'keep').exists(), 'Paused task removed an item')
                send({'control': 'cancel'})
            response = native_result(worker.delete(plan, options={'initialPaused': True}, controls=control))
            check(response['outcome'] == 'cancelled' and (target / 'keep').exists(), 'Cancellation failed')
        run('IPC initial pause followed by cancellation preserves files', pause_cancel)

        def pending_and_retries() -> None:
            target = root / 'retry'
            target.mkdir(); blocked = target / 'blocked.txt'; blocked.write_bytes(b'original')
            (target / 'free.txt').write_bytes(b'free')
            plan = worker.prepare([target])
            child = subprocess.Popen([str(holder), str(blocked)], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                json.loads(child.stdout.readline())
                report = root / 'retry-failures.jsonl'
                response = native_result(worker.delete(plan, failures=report))
                check(response['outcome'] == 'partial' and not (target / 'free.txt').exists(),
                      'A blocked file stopped independent work or was reported as success')
                child.stdin.write(b'close\n'); child.stdin.flush(); child.wait(timeout=5)
                blocked.rename(target / 'original-kept.txt')
                blocked.write_bytes(b'replacement - must survive retry')
                response = native_result(worker.delete(plan, options={'retryReport': str(report)}))
                check(response['outcome'] == 'partial', 'Identity replacement was not rejected on retry')
                check(blocked.read_bytes().startswith(b'replacement') and (target / 'original-kept.txt').exists(),
                      'Retry deleted a same-name replacement or rescanned new files')
                outside = root / 'outside.txt'; outside.write_bytes(b'outside')
                outside_target = worker.prepare([outside])['targets'][0]
                report.write_text(json.dumps({'type': 'failure', 'target': outside_target}) + '\n', encoding='utf-8')
                response = worker.delete(plan, options={'retryReport': str(report)})['terminal']
                check(response.get('code') == 'INVALID_REPORT' and outside.exists(), 'Out-of-range retry was accepted')
            finally:
                if child.poll() is None:
                    child.stdin.close(); child.wait(timeout=5)
                if not child.stdin.closed: child.stdin.close()
                child.stdout.close(); child.stderr.close()
        run('partial deletion, failure-only retry, identity replacement and report scope', pending_and_retries)

        def process_usage() -> None:
            directory = root / 'usage'; directory.mkdir()
            selected = directory / 'held.txt'; selected.write_bytes(b'held by test child')
            adjacent = root / 'usage-adjacent'; adjacent.mkdir()
            child = subprocess.Popen([str(holder), str(selected)], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                identity = json.loads(child.stdout.readline())
                identity['paths'] = [str(directory)]
                identity['op'] = 'process'; identity['confirmed'] = True
                scan = native_result(worker.request({'op': 'scan', 'paths': [str(directory)],
                    'onlyPid': child.pid, 'budgetSeconds': 20}))
                found = [entry for entry in scan['processes'] if entry['pid'] == child.pid]
                check(len(found) == 1 and found[0]['creationTime'] == identity['creationTime'],
                      'Dedicated file-holder process was not identified')
                session = wintypes.DWORD()
                if not ctypes.windll.kernel32.ProcessIdToSessionId(child.pid, ctypes.byref(session)):
                    raise ctypes.WinError()
                service_session = session.value == 0
                output['processActionEnvironment'] = {
                    'sessionId': session.value,
                    'verifiedBehavior': 'service-session-denied' if service_session else 'interactive-child-terminated',
                }
                if service_session:
                    check(not found[0]['actionAllowed'] and found[0]['restriction'] == 'SERVICE_OR_UNKNOWN_SESSION',
                          'Service-session protection must also apply to CI fixture processes')
                else:
                    check(found[0]['actionAllowed'], 'A normal fixture process was incorrectly protected: ' + str(found[0]))
                scan = native_result(worker.request({'op': 'scan', 'paths': [str(adjacent)],
                    'onlyPid': child.pid, 'budgetSeconds': 20}))
                check(not scan['processes'], 'Directory prefix matched an adjacent sibling')
                module_scan = native_result(worker.request({'op': 'scan', 'paths': [str(holder)],
                    'onlyPid': child.pid, 'budgetSeconds': 20}))
                check(any('module' in file['sources'] for entry in module_scan['processes']
                          for file in entry['files']), 'Loaded executable module was not detected')
                response = worker.request({**identity, 'creationTime': '0000000000000000', 'action': 'terminate'})['terminal']
                check(response.get('code') == 'PROCESS_CHANGED' and child.poll() is None, 'Stale PID identity was accepted')
                response = worker.request({**identity, 'action': 'terminate', 'confirmed': False})['terminal']
                check(response.get('code') == 'CONFIRMATION_REQUIRED' and child.poll() is None, 'Process termination lacked explicit consent')
                if service_session:
                    for action in ('close', 'terminate'):
                        denied = worker.request({**identity, 'action': action})['terminal']
                        check(denied.get('code') == 'SERVICE_OR_UNKNOWN_SESSION' and child.poll() is None,
                              'A service-session fixture must be left running by the production worker')
                    # Release only our fixture through its own test protocol.
                    child.stdin.write(b'close\n'); child.stdin.flush(); child.wait(timeout=5)
                else:
                    closed = native_result(worker.request({**identity, 'action': 'close'}))
                    check(closed['status'] == 'noClosableWindow' and child.poll() is None,
                          'Normal close escalated or claimed to close a headless process')
                    ended = native_result(worker.request({**identity, 'action': 'terminate'}))
                    check(ended['status'] == 'exited', f'Termination was not verified: {ended}')
                    child.wait(timeout=5)
                check(native_result(worker.delete(worker.prepare([directory])))['outcome'] == 'succeeded',
                      'File remained locked after test-child exit')
            finally:
                if child.poll() is None:
                    try: child.stdin.write(b'close\n'); child.stdin.flush()
                    except OSError: pass
                    try: child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill(); child.wait(timeout=5)  # Only the fixture child created above.
                child.stdin.close(); child.stdout.close(); child.stderr.close()
        run('file and module usage, PID identity, non-forced close, explicit owned-child termination', process_usage)

    output['integrationTests'] = tests
    if any(test['outcome'] != 'passed' for test in tests):
        raise AssertionError('One or more Windows file-tools integration tests failed')


def populate(directory: Path, count: int, *, flat: bool) -> None:
    directory.mkdir()
    payload = b'fixture\n' * 16
    if flat:
        for index in range(count):
            (directory / f'f-{index:08d}.txt').write_bytes(payload)
    else:
        parent = directory
        for index in range(count):
            if index % 500 == 0:
                parent = directory / f'd-{index // 500:05d}'
                parent.mkdir()
            (parent / f'f-{index:08d}.txt').write_bytes(payload)


def benchmark(worker: Worker, counts: list[int], real_gib: int, output: dict,
              dart: str | None = None) -> None:
    rows: list[dict] = []
    with tempfile.TemporaryDirectory(prefix='VerTree-FileTools-Benchmark-') as temporary:
        root = Path(temporary)
        marker = root / '.vertree-test-fixture'; marker.write_text('benchmark fixture', encoding='utf-8')
        for count in counts:
            for mode in ('native-serial', 'native-auto', 'dart-recursive' if dart else 'python-recursive'):
                target = root / 'dataset'
                population_start = time.perf_counter()
                populate(target, count, flat=count == min(counts))
                population_seconds = time.perf_counter() - population_start
                if mode.startswith('native'):
                    preparation_start = time.perf_counter()
                    plan = worker.prepare([target])
                    preparation_seconds = time.perf_counter() - preparation_start
                    measured = worker.delete(plan, timeout=max(300, count / 100),
                        options={'workers': 1 if mode == 'native-serial' else 0})
                    result = native_result(measured)
                    check(result['outcome'] == 'succeeded' and not target.exists(), str(result))
                    row = {'case': f'{count}-small-files', 'mode': mode,
                           'populationSeconds': population_seconds, 'prepareWallSeconds': preparation_seconds,
                           'deleteWallSeconds': measured['wallSeconds'], **result['progress']}
                else:
                    start = time.perf_counter()
                    if dart:
                        completed = subprocess.run([dart, str(ROOT / 'tools' / 'benchmark_dart_delete.dart'),
                            str(target), str(marker)], check=True, text=True, capture_output=True, timeout=max(300, count / 100))
                        details = json.loads(completed.stdout)
                    else:
                        shutil.rmtree(target); details = {}
                    row = {'case': f'{count}-small-files', 'mode': mode,
                           'populationSeconds': population_seconds,
                           'deleteWallSeconds': time.perf_counter() - start, **details}
                rows.append(row)
                print(json.dumps(row, ensure_ascii=False), flush=True)
        if real_gib:
            target = root / 'real-large.bin'
            block = b'VerTree benchmark\n' * (1024 * 1024 // 18)
            # Deterministic normal file writes, not a sparse SetEndOfFile fixture.
            remaining = real_gib * 1024 ** 3
            with target.open('wb', buffering=8 * 1024 * 1024) as file:
                while remaining:
                    data = block[:min(len(block), remaining)]
                    file.write(data); remaining -= len(data)
                file.flush(); os.fsync(file.fileno())
            size = target.stat().st_size
            measured = worker.delete(worker.prepare([target]))
            result = native_result(measured)
            check(result['outcome'] == 'succeeded' and not target.exists(), 'Real large-file deletion failed')
            rows.append({'case': f'{real_gib}-GiB-real-written-file', 'mode': 'native-auto',
                         'logicalBytes': size, 'deleteWallSeconds': measured['wallSeconds'], **result['progress']})
            print(json.dumps(rows[-1]), flush=True)
    output['benchmarks'] = rows
    output['benchmarkNotes'] = [
        'Each mode receives a newly generated equivalent temporary data set.',
        'Single run per case/mode; order is fixed and caches are not artificially cleared.',
        'Population is excluded from deletion timings; native preparation and process overhead are recorded separately.',
        'Logical bytes are not asserted to equal freed disk space; file contents are not read by the native deleter.',
        'Performance numbers apply only to this machine/filesystem, not untested HDD/SMB/ReFS devices.',
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker', type=Path, default=ROOT / 'build/file_tools_native/Release/vertree_file_worker.exe')
    parser.add_argument('--holder', type=Path, default=ROOT / 'build/file_tools_native/Release/vertree_file_lock_holder.exe')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/file_tools_dev/integration-results.json')
    parser.add_argument('--benchmark', action='store_true')
    parser.add_argument('--counts', default='10000,100000,300000')
    parser.add_argument('--real-gib', type=int, default=0)
    parser.add_argument('--dart')
    options = parser.parse_args()
    if os.name != 'nt': parser.error('This test runner requires Windows')
    if not options.worker.is_file() or not options.holder.is_file(): parser.error('Build the native worker and test holder first')
    if not 0 <= options.real_gib <= 10: parser.error('--real-gib must be 0..10')
    counts = [int(value) for value in options.counts.split(',')]
    if any(value < 1 or value > 1000000 for value in counts): parser.error('Benchmark counts must be 1..1000000')
    output: Json = {'schemaVersion': 1, 'os': sys.getwindowsversion()[:],
                    'worker': str(options.worker.resolve()), 'recordedAt': time.strftime('%Y-%m-%dT%H:%M:%S%z')}
    exit_code = 0
    try:
        worker = Worker(options.worker.resolve())
        run_integration(worker, options.holder.resolve(), output)
        if options.benchmark:
            benchmark(worker, counts, options.real_gib, output, options.dart)
    except BaseException as error:
        output['error'] = str(error); exit_code = 1
        print(f'FAILED: {error}', file=sys.stderr)
    finally:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding='utf-8')
        print(f'Results: {options.output}', flush=True)
    raise SystemExit(exit_code)


if __name__ == '__main__':
    main()
