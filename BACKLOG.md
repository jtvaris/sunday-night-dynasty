# Dynasty - Backlog (Completed)

## 2026-07-08 — Kierros 2: runkosarja pelattavaksi (game sim korjattu)

- [x] GameSimulatorin regulation-looppi ei voinut KOSKAAN päättyä (Q4:n aikaloppu ei kasvattanut quarteria eikä exit-ehto voinut laueta → ikuinen silmukka nollapituisilla draiveilla). Yksi ottelu ei ollut ikinä simuloitunut loppuun. Korjattu: break kun Q4:n aika loppuu.
- [x] SimPlayer-snapshot-refaktorointi: pelaajien attribuutit luetaan SwiftData-malleista kerran per ottelu plain structeihin; GameSimulator/DriveSimulator/PlaySimulator ajavat snapshoteilla (SwiftData-getterit dynamic casteineen olivat hot loopissa). Fatigue kirjataan takaisin simin jälkeen. Korjasi samalla piilobugin: "väliaikaiset" moraalimodifikaattorit rappeuttivat pysyvästi live-malleja.
- [x] Verifioitu simulaattorissa: viikon advance ~2 s (ennen: ikuinen jumi 100 % CPU), viikon 1 ottelu voitettu, post-game-pressitilaisuus toimii (tone-tagit, running impact, Promises Tracked), viikko 2 dashboard 1-0, omistaja 66→81 %.
- Diagnosointi: `sample`-CPU-profiili simulaattoriprosessista → täsmällinen file:line kahdesti (ensin SwiftData-getterit, sitten looppiraja).

## 2026-07-08 — Kierros 1: pelattavuuden P0-korjaukset (soft-lock poistettu)

- [x] OTAs required task -järjestelmä korjattu: "Set depth chart" ja "Set training focus" valmistuvat nyt oikeasta pelitilasta (refreshTaskCompletionStatus-caset); "Enter the Draft" valmistuu kun rosterissa on tämän kauden varaus. Eteneminen OTAs → Training Camp → Preseason → Roster Cuts → Regular Season Week 1 varmistettu simulaattorissa ilman debug-työkaluja.
- [x] Depth chart persistoituu: DepthChart tallennetaan Career.depthChartData:an jokaisen muutoksen jälkeen (aiemmin puhdas @State, generoitiin uudelleen joka avauksella). Auto-Set-nappi tekee nyt näkyvän asian (lataa tallennetun + generoi + tallentaa).
- [x] Training Plan lataa tallennetun suunnitelman avattaessa ja päivittää olemassa olevan rivin (upsert) — 60/20/20 ei enää palaudu 34/33/33:ksi eikä synny duplikaattirivejä.
- [x] Tallennus: eksplisiittinen save WeekAdvancer.advanceWeek:n jälkeen + scenePhase background/inactive -save DynastyApp:iin — force-quit ei enää kadota vaihetta/muokkauksia.
- [x] Debug-skip korjattu: pysähtyy .regularSeason/.freeAgency-kohtaan (ei enää koko kauden main-thread-simulaatiota → ei jäätynyttä "Skipping…"-tilaa), tallentaa joka askeleen, dynaaminen label.
- [x] Draft-varaukseen vahvistusdialogi (kaikki 3 pintaa) + position-chippien deterministinen järjestys — väärät varaukset (3/6 kierroksella 1) eivät enää mahdollisia.
- [x] KR/PR-kandidaattilistat lajittelevat nopeudella/ketteryydellä (ei enää QB1:tä palauttajaksi); sama pelaaja ei voi enää olla kahdessa positioslotissa (KR/PR-tuplarooli sallittu).
- [x] "Week 0 Focus" → vaiheen nimi offseasonissa (SeasonPhase.displayName lisätty); inj%-label käyttää WorkloadEngine.injuryRiskPct-kaavaa (durability + workload).
- Työkalut: 6-agentin map-workflow → juurisyyt file:line-tarkkuudella; ~223 screenshotia /tmp/snd-screenshots/; TODO.md:ssä täysi kierros 1 -analyysi (designer/himopelaaja/casual + FM-treeniauditointi).

## 2026-03-23

- [x] Palkkajärjestelmä: cap-suhteelliset palkkavaatimukset, realistiset sopimusrakenteet, vuosikohtainen cap hit -erittely
- [x] Draft realism: fyysiset statsit skaalattu (Rd1: 82-96), positional draft value, draft class strength, combine-ajat korreloivat SPD:n kanssa, position drill A-F skaala, top performers 1-2 per positio
- [x] Scouting UI: FIT/NEED/RISK selkeämmät, scouting report dots, starter-vertailu, position needs, draft picks näkyvissä, Big Board sort+notes, Interviews priority+capacity+bust risk
- [x] Sopimukset: extend contract +vuodet, vuosierittely, chat ei häviä, vanhenevat max sopimuspituudet, eläköityminen Key Decisionsissa, natural position palkanlaskennassa
- [x] Dashboard: satisfaction scoret (Owner/Morale/Media/Legacy), hasExpiringContracts, hasScoutsAssigned, playoffRoundName
- [x] Coaching: position coach statsit realistiset (1-5 hyvää, loput 40-60), coach hireSeasonYear + contractYears, seasonsOnTeam lasketaan
- [x] Free Agency UI: starter-vertailu, scheme fit, team needs, 6 sortausvaihtoehtoa, cap impact, OVR trend, draft-vertailu, multi-signing planner, competition intensity, guaranteed-arviot
- [x] Interview Report: personality-badget värikoodattu, Football IQ grade, interview grade A-F, bust risk before/after, shortlist+red flag togglet, 36 personality-kuvausta, combine inline, scout recommendation
- [x] FA Complete: cap breakdown, before/after, FA Grade, signing details+steal/overpay, players lost, league signings, remaining needs, comp picks, media reaction
- [x] Pro Days: scout-kortit (specialty, accuracy, assignments), expandable koulut, priority indicators, recommended schools, scout-koulu matching, "Send All Recommended", capacity counter
- [x] FA Bidding War: AI need-based bidding, player auction/shopping around, instant signing overpay, day-by-day updates, motivation affects decisions, bidding war escalation
- [x] Mock Draft: positional value fix (P/K/FB ei top 10), position diversity, letter grades, own pick highlight, team needs, media comments, rounds 1-3, trade scenarios, BPA vs Need strategy, target availability
- [x] Scouting flow: scout modal (specialty, prospects, recommendations), pro day capacity 3-4, dashboard task completion, personal workouts, interview filtering+select all, Football IQ generation fix (Rd1: 70-95)
- [x] Big Board overhaul: composite score (OVR × positional value), 7 tieriä, FIT/NEED korjattu, haku, suodatus, auto-rank, value pick indicator, context menu reorder, available at pick probability
- [x] Combine Risers/Fallers layout korjattu (uusi arvo ylös, vanha alas)
- [x] Data consistency audit: kaikki scouting-näkymät käyttävät nyt yhtenäistä grade/color/projection-logiikkaa
- [x] Custom grade/star: oma arvosana (Top 5 → UDFA) + tähti kaikissa prospect-listoissa (context menu + badge + filtering)
- [x] Draft Order -näkymä: 7 kierrosta, omat pickit korostettu, traded picks, pick value indicators, team records

## 2026-03-22

- [x] Big Board: NEED-sarake, RISK-arviointi, manual tier, navigointi, position picker
- [x] ProspectDetailView: compact redesign, Quick Assessment Row, athletic profile, stock trajectory
- [x] Salary cap $255M -> $265M (2026), starter-palkkojen kalibrointi
- [x] Scouting: fokusattribuutit, fokuspositiobonus +15%

## 2026-07-08 — Coach Mode (live 3D -pelinjohto)

- [x] LiveGameEngine: play-by-play -moottori olemassa olevan simun päälle (down/distance/kello/possession, AI-vihjeet, simToEnd, täysi persistointipariteetti WeekAdvancerin kanssa)
- [x] PlaySimulator: OffensivePlayCall + DefensivePackage -modifikaattorit (nil = vanha käytös), findQB/findRB paras-overall
- [x] 3D-kenttä: maalitolpat, broadcast-kamera-ajo, PlayStep-aikajana, pallon carry/arc/slide, joukkueväriset maalialueet
- [x] PlayChoreographer: skriptit kaikille lopputulemille (juoksu/syöttö/sacki/INT/fumble/TD/puntti/FG/safety/kneel/spike)
- [x] Humanoidipelaajat (jalat, torso, hartiat, kädet, pää, kypärä) + juoksuanimaatio (kääntyminen, lean, bob) — käyttäjäpalaute
- [x] All-22-koreografia: OL/DL-kontakti, WR-reitit, DB-peitto, LB-pudotukset, takaa-ajo, punttikattaus, TD-juhlinta — käyttäjäpalaute
- [x] CoachedGameView: play-kutsupaneeli (kategoriat, AI-ehdotus, SNAP), puolustusasennot live vastustajan drivella, 4th down -paneeli, Skip Drive, Sim to End → FINAL → GameSummary
- [x] Dashboard: "Coach the Game" -nappi, hero näyttää pelatun viikon tuloksen (W/L xx–yy) oikealla viikko+vastustaja-parilla
- [ ] Balanssiauditointi: boostien stackkaus simToEndissä (yksi 60-21/833yds -outlier)
- [ ] 3D-viilaus: pallon spiraali potkuissa, TD-kamera-ajo, laitetehoprofilointi

## 2026-07-09 — Coach Mode R4 (matchupit, pelikirjat, X&O, NFL-ilme)

- [x] MatchupResolver: nimetyt kaksinkamppailut joka snapista (edge vs tackle, WR-separaatio vs CB, POA-juoksublokit, INT-luku) — rating-painotettu eli tähdet voittavat useammin; tulokset ohjaavat 3D-visuaalia (taskun romahdus, separaatio, aukon koko)
- [x] Scheme-tuttuus näkyviin: alle 45% familiarity → busted assignment -callout ("cuts the route short — still learning the playbook")
- [x] FieldUnit: oikeat avauskokoonpanot kentälle roolijärjestyksessä + stabiilit pelinumerot positioalueittain
- [x] Matchup-callout-kapselit kentän päälle (voitto/häviö/bust/tähti) + voittajan pulssi hahmossa
- [x] Pelikirjapohjainen pelivalinta: OC:n scheme + familiarity-% otsikossa, asentamattomat pelit himmennetty, AI ehdottaa vain pelikirjasta; puolustuspresetit scheman mukaan
- [x] X&O-pelikuviot: reittipiirrokset valitulle pelille + puolustuskuvio (zonet/man/blitz-nuolet) stance-paneeliin
- [x] NFL-univormut: koti värissä + valkoiset housut, vieras valkoisessa + värilliset housut/kypärä; kypärät + maskit + ihonsävyt
- [x] Bye-viikon herokortti ("Week 4 · Bye Week — next up vs CHI in Week 6")
- [ ] Aikataulugeneraattori: GB:llä 2 byetä peräkkäin (viikot 4-5) — varmista 1 bye/joukkue
- [ ] Sim-target rajaus kentällä oleviin vastaanottajiin (pallo animoituu nyt lähimmälle roolille, feed nimeää oikean)

## 2026-07-09 — Coach Mode R5 (sulavuus, Madden 98, formaatiot, call sheetit)

- [x] Töksähtely pois: play-liikkeet lineaarisia askelten yli (ease vain formaatiosiirtymissä)
- [x] Madden 98 -ilme: kamera kauempaa/ylempää (~45yd näkyvissä), 1.18× hahmot, leikkuuraidat, proseduraaliset katsomot yleisötekstuurilla
- [x] Callit ohjaavat formaatioita molemmin puolin (I-form/gun/spread; nickel/dime/goal line/press/blitz-creep) + live-esikatselu selatessa
- [x] Puolustuksen call sheet: 10 nimettyä peliä kortteina (kaavio+kuvaus+scheme-tagit); AI-puolustus pelaa myös oikeita paketteja
- [x] Hyökkäyksen clipboard-kortit kuvauksineen; 6 uutta peliä (Counter, Toss, Hitch, TE Seam, Deep Cross, Flood) → 5-6 peliä/osio
- [x] Kantajan nimeäminen: kentän RB = feedin RB (FieldUnit peilaa findRB:tä)

## 2026-07-09 — Coach Mode R6 (Madden 98 -grafiikka)

- [x] Juoksusykli: lonkka/olka-niveletyt raajat heiluvat vastakkaisvaiheessa liikkeen ajan
- [x] Linjamiesten kyykkyasennot snapissa (OL+DL)
- [x] Matala Madden-kamera takaa (FOV 52), koko kenttä näkyvissä, pelaajat isoina etualalla
- [x] Proseduraalinen spekkeliturf + tummemmat sävyt + etäisyyssumu
- [x] Kenttäkoristeet: maalialuetekstit, keskilogo, keltainen FD-viiva + sininen LOS, pylonit
- [x] Pallo: isompi, raidat, spiraali/tumble-pyöritys
- [x] Varjoläiskät pelaajien alle; kenttä laajenee 68 %:iin pelin ajaksi
- [x] Katsomot poistettu (käyttäjän toive)
- [ ] R7: taklauskaatumiset, pallonkanto-asento, polvet/kyynärpäät, seurantakamera pitkillä juoksuilla

## 2026-07-09 — Coach Mode R7–R10

- [x] R7: taklauskaatumiset (kantaja+taklaaja maahan, sacki hautaa QB:n), pallo kainalossa kantoasennossa, seurantakamera pitkillä pelivedoilla (varmennettu 45 jaardin karkumatkalla)
- [x] R8: kaksisegmenttiset raajat — polvet ja kyynärpäät taipuvat juoksusyklissä
- [x] R9: kiinniottokurotus (kädet ylös pallon saapuessa), sivuraja-aidat valkoisin reunoin, callout-sijoittelu
- [x] R10: retro "2ND & 10" -broadcast-kyltti snapissa + TD-konfetti ja kamera-ajo maalialueelle
- [ ] R11-ehdokkaat: gang-tackle-kasat, QB:n heittoliike, FG-kamera tolppien takaa, pelin nimi kylttiin

## Iso kuva: R21–R40 (kirjattu 2026-07-09, yksityiskohdat muistissa project_roadmap_r11_r40)

- Kaari 1 Offseason: R21 kaupat, R22 sopimusneuvottelut 2.0, R23 FA-syvennys, R24 draft-huone 2.0
- Kaari 2 Pelaajat: R25 persoonat/pukuhuone, R26 kehitys 2.0 (training-velat), R27 scouting-organisaatio, R28 vammat/lääkintä
- Kaari 3 Liiga: R29 uutiskierre, R30 coaching carousel + tree, R31 omistaja/talous (SeasonGoals), R32 monikausisilmukka (HOF/LegacyTracker)
- Kaari 4 Coach-mode 2.0 & tuote: R33 vastustaja-AI, R34 audio, R35 replayt, R36 taktinen syvyys, R37 onboarding, R38 saavutettavuus/lokalisointi, R39 suorituskyky, R40 pelimuodot

## 2026-07-09..11 — R11-R40 + coach-mode 3.0 (koko roadmap) — VALMIS & LOPPUVERIFIOITU

Koko kehitysroadmap R11-R40 + coach-mode 3.0 -putki toteutettu ja loppuverifioitu simulaattorissa (iPad Pro 13" M5, iOS 26.4, BUILD SUCCEEDED). Committoidut kierrokset (git-hashit) + tämän istunnon committoimaton viimeistelyputki (R37-R39 + pelaaja-IQ/selostus):

- **Liigakierrokset R11-R23** (`b9758ca`, `dd56cc2`): sim-eheys & luottamus (R12), sää + tunnelma (R15), live-vammat & rotaatio (R16), puoliaika-analyysi (R17), kehitys/narratiivi coached-peleistä (R18), kausi-integraatio & panokset (R19), persona-auditti (R20), kaupat + AI-tarjoukset (R21), sopimusneuvottelut 2.0 + franchise tag (R22), FA-syvennys: tampering, vierailut, comp pickit (R23).
- **Offseason-syvennys R24-R25** (`8ee6334`): draft-huone 2.0 (trade up/down, war room, AI-draft, UDFA), pukuhuone & kemiat; vieraskamerakorjaus + Blender-asset-pipeline.
- **Pelaajat & liiga R26-R29** (`9c77bf2`): kehitys 2.0 (treenifokus, viikkoraportit, mentorointi, breakoutit), scouting-organisaatio (budjetti, kohdennukset), vammat/lääkintä 2.0 (historia, kuntoutus, head trainer), liigan narratiivimoottori (power rankings, MVP-kisa, storylinet).
- **Liigan pitkä kaari R30-R32** (`d745805`, `9ea5681`): coaching carousel + oma coaching tree, omistaja & talous 2.0 (SeasonGoals), monikausisilmukka (HOF/LegacyTracker) — 10 kautta tervettä; OVR-drift kalibroitu (+0,99/5 kautta).
- **Coach-mode 3.0 fidelity** (`8233b75`, `84e84cc`, `246ec4d`, `04a5b52`, `c297c43`, `78c7dd6`): 3D-pelaajamallit + kit v2 (positiokohtaiset body typet, varusteet), Madden 2000 -tarkkuus + HUD-luettavuus + Coach's Board, call-sheet 2.0 + kaksipisteinen, play-calling 3.0 (reittiaito koreografia, adaptiivinen AI, päätöskello 10 s), mitattu coach-kamera + animaatiosanasto, liikeyksilöllisyys & reaaliaikatahti (videoprofiloitu 60 fps).
- **R33+R40 + R34-R36** (`b7ada9f`, `dc149a4`): koordinaattoripersoonat + pelimuodot (fantasy draft, skenaariot, custom-liiga), proseduraalinen audio (SFX + yleisö), replayt & highlightit (moni­kamerakulma sideline/end zone/iso, post-game highlight reel), taktinen syvyys (audiblet, QB:n coverage-luku, pelikirjan kasvatus).
- **Viimeistelyputki (committoimatta tässä istunnossa):** pelaaja-IQ (awareness-päätökset koko kentälle) + puolustusselostus (torjujat/taklaajat/isot iskut nimetään feed-riveille), R37 onboarding (first-run-vihjeet: hallintanäkymän esittely, ensimmäisen snapin opastus, pelinaikaiset vihjepalkit + How to Play + Reset Tips), R38 saavutettavuus & lokalisointi (String Catalog en+fi, VoiceOver, Reduce Motion, WCAG-kontrastiaudit), R39 suorituskyky (advance-viikko −74 %, FA-simu −98 %/monikausi −73 %, PerfLog-mittari) + iPad mini -laitekattavuus.
- **Loppuverifiointi (2026-07-13):** coached-peli GB/BUF-tyylisesti todennettu — 3D-kenttä + play-calling + audible + Manage/Coach's Board + replay (post-game highlight reel monikulmalla), liikeprofiili 186 s videosta max frame-gap 0,20 s (ei >0,5 s jäätymiä); advance-viikko (Wk3→4→5) tuottaa dev-raportin + uutiset + power rankings + press conference -otsikot; fi-kieli lukee (valikko + dashboard + asetukset); onboarding-coach-mark näkyy resetin jälkeen.
- **Balanssi loppuverifioitu:** `debugSimulate(50)` 5 kfg-varianttia — pisteet/joukkue 23,8-26,2 (haarukka 18-28), rangaistukset/peli 9,1-10,0 (~9,5), ei poikkeamia, schedule-integriteetti OK; `MultiSeasonSmokeTest` 3 kautta — 76 advancea, ei watchdogia, avgOVR-drift 70,63 → 71,48 (Δ+0,85, ei karkaamista).
