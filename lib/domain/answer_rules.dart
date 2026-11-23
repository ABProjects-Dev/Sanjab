/// Answer validation rules for the Stop button.
///
/// Single project rule: Stop is enabled only when **every** answer field of
/// the player in the current round has at least [kStopMinValidChars] valid
/// characters.
///
/// A valid character is one that:
///  * is visible (spaces, half-spaces, zero-width characters, bidi marks,
///    BOM and control characters do not count);
///  * is not whitespace, neither at the edges nor in the middle of the answer.
///
/// The same helpers are used by the UI, the domain layer and the host so the
/// rule cannot drift between layers.
library;

import 'package:characters/characters.dart';

/// Minimum valid characters per answer field before Stop becomes available.
const int kStopMinValidChars = 2;

/// Maximum number of user-perceived characters accepted in an answer.
const int kMaxAnswerLength = 80;

/// Return the number of grapheme clusters shown to a user.
int answerCharacterCount(String text) => text.characters.length;

/// Whether the answer fits the shared UI and host-server length limit.
bool isAnswerWithinLimit(String text) =>
    answerCharacterCount(text) <= kMaxAnswerLength;

/// Characters excluded from the valid count (whitespace and invisible):
///  * U+0000..U+0020  control characters and the plain space
///  * U+007F..U+00A0  control characters and no-break space (NBSP)
///  * U+00AD         soft hyphen
///  * U+1680, U+180E Unicode spaces
///  * U+2000..U+200F spaces, zero-width characters (ZWSP/ZWNJ/ZWJ) and LRM/RLM
///  * U+2028..U+202F line and paragraph separators, narrow spaces
///  * U+205F..U+2064 math space, word joiner and invisible operators
///  * U+2066..U+206F bidi control marks
///  * U+3000, U+FEFF, U+FFF9..U+FFFB ideographic space, BOM and annotation marks
final RegExp _invisibleRunes = RegExp(
  '[\u0000-\u0020\u007F-\u00A0\u00AD\u1680\u180E'
  '\u2000-\u200F\u2028-\u202F\u205F-\u2064\u2066-\u206F'
  '\u3000\uFEFF\uFFF9-\uFFFB]',
);

/// Strips whitespace and invisible characters before counting valid ones.
///
///
/// Example: `'  ab\u200c  '` becomes `'ab'`.
String normalizeAnswerForStop(String text) =>
    text.replaceAll(_invisibleRunes, '');

/// Number of valid characters in an answer.
///
/// Leading and trailing spaces, inner spaces, half-spaces and invisible
/// characters are not counted.
int validAnswerCharCount(String text) =>
    normalizeAnswerForStop(text).runes.length;

/// Whether this answer field has at least [kStopMinValidChars] valid characters.
bool isAnswerEligibleForStop(String text) =>
    validAnswerCharCount(text) >= kStopMinValidChars;
