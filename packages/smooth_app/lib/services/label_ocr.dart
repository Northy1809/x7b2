import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';

/// Reads the text on a photographed label. On-device (Google ML Kit): free,
/// works offline, no account or API key.
abstract class LabelOcr {
  Future<String> readText(final String imagePath);

  /// Each line with its height on the photo, plus the full text.
  Future<LabelText> readLines(final String imagePath);
}

class LabelText {
  const LabelText(this.text, this.lines);

  static const LabelText empty = LabelText('', <PackTextLine>[]);

  final String text;
  final List<PackTextLine> lines;
}

class MlKitLabelOcr implements LabelOcr {
  const MlKitLabelOcr();

  @override
  Future<String> readText(final String imagePath) async => (await readLines(imagePath)).text;

  @override
  Future<LabelText> readLines(final String imagePath) async {
    final TextRecognizer recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final RecognizedText result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return LabelText(result.text, <PackTextLine>[
        for (final TextBlock block in result.blocks)
          for (final TextLine line in block.lines) PackTextLine(line.text, line.boundingBox.height),
      ]);
    } finally {
      await recognizer.close();
    }
  }
}
