class StringUtils {
  static String truncate(String? input, int maxLength, [String suffix = ".."]) {
    if (input == null) {
      return "";
    }

    if (input.length <= maxLength) {
      return input;
    }
    return "${input.substring(0, maxLength)}$suffix";
  }
}
