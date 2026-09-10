import 'dart:io';

Future<String?> saveCsvReport(String fileName, String csv) async {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return null;

  final documents = Directory('$home${Platform.pathSeparator}Documents');
  final target = await documents.exists() ? documents : Directory(home);
  final file = File('${target.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(csv);
  return file.path;
}
