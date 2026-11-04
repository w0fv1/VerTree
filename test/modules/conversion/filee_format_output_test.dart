import 'package:test/test.dart';
import 'package:vertree/modules/conversion/infrastructure/filee_format_output.dart';

void main() {
  test('target capabilities exclude optional engines and resolve aliases', () {
    final formats = FileeFormatOutput.formats('''Image:
  png        PNG  .png
  jpg        JPG  .jpg .jpeg
  mp4        MP4  .mp4
  raw        RAW (read only)  .raw
''');
    final targets = FileeFormatOutput.targets(
      '''JPG (jpg) converts to:
  png, jpg
With optional engines (install them in Filee, Settings → Engines):
  mp4
''',
      formats,
      'jpeg',
    );
    expect(targets.map((format) => format.id), ['png']);
    expect(formats.map((format) => format.id), ['png', 'jpg', 'mp4']);
  });
  test('unknown source has no fabricated targets', () {
    expect(FileeFormatOutput.targets('Unknown format', [], 'unknown'), isEmpty);
  });
}
