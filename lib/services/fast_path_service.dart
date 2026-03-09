/// Fast-path field resolution — bypasses the on-device SLM entirely.
///
/// When the [QueryMapperService] detects a question that maps directly to a
/// known document field (e.g. "passport number"), this service performs an
/// immediate dictionary lookup and returns a formatted answer without ever
/// touching the SLM, preventing timeouts on slow mobile devices.
class FastPathService {
  /// Tries to answer a question directly from [documentJson] based on the
  /// pre-mapped [keys].
  ///
  /// Returns a [FastPathResult] describing one of three outcomes:
  ///  - [FastPathOutcome.resolved] — found the value(s), answer is ready.
  ///  - [FastPathOutcome.notFound] — field was known but missing from document.
  ///  - [FastPathOutcome.unknown] — no field mapping detected; fall to SLM.
  FastPathResult resolve({
    required Map<String, dynamic> documentJson,
    required List<String> keys,
  }) {
    // No field detected → question is open-ended, let SLM handle it.
    if (keys.isEmpty) return const FastPathResult(FastPathOutcome.unknown);

    final foundValues = <String>[];
    for (final key in keys) {
      // Try underscore variant first (canonical), then space variant as alias
      // to handle documents scanned before key normalization was applied.
      final variants = [key, key.replaceAll('_', ' ')];
      for (final variant in variants) {
        if (documentJson.containsKey(variant)) {
          final niceKey = key
              .split('_')
              .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' ');
          foundValues.add('$niceKey: ${documentJson[variant]}');
          break; // found via one of the variants — don't double-add
        }
      }
    }

    if (foundValues.isNotEmpty) {
      return FastPathResult(FastPathOutcome.resolved, answer: foundValues.join('\n'));
    }

    // Field detected but NOT present in the extracted document data.
    return const FastPathResult(
      FastPathOutcome.notFound,
      answer: 'Not found in document data.',
    );
  }
}

enum FastPathOutcome { resolved, notFound, unknown }

class FastPathResult {
  final FastPathOutcome outcome;
  final String? answer;
  const FastPathResult(this.outcome, {this.answer});
}
