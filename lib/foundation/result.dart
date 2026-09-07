class Result<T, E> {
  final String msg;
  final T? value;
  final E? error;
  final bool isErr;

  Result.ok(this.value, [this.msg = "ok"]) : error = null, isErr = false;

  Result.err([this.error, String? msg])
    : msg = msg ?? error.toString(),
      value = null,
      isErr = true;

  Result.eMsg([this.msg = "err"]) : error = null, value = null, isErr = true;

  bool get isOk => !isErr;

  T unwrap() {
    if (isOk) return value as T;
    throw Exception('Attempted to unwrap an Err value');
  }

  T unwrapOr(T defaultValue) => isOk ? value as T : defaultValue;

  E unwrapErr() {
    if (isErr) return error as E;
    throw Exception('Attempted to unwrapErr an Ok value');
  }

  Result<U, E> map<U>(U Function(T) fn) {
    if (isOk) {
      return Result.ok(fn(value as T));
    } else {
      return Result.err(error as E, msg);
    }
  }

  Result<T, F> mapErr<F>(F Function(E) fn) {
    if (isErr) {
      return Result.err(fn(error as E), msg);
    } else {
      return Result.ok(value as T, msg);
    }
  }

  void when({
    required void Function(T value) ok,
    required void Function(E? error, String msg) err,
  }) {
    if (isOk) {
      ok(value as T);
    } else {
      err(error, msg);
    }
  }

  U match<U>(U Function(T) ok, U Function(E) err) {
    return isOk ? ok(value as T) : err(error as E);
  }

  @override
  String toString() {
    if (isOk) {
      return 'Result.ok(value: $value, msg: "$msg")';
    } else if (isErr) {
      return 'Result.err(error: $error, msg: "$msg")';
    }
    return 'Result(msg: "$msg")';
  }
}
