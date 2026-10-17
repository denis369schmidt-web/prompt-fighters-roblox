# Assets, Lizenzen und Marken-Check

## Fremde Dateien

Noch keine. Jede Datei, die nicht selbst erstellt ist (Modell, Animation, Sound, Schrift), kommt hier mit Quelle und Lizenz hinein.
Godot-Modelle (Mixamo, Tripo-Exporte) werden **nicht** übernommen; der Importer lässt alle Asset-Pfade weg.

| Datei | Quelle | Lizenz | Hinzugefügt |
|---|---|---|---|

## Marken-Check der Kämpfer (vor Launch erledigen)

Das Godot-Projekt enthält eine Umbenennungs-Tabelle (`progression.gd`, `RENAMED_IDS`), die zeigt, dass viele Kämpfer
von bekannten Anime-, Spiele- und Kartenspiel-Figuren abgeleitet sind. Namen allein reichen nicht: **Silhouette, Farben,
Frisur, Kleidung, Technik- und Finisher-Namen** müssen so eigenständig sein, dass niemand die Vorlage erkennt.
In `Data/Roster.luau` tragen diese Kämpfer ein Feld `ipReview` mit dem konkreten Punkt.

| Kämpfer | Was zu ändern ist |
|---|---|
| HIKARU | Finisher „Dreizehnte Form“ und Sonnenatem-Motiv umbenennen und neu gestalten |
| TOBI, BRUNO, KAIRO, VARAKH, XYLAR, JUBEI, REN, AMETHYA | Look und Technik-Namen weg von den bekannten Vorlagen |
| GLACIEM, ORYN, ZIP, RAIGA, ALBION, PYRAX | Optik (Farben, Körperform, Muster) eigenständig |

Empfehlung: Für den Launch (16 Kämpfer, siehe `GROWTH.md`) zuerst Kämpfer ohne `ipReview` nehmen und die übrigen
erst nach dem Redesign als wöchentliche Drops veröffentlichen.
