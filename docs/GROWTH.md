# Growth: Prompt Fighters viral machen

Roblox empfiehlt Spiele nach **Engagement** (Retention, Spielzeit, Wiederkehr, Käufe). Werbung und Videos bringen
Spieler herein, aber nur die ersten Minuten entscheiden, ob der Algorithmus sie weiterschickt. Darum steht hier
zuerst das Spiel selbst, dann die Kanäle.

## 1. Positionierung in einem Satz

**„Tippe irgendeinen Kämpfer. Prügel dich damit gegen deine Freunde.“** (EN: *Type ANY fighter. Fight your friends.*)

Der Prompt ist der Hook, den man in 3 Sekunden versteht, und er erzeugt bei jedem Spieler einen anderen Moment.
Kein anderes Roblox-Kampfspiel hat das. Alles im Marketing zeigt zuerst den Prompt, dann den Kampf.

Titel-Vorschlag: `Prompt Fighters ⚔️ Type ANY Fighter`. Beschreibung DE/EN, erste Zeile = derselbe Satz.

## 2. Die ersten 60 Sekunden (Pflicht für Phase 7)

| Sekunde | Was passiert | Warum |
|---|---|---|
| 0–5 | Kein Menü. Spawn direkt vor dem **Prompt-Terminal** in der Lobby: „Beschreibe deinen Kämpfer“. Darunter 3 Vorschlag-Chips („Lavagolem mit Hammer“, „Eisninja“, „Sternendrache“), damit Handy-Spieler nicht tippen müssen. | Der Hook kommt sofort, ohne Lesen. |
| 5–12 | **Kämpfer-Enthüllung:** Lichtsäule, Kamera dreht, Name und Signatur blenden ein. Text vorher immer durch `TextService` gefiltert. | Erster Wow-Moment, erster Clip. |
| 12–20 | Automatisch in ein Match 1 gegen 3 Bots (Stufe 1–2). Eingabehinweise im Spiel statt Tutorial-Bildschirm. | Erstes Match unter 20 s (Spec-Ziel: unter 60 s). |
| 20–50 | Bots sind so eingestellt, dass der Spieler schnell über 100 % schlägt. **Erster Finisher ist garantiert verfügbar**, der Code blinkt groß auf dem Bildschirm. | Der stärkste Moment des Spiels passiert in der ersten Minute. |
| 50–60 | Ergebnis: Note (fast immer A/S), XP-Balken, „Nochmal“ riesig, daneben „Neuer Prompt“. Kein Shop-Popup. | Zweites Match starten ist der wichtigste Funnel-Schritt. |

Messen mit `AnalyticsService:LogFunnelStepEvent`: Join → Prompt erstellt → Match gestartet → erster KO → Finisher → zweites Match.

## 3. Clip-Momente, die das Spiel selbst erzeugt

Jeder dieser Momente bekommt Zeitlupe, Kamera-Show und einen „Clip speichern“-Knopf über die
[Captures-API](https://create.roblox.com/docs/en-us/reference/engine/classes/CaptureService) (Screenshots und Videos, die Spieler speichern und teilen können).

1. **Prompt-Enthüllung:** „Ich habe *X* getippt und DAS bekommen.“ Bestes TikTok-Format überhaupt.
2. **Finisher-Kino:** stilisiert (Licht, Eis, Siegel), kein Blut. Finisher-Kino Plus verkauft genau diesen Moment.
3. **999 %-Abschuss:** Kämpfer fliegt mit Sternblitz aus dem Bild. Großer roter Prozentwert.
4. **„HERAUSFORDERER!“**-Einblendung und **Sudden Death** bei 150 %.
5. **Boss-Phase 2:** Marmorstatue zerbricht, Höllenfürst steht auf.
6. **Prompt gegen Prompt:** zwei absurde Prompts gegeneinander („Toaster-Ritter“ gegen „Wolkenbär“).

Für Creator: ein **Creator-Modus** auf Privatservern (HUD aus, freie Kamera, Zeitlupe). YouTuber brauchen saubere Bilder.

## 4. Teilen- und Einlade-Schleifen

| Schleife | Wie | Belohnung |
|---|---|---|
| **Prompt-Code** | Jeder Prompt-Kämpfer bekommt einen kurzen Code (aus dem Seed, `Util/Seed.luau`). Freunde geben den Code ein und spielen genau deinen Kämpfer, mit deinem Namen auf der Karte. Code statt Text, damit nichts Ungefiltertes geteilt wird. | Ersteller sieht „47 Spieler haben deinen Kämpfer gespielt“ (Status) |
| Freunde einladen | `SocialService:PromptGameInvite`, Party folgt in denselben Server und dasselbe Match | Münzen, sobald der Freund ein Match beendet |
| 2v2 mit Freund | Team-Modus im Schnellkampf | +20 % XP mit Freund im Team |
| Tages-Herausforderung | Für alle gleich (Seed aus Datum), Bestenliste des Tages | Vergleich mit Freunden |
| Roblox-Gruppe | Beitritt per `GroupService` geprüft | 300 Münzen einmalig |
| [Experience Notifications](https://create.roblox.com/docs/production/promotion/experience-notifications) | Nur mit Zustimmung: neue Saison, neuer Kämpfer, Serie läuft ab | holt Spieler zurück |
| Codes | Auf X, Discord und in der Gruppe; Like-Ziele nur als Gemeinschafts-Code („bei 10 000 Likes neuer Code“), nie Belohnung pro Like | Münzen, nie Robux-Werte |

## 5. Icon und Thumbnails (3 Varianten für den A/B-Test)

| Variante | Bild | Text |
|---|---|---|
| A „Prompt“ | Eingabefeld mit „lava golem with a hammer|“, Pfeil, riesiger Lavagolem schlägt in die Kamera | TYPE ANY FIGHTER |
| B „999 %“ | Kämpfer fliegt diagonal aus der Arena, Funkenschweif, riesige rote **999%** | – |
| C „Boss-Raid“ | vier kleine Kämpfer vor einer 20 m hohen Engelsstatue mit glühenden Augen | 4 vs BOSS |

Icon: ein Kämpferkopf mit leuchtenden Augen, daneben ein blinkender Text-Cursor „|“. Starker Kontrast,
höchstens ein Wort. Klickrate im Creator Hub testen; Ziel ≥ 5 % (Roadmap-KPI).

## 6. Inhalts-Takt: 58 Kämpfer sind ein Jahr Updates

**Wichtigste Schärfung:** Nicht mit allen 58 Kämpfern starten. Launch mit **16** (10 Starter + 6 freischaltbar),
danach **jede Woche ein neuer Kämpfer** als „Neuer Herausforderer“-Event. Die Daten sind schon fertig importiert,
jeder Drop ist billig und trotzdem ein Rückkehrgrund und ein Video.

| Takt | Inhalt |
|---|---|
| wöchentlich (Freitag, vor dem Wochenend-Peak) | neuer Kämpfer oder neue Arena, Wochen-Event wechselt automatisch |
| alle 2 Wochen | Balance-Patch mit kurzer Patch-Note im Spiel |
| alle 8 Wochen | neue Saison im Ruhmespfad mit Thema („Himmelssturm“, „Höllenschmiede“) und neuem Boss |
| Feiertage | Halloween-Mutator, Winter-Arena, Jahrestag |

## 7. Bezahlte Reichweite (Roblox Ads Manager)

Erst wenn **D1 ≥ 20 %** (Roadmap): Sponsored Experience mit ≈ 50 € testen, alle drei Thumbnails gegeneinander.
Messen: Kosten pro Spieler gegen Umsatz pro Spieler über 30 Tage. Nur skalieren, wenn der Umsatz höher ist.

## 8. Video-Plan (TikTok, YouTube Shorts, Reels)

Ab dem ersten spielbaren Build 1–2 Kurzvideos pro Tag, Hook in der ersten Sekunde.
Formate: „Ich habe *X* getippt“, „Kommentiere einen Prompt, ich spiele ihn“ (Kommentare liefern die nächsten Videos),
„999 %-Challenge“, „Boss in unter 60 s“, Devlog („Tag 12: mein Smash-Spiel auf Roblox“).

## 9. Kennzahlen und Abbruchkriterien

| KPI | Ziel | Wenn verfehlt |
|---|---|---|
| Join → erstes Match | < 20 s, ≥ 90 % | Onboarding kürzen |
| Erstes → zweites Match | ≥ 60 % | erstes Match leichter, Finisher früher |
| D1 / D7 | ≥ 25 % / ≥ 8 % | keine Werbung schalten, erst Retention reparieren |
| Thumbnail-Klickrate | ≥ 5 % | neue Thumbnails testen |

## 10. Regeln, die Reichweite schützen

Inhalts-Rating „Mild“ (kein Blut, keine Zerstückelung), damit das Spiel für alle Altersgruppen sichtbar bleibt.
Keine Links aus dem Spiel heraus außer den offiziellen Social Links. Keine Fake-Gewinnspiele. Keine Marken- oder
Anime-Kopien (siehe `ASSET_LICENSES.md`): ein Copyright-Takedown löscht jede Reichweite auf einen Schlag.
