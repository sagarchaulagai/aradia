class LatestVersionFetchModel {
  String? latestVersion;
  List<String>? changelogs;

  LatestVersionFetchModel({this.latestVersion, this.changelogs});

  LatestVersionFetchModel.fromJson(Map<String, dynamic> json) {
    latestVersion = json['latest_version'];
    changelogs = json['changelogs'].cast<String>();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['latest_version'] = latestVersion;
    data['changelogs'] = changelogs;
    return data;
  }
}
