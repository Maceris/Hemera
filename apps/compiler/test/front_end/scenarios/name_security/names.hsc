package name_security

/*
 * UTS #39's checks of names (docs/formatting.md, Identifiers): two warned as looking like another (W2000), one as mixing
 * scripts (W2001), one as having a character that isn't for everyday text (W2002), and the rest, which are fine.
 */

// cop in Latin, then in Cyrillic, which looks the same (W2000)
cop :: 1
сор :: 2

// ox is in Latin here, and in Cyrillic in other.hsc (W2000)
ox :: 3

// Latin and Cyrillic in one name (W2001)
total_итог :: 4

// Runic, which UTS #39 doesn't recommend for names (W2002)
ᚠᚢ :: 5

// Fine: one script each, or Latin, Han and kana, or Han and Hangul together
имя :: 6
日本語_name :: 7
ひらがな漢字 :: 8
한국어漢字 :: 9
πλάτος :: 10
