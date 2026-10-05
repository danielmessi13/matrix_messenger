import 'package:diacritic/diacritic.dart';
import 'package:flutter/widgets.dart';

extension StringExtensions on String {
  String get foldedForSearch => removeDiacritics(this).toLowerCase();

  String get initials {
    final words = replaceAll(
      RegExp(r'^[@#]+'),
      '',
    ).split(RegExp(r'[\s._-]+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return (words[0].characters.first + words[1].characters.first)
        .toUpperCase();
  }

  String get userInitials => split(':').first.initials;
}
