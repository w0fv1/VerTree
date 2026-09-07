/// Stable application failure. Adapters own localization and protocol mapping.
class OperationFailure implements Exception {
  const OperationFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
