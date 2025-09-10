// Utility helpers to sanitize user-provided names for files and folders.

String sanitizeFileName(String input, {int maxLength = 120}) {
  // Replace characters invalid on common filesystems and MediaStore folders
  var s = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  // Remove control characters
  s = s.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  // Normalize whitespace
  s = s.trim();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) s = 'untitled';
  if (s == '.' || s == '..') s = '_';
  if (s.length > maxLength) s = s.substring(0, maxLength);
  return s;
}

String sanitizeDir(String input) {
  // Directory segment sanitization reuses file name constraints
  final s = sanitizeFileName(input);
  return (s == '.' || s == '..') ? '_' : s;
}

