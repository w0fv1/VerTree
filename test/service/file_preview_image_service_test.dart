import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/service/file_preview_image_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('validates output geometry and preserves page/time selection', () {
    final request = PreviewImageRequest.fromJson({'path': p.absolute('sample.pdf'), 'page': 2, 'width': 800});
    expect(request.options, {'width': 800, 'height': 1600, 'page': 2, 'timeSeconds': 0});
    for (final invalid in [{'width': 0}, {'height': 4097}, {'page': 1.5}, {'timeSeconds': -1}]) {
      expect(() => PreviewImageRequest.fromJson({'path': p.absolute('sample.pdf'), ...invalid}), throwsFormatException);
    }
    expect(() => PreviewImageRequest.fromJson({'path': 'relative.pdf'}), throwsFormatException);
  });
}
