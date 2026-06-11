# Spanish language module for RHVoice

This language module contains needed binaries to build and run Spanish voices.

It works in both Castilian and neutral Latin bariants. In the future, we will follow variants with specific rules, like Argentinian Spanish, if someone give us voices of these specific variants, in which have changes of sounds in some phonemes.
If so, these variants will be available by branches of this repository.

## Features

- [Extra] currency and date support (binaries only, not registered in the core at all): These binaries translates a given currency or date format to human-speaker readable string. It probably can be available in the future by special c++ code for it.
  - Currency example: $1.25 (1 dólar y 25 centavos)
  - Date example (dd/mm/yyyy): 23/07/2025 (veintitrés de julio del dos mil veinticinco)
- Pronunciation dictionary: this is a set of the most comon foreign entries, that which needs to be pronounced as such.
  - Browsers: Chrome (croum) Firefox (fáirfox)
  - Places: Texas (tejas)
- Newest language detection: by default is disabled, but you will be able to share phonemes between Spanish and other second language, if this second language has a vocabulary set. It is currently set for English phonemes.
  - We probably will follow bilingual voices in the future in an individual language module for bilingual stuff, to be backward compatible with standard voices. Watch this space!
- Pitch marks for exclaim and question sentences. All voices will interpret them by raising or lowering pitch, according to the pitch range of the speaker.
- [Extra] Fanci normalization: we know that NVDA has own unicode normalization support. However, RHVoice is multiplatform, and these are fully supported in this language module, useful to read poems with stylized text.
- [Extra] [SAPM](https://www.tumblr.com/rhvoice-ec/774835280946528256/our-spanish-implementations-using-sentence-based) (Sentence-Aware Prosody Modelling): It correctly interprets prosody of Spanish words that have more than one context, and a context handles a different accentuation or stress. Rich prosody ensured, and improves experience for screen reader users.
- [Extra] Special skills to handle initialisms (AKA **siglas** in Spanish): This integrates special rules, especially in tokenization, to interpret initialisms as letter sequences in an efficient way.
  - Examples: NVDA, CNE, ADN.
