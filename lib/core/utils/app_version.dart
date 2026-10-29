/// `1.2.3` style versions (the build number after `+` is ignored).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  factory AppVersion.parse(String text) {
    final core = text.split('+').first.trim();
    final parts = core
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    int at(int i) => i < parts.length ? parts[i] : 0;
    return AppVersion(at(0), at(1), at(2));
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion o) => compareTo(o) < 0;
  bool operator >=(AppVersion o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
