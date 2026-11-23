/// Persian display helpers: Persian digits and time formatting.
library;

const List<String> _persianDigits = <String>[
  '۰',
  '۱',
  '۲',
  '۳',
  '۴',
  '۵',
  '۶',
  '۷',
  '۸',
  '۹',
];

/// Convert every Latin digit in a string to a Persian digit.
String faNum(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.write(_persianDigits[rune - 0x30]);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Format remaining time as mm:ss with Persian digits.
String faTimer(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).ceil().clamp(0, 24 * 3600);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return faNum('$mm:$ss');
}

/// Human-readable Persian duration label (for example 5 minutes).
String faDurationLabel(int seconds) {
  if (seconds % 60 == 0) return '${faNum(seconds ~/ 60)} دقیقه';
  return '${faNum(seconds)} ثانیه';
}

/// Convert Persian/Arabic digits to Latin (for technical input such as IP and port).
String faToEnDigits(String input) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final pi = persian.indexOf(ch);
    if (pi >= 0) {
      buffer.write(pi);
      continue;
    }
    final ai = arabic.indexOf(ch);
    if (ai >= 0) {
      buffer.write(ai);
      continue;
    }
    buffer.write(ch);
  }
  return buffer.toString();
}
