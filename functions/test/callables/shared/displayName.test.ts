// #1216a: normalizeRequiredDisplayName rejects the bidi/zero-width format
// reject-set K + enforces a visible-char floor, mirroring the Dart validator
// and firestore.rules isValidDisplayName. ZWNJ/ZWJ (U+200C/U+200D) stay
// allowed. Escaped notation ONLY — never raw invisibles in source (visible
// Persian/Arabic/emoji stay literal: they are legal).
import { normalizeRequiredDisplayName } from '../../../src/callables/shared/displayName';

// Reject-set K, one code point per entry (range-EXPANDED, ZWNJ/ZWJ excluded).
const K_CODE_POINTS = [
  0x00ad, 0x200b, 0x200e, 0x200f,
  0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
  0x2060, 0x2061, 0x2062, 0x2063, 0x2064,
  0x2066, 0x2067, 0x2068, 0x2069,
  0xfeff,
];

const VECTORS: Array<{ label: string; input: string; accept: boolean }> = [
  { label: 'V1 Ali', input: 'Ali', accept: true },
  { label: 'V2 RLO', input: 'Ali\u202e', accept: false },
  { label: 'V3 LRO', input: '\u202dhack', accept: false },
  { label: 'V4 isolate controls', input: 'a\u2066b\u2069', accept: false },
  { label: 'V5 ZWSP-only', input: '\u200b\u200b', accept: false },
  { label: 'V6 embedded ZWSP', input: 'Ali\u200bx', accept: false },
  { label: 'V7 Persian ZWNJ', input: 'می\u200cخواهم', accept: true },
  { label: 'V8 emoji ZWJ sequence', input: '\u{1F468}\u200d\u{1F469}\u200d\u{1F467}', accept: true },
  { label: 'V9 joiner-only fails floor', input: '\u200d\u200c', accept: false },
  { label: 'V10 joiners+ASCII space', input: '\u200d \u200c', accept: false },
  { label: 'V11 BOM', input: 'Bob\ufeff', accept: false },
  { label: 'V12 soft hyphen', input: 'x\u00ady', accept: false },
  { label: 'V13 LRM', input: '\u200eltr', accept: false },
  { label: 'V14 plain Arabic', input: 'عمر', accept: true },
  { label: 'V15 word joiner', input: 'Ali\u2060', accept: false },
  // V16 NBSP-only: TS mirrors the CLIENT (JS trim strips NBSP → empty → reject),
  // diverging from rules (which accept) — the documented safe-direction split.
  { label: 'V16 NBSP-only', input: '\u00a0', accept: false },
];

function rejectCode(input: unknown): string | undefined {
  try {
    normalizeRequiredDisplayName(input as never);
    return undefined;
  } catch (e) {
    return (e as { code?: string }).code;
  }
}

describe('#1216a normalizeRequiredDisplayName format-char rejection', () => {
  for (const v of VECTORS) {
    test(`${v.label} => ${v.accept ? 'ACCEPT' : 'REJECT'}`, () => {
      if (v.accept) {
        expect(normalizeRequiredDisplayName(v.input)).toBe(v.input);
      } else {
        expect(rejectCode(v.input)).toBe('invalid-argument');
      }
    });
  }

  test('full-K iteration: every K code point rejects "Ali"+char', () => {
    for (const cp of K_CODE_POINTS) {
      const input = `Ali${String.fromCodePoint(cp)}`;
      expect(rejectCode(input)).toBe('invalid-argument');
    }
  });
});
