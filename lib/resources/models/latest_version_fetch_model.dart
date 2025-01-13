class LatestVersionFetchModel {
  String? latestVersion;
  List<String>? changelogs;

  LatestVersionFetchModel({this.latestVersion, this.changelogs});

  LatestVersionFetchModel.fromJson(Map<String, dynamic> json) {
    latestVersion = json['latest_version'];
    changelogs = json['changelogs'].cast<String>();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['latest_version'] = this.latestVersion;
    data['changelogs'] = this.changelogs;
    return data;
  }
}
