import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/modules/conversion/domain/conversion_models.dart';

void main() {
  test('detects extensions case-insensitively', () {
    expect(hasFileExtension(r'C:\Temp\Photo.JPEG', 'jpg'), isFalse);
    expect(hasFileExtension('/tmp/photo.webp', 'webp'), isTrue);
  });

  test('removes only the final extension', () {
    expect(fileNameWithoutExtension('/tmp/archive.tar.gz'), 'archive.tar');
    expect(fileNameWithoutExtension('/tmp/README'), 'README');
  });
}
