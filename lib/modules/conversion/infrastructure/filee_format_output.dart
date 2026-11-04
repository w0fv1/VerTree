import '../domain/conversion_models.dart';

class FileeFormatOutput {
  static List<ConversionFormat> formats(String output) {
    final pattern = RegExp(
      r'^\s{2}([a-z0-9][a-z0-9_-]*)\s{2,}(.+?)\s{2,}((?:\.\S+\s*)+)$',
    );
    return [
      for (final line in output.split('\n'))
        if (!line.contains('(read only)'))
          if (pattern.firstMatch(line) case final match?)
            ConversionFormat(
              id: match.group(1)!,
              name: match.group(2)!.trim(),
              extensions: RegExp(r'\.([a-z0-9]+)', caseSensitive: false)
                  .allMatches(match.group(3)!)
                  .map((extension) => extension.group(1)!.toLowerCase())
                  .toList(),
            ),
    ];
  }

  static List<ConversionFormat> targets(
    String output,
    List<ConversionFormat> formats,
    String sourceExtension,
  ) {
    final marker = output.indexOf('converts to:');
    if (marker < 0) return const [];
    final available = output
        .substring(marker + 'converts to:'.length)
        .split('With optional engines')
        .first;
    final ids = available.split(',').map((id) => id.trim()).toSet();
    return formats
        .where(
          (format) =>
              ids.contains(format.id) &&
              !format.extensions.contains(sourceExtension.toLowerCase()),
        )
        .toList();
  }
}
