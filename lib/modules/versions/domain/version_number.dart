class FileVersion implements Comparable<FileVersion> {
  final List<Segment> segments;

  FileVersion._(List<Segment> segments)
    : segments = List.unmodifiable(segments);

  factory FileVersion(String versionString) {
    return FileVersion._(_parse(versionString));
  }

  static List<Segment> _parse(String versionString) {
    final parts = versionString.split('-');
    final segs = <Segment>[];
    for (final part in parts) {
      List<String> bv = part.split('.');
      if (bv.length != 2) {
        throw FormatException("Invalid version segment: $part");
      }
      final branch = int.parse(bv[0]);
      final ver = int.parse(bv[1]);
      segs.add(Segment(branch, ver));
    }
    return segs;
  }

  factory FileVersion.fromSegments(List<Segment> segs) {
    return FileVersion._(List<Segment>.from(segs));
  }

  FileVersion nextVersion() {
    if (segments.isEmpty) {
      return FileVersion('0.0');
    }
    final newSegs = List<Segment>.from(segments);
    final last = newSegs.last;
    newSegs[newSegs.length - 1] = Segment(last.branch, last.version + 1);
    return FileVersion.fromSegments(newSegs);
  }

  FileVersion branchVersion(int branchIndex) {
    final newSegs = List<Segment>.from(segments);
    newSegs.add(Segment(branchIndex, 0));
    return FileVersion.fromSegments(newSegs);
  }

  @override
  String toString() {
    return segments.map((seg) => '${seg.branch}.${seg.version}').join('-');
  }

  String get branchPath {
    return segments.map((seg) => seg.branch.toString()).join('-');
  }

  int get revisionNumber {
    if (segments.isEmpty) {
      return 0;
    }
    return segments.last.version;
  }

  @override
  int compareTo(FileVersion other) {
    final minLen = segments.length < other.segments.length
        ? segments.length
        : other.segments.length;
    for (int i = 0; i < minLen; i++) {
      final diffBranch = segments[i].branch - other.segments[i].branch;
      if (diffBranch != 0) return diffBranch;
      final diffVer = segments[i].version - other.segments[i].version;
      if (diffVer != 0) return diffVer;
    }
    return segments.length - other.segments.length;
  }

  @override
  bool operator ==(Object other) =>
      other is FileVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(segments);

  bool isSameBranch(FileVersion other) {
    if (segments.length != other.segments.length) {
      return false;
    }
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].branch != other.segments[i].branch ||
          (i < segments.length - 1 &&
              segments[i].version != other.segments[i].version)) {
        return false;
      }
    }
    return true;
  }

  bool isChild(FileVersion other) {
    if (!isSameBranch(other)) return false;
    return segments.last.version + 1 == other.segments.last.version;
  }

  bool isDirectBranch(FileVersion other) {
    if (other.segments.length != segments.length + 1) {
      return false;
    }
    final n = segments.length;
    for (int i = 0; i < n; i++) {
      if (segments[i] != other.segments[i]) {
        return false;
      }
    }
    final lastOther = other.segments[other.segments.length - 1];
    if (lastOther.version != 0) {
      return false;
    }
    return true;
  }

  bool isIndirectBranch(FileVersion other) {
    if (other.segments.length <= segments.length + 1) {
      return false;
    }
    for (int i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) {
        return false;
      }
    }
    return true;
  }
}

class Segment {
  final int branch;
  final int version;

  const Segment(this.branch, this.version);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Segment) return false;
    return branch == other.branch && version == other.version;
  }

  @override
  int get hashCode => Object.hash(branch, version);
}
