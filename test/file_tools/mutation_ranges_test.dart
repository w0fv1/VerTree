import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/file_access/file_access.dart';

void main() {
  test('subtree is component-aware, Windows case conservative', () {
    final tree = MutationScope.subtree(r'C:\work\a');
    expect(tree.overlaps(MutationScope.file(r'c:\WORK\a\deep\x')), isTrue);
    expect(tree.overlaps(MutationScope.file(r'C:\work\abc\x')), isFalse);
    expect(
      tree.overlaps(MutationScope.directoryEntries(r'C:\work\a\deep')),
      isTrue,
    );
    expect(tree.overlaps(MutationScope.task(r'C:\work\a')), isFalse);
  });
  test('reservation rejects new writers, drains accepted work', () async {
    final writes = FileMutationCoordinator();
    final gate = Completer<void>();
    final order = <String>[];
    final first = writes.run(
      [MutationScope.directoryEntries(r'C:\p\a')],
      () async {
        await gate.future;
        order.add('write');
      },
    );
    final scope = MutationScope.subtree(r'C:\p');
    final lease = writes.reserve([scope]);
    final deletion = writes.run([scope], () async {
      order.add('delete');
    }, reservation: lease);
    await expectLater(
      writes.run([MutationScope.file(r'C:\p\a\x')], () async {}),
      throwsStateError,
    );
    await writes.run([MutationScope.file(r'D:\other')], () async {
      order.add('independent');
    });
    gate.complete();
    await first;
    await deletion;
    expect(order, ['independent', 'write', 'delete']);
    lease.release();
    await writes.close();
  });
  test('failure and nested acquisition do not poison queue', () async {
    final writes = FileMutationCoordinator();
    final scope = MutationScope.file('/work/a');
    await expectLater(
      writes.run([scope], () => writes.run([scope], () async {})),
      throwsStateError,
    );
    expect(await writes.run([scope], () async => 42), 42);
    await writes.close();
    await expectLater(writes.run([scope], () async {}), throwsStateError);
  });
}
