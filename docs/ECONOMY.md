# Wirtschaft und Monetarisierung

Alle Preise stehen im Code in `src/ReplicatedStorage/Shared/Data/Products.luau` (Robux) und in den Daten-Modulen
(Münzen). Tests in `tests/Products.spec.luau` prüfen die Fairness-Regeln automatisch.

## Regeln (nicht verhandelbar)

1. **Kein Pay-to-Win.** Kein Produkt ändert Kampfwerte. Ranked: keine Startwaffen, nur die 8 klassischen Items.
2. **Nichts Zufälliges gegen Robux.** Jedes Produkt listet genau, was es gibt. Truhen geben das nächste fehlende Item
   einer sichtbaren Liste oder feste Münzen.
3. **Eine Spielwährung:** Münzen. Keine Gems.
4. **Kein Kauf-Popup nach einer Niederlage, keine Fake-Countdowns.** Das 72-h-Fenster des Startpakets ist echt.

## Was beim Spieler ankommt und was bei uns

Rechnung aus `roblox/roadmap.md`: Roblox behält 30 % Marktplatzgebühr, DevEx zahlt 0,0038 USD pro verdientem Robux.
Von einem ausgegebenen Robux bleiben ≈ 0,0027 USD (≈ 0,0023 €). **Grob 20 % von dem, was Spieler zahlen, kommen bei uns an.**

| Produkt | Robux | Spieler zahlt ca.* | Bei uns ca. |
|---|---|---|---|
| Ruhmespfad Premium | 499 | 6,20 € | 1,15 € |
| VIP | 399 | 5,00 € | 0,92 € |
| Startpaket | 99 | 1,25 € | 0,23 € |
| Münzbeutel XL | 899 | 11,20 € | 2,07 € |

*Schätzung über den Robux-Kaufpreis von ≈ 1,25 € pro 100 Robux; hängt von Paket und Land ab.

## Game Passes (einmalig)

| Pass | Robux | Inhalt | Warum dieser Preis |
|---|---|---|---|
| VIP | 399 | Goldener Name, Chat-Tag, +1 Arena-Stimme (max. 3 gesamt), VIP-Lounge, Siegerpose, +10 % Münzen | Status-Pass, sichtbar in Lobby und Match |
| Doppelte Münzen | 349 | +100 % Münzen aus Kämpfen | erfahrungsgemäß der meistverkaufte Pass in Progressions-Spielen |
| Doppelte XP | 299 | +100 % Spieler- und Kämpfer-XP | |
| Finisher-Kino Plus | 249 | alternative Kamerafahrten, **Finisher-Replay als Clip** | verkauft genau den Moment, der in Videos geteilt wird |
| Waffenkammer | 299 | alle 8 Shop-Waffen (nicht in Ranked) | Münzwert 5 500 |
| Arena-Sammlung | 499 | alle 22 Zusatz-Arenen | Münzwert 11 850 |
| Prompt-Labor Plus | 199 | 10 statt 3 Prompt-Slots, Farbwahl, eigener Kartenname, Aura-Stile | Einstieg über das Alleinstellungsmerkmal |
| Privatserver | 100 / Monat | Roblox-Privatserver mit Mutator-, Waffen-, Bot-Einstellungen | |

Münz-Boni werden **addiert** (`Progression.matchCoins`): VIP + Doppelte Münzen = ×2,1, nicht ×2,2.

## Developer Products (mehrfach)

| Produkt | Robux | Inhalt |
|---|---|---|
| Münzbeutel S / M / L / XL | 49 / 149 / 399 / 899 | 500 / 1 700 / 5 000 / 12 000 Münzen (Kurs steigt mit Größe, per Test geprüft) |
| Startpaket | 99 | Kämpfer nach Wahl + 1 000 Münzen + Skin CHROM; einmal, nur in den ersten 72 h |
| Kämpfer sofort | 149 / 199 / 299 | Kämpfer der Münz-Stufe 600 / 900 / 1200 |
| Skin direkt | 99–449 | Rotations-Shop; Preis nach Münzpreis (`Products.skinRobux`) |
| NEON-NÄCHTE | 399 | 5 Arenen + Skins NEONPULS, GALAXIE |
| HIMMEL & HÖLLE | 599 | 4 Skins + SEELENSENSE + DRACHENLANZE |
| Abenteuer-Rettung | 25 | einmal pro Lauf weiterspielen, nur Solo; **Lauf zählt dann nicht für die globale Bestenliste** |
| Ruhmespfad Premium | 499 | Premium-Spur der Saison, sofort alles bis zur aktuellen Stufe |
| Ruhmespfad Premium+ | 899 | Premium + 15 Stufen (Anker für die 499er-Version) |
| Ruhmespfad +10 Stufen | 199 | Stufen überspringen |

## Abo „Arena-Gönner“ (≈ 4,99 € / Monat)

Täglich 150 Münzen (Login nötig, holt Spieler täglich zurück), monatlich 1 exklusiver Skin, Abo-Rahmen,
+1 Tagesaufgaben-Neuwurf, Titel „Gönner der Arenen“. Status bei jedem Login über die Subscription-API neu lesen.

## Münzen: Zufluss und Abfluss (Schätzung, wird in Phase 4 mit echten Daten ersetzt)

Münzen pro Kampf = XP / 4 × Siegesserie × Note × Event (wie Godot `end_match`). Ein typischer Kampf gibt 75–215 XP,
also im Schnitt **≈ 40 Münzen**.

| Quelle pro Tag | Gratis-Spieler (30 min, 6 Kämpfe) | Zahler (Doppelte Münzen + VIP) |
|---|---|---|
| Kämpfe | 240 | 500 |
| Login-Kalender (Ø) | 145 | 145 |
| Tages-Herausforderung (Ø Serie) | 250 | 250 |
| Wochenaufgaben (umgelegt) | 130 | 130 |
| Ruhmespfad gratis (umgelegt) | 60 | 60 |
| Abo | – | (+150 falls Gönner) |
| **Summe** | **≈ 825** | **≈ 1 085–1 235** |

| Senke | Münzen gesamt |
|---|---|
| 48 Kämpfer (16 × 600, 16 × 900, 16 × 1200) | 43 200 |
| 22 Arenen | 11 850 |
| 12 Shop-Skins | 9 350 |
| 8 Shop-Waffen | 5 500 |
| **Alles** | **69 900** |

Ein Gratis-Spieler kauft alles in ≈ 85 Tagen, ein Zahler in ≈ 60. Dazu kommt „jeder 3. Sieg schaltet einen Kämpfer frei“.
Das ist großzügig und gut für die Retention, aber es senkt den Verkauf von „Kämpfer sofort“.
**Stellschraube:** Wenn D7 gut ist, aber kaum Kämpfer verkauft werden, auf „jeder 5. Sieg“ gehen.

## Weitere Einnahmen

- **Creator Rewards** (ersetzt seit 24.07.2025 die Premium Payouts): Roblox zahlt für aktive, ausgebende und neu
  gewonnene Spieler. Premium-Mitglieder bekommen +10 % XP, damit sie bleiben.
- **Rewarded Video Ads**, falls die Experience berechtigt ist: freiwillig, +50 % Münzen nach dem Kampf, nie im Kampf.
- **Rotations-Shop:** täglich 4 Skins/Emotes, wöchentlich ein hervorgehobenes Set. Knappheit durch echte Rotation, ohne Zufall.
- **Gruppen-Bonus** (300 Münzen) und **Freunde einladen** (Belohnung, wenn der Freund ein Match beendet).
- **Später: UGC-Avatar-Items** der Kämpfer-Ausrüstung im Roblox-Marktplatz. Spieler tragen sie in anderen Spielen =
  Werbung. Braucht UGC-Berechtigung; erst nach dem Launch prüfen.
- **Später prüfen: Geschenke** (Skin für einen Freund im selben Server kaufen). Vor dem Bau die aktuellen Roblox-Regeln lesen.

## Schärfungen gegenüber dem Bau-Prompt

| Änderung | Grund |
|---|---|
| Ruhmespfad Premium+ (899) neu | Preisanker: macht 499 attraktiv und hebt den Umsatz pro Käufer |
| Finisher-Kino Plus mit Replay-Clip | Kosmetik, die genau den teilbaren Moment verstärkt (siehe `GROWTH.md`) |
| Prompt-Labor Plus mit Aura-Stilen | Das Alleinstellungsmerkmal bekommt eigene Kosmetik |
| Kämpfer sofort mit drei festen Preisen | klarer als „149–299“, per Test für jede Münz-Stufe vorhanden |
| Rettung zählt nicht für die Bestenliste | sonst Pay-to-Win in der Rangliste |
| Boni addieren, Stimmen gedeckelt | Wirtschaft und Arenawahl bleiben fair |
| Premium Payouts → Creator Rewards | Programm wurde von Roblox ersetzt |
