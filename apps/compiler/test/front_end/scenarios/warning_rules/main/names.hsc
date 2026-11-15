package warning_rules

import wordy from "std:wordy"

// Latin and Cyrillic in one name (hemera:W2001), shown unless the build allows it
total_итог :: 1

// Runic (hemera:W2002), which ALLOWED_WARNINGS allows in this package
ᚠᚢ :: 2

answer :: wordy.ANSWER
