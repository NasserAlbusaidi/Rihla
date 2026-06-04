import Decimal from 'decimal.js';

// MONEY SURFACE (#53). Display-only formatter for push-notification copy — it
// never feeds balance math. But a wrong subunit scale renders visibly-wrong
// money in the notification, so this MUST mirror MoneySerializer's scale table
// byte-for-byte (lib/core/services/money_serializer.dart:8-19) and, like
// MoneySerializer._scale (:55-57), look the currency up CASE-INSENSITIVELY.
const CURRENCY_SCALE: Readonly<Record<string, number>> = {
  OMR: 1000,
  USD: 100,
  EUR: 100,
  GBP: 100,
  SAR: 100,
  AED: 100,
  JPY: 1,
  KWD: 1000,
  BHD: 1000,
  QAR: 100,
};

// Unknown/garbage currency falls back to OMR's scale, mirroring the client read
// fence (Settlement.fromFirestore, expense_provider.dart #47) so a forged/legacy
// doc never throws inside a fire-after-commit trigger.
const FALLBACK_SCALE = CURRENCY_SCALE.OMR;

function scaleFor(currency: string): number {
  return CURRENCY_SCALE[currency.toUpperCase()] ?? FALLBACK_SCALE;
}

function fractionDigits(scale: number): number {
  let digits = 0;
  let remaining = scale;
  while (remaining > 1) {
    remaining /= 10;
    digits += 1;
  }
  return digits;
}

/**
 * Formats integer subunits (`amountFils`) as a fixed-precision decimal string
 * for the currency's scale: OMR 10500 -> "10.500", USD 999 -> "9.99",
 * JPY 1000 -> "1000". Case-insensitive; unknown currency -> OMR scale.
 */
export function formatAmount(amountFils: number, currency: string): string {
  const scale = scaleFor(currency);
  const digits = fractionDigits(scale);
  return new Decimal(amountFils).div(scale).toFixed(digits);
}
