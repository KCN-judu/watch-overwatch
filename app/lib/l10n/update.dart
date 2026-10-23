/// Checking for, downloading and installing a new version. See strings.dart.
class UpdateStrings {
  const UpdateStrings();

  String get title => '版本更新';
  String get cmdCheck => '检查更新…';
  String get check => '检查更新';
  String get checking => '正在检查新版本…';
  String newVersion(String v) => '新版本 $v';
  String get newVersionTip => '点开查看更新内容';
  String upToDate(String v) => '已是最新版本（$v）';
  String available(String latest, String current) =>
      '$latest 可以更新（当前 $current）';
  String published(String date) => '发布于 $date';
  String get notesTitle => '更新内容';
  String get noNotes => '这一版没有写更新说明。';
  String get later => '以后再说';
  String get openPage => '在网页查看';
  String get download => '下载更新';
  String downloading(String got, String total) => '正在下载 $got / $total';
  String get verifying => '正在校验…';
  String get ready => '已下载并校验，重启后即为新版本。';
  String get restart => '重启并更新';
  String get retry => '重试';
  String failed(String why) => '没有更新成功：$why';
  String get checkFailed => '连不上 GitHub，查不到新版本。请检查网络后重试。';
  String get devBuild => '当前是开发构建，不能自动安装。请到网页下载发布包。';
  String get privacy => '检查更新只访问 GitHub 上本项目公开的发布页，不发送账号或对局数据。';
  String get version => '版本';
  String get autoCheck => '自动检查更新';
  String get autoOn => '启动时检查';
  String get autoOff => '不检查';
}
