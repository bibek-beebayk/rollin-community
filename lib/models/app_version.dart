class AppVersion {
  final String versionCode;
  final bool isMandatory;
  final String releaseNotes;
  final String? apkUrl;

  AppVersion({
    required this.versionCode,
    required this.isMandatory,
    required this.releaseNotes,
    this.apkUrl,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      versionCode: json['version_code'] ?? '1.0.0+1',
      isMandatory: json['is_mandatory'] ?? false,
      releaseNotes: json['release_notes'] ?? '',
      apkUrl: json['apk_url'],
    );
  }
}
