# NOTICE — компоненти та ліцензії / Third-party components and licenses

Перелік усіх сторонніх компонентів застосунку **RHVoice UA (RHVoice Ukrainian)**
та їхніх ліцензій. Звірено з файлами, які реально входять у збірку
(`RHVoiceCore/Package.swift`, `UkrainianVoicesApp/project.yml`), аудит 2026-08-05.

Повні тексти всіх згаданих ліцензій — у теці [`LICENSES/`](LICENSES/) цього
репозиторію; ті самі тексти постачаються всередині застосунку (екран «Ліцензії»).

---

## Ліцензія застосунку

**RHVoice UA розповсюджується за GNU General Public License версії 3 або
(на ваш вибір) будь-якої пізнішої версії** — див. [`LICENSE`](LICENSE)
(повний текст: [`LICENSES/GPL-3.0.txt`](LICENSES/GPL-3.0.txt)).

Разом із GPL-3 застосовується **додатковий дозвіл на розповсюдження через
Apple App Store**, опублікований авторкою RHVoice Ольгою Яковлевою 03.08.2026 —
див. [`APP_STORE_EXCEPTION.md`](APP_STORE_EXCEPTION.md).

**Чому саме GPL-3, а не LGPL.** У бінарник збірки лінкуються файли рушія під
чистою GPL-2.0-or-later: увесь каталог `src/hts_engine/` (HTS-синтез),
`src/audio/` (аудіо-підсистема) і обгортки вокодера в `src/core/`
(`hts_vocoder_wrapper.cpp`, `model_answer_cache.cpp`, `str_hts_engine_impl.cpp`).
Тому сукупна робота є GPL, а не LGPL. У всіх цих файлах стоїть формулювання
«or (at your option) any later version», що дозволяє законно обрати версію 3.
Додатковий аргумент: бібліотека **sonic** під Apache-2.0 сумісна з GPL-3, але
несумісна з GPL-2.

Вихідний код кожної розповсюджуваної збірки:
<https://github.com/abuten1977-design/RHVoiceUkraine>

---

## Рушій синтезу

| Компонент | Правовласник | Ліцензія |
|---|---|---|
| **RHVoice** (core, lib) | Ольга Яковлева | LGPL-2.1-or-later (більшість файлів) і GPL-2.0-or-later (частина файлів) → у сукупності GPL-3 з App Store exception |
| **hts_engine API** | HTS Working Group; Nagoya Institute of Technology; Tokyo Institute of Technology | Оригінал — 3-clause BSD ([`LICENSES/BSD-3-Clause-hts_engine.txt`](LICENSES/BSD-3-Clause-hts_engine.txt)); файли у складі RHVoice модифіковані авторкою рушія під GPL-2.0-or-later |

**Обов'язкове застереження за BSD-ліцензією hts_engine API:**

> Copyright (c) 2001-2015 Nagoya Institute of Technology, Department of Computer
> Science; 2001-2008 Tokyo Institute of Technology, Interdisciplinary Graduate
> School of Science and Engineering. All rights reserved.
> Redistributions in binary form must reproduce the above copyright notice, this
> list of conditions and the following disclaimer in the documentation and/or
> other materials provided with the distribution.

MAGE (GPLv3) у збірку **не входить** — перевірено по `Package.swift` і
`project.yml` (файлів MAGE у дереві репозиторію немає взагалі).

---

## Сторонні бібліотеки у складі збірки

| Бібліотека | Автор | Ліцензія | Повний текст |
|---|---|---|---|
| **sonic** | Bill Cox | Apache-2.0 | [`LICENSES/Apache-2.0-sonic.txt`](LICENSES/Apache-2.0-sonic.txt) |
| **Boost 1.79** (header-only) | Boost contributors | BSL-1.0 | [`LICENSES/BSL-1.0.txt`](LICENSES/BSL-1.0.txt) |
| **rapidxml** | Marcin Kalicinski | BSL-1.0 або MIT (на вибір) | [`LICENSES/BSL-1.0.txt`](LICENSES/BSL-1.0.txt) |
| **utf8cpp** | Nemanja Trifunovic | Boost-style permissive | [`LICENSES/BSL-1.0.txt`](LICENSES/BSL-1.0.txt) |
| **ZIPFoundation** | Thomas Zoechling | MIT | [`LICENSES/MIT-ZIPFoundation.txt`](LICENSES/MIT-ZIPFoundation.txt) |

У репозиторії також лежать, але **у збірку не входять**: `src/third-party/cldr`
(Unicode License), `src/third-party/tclap` (MIT), допоміжні модулі CMake.

---

## Українські голоси (вбудовані у застосунок)

Голосові дані створено командою **«Синтезатор української мови»**. Дані
постачаються **без змін**: збірка копіює їх як є і не перетворює
(перевірено по `postBuildScripts` у `project.yml` — змінюється лише
конфігураційний файл рушія `RHVoice.conf`, самі голоси не чіпаються).

| Голос | Диктор | Команда | Ліцензія |
|---|---|---|---|
| **Anatol** | Анатолій Подорожко, диктор Харківського обласного радіо | Artem Plaksin, Volodymyr Pyrih, Sergey Parshakov, Zvonimir Stanecic | LGPL-2.1 ([текст](LICENSES/LGPL-2.1.txt)) |
| **Natalia** | Наталія Чехаль | Artem Plaksin, Volodymyr Pyrih, Tomasz Bilecki, Zvonimir Stanecic | LGPL-2.1 ([текст](LICENSES/LGPL-2.1.txt)) |
| **Marianna** | Marianna Firtka, радіоведуча | Artem Plaksin, Volodymyr Pyrih, Maryna Herelyuk, Sergey Parshakov, Beka Gozalishvili | CC BY-ND 4.0 ([текст](LICENSES/CC-BY-ND-4.0.txt)) |
| **Volodymyr** | Володимир Беглов | команда проєкту «Синтезатор української мови» | CC BY-ND 4.0 ([текст](LICENSES/CC-BY-ND-4.0.txt)) |

Контакти команди: <https://facebook.com/syntezator>, vp88.mobile@gmail.com,
<https://rhvoice.su>

---

## Англійські голоси (завантажуються за потреби)

Голоси **Бен (bdl)**, **Клара (clb)**, **Сара (slt)**, **Радж (ksp)** не входять
у застосунок; користувач завантажує їх окремо з релізу `voice-data-v1` цього
репозиторію.

Основа — мовний корпус **CMU ARCTIC**, Carnegie Mellon University. Моделі
натреновано для рушія RHVoice, тобто це **змінені похідні** оригінальних даних
(ліцензія вимагає позначати зміни явно). Повний текст ліцензії:
[`LICENSES/CMU-Festvox.txt`](LICENSES/CMU-Festvox.txt).

---

## Мовні дані

| Дані | Склад | Ліцензія |
|---|---|---|
| **Ukrainian** | словники, правила наголосу, фонетика, токенізація | у складі RHVoice (ліцензія рушія) |
| **English** | `cmulex.fst`, `cmulex.lts` — похідні від CMU Pronouncing Dictionary | [`LICENSES/CMU-cmudict.txt`](LICENSES/CMU-cmudict.txt) |

Англійські мовні дані вбудовані в застосунок, бо український мовний модуль
оголошений двомовним (`bilingual=English`) і потребує їх для читання латиниці.

---

## Товарні знаки та логотипи

Наступні матеріали **не підпадають під GPL-3** і не ліцензуються цим
репозиторієм — це чужі товарні знаки, використані в межах проєкту з дозволу:

1. Логотипи донорів — Європейський Союз, Фонд Східна Європа, «Фенікс: Сила
   спільнот», Act to Drive Change:
   `UkrainianVoicesApp/App/Assets.xcassets/DonorLogosBar.imageset/`.
2. Іконка застосунку:
   `UkrainianVoicesApp/App/Assets.xcassets/AppIcon.appiconset/`.

Той, хто створює похідну роботу на основі цього коду, має **видалити ці
матеріали** зі своєї збірки.

---

## Власний код

Власний код застосунку (Swift, Objective-C++, конфігурація збірки) належить
**ГО «Харківський центр реабілітації молодих осіб з інвалідністю та членів їх
сімей „Право вибору“»** (грант № ФС 01/05-26) і розповсюджується за GPL-3
(або пізнішою) разом із App Store exception. Фонд Східна Європа та Європейський
Союз мають право зазначати себе як донорів.

Застосунок розповсюджується **безкоштовно**, без внутрішніх покупок і реклами —
вимога грантової угоди.

---

## Що лишається зробити перед публікацією в App Store

1. Отримати письмовий дозвіл команди «Синтезатор української мови» на
   розповсюдження голосів через App Store і через нотаризований macOS-канал
   (додатковий дозвіл Ольги Яковлевої стосується лише рушія).
2. Підготувати власний ліцензійний договір (Custom EULA) в App Store Connect —
   стандартний EULA Apple суперечить GPL-3 §10.
3. Додати до архівів завантажуваних англійських голосів файл ліцензії CMU і
   позначку про те, що моделі є зміненими похідними.
4. Опублікувати політику приватності за публічною адресою.
