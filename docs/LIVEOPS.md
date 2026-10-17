# Live-Ops

## Kennzahlen (wöchentlich ansehen)

D1 / D7 / D30-Retention, Ø Sitzungsdauer, Anteil zahlender Spieler, Umsatz pro täglichem Spieler (ARPDAU),
Funnel Join → Prompt → erstes Match → zweites Match → Tagesaufgabe, Münz-Zufluss und -Abfluss pro Tag.
Richtwerte und Abbruchkriterien: `docs/GROWTH.md` Abschnitt 9 und `roblox/roadmap.md` (KPI-Übersicht).

## Kalender

| Rhythmus | Aufgabe |
|---|---|
| wöchentlich, Freitag | neuer Kämpfer oder Arena live, Wochen-Event wechselt (`DOPPEL-XP-WOCHE`, `GOLDRAUSCH`, `MUTATOREN-FESTIVAL`, `WOCHE DER HERAUSFORDERER`, `LEGENDEN-WOCHE`) |
| täglich, automatisch | Tages-Herausforderung (Seed aus Datum), Rotations-Shop (4 Angebote) |
| alle 8 Wochen | Saisonwechsel Ruhmespfad und Ranked |

## Vor jedem Update

Tests grün, Changelog-Eintrag, Preise nur über `Products.luau`, kein Datenschema-Bruch ohne Migration.
