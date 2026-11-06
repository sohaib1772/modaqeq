import 'dart:io';
import 'package:modaqeq_maktabali/services/print_feedback_script.dart';

void main() {
  Directory('build').createSync();
  File(
    'build/print-feedback.js',
  ).writeAsStringSync(printFeedbackScript('https://fixture.example'));
}
