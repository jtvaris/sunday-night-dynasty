# Dynasty - TODO

## Round 29: Liigan narratiivi — uutiskierre, power rankings, storylinet (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] UUTISLOKI PYSYVÄKSI (`Career.newsLogData: Data?` + `newsLog: [NewsItem]`-bridge, cap 150 — optionaalinen kenttä → kevyt migraatio): WeekAdvancer.advanceWeek persistoi jokaisen advancen `lastNewsItems`-otsikot careerille (newest first) → NewsView.loadNews() lataa nyt oikean feedin (aiemmin palautti AINA tyhjän, uutisia ei näytetty koskaan). Kattaa myös offseason-/deadline-uutiset, koska hook on advanceWeekin lopussa kaikille poluille.
- [x] UUTISKIERRE (uusi `Engine/Media/LeagueNarrativeEngine.swift`, stateless): viikoittain max 6 storyline-otsikkoa perusfeedin päälle — voittoputket 3+ (max 2/vko, vain kun putki on KASVANUT viimeksi raportoidusta → ei toistoa viikosta toiseen; `reportedStreaks`-markerit), tappioputket (max 1/vko, sama anti-repeat), yllätystulokset (edellisviikon top-10 kaatuu 10+ sijaa alempana olevalle 7+ pisteellä), coach hot seat (AI-joukkue 4+ peliä alle .500 viikosta 6, yksi story/joukkue/kausi). Kaikissa 3 otsikko+body-varianttia jotka rotatoivat viikkoindeksillä (variaatiopoolit).
- [x] POWER RANKINGS: koko liigan 32 joukkueen viikkoranking — winPct×100 + viimeisen 3 viikon forma×4 + putkiproxy×1,5 (pistemarginaalia ei ole Team-mallissa; forma+putki kantavat recency-signaalin), stabiili tie-break lyhenteellä. Per joukkue liikesuunta (previousRank → ▲▼—) ja yhden lauseen template-blurbi (putki/nousija/putoaja/kärki/keskikasti/rebuild-poolit, variantti rotatoi viikolla). Viikoittainen rankings-uutinen (top-3 + isoin nousija + oma sijoitus); NewsGeneratorin vanha duplikaatti-rankingsuutinen poistettu (narratiivimoottori omistaa sen nyt).
- [x] STORYLINE-JATKUVUUS (`Career.leagueNarrativeData: Data?` + `LeagueNarrativeState`-bridge — optionaalinen → kevyt migraatio): edellisviikon ranking (liikesuuntiin), MVP-kisan kumulatiiviset pisteet (top-12 säilyy), raportoidut putket/hot seatit/divisioonaparit/kausikaari-checkpointit. MVP-kisa: heuristinen viikkokertymä (joukkueen winPct + tähtitaso OVR-82 + positiobias QB 3.0 / RB 1.8 / WR 1.4 + viikkovoitto + pieni varianssi — kausistatseja EI ole persistoitu liigatasolla, ks. rajaukset), top-3-uutinen 3 viikon välein viikosta 6. Divisioonataisto: viikosta 12 kaksi kärkijoukkuetta ≤1 voiton päässä → rivalry-kehysuutinen, yksi story/pari/kausi. Kausikaari: käyttäjän joukkueen odotukset (SeasonGoals.ownerExpectation → odotetut voitot 5–12) vs voittotahti checkpointeissa vko 6/12/16 (±2 voiton projektio → positive/negative, vko 12 myös on-track-neutraali).
- [x] UI (NewsView — olemassa olevaa feediä parannettu, ei rinnakkaista näkymää): Power Rankings -kortti (top-10 + oma joukkue kullalla korostettuna, alle top-10:n oma rivi "…"-erottimella; rank, ▲▼—-liike, lyhenne+nimi+record+blurbi) ja MVP Race -kortti (top-3, suhteellinen "case strength" -palkki, oman joukkueen kandidaatti kullalla) myöhäiskaudella (state.week ≥ 10) — kortit All- ja League-filttereissä. Uutisvirran ryhmittely: jokaisen päiväbucketin sisällä "YOUR TEAM" ensin, sitten "LEAGUE NEWS" (sub-labelit vain kun molempia on).
- [x] PRESSER-KYTKÖS (kevyt, R18-GameFacts-mekanismi): `GameFacts` laajennettu (powerRank, powerRankMovement, mvpCandidateName/Rank — oletusarvot → legacy-kutsujat kääntyvät muuttumatta). Kaksi uutta kysymysvarianttia: power ranking (top-5 tai ±5 sijan liike; kysymysteksti mukautuu nousu/pudotus/#1/top-5-tilanteeseen) ja MVP-kisa (oman joukkueen pelaaja top-3:ssa; leader-variantti). Ottavat satunnaisen kolmoskysymyksen slotin ~50 %:ssa kun ehdot täyttyvät — ei uusia pakollisia kysymyksiä.
- [x] PARITEETTI & AI: kaikki presentaatiota — GameSimulator/PlaySimulator/records koskemattomia; narratiivimoottori vain LUKEE tulokset (ajetaan WeekAdvancerissa tulossimulaation jälkeen, ennen presseriä jotta tuore ranking on lainattavissa). AI-joukkueisiin ei kohdistu mitään vaikutuksia (hot seat/rankings ovat uutistekstiä).
- [x] BUILD: xcodebuild BUILD SUCCEEDED (iPad-simulaattori 049C7295).

### Rajaukset
- [ ] Tilastojohtajien virstanpylväsuutiset (1000 yd / 30 TD) jätetty pois: liigatason kausistatseja ei persistoida (PlayerGameStats syntyy vain käyttäjän pelistä eikä talleteta; PlayerSeasonHistory.keyStatit ovat 0-TODO) — MVP-kisa ajetaan heuristiikalla samasta syystä. Kun kausistatsi-pipeline laskeutuu, LeagueNarrativeEngineen on valmis paikka (accumulateMVPRace + milestone-generaattori).
- [ ] Power rankings -pisteytyksessä ei pistemarginaalia (Team-mallissa vain W/L/T; StandingsCalculator vaatisi pelilistan joka viikko — forma-komponentti ajaa saman recency-asian kevyemmin).
- [ ] Playoff-viikot eivät generoi narratiivipäivitystä (rankings jäätyy vko 18:n tilaan; playoff-uutiset tulevat olemassa olevista poluista).
- [ ] Vanhat tallennukset: newsLog alkaa tyhjänä ja täyttyy ensimmäisestä advancesta; rankings-kortti ilmestyy ensimmäisen pelatun viikon jälkeen (previousRank nil → liike "—").

## Kit V2: laatikkomaisuus pois + positiokohtaiset body typet + varusteet (2026-07-09)

Käyttäjän palaute screenshotista: "todella vähän detaileja, pelaajat on laatikkomaisia". Juurisyy: flat shading + matalat segmenttimäärät Blender-kitissä. Lisäksi coach-kameran etäisyydelle tuotiin positiokohtaiset ruumiinrakenteet ja varustedetaljit.

### Shipped (BUILD SUCCEEDED ×2, verifioitu simulaattorissa screenshot-cropeista)
- [x] OSA 0 — SMOOTH SHADING + GEOMETRIA (`tools/asset-pipeline/player_kit.py`): kaarevat pinnat smooth (helmet/torso/raajat/pallo; facemask/cleat/laces jäävät flateiksi — kova geari lukee terävänä); segmentit ylös: raajat 8→12 (+3 välirinkiä, gaussin bulge kaartuu nyt pituussuunnassa), torso 12→16 (+cuts 4→6), kypärä 12×8→16×10, pallo 12×8→16×10; torson profiili smoothstep-interpoloitu (lantio→vyötärö→rinta→pad-flare ilman kulmia siluetissa), pad-shelfin kruunu pyöristetty, lantion alareuna tuckattu. Trit/figuuri ≈ 2 120 (budjetissa ~2500). Generoitu uudelleen + previewit KATSOTTU (figure_front/three_quarter: hahmo lukee pyöreänä, ei laatikkona) + `PlayerKit.usdc` kopioitu `dynasty/dynasty/Resources/`.
- [x] BODY TYPET (`FootballFieldScene.BodyType` heavy/medium/lean + `applyBodyType`): HEAVY OL/DL (torso ×1.25 lev / ×1.2 syv, raajat +15 % paksummat, −4 % pituus), MEDIUM QB/RB/TE/LB (baseline), LEAN WR/CB/S (torso ×0.88, raajat −10 %, +3 % pituus). Toteutus absoluuttisina figure/body/raaja-skaaloina (base × kerroin) → idempotentti restamppaus joka ryhmityksessä, koska samat 22 nodea vaihtavat hyökkäys/puolustus-roolia pallonmenetyksissä. Roolimappi `PlayChoreographer.bodyTypes(offenseIsHome:)` (sama slot-sopimus kuin stances); langoitettu movePlayersToFormation/positionPlayers-parametreina (CoachedGameView: avausryhmitys, pre-snap, syncFieldToSituation; kickoff-ryhmitykset jättävät buildit ennalleen). Toimii kit- JA fallback-figuurille (fallback muuten ennallaan speksin mukaan).
- [x] VARUSTEET (buildKitFigure): (a) kypärän kylkiin joukkuelyhenne-decalit (SCNPlane ±x, per-figuuri HELMETDECAL-materiaali, cached 256 px tekstuuri, tekstin sävy kypäräluminanssin mukaan; piilossa kun abbreviation tyhjä = legacy quick match — applyUniform togglaa); (b) facemask joukkueväriin ~40 %:lle joukkueista (deterministinen abbreviation-hash; MASK nyt per-figuuri-retint — aiempi jaettu prototyyppimateriaali olisi vuotanut cage-värin joukkueiden välillä); (c) hihat: vastavärinen olkavarsirengas (STRIPE, valkoinen värillisellä paidalla / accent valkoisella); (d) sukat: joukkuevärinen rengas nilkan yllä (SOCK, accent valkoisilla housuilla / valkoinen värillisillä); (e) kädet: skin-pallot forearm-päihin (jakavat figuurin SKIN-kopion).
- [x] LÄHIKUVATARKKUUS: numero- ja kypärädecal-tekstuurit 128→256 px (fontit ×2); kypärä kiiltävä (kit roughness 0.25), jersey matta (0.6) — ennallaan kitissä, todettu.
- [x] UNIFORMIT: `CoachedGameView.setUniforms` välittää nyt joukkuelyhenteet (`Uniform.home/away(teamColor:abbreviation:)`) → decalit + facemask-arvonta aktiivisia coach-pelissä.
- [x] VERIFIOITU ITSE (build + asennus + coached-peli + screenshotit + PIL-cropit, 2 iteraatiota): hahmot lukevat pyöreinä (ei laatikoita), OL/DL selvästi leveämmät kuin WR/DB (ATL DL vs GB WR vertailtu), "GB"-kypärädecal luettavissa WR:n kypärän kyljestä, hihanraidat molemmissa hihoissa, kultaiset sukkarenkaat valkoisten säärien päällä, kädet näkyvät, selkänumerot terävät, pallo prolaatti + nauhat. Iteraatio 1→2: raita siirretty pad-flaren alta keskiolkavarteen (y −0.09→−0.14, r 0.1) ja sukka isommaksi (r 0.068, h 0.13) — kumpikaan ei lukenut ekalla kierroksella.
- [x] PARITEETTI & EI-REGRESSIOT: kaikki presentaatiota (Blender-kit + scene-nodet + choreographer-roolimappi + view-parametrit) — engine/sim-poluissa nolla muutosta; RouteSpec-koreografia ja 10 s päätöskello koskemattomia; animaatiot ajavat rotaatioita/positioita, eivät skaaloja (pulse skaalaa containeria, ei figurea) → body-skaalat säilyvät.

### Rajaukset
- [ ] Proseduraalinen fallback-figuuri EI saa raitoja/sukkia/käsiä/kypärädecaleja (speksin mukaan ennallaan paitsi figure-tason body-skaalaus) — kit on ainoa tuotantopolku.
- [ ] Kickoff/erikoisryhmä-ryhmitykset pitävät edellisen snapin buildit (roolislotit eivät vastaa scrimmage-sopimusta) — seuraava scrimmage-pre-snap restamppaa oikeat.
- [ ] Kypärädecalit näkyvät vain sivu/viistokulmista (kyljissä, kuten oikeasti) — suoraan takaa/edestä ne ovat edge-on.
- [ ] MatchView (quick match legacy) ei välitä lyhenteitä → decalit piilossa ja kaikki buildit medium — tarkoituksella ennallaan.

## Round 28: Vammat & lääkintä 2.0 — historia, kuntoutus, head trainer, paluupäätökset (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] VAMMAHISTORIA (`Player.injuryHistoryData: Data?` + `[InjuryRecord]`-bridge, uusi `Domain/Models/Player/InjuryRecord.swift` — optionaalinen kenttä → kevyt migraatio): jokainen vamma tallentuu pysyvästi (tyyppi, kesto, kausi+viikko; live-pelin vammat season/week 0 = "unknown", koska LiveGameEngineen ei kosketa rinnakkaisajon aikana — applyInjuryn uudet season/week-parametrit ovat oletusarvollisia, joten liven kutsu kääntyy muuttumatta ja historia tallentuu silti). Toistuvuus: `MedicalEngine.injuryCheck` painottaa tyyppivalinnan aiemmin vammautuneisiin kehonosiin (+60 %/aiempi kerta, cap 2.5×) — kokonaisilmaantuvuus EI muutu, vain tyyppijakauma per pelaaja. Pysyvä durability-vaikutus vain uusiutumista (sama tyyppi 2. kertaa+): 25 % chance −1, vakavat toistot (severity 4+, ~6 %) −2 — maltillinen, liiga ei rapistu.
- [x] KUNTOUTUSVARIANSSI (`MedicalEngine.processWeeklyRehab(player:trainer:)`): viikkorulla ahead of schedule (−2 vkoa) / on track (−1) / setback (0, ~30 %:ssa +1 vko takaisin, ei koskaan yli alkuperäisen ennusteen). Ilman traineria painot 10/80/10 → odotusarvo ≈ 0.97–1.0 vko/vko eli quick sim -poissaoloaika ~ennallaan (pariteetti); head trainer siirtää painoja (ahead 10→20 %, setback 10→4 %). `Player.rehabStatusRaw` (optionaalinen → kevyt migraatio) näyttää tilan UI:ssa. Inbox-nosto isoista käänteistä (setback/ahead) kun OVR ≥ 78 tai vamma ≥ 4 vkoa. Legacy `processWeeklyRecovery` säilyy (ei muita kutsujia).
- [x] HEAD TRAINER -ROOLI (`CoachRole.headTrainer`, olemassa oleva Coach-staffirakenne kuten speksi salli): palkka $250K–1.1M, taito = playerDevelopment → rehab-painot, setback-riski ja rush-back-uusiutumiskerroin (×1.5 → ×1.1 huipputrainerilla). Palkkaus kuten muut medical-staffit (CoachingStaffView Medical-osio 2→3 slottia, vacant-kortti → kandidaattipooli → hire-sheet; displayName/abbreviation TRN/sortOrder/roleDescription/badgeColor/impact-kuvaukset lisätty). LeagueGenerator generoi trainerin kaikille joukkueille uusissa liigoissa; vanhoissa careereissa slotti on vapaana (ei trainer = neutraalit rehab-painot → ei etua/haittaa AI:lle).
- [x] PALUUPÄÄTÖS (Rush back vs Hold out): kun käyttäjän pelaaja saavuttaa viimeisen rehab-viikon, syntyy `ReturnDecision` (`Career.pendingReturnDecisionsData: Data?` — optionaalinen → kevyt migraatio) + actionRequired-inbox. Rush back = `MedicalEngine.rushBack`: pelaa heti, 2 viikon korotettu uusiutumisriski (×1.5 injuryCheckissä, trainer lieventää) + kuntohaitta (fatigue +15, palautuu ~1–2 vkossa normaalisti = "pieni tehohaitta" ilman GameSimulator-jakaumien muutosta). Hold out / ei valintaa = turvallinen normaali paraneminen (oletus). AI ei koskaan rushaa (päätöksiä generoidaan vain käyttäjälle). Päätökset siivotaan parantuneilta ja kauden vaihtuessa; UI:n confirmation-dialog varoittaa riskeistä.
- [x] INJURY REPORT -UI (uusi `UI/Roster/InjuryReportView.swift`, sheet RosterView'n toolbar-napista jossa badge = vammat+päätökset): paluupäätökset nappeineen, nykyiset vammat (tyyppi, rehab-status-chip ahead/on track/setback, paluuarvio x/y vkoa, kiertonuoli-ikoni + xN toistuville), "Elevated Risk" -osio rush-back-pelaajille, Medical Staff -footer (trainerin nimi+taso tai palkkauskehote). PlayerDetailView'n injuryHistorySection näyttää nyt oikean historian (6 viimeisintä, toistuvuus-flagit) + rehab-statuksen + rush-back-varoituksen — "No injury history" vain kun historia on aidosti tyhjä. Liigan tähtivammat (OVR ≥ 85) → NewsItem (.injury, negative) WeekAdvancerin vammarullasta.
- [x] PARITEETTI: perusilmaantuvuus ennallaan (injuryCheckin base 0.5 %/play, fatigue/durability/doctor-kertoimet koskemattomia; ainoa rate-muutos on opt-in rush-back-ikkuna). LiveGameEngine/GameSimulator/PlaySimulator koskemattomia; live-vammat kirjautuvat historiaan applyInjury-defaulteilla. R16-livepariteetti (liveGameInjuryTeamIDs-skip) ennallaan.
- [x] BUILD: xcodebuild BUILD SUCCEEDED (iPad-simulaattori 049C7295), 2 ajoa (välibuild kääntäjän exhaustiveness-tarkistukseen — kaikki CoachRole-switchit katettu).

### Rajaukset
- [ ] Live-pelin vammoihin ei season/week-kontekstia (LiveGameEngine kutsuu applyInjurya defaulteilla; Engine/Match jätettiin koskematta rinnakkaisen UI/Match-putken vuoksi) — historia näyttää niille vain tyypin ja keston. Helppo jatko: välitä season/week LiveGameEngine.persistissä.
- [ ] Playoff-viikot eivät aja rehab-tickiä (olemassa oleva käytös — vammat "jäätyvät" playoffeihin quick simissä); InjuryReportView siivoaa silti vanhentuneet päätökset avattaessa.
- [ ] AI-tiimit eivät palkkaa head traineria olemassa oleviin careereihin (uudet liigat saavat LeagueGeneratorista) — ilman traineria rehab-odotusarvo on neutraali, joten AI-rosterit eivät kärsi; AI-staffin täydennyspalkkaus on oma isompi työnsä.
- [ ] PlayerDevelopmentEngine.processInjury (AI-offseason-legacy, oma 15 % durability-roll) jätettiin ennalleen — sen yhtenäistäminen MedicalEngineen kuuluu legacy-siivoukseen.

## Round 27: Scouting-organisaatio — kohdennukset, oma budjetti, deterministinen palkkauspooli (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] OMA SCOUTING-BUDJETTI (`Owner.scoutingBudget/previousScoutingBudget`, oletusarvot → kevyt migraatio): skoutit eivät enää syö valmentajapottia. `BudgetEngine.calculateScoutingBudget` ($2–6M base spending willingnessistä × markkina ±10% × menestys 0.90–1.15, floor $1.5M) + `defaultScoutingBudget`-helperi. Kauden vaihteessa WeekAdvancer.startNewSeason päivittää molemmat potit; LeagueGenerator antaa uusille omistajille willingness-skaalatun scouting-potin. Valintapaine laatu vs määrä: 8 huippuskoutin palkat (~$650K–2M chief, $150K–1M muut) eivät mahdu keskipottiin.
- [x] BUDJETTI KYTKETTY PALKKAUKSEEN: CoachingStaffView jakaa potit (remainingBudget = vain valmentajat, uusi remainingScoutBudget), budjettiheaderiin oma scouting-rivi + palkki (accentBlue), over-budget-varoitus nimeää ylittyneen potin. HireScoutView saa oikean jäljellä olevan scouting-budjetin — myös ScoutingHubin HireScoutSheet, jossa oli kovakoodattu 5 000 K placeholder (korjattu laskemaan owner-potista miinus nykyiset palkat). ScoutTeamView'n budjettirivi näyttää scouting-potin + jäljellä/yli -värityksen.
- [x] WATCH-KOHDENNUKSET (`Scout.assignmentPoolRaw: String?` — optionaalinen kenttä, kevyt migraatio + `ScoutAssignmentPool`-enum Top 50/Top 150): generateWeeklyReports rakentaa konsensus-boardin VAIN julkisesta tiedosta (scoutedOverall + draftProjection, ei true-arvoja) ja rajaa skoutin viikkovisiitit kohdennettuun joukkoon; fallback alueeseen jos leikkaus tyhjä. Kohdennettu skoutti tekee 4–6 visiittiä/vko (vs 3–5) ja saa +5 accuracy (watch pool) — kohdennetut prospektit paljastuvat nopeammin ja tarkemmin.
- [x] FOCUS-POSITIO VIIKKORAPORTTEIHIN: `scout.focusPosition` vaikutti ennen vain combine/pro day -raportteihin — nyt se sekä suodattaa viikkovisiittien poolin ("OL-skoutti katsoo OL:ää") että antaa +10 accuracyn positio-osumaan, yhdenmukaisesti muun tarkkuusjärjestelmän kanssa (ei rinnakkaismekaniikkaa; heikon skoutin leveä virhemarginaali = bust-riski säilyy).
- [x] DETERMINISTINEN PALKKAUSPOOLI: `CoachingEngine.generateScoutCandidates(role:count:seed:)` + SplitMix64-`ScoutPoolGenerator` + `scoutPoolSeed(teamID:role:season:)` (FNV-1a stabiilista avaimesta — Hasher on launch-randomoitu, siksi oma hash). Sama joukkue+rooli+kausi näkee aina saman kandidaattilistan (ei sheet-uudelleenavaus-rerollausta); `RandomNameGenerator.randomName(using:)`-seeded-variantti nimille. Molemmat kutsupaikat (CoachingStaffView, ScoutingHubView) välittävät seedin.
- [x] UI — SCOUT TEAM: rivikohtainen kolmas valikko "Watch: Region/Top 50/Top 150" (success-väri) fokuspositio- ja attribuuttivalikoiden viereen, otsikkoselite päivitetty; ScoutDetailView'hun uusi "Assignments"-osio (Focus Position / Focus Attribute / Watch Pool + kuvaus). Kaikki Theme-tokeneilla.
- [x] UI — "SCOUTED BY X": prospektiriville (ProspectRowView sub-info) pieni "by R. Collins · 70%" -rivi (viimeisin raportti + luottamus) confidence-dottien jatkoksi; ProspectDetailView'n "Scouted (N reports)" -riville "latest by X (Y% confidence)". Uudet computed-propertyt `CollegeProspect.latestScoutName/latestReportConfidence`.
- [x] AI-POLKU ENNALLAAN: viikkoraportit generoidaan vain käyttäjän joukkueen skouteille (kuten ennenkin), AI-draft-osumatarkkuus ja mock draft -logiikka koskemattomia; scouting-budjetti lasketaan AI-omistajillekin mutta AI ei palkkaa skoutteja → ei vaikutusta AI-rostereihin. Quick sim -pariteetti: GameSimulator/PlaySimulator koskemattomia.
- [x] BUILD: xcodebuild BUILD SUCCEEDED (iPad-simulaattori 049C7295).

### Rajaukset
- [ ] In-season-palkkauksen määrärajoitusta ei lisätty erikseen — nykyinen roolipohjainen malli (8 slottia, palkkaus vain vapaisiin rooleihin ScoutingHubissa) + budjettipotti rajaavat churnin jo käytännössä; erillinen "1 palkkaus/kausi" -laskuri olisi vaatinut uuden persistoitavan kentän kevyellä hyödyllä.
- [ ] Konsensus-board käyttää legacy `scoutedOverall`-kenttää (viikkoraporttien oma pipeline päivittää sitä) — GradeRange-midpointtiin siirto kuuluu isompaan legacy-kenttien siivoukseen.
- [ ] `Owner.previousScoutingBudget` tallentuu mutta muutosnuolta ei vielä näytetä UI:ssa (coaching-budjetin change-badge näyttää vain valmentajapotin).

## Coach-kameran kalibrointi: korotettu valmentajanäkymä Madden-läheltä ja broadcast-kaukaa väliin (2026-07-09)

Käyttäjän palaute lähikamerasta: "valmentajan näkökulmasta liian läheltä kuvattu!" — edellinen Coach-kehys (kamera h4.8 / LOS−17.5, FOV 27°) ampui yli: etualan hahmot ~31 % ruudusta, koko boxi ei mahtunut kuvaan. Uusi tavoite: korotettu coach-perspektiivi, koko ydinmuodostelma (OL-boxi + backfield + LB-taso) kerralla, pelaajat silti ~4× vanhaa kaukokuvaa isompia.

### Shipped (BUILD SUCCEEDED)
- [x] UUSI COACH-KEHYS (`UI/Match/FootballFieldScene.swift` — vain offsetit/FOV, toggle+rakenne edelliseltä ajolta säilyi): offense kamera (0, 7.5, LOS−16.5·vf), target (0, 1.0, LOS+4·vf); defense kamera (0, 8.5, LOS−16.5·vf), target (0, 1.0, LOS+3·vf) — korkeampi jotta reitit erottuvat OL:n yli; FOV 27° → 52° (sama linssi kuin broadcast → tyylivaihdossa liikkuu vain positio). zNear 1 ok — lähin pelaaja ~10 yd linssistä, ei leikkautumista yhdessäkään screenshotissa.
- [x] MITATUT PROSENTIT (pakollinen iterointi: 3× build+asennus+coached-peli+screenshot+PIL-pikselimittaus, `measure.py` + ruler-cropit scratchpadissa): hyökkäys-pre-snap — etualan backit #34/#19 197/184 px / 1407 px viewport = **14.0/13.1 %** perusryhmityksissä (tavoite 12–16 ✓), syvimmissä split-back-seteissä (~7 yd + push-in) ~**17 %** (haarukan yläreunan yli ~1 %-yks., hyväksytty — ensimmäinen −15.5 yd -versio mittasi 17.6 % jo perusseteissä → siirretty −16.5:een); OL LOS:lla ~7.5 %. Puolustus-pre-snap — etualan LB:t 185 px = **13.1 %** (10–14 ✓; ekan version −18.5/9.0 mittasi 9.7 % → kiristetty −16.5/8.5), DL ~9 %. KOKO boxi + backfield + LB-taso mahtuu kuvaan molemmissa kehyksissä (verifioitu useissa screenshoteissa eri LOS-paikoista), LOS-stripe ylittää ruudun koko leveydeltä, laitahyökkääjät leikkautuvat reunoista pre-snapissa speksin sallimalla tavalla.
- [x] KRIITTINEN LÖYTÖ+FIKSI — kenttäkosketus jäädytti kameran pysyvästi: `SceneKitFieldView` piti `allowsCameraControl = true` → ensimmäinen tap/drag kentän päällä luovutti pointOfView'n SceneKitin vapaalle käyttäjäkameralle, minkä jälkeen KAIKKI skriptatut focus/follow/pull-back-siirrot lakkasivat näkymästä (kamera "jumissa" edellisen framen paikassa — diagnosoitu toistuvista stale-kehyksistä idb-tappien jälkeen, kuvasarjat scratchpadissa). Fiksi: `SceneKitFieldView` sai `allowsCameraControl`-parametrin (oletus true → MatchView-replay ennallaan), CoachedGameView antaa `false`. Verifioitu: 3 tahallista kenttätappiä + 60 s pelejä → kehys pysyy oikeana joka pre-snapissa ja wait-statessa.
- [x] PELIN AIKANA: follow-refocus (`execute` .carry/.arc → `followCamera`) perii Coach-offsetit `currentShotStyle`n kautta (rakenne ennallaan), seurantakynnys 7→8 yd leveämmälle kehykselle; easing (0.7–1.7 s) ennallaan → ei hyppyjä. Taklauksen jälkeinen `pullBackAfterPlay` (+30 % / 1 s) ennallaan ja palautus seuraavaan pre-snapiin toimii (verifioitu monen perättäisen pelin sarjoissa).
- [x] TOGGLE: HUD-kameranappi (video.fill/tv), `@AppStorage`-muisti ja Broadcast=vanhat kaukokehykset — edelliseltä ajolta, verifioitu molempiin suuntiin uusilla arvoilla. Pre-snap push-in coach-tilassa edelleen kuiskaus (0.5 yd); kickoff aina broadcast (verifioitu avauspotkusta), kickCamera/celebrate ennallaan; sääslab seuraa fokusta.
- [x] BILLBOARD-NUMEROT: coach-kehyksessä 0.0 → **0.35** (himmeinä mutta näkyvissä — tällä etäisyydellä paitanumerodecalit eivät yksin kanna takarivin pelaajille; broadcast 0.6 ennallaan). Kommentit päivitetty.
- [x] FIX FORWARD (ei tämän vaiheen työtä, mutta puu ei kääntynyt): työpuussa ollut keskeneräinen HELMETDECAL-viittaus `Self.abbreviationTexture(...)` ilman toteutusta → lisätty `abbreviationTexture(_:darkText:)` -helperi (cachetettu UIGraphicsImageRenderer-tekstuuri, sama tyyli kuin numberTexture; 3-kirjaimiset lyhenteet pienemmällä fontilla).
- [x] EI REGRESSIOITA: Coach's Board, HUD, feed, päätöskello ja RouteSpec-koreografia koskemattomia — diffi kohdistuu vain kameraoffsetteihin, billboard-opacityyn, followTriggeriin, SceneKitFieldView-parametriin ja decal-helperiin. Sim-pariteetti: kaikki presentaatiota, engine-poluissa nolla muutosta.

### Rajaukset
- [ ] Syvimmät split-back-setit (backit ~7 yd + pre-snap-dolly) mittaavat ~17 % (speksin 12–16 yläreunan yli ~1 %-yks.) — yhden offsetin kompromissi; perusryhmitykset 13–15 %. Jos halutaan tiukemmin, dollyn voi poistaa coach-tilassa (speksi sallii "pois tai hyvin pieni").
- [ ] Puolustuskehyksessä omat syvät safetyt jäävät pre-snapissa kuvan alareunan taakse (boxi+LB-taso on prioriteetti; Broadcast näyttää koko shellin) — sama linjaus kuin edellisellä kierroksella.
- [ ] Lumihiutaleita spawnaa satunnaisesti lähelle linssiä uudella matalammalla kamerakorkeudella (slab y 4–12 vs kamera y 7.5–8.5) — oma taskinsa jo jonossa (#16 "Sää-slab matalalle coach-kameralle").
- [ ] Testipelit pelattiin viikon 9 ATL-ottelua vasten mutta jätettiin kesken (app terminate) — keskeneräinen peli ei kirjaudu; Coach the Game käynnistyy puhtaalta pöydältä.

## Round 26: Kehitys 2.0 — treenifokus, viikkoraportit, mentorointi näkyväksi, breakoutit (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] TREENIFOKUS (`Engine/PlayerDevelopment/TrainingFocusEngine.swift`, uusi): `TrainingFocusArea`-enum (17 aluetta, positiokohtaiset + Conditioning/Film Study kaikille; esim. QB Accuracy/Arm Talent/Pocket Work, WR Route Running/Hands, OL Pass Protection/Run Blocking). Max 3 fokuspelaajaa/joukkue (`Player.trainingFocusAreaRaw: String?` — optionaalinen kenttä, kevyt migraatio). Viikkotick: fokusattu pelaaja rullaa +1 attribuuttipisteen fokusalueen sisään; todennäköisyys skaalautuu iällä ALAS (pre-peak 0.32 / peak 0.18 / post-peak 0.06 base), work ethicillä (±25 %), positiovalmentajan dev-arvolla (±15 %) ja moraalilla (≥80 ×1.15 / ≤35 ×0.7). Sama katto kuin dev-enginessä (truePotential×0.65+35). EI kosketa kausikehitys-pipelinea (processOffseason/camp ennallaan) — puhdas additiivinen mikrokehitys.
- [x] VIIKKORAPORTTI (`Domain/Models/League/DevelopmentReport.swift` uusi + `Career.developmentReportLogData` bridge, max 10 vk): WeekAdvancerin steps 7b/7c kokoavat käyttäjän joukkueelle risers (+1 attribuutti nimellä + syy-chip), breakoutit, mentoriparit ja stalled-listan (holdout/vamma = kehitys seis, matala morale = hidastaa, post-peak-fokus = "gains are rare"). Inbox-digest joka viikko uudelta lähettäjältä (`MessageSender.developmentStaff` "Player Development") + attachment-linkki raporttinäkymään; muistutusrivi jos fokusslotit tyhjinä.
- [x] MENTOROINTI NÄKYVÄKSI: R25:n piilotettu +10 % XP-boost raportoidaan nyt — aktiiviset parit (LockerRoomEngine.activeMentorships) listataan sekä viikkoraportissa ("Mentor → protégé, +10% development speed") että Development-näkymän omassa osiossa.
- [x] BREAKOUT-TAPAHTUMAT: `rollBreakout` — nuori (≤3 v pro, ≤25 v) korkealla potentiaalilla (≥82) + kunnossa oleva morale (≥60) voi ottaa kertahypyn +4–6 pistettä positioryhmään (+1 awareness); 6 %/vko/joukkue, kova katto 2/kausi/joukkue (in-memory-laskuri). Tuottaa liigauutisen (NewsItem, playerPerformance) kaikille joukkueille + oman korostetun rivin käyttäjän raporttiin.
- [x] AI-VASTINE: `autoAssignFocus` — AI-joukkueet täyttävät 3 slottia automaattisesti parhailla nuorillaan (truePotential desc, nuorin ensin; post-peak-slotit kierrätetään, trade-ylivuoto trimmataan) → sama mekanismi, ei ilmaista etua käyttäjälle. Käyttäjän joukkueen valintoja EI koskaan ylikirjoiteta.
- [x] UI (`UI/Roster/DevelopmentReportView.swift`, uusi — ei UI/Match!): Development-hubi — fokusslotit (pelaajarivi + aluevalinta-Menu + PAST PEAK -varoitus + poisto), pelaajavalitsin-sheet (nuoret ensin, potential-label jos scoutattu, "Low gains" -varoitus vanhoista), mentoriosio, viikkoraporttikortit syy-chipeillä. Reititys: `TaskDestination.developmentReport` + ShellDestination + CareerShellView-mappaus + dashboardin quick action "Development" (regularSeason-ryhmä). Tokenit/tumma korttikieli (backgroundTertiary-rivit, accentGold/eliteGreen/success/warning/danger, DSSpacing/DSCornerRadius).
- [x] BUILD: xcodebuild BUILD SUCCEEDED (iPad-simulaattori 049C7295). Quick sim -pariteetti: GameSimulator/PlaySimulator koskemattomia — kaikki muutokset WeekAdvancer-hookkeja + malleja + UI:ta.

### Rajaukset
- [ ] Fokusvalinta vain Development-hubissa (dashboard quick action / inbox-linkki) — PlayerDetailView'hun ei lisätty fokus-badgea/valintaa tällä kierroksella (iso jaettu tiedosto, pidettiin riski pienenä).
- [ ] Fokustick pyörii vain runkosarjaviikoilla (advanceRegularSeasonWeek) — camp/preseason-viikoilla oma TrainingPlan-järjestelmä kattaa treenauksen; raportteja ei synny offseasonissa.
- [ ] Breakout-laskuri on in-memory (nollautuu appin restartissa) — hyväksytty kevennys, virhe on "korkeintaan pari ylimääräistä breakoutia", ei SwiftData-kenttää.
- [ ] `updatePotentialRealization` on edelleen kytkemättä (kartoituslöydös) — ei kuulunut tämän kierroksen speksiin.

## Madden-mittakaavan kamera: Coach-lähikehys oletukseksi + Coach/Broadcast-toggle (2026-07-09)

Käyttäjä: "grafiikka ei ole parantunut yhtään" — juurisyy hahmojen ~3–4 % ruutukoko. Referenssi Madden 99/2000 PSX pre-snap: matala kamera suoraan hyökkäyksen takana.

### Shipped (BUILD SUCCEEDED)
- [x] COACH-LÄHIKEHYS OLETUKSEKSI (`UI/Match/FootballFieldScene.swift`): uusi `CameraStyle`-enum (coach/broadcast) + `setCameraStyle`. `focusCamera` valitsee kehyksen tyylin mukaan — coach-offense: kamera (0, 4.8, LOS−17.5·vf) ≈ 10 jaardia syvimmän backin (~7 yd) takana lähes kypärätasolla, target (0, 0.9, LOS+5·vf), pitkä 27°:n linssi; coach-defense: sama matala kehys oman boxin takaa mutta korkeampi ja kauempaa (0, 6.5, LOS−19.5·vf), target LOS+2.5·vf → OL ei peitä QB:tä/reittejä. Broadcast = entiset kaukokehykset (24/33 korkeat, FOV 52). FOV animoituu SCNTransactionilla samassa easessa kuin siirto; zNear 1 ok — lähin pelaaja ~9 yd linssistä, ei leikkautumista (verifioitu myös punt-muodostelmalla, punttaaja 7 yd).
- [x] MITATUT PROSENTIT (pakollinen iterointi tehty: build + asennus + coached-peli + screenshot + Python-pikselimittaus scratchpadissa `cam/measure.py`): hyökkäys-pre-snap — etualan back/QB #19 442 px / 1420 px viewport = **31.1 %** (tavoite 28–35 ✓), OL kolmipisteessä 330 px = **23.2 %** (tavoite ≥18 ✓); puolustus-pre-snap — etualan LB 355 px = **25.0 %**, DL LOS:lla 289 px = **20.4 %** (≥18 ✓, tarkoituksella hieman ylempää speksin mukaan); kenttäsyvyys molemmissa ~25–30 yd (QB+backfield ja reittialue luettavissa). Prosentit 3D-viewportin korkeudesta (Maddenissa viewport = koko ruutu; täällä kenttä on ruudun ylälohko).
- [x] PELIN AIKANA TIUKKA MATALA SEURANTA: follow-refocus (`execute` .carry/.arc) käyttää shotissa olevaa tyyliä (`currentShotStyle`) → kamera liukuu pallon mukana samoilla coach-offseteilla; seurantakynnys tyylin mukaan (coach 7 yd, broadcast 11) — tiukka kehys lähtee mukaan aiemmin eikä kantaja karkaa kuvasta. Olemassa oleva easing (followCamera 0.7–1.7 s) ennallaan → ei hyppyjä pitkissä peleissä.
- [x] PULL-BACK TAKLAUKSEN JÄLKEEN: uusi `pullBackAfterPlay()` — kamera easaa ~30 % kauemmas aim-sädettä pitkin (nousee samalla ~30 %) 1 s ajan, jotta kasa näkyy; `finishPlay` kutsuu ei-potku/ei-TD-peleissä ja viivästää `proceed`ia ~1 s (sama guard-kuvio kuin injury-holdissa) → seuraava pre-snap-sync palauttaa tiukan kehyksen absoluuttisiin koordinaatteihin. Coach-tyylissä vain; broadcast no-op.
- [x] TOGGLE + MUISTI (`UI/Match/CoachedGameView.swift`): pieni pyöreä kameranappi kentän oikeaan alakulmaan (SF symbol `video.fill` = coach / `tv` = broadcast), `@AppStorage("coachCameraStyle")` säilyttää valinnan pelien yli; vaihto livenä liu'uttaa kehyksen uuteen tyyliin (0.7 s). Verifioitu simulaattorissa molempiin suuntiin.
- [x] REUNAEHDOT: kickoffit AINA broadcast-kehyksellä (`focusCamera(style: .broadcast)` — 60 jaardiin levinnyt muodostelma ei mahdu lähikuvaan; myös palautus-TD:n päätyfokus), ja follow-cam perii saman tyylin potkun paluujuoksun ajaksi; kickCamera (FG/XP matalalta tolppien takaa) ennallaan + palauttaa broadcast-FOV:n potkuksi; pre-snap push-in coach-tilassa kuiskaus (0.5 yd, ei laskua; broadcast ennallaan 2 yd/−0.4); billboard-numerot piiloon coach-kehyksessä (paitanumerodecalit kantavat; broadcastissa 0.6-opacity kuten ennen — `billboardNumberOpacity`, myös buildPlayer-polku); sääslab seurasi fokusta jo; LOS/1st down -markerit lukevat lähikuvassa oikein (verifioitu screenshotein).
- [x] EI REGRESSIOITA: MatchView (quick match) käyttää scenen oletusta `.broadcast` eikä koskaan kutsu focusCameraa → täysin ennallaan; Coach's Board, HUD, feed ja 10 s päätöskello koskemattomia; RouteSpec-koreografiaan ei koskettu. Sim-pariteetti: kaikki muutokset presentaatiota (kamera + 1 s proceed-viive) — engine-poluissa nolla muutosta.

### Rajaukset
- [ ] Puolustuksen lähikehyksessä oma syvä secondary (CB:t/safetyt) jää kameran taakse/ulkopuolelle pre-snapissa — Madden-tyylinen kompromissi: boxi + QB/backfield täyttävät ruudun, peittokortit kertovat shellin; Broadcast-toggle näyttää halutessa koko muodostelman.
- [ ] Coach-kehyksen yläreunassa näkyy kapea kaista yötaivasta/maalitolpat — pidetty tarkoituksella (stadion-tunnelma, PSX-Maddenissakin horisonttikaista); pitch valittu niin ettei syvin back leikkaudu alareunasta.
- [ ] Pull-back-beatin 1 s lisäys pelirytmiin kaikissa scrimmage-peleissä (presentaatioviive, ei kellovaikutusta) — injury-hold (1.7 s) ajaa sen yli entiseen tapaan.

## Play-calling 3.0 — sim-verifiointi (2026-07-09)

Verifioitu simulaattorissa (iPad Pro 13", Week 9 GB vs ATL, SNOW; live-peli ~2 vuosineljännestä). Screenshotit: `/tmp/snd-screenshots/play-calling-3/`. Build vihreä ×3 (feature-build, parity-harness-build, siivottu loppubuild).

### Verifioitu
- [x] (a) REITIT: Deep Cross kutsuttu ja snap-plate "2ND & 10 · DEEP CROSS" + kaikki vastaanottajat reiteillään mid-play (`08_cross_selected`, `09_cross_t1`; X&O-kortti rinnalla `07_medium_tab`). Screen: "3RD & 16 · SCREEN", QB odottaa ja dumppaa RB:lle (kohde M. Dixon feedissä) (`57_screen_sel`, `59_screen_t1`). Toss Sweep: "3RD & 10 · TOSS SWEEP", pitchi + kantajan kaari laidalle, tulos "Marcus Dixon rushes for 8 yards" + run-block-ticker "D. Davis paves the lane — M. Dixon hits it clean" (`84_toss_sel_1`, `85/86_toss_1_*`). Kukaan ei seiso paikallaan pass-snapeissa (kuvasarjat).
- [x] (b) PEITOT: Cover 2 Shell ja Double A-Gap kutsuttu ja ajettu livenä (dialattu kutsu näkyy "they wait for you" -rivillä ja plate-tuloksissa; `22_c2_selected`, `86_toss_2_t1` = DAG dialattuna, `88/89_dag_live_*`). Kulmien squat + safety-split ja 2 LB:n A-aukko-ryntäys verifioitu koreografiakoodista (`PlayChoreographer.swift`: cover2 → `cbDepth ≤ 5`, safetyt ±9/13 + flat-zonet ±13/5 ja syvät puolikkaat; doubleAGap → LB:t ±1.2/1.8 pre-snap, `plan.blitzers=[4,5]`, `blitzPath` gapX ±1.0 → QB) — kaukokameran stillit liian pieniä yksittäisten squattien kuvatodisteeksi, geometria koodissa 1:1 korttien kanssa.
- [x] (c) QB-LUKU: "had a step — the ball went elsewhere" -ticker osui useasti molemmille joukkueille: M. Dixon (`03_playcall_ui`, `16_dc_t1`), P. Griffin (`21_def_ui`, `36_after_timeout`), P. Baker — signaali + väri (punainen = oma QB missasi) toimivat.
- [x] (d) ADAPTAATIO molempiin suuntiin: puolustussuunta — GB:n lyhyt/screen-painotteinen mix laukaisi "They're sitting on your short routes" (`71_after_skip`) ja "ATL is sniffing out the screen game" (`84_toss_sel_1`); hyökkäyssuunta — zone-kutsujen spämmi (Cover 2/3) laukaisi keltaisen eye-intel-chipin "They're working the soft spots in your zone" (`24_c2_t1`, chip + feed-rivi). Counter-painotus (run-stop-frontit inside-run-spämmiin jne.) koodikatselmoitu `AdaptiveOpponentAI.defensiveCounterCalls` — 10 s kello + tap-latenssi esti puhtaan 5× saman juoksun spämmin käsin; mekanismi identtinen (täsmäpeli 3/5 -triggeri todennettu koodista).
- [x] (e) KELLO: ylitys hyökkäyksessä → "Delay — J. Love checks into Screen/Slant" + kortti korostuu + autosnap (`03`, `13_state`); puolustuksessa → "Delay — GB defense checks into Cover 3" ja dialatulla kutsulla "rolls with Cover 4 Match" (`13`, `54_after_skip2`); erikoisryhmät → "Delay — the punt team takes the field" / "the field goal unit trots out" (`55_poll`, `53_after_skip`). Numerobadge-tilat: 5 amber (`63_atl_drive`, `71`), 3 punainen (`13`), 0 punainen (`54`). AIKALISÄ nollasi kellon: TO·3→TO·2, toast "Timeout, GB — the clock is stopped.", badge pois (`36_after_timeout`). Coach's Board pysäytti kellon: board auki ~1 min → sama down/klo paluulla (`05_manage_open` → `07_medium_tab`, 2nd&10/12:51 ennallaan).
- [x] PARITEETTI: `GameSimulator.debugSimulate(n: 50)` ajettu väliaikaisella env-vartioidulla kutsulla (`DynastyApp.init`, poistettu ajon jälkeen, rebuild vihreä): points/team mean 20.5 (std 10.5, min 0, max 51), yards/team 332, penalties 9.0/game, margin 14.6, schedule integrity 2025–2032 OK — tavoitehaarukassa ~20–25, adaptaatio+koreografia eivät vuoda quick simiin.

### Havainnot (ei korjattu — ei bugeja)
- [ ] 62 jaardin FG upposi lumipelissä (DeAndre Warren) — pitkien FG:iden onnistumiskäyrä + sääpenalty voisi kaivata balanssisilmäystä (ei tämän kierroksen regressio).
- [ ] Kaukokamera (away-puolen drivet omalla kenttäpuoliskolla) jättää puolustuskoreografian pieneksi stillikuviin — mahdollinen tuleva "isolate defense" -kamera tai replay-zoom auttaisi visuaalista verifiointia (pelattavuudessa ok).
- [ ] Automaatiohuomio (ei tuotekoodia): 10 s ikkuna + idb-tap-latenssi (~1–2 s/tap) tekee skriptatusta play-callingista hauraan; Coach's Board -pausea voi käyttää "freeze-frameen" testiajoissa.

## Pelinvalinnan päätöskello: 10 s molemmille puolille, ylityksestä autovalinta (2026-07-09)

Käyttäjä: "hyökkäykseen ja puolustukseen kuvion päättämiseen aika, ~10 s; jos ei päätetä, QB tai puolustus valitsee automaattisesti yksinkertaisen pelin".

### Shipped (BUILD SUCCEEDED)
- [x] KELLO (`UI/Match/CoachedGameView.swift`): nimetty vakio `CoachedGameView.playClockSeconds = 10`; 10 Hz `Timer.publish`-ticker + `armPlayClock()/disarmPlayClock()/tickPlayClock()`. Kello virittyy `proceed()`issä täsmälleen kun call-sheet muuttuu interaktiiviseksi: hyökkäyssheet, puolustuksen READY-odotus, 4th down -paneeli, kickoff-valintapaneeli (deep/onside), post-TD XP/2pt-paneeli JA AI:n 2pt-yrityksen "call your stop" -puolustuspäätös. Halftime-haara palaa ennen viritystä → kello ei koskaan laukea halftime-overlayn alla; "Go for 2 → CALL THE PLAY" avaa try-sheetin TUOREELLA kellolla.
- [x] VISUAALI: kapselirengas SNAP/READY/KICK/KICK XP -napin ympärillä (`playClockWrapped` — `Capsule().trim` kuluu ajan mukana, lineaarinen animaatio) + numerobadge napin viereen viimeiset 5 s (`contentTransition(.numericText)`); kulta > 5 s, amber ≤ 5 s (warning), punainen ≤ 3 s pulssilla (`PlayClockPulse`-phaseAnimator, rengas + numero). Kaikki 5 commit-nappia kiedottu.
- [x] YLITYS → AUTOVALINTA (`playClockDidExpire`, haarajärjestys = callPanel): EI delay of game -rangaistusta, feed-rivi kertoo aina (uusi `LiveGameEngine.postFeedNote` — sama playLog-only-mekanismi kuin vaihto/intel-rivit, `emitAdaptationHint` refaktoroitu käyttämään samaa; ei drive/stats/pariteettivaikutusta). Autovalinnan jälkeen ~1.5 s esittely (valittu kortti korostuu + muodostelmapreview) ja snap lähtee itsestään (`afterAutoCallShowcase`).
  - Hyökkäys: "QB checks it down" — 3rd/4th & ≥7 → pelikirjan ensimmäinen installoitu lyhyt passi (Slant-fallback); muuten ~50/50 Inside Run (tai ensimmäinen installoitu juoksu) / lyhyt passi. Feed: "Delay — J. Love checks into Inside Run". Kortti valitaan + kategoria-tab vaihtuu näkyviin.
  - Puolustus: DC checkkaa scheme-pohjaiseen baseen (`schemeBaseDefensiveCall`: Tampa 2 / 4-3 → Cover 2 Shell; Press Man → Man Free; muut → Cover 3 — kaikki aina installoituja). Feed: "Delay — GB defense checks into Cover 3".
  - 4th down: esivalittu erikoisryhmäkortti (FG jos matkalla, muuten punt) lähtee. Kickoff-paneeli: valittu kortti (deep oletus / dialattu onside) potkaistaan. XP/2pt-paneeli: XP potkaistaan; dialattu "Go for 2" avaa sheetin autovalitulla 50/50-pelillä ja snappaa itse.
- [x] VALITTU-TILAN KUNNIOITUS: jos pelaaja EHTI itse napauttaa kortin muttei painanut SNAP, ylitys snappaa VALITULLA pelillä — `offCallDirtied`/`defCallDirtied`-liput (proceed():n esivalitsema AI-suggestion EI ole pelaajan valinta → delay checkkaa silti alas; brain-chipin adoptointi lasketaan valinnaksi). Puolustuksessa edellisen snapin kutsu ilman kosketusta tässä ikkunassa = ei valinta → DC:n base.
- [x] PAUSSIT & OHITUKSET: `playClockPaused` — Coach's Board / Stats / halftime / final / confirm-dialogit / play-animaatio pysäyttävät tickin (jatkuu suljettaessa siitä mihin jäi). AIKALISÄ (TO-nappi) täyttää kellon takaisin täyteen (paitsi jos autovalinta on jo liikkeellä). Sim to End ja Skip Drive disarmaavat kellon; runPlay/runKickoff disarmaavat snapissa. Kilpajuoksut: `playClockGeneration`-token — manuaalinen SNAP/KICK 1.5 s -esittelyn aikana invalidoi viivästetyn autosnapin, tuplasnap mahdoton.
- [x] SETTINGS (`UI/MainMenu/SettingsView.swift`): uusi `PlayClockSetting`-enum (10 s / 15 s / Off), Gameplay-osioon "Play Clock" -picker (timer-ikoni), UserDefaults-avain `playClockSetting`, footer-selite, reset palauttaa 10 s:iin. Off → kello ei koskaan viritty, peli käyttäytyy täsmälleen kuten ennen.
- [x] PARITEETTI: kaikki uusi on UI-tason logiikkaa (`CoachedGameView`) + presentaatio-`postFeedNote`; engine-sim-polut, quick sim ja nil-argumentti-`step` koskemattomia.

### Rajaukset
- [ ] Aiempi "puolustusvalinnassa ei aikapainetta" -linjaus (User todos -listan rivi) korvautuu tällä uudemmalla speksillä — Off-asetus palauttaa vanhan rauhallisen käytöksen.
- [ ] "Try Options"/"4th Down" -back-chevronit eivät nollaa kelloa (sama päätösikkuna jatkuu) — tarkoituksellinen: edestakaisin selailulla ei voi paeta kelloa.
- [ ] Kello virittyy heti kun paneeli aukeaa (muodostelmasiirto ~0.3 s kuuluu ikkunaan) — käytännössä merkityksetön 10 s:ssa.
- [x] Silmämääräinen simulaattoriverifiointi TEHTY 2026-07-09 (delay-feedit molemmilla puolilla + erikoisryhmillä, badge 5/3/0-tilat, TO-täyttö, board-pause) — ks. "Play-calling 3.0 — sim-verifiointi" ylhäällä.

## Adaptiivinen vastustaja-AI: toistuvat kutsut tunnistetaan ja counteroidaan (2026-07-09)

Käyttäjä: "jos pelaaja kutsuu saman tai samanlaisen pelin useasti, AI:n pitää adaptoitua ja valita kuvio joka toimii sitä vastaan — sama puolustuksessa ja hyökkäyksessä".

### Shipped (BUILD SUCCEEDED)
- [x] TENDENSSISEURANTA (`Engine/Match/AdaptiveOpponentAI.swift`, uusi): `Tracker` kirjaa pelaajan EKSPLISIITTISET kutsut tässä pelissä recency-painotettuna (viimeiset 10, paino 0.85^ikä, min. otos 5). Hyökkäys kategorioittain (sisäjuoksu/ulkojuoksu/screen/lyhyt/keski/syvä/PA — johdettu OffensivePlayCallin kategoriasta + run-gap/pass-depth-vihjeistä; spike/kneel ei kirjata) + täsmäpeleittäin (sama peli 3/5 viimeisestä laukaisee heti, ilman min-otosta). Puolustus perheittäin DefensivePackagesta: man (coverage==manToMan) / zone (muut) / blitz-osuus (blitz!=noBlitz) / single-high (Cover 1/3). Kirjaus `LiveGameEngine.step`issä vain pass/run-snapeista (intentio lasketaan vaikka flägi pyyhkii downin) — AI:n omia kutsuja EI kirjata, nil-argumenttipeli ei kirjaa mitään.
- [x] AI-PUOLUSTUS ADAPTOITUU (pelaaja hyökkää): kun kategoria ≥ skaalattu kynnys painotetusta massasta TAI sama täsmäpeli 3/5 → `aiDefensivePackage()` korvaa base-valinnan counter-paketilla osuudella snapeista: sisäjuoksu→Bear/Goal Line/Double A-Gap; ulkojuoksu/sweep→Corner Blitz/Safety Blitz/Cover 2 (edge+contain); lyhyt/screen→Man Press/2-Man/Nickel; keski→2-Man/Cover 4 Match/Dime; syvä→Cover 2/Quarters/2-Man; PA-spämmi→disciplined zone (Cover 3/Quarters/C4 Match). Counter EI koskaan yliaja red zone -selloutia (≤10 yd) eikä late-lead-preventiä; poolista suositaan vastustajan DC-skeeman pelikirjaan asennettuja kutsuja.
- [x] AI-HYÖKKÄYS ADAPTOITUU (pelaaja puolustaa): uusi `aiOffensiveCall()` → blitz-osuus yli kynnyksen (base 45 %) → screen/slant/quick out/draw/flat; man-valtainen (base 50 %) → mesh/drag/deep cross; zone-valtainen (base 65 % — zone on call-sheetin peruskudos, vaatii lähes puhtaan zonen) → seam/curl/dig/stick; single-high-valtainen (base 50 %) → post/PA deep/go/corner. Vahvin signaali (suurin marginaali omaan kynnykseensä) voittaa. Tilannejärki: ei drawta pitkään väliin (paitsi screen), ei syviä ≤25 yd päädystä, EI KOSKAAN 4th downilla (punt/FG-päätökset base-logiikalle); nil = tismalleen entinen `decidePlayCall`. CoachedGameView välittää counterin sekä `step`iin että koreografille (READY-snap + Skip Drive) → RouteSpec näyttää AI:n counter-kuvion kentällä.
- [x] DC/OC-SKAALAUS: kynnys ja counter-osuus skaalautuvat VASTUSTAJAN koordinaattorin arvosanalla ((playCalling+adaptability)/2, fallback 50): kynnys = base +10pp (heikko 0) … −10pp (eliitti 100) → kategoria-base 40 % lukee heikolla ~50 %, eliitillä ~30 %; counter-osuus 0.20 → 0.60 (clamp max 60 % — AI ei muutu deterministiseksi). Counter-arvonta kerran per snap EDELLISEN stepin lopussa (`updateAdaptationState`, defer) → pre-snap-preview ja varsinainen snap näkevät saman kutsun.
- [x] PALAUTE: kun AI:n luku aktivoituu ensi kertaa tai vaihtuu → broadcast-intel: puolustussuunta "CHI is keying on the inside run" / "They're sitting on your short routes" / "They've stopped biting on the play fake"; hyökkäyssuunta "J. Love checks to the quick game — they saw the blitz coming" (QB-nimi live-yksiköstä) / man/zone/single-high-variantit. Julkaisu `lastAdaptationHint`inä (`AdaptationHint`, Equatable) → CoachedGameView'n uusi keltainen eye-intel-chip kentän yläkulmassa (4.5 s, sideline-noten rinnalla VStackissa) + feed-rivi play-tickeriin (sama playLog-only-mekanismi kuin vaihdoilla — ei drive/stats-vaikutusta). Rate-limit: max 1 vihje / 2 min PELIAIKAA (`elapsedGameSeconds`).
- [x] EI TUPLARANGAISTUSTA: counterit vaikuttavat vain olemassa olevien play-vs-play-modifierien kautta (DefensivePackage-modifierit / SimulatorHintit) — ei erillistä ennustettavuusmalusta. Kutsujen mixaaminen pudottaa osuudet kynnysten alle → dominantti nil → counterit pois → AI palaa base-logiikkaan.
- [x] PARITEETTI: kaikki uusi elää vain live-AI-poluissa (`aiDefensivePackage`/`aiOffensiveCall`/`step`in eksplisiittiset kutsut). Nil-argumentti-step ei kirjaa, ei kuluta RNG:tä (tyhjä tracker → dominantit nil ilman arvontaa) eikä julkaise mitään; `GameSimulator.simulate` ei koske koko tyyppiin — quick sim -jakaumat ennallaan. Conversion-snapit (XP/2pt) kirjaamisen ja adaptaation ulkopuolella.

### Rajaukset
- [ ] Rate-limitin nielaisema intel-vihje ei uusiudu (luku jää aktiiviseksi hiljaa) — tarkoituksellinen "ei spämmiä" -tulkinta.
- [ ] Man-shellien single-high/two-high-eroa ei voi johtaa DefensivePackagesta (Man Free vs 2-Man näkyvät vain man-perheenä) — single-high-signaali luetaan zone-shelleistä (Cover 1/3).
- [ ] Skip Driven sisällä counterit toimivat mutta intel-chipit voivat vilahtaa ohi (feed-rivi jää tickeriin).
- [x] Silmämääräinen simulaattoriverifiointi TEHTY 2026-07-09 (intel-chip + molempien suuntien keying-vihjeet livenä; counter-poolit koodikatselmoitu) — ks. "Play-calling 3.0 — sim-verifiointi" ylhäällä.

## Reittiaito koreografia: kutsuttu kuvio näkyy kentällä 1:1 (2026-07-09)

Käyttäjä: "kutsuin Deep Crossin, kukaan ei juossut cross-kuviota" + "pitäisi näyttää miten KAIKKI reitit juostiin ja puolustettiin" + "jos laitahyökkääjä voittaa puolustajansa mutta ei saa palloa, näkee että QB on voinut tehdä virheen".

### Shipped (BUILD SUCCEEDED)
- [x] ROUTESPEC — YKSI TOTUUS (`UI/Match/RouteSpec.swift`, uusi): jokaiselle OffensivePlayCallille reittikartta per rooli (waypointit LOS-suhteellisina, `lateral` peilautuu pelaajan kentän puolen mukaan — yksi taulu palvelee molemmat laidat). Deep Cross = ulko-WR syvä risti vasen→oikea + slot (muodostelmassa oikealle flipattuna) vastakkainen matala risti; Mesh = kaksi matalaa ristiä eri syvyyksillä; Wheel = RB kaartaa sivurajalle; Curl/Comeback = pysähdys+paluu; Stick = TE:n nopea pysäytys; Go/Bomb = verticalit + slot-sauma; juoksuille kantajan rata (dive suora, sweep/toss kaari, counter jab+leikkaus, jet sweep motion-reitti, draw myöhäinen mesh). Lisäksi `generic(forDepth:)` AI-drivejen kutsuttomille snapeille ja `checkdown(role:)` kun sim kohdisti blokkaajalle. `RoutePath` = kaarenpituusparametrisoitu polyline (`slice/point/fractionNearest/maxDepth`).
- [x] KORTTI = SPECIN 2D-PROJEKTIO: `RouteSpec.diagram(for:)` projisoi SAMAN specin + SAMAN muodostelmafunktion (`PlayChoreographer.offensePositions`, nyt internal) normalisoituun korttitilaan; `PlayDiagramView`n käsinpiirretty ~120-rivinen reittitaulukko POISTETTU — kortti ja kenttä eivät voi erota. (DefenseDiagramView ennallaan.)
- [x] KAIKKI REITIT JUOSTAAN: `PlayStep` sai `paths`-kentän (waypoint-polut; scene ajaa ne ketjutettuina `run`-legeinä SCNActioneina, legit kuolevat playGenerationin mukana — ei per-frame-logiikkaa). Pass-pelissä kaikki spec-reitilliset juoksevat reittinsä TÄYSINÄ koko playn ajan (snap+droppi+lento tasavauhtisina fraktioina); OL pass-blokkaa ja tasku painuu (pocketMoves), reititön RB asettuu blitz-pickupiin. KOHDE: kiinniottopiste sijoitetaan kohteen SPECIN reitille simuloidun syvyyden kohdalle (air = gain − maltillinen YAC-osuus; reitin syvyysskaalaus clampattu 0.85–1.2; muuten lähin piste reitillä `fractionNearest`) — YAC jatkaa siitä simin loppupisteeseen. Tulos/kohde/jaardit simistä, eivät muutu.
- [x] PUOLUSTUS PELAA KUTSUNSA (`defensePlan`): man-kutsut (Man Press/Free/2-Man, Cover 1) peilaavat vastaanottajansa reittiä `mirrorPath`-trailina — trail-etäisyys playn matchup-eventeistä (reitin voittaja irtoaa ~1.5 yd, hävinnyt roikkuu ~0.3 yd, kohde simin separationista; CB↔WR-roolimappaus sama kuin MatchupResolver.coverFor); zone-kutsut pudottavat landmarkeihin (Cover 2 squat-flatit + 2 syvää puolikasta, Cover 3 kolme syvää kolmannesta, Quarters neljä, Prevent syvä kuori) ja LÄHIN zone-mies murtaa palloa kohti kun pallo on ilmassa; blitzaajat ryntäävät specin aukoista (Double A-Gap 2 LB:tä A-aukkoihin, Safety/Corner Blitz oikea mies reunasta, All-Out kaikki).
- [x] ERIKOISKOREOGRAFIAT: PA Deep = QB myy kärryn (RB sukeltaa linjaan ilman palloa, LB:t astuvat ylös ennen palautumista droppeihinsa); Screen = QB droppaa ja ODOTTAA, DL päästetään läpi, sisä-OL valuu saattueeksi, kiinniotto LOS:n TAKAA ja YAC saattueen perässä (myös epäonnistunut screen: pallo nurmeen jalkoihin); Draw = QB peruuttaa kuin syöttöön (clearit myyvät droppia, zonet vajoavat) ja ojentaa myöhään; Jet Sweep = slot PRE-SNAP-MOTIONISSA ennen snapia (pallo ei liiku), kantaja seuraa motionia; QB Sneak / Goal Line Dive = matala suora työntö. Toss saa pienen pitchikaaren.
- [x] QB:N VIRHEET LUETTAVIKSI: (a) `MatchupResolver.resolveOpenNonTarget` — paras EI-kohdattu eligible arvioidaan rating-vetoisesti; selvästi voittanut merkitään `PlayMatchups.openNonTargetOffRole`iin → kentällä hänen man-trailinsa kasvaa (~1.7 yd, selvästi auki) ja playn lopussa kädet ylös -ele (olemassa oleva `reaches`-API); (b) kun auki ollut jäi ilman palloa JA heitto epäonnistui (inc/INT/säkki) tai jäi lyhyeksi → feed-/callout-rivi "X had a step — the ball went elsewhere" (event olemassa olevaa Kind-settiä, `qbMissedOpenMan`-lippu); (c) sama signaali −1.5/kpl QB:n `playerGameGrade`en (`missedReadCounts`, dokumentoitu). EI muutoksia kohteen valintaan tai simin jakaumiin — resolveri on live-only-presentaatiota kuten ennenkin.
- [x] SÄKKI: tasku romahtaa VOITTANEEN rusherin puolelta — `pocketMoves(beatenBlocker:)` ajaa matchup-eventin nimeämän rusherin blokkaajan (blockerFacing-mappi) syvälle taakse; reitit juoksevat silti täysinä (näkee kuka ehti auki) ja auki ollut nostaa kädet säkin jälkeen.
- [x] Suorituskyky: polkuanimaatiot ovat SCNAction-ketjuja kuten ennen (`FootballFieldScene.runPath` ajastaa legit DispatchQueuella playGeneration-vahdilla; `effectiveDuration` huomioi pathit) — ei renderöintisilmukan per-frame-päivityksiä.

### Rajaukset
- [ ] Juoksupeleissä puolustus pelaa run-fit-konvergenssia (ei man/zone-pudotuksia) paitsi Draw, joka myy passia — tarkoituksellinen: run-keyt laukeavat heti.
- [ ] Ei-kohdatut vastaanottajat jäätyvät reittinsä päähän YAC-vaiheessa (eivät blokkaa downfieldiä) — pieni jatkokandidaatti.
- [ ] Jet sweepin motion-mies jää feikiksi (sim nimeää kantajaksi RB:n — feedin totuus voittaa); kahden pisteen QB Sneak ilman matchup-attribuutiota näyttää QB:n työnnön specin mukaan.
- [x] Silmämääräinen simulaattoriverifiointi TEHTY 2026-07-09 (Deep Cross / Screen / Toss Sweep -platet ja reitit livenä, QB-miss-ticker molemmille joukkueille) — ks. "Play-calling 3.0 — sim-verifiointi" ylhäällä.

## Madden graphics & UX — sim-verifiointi (2026-07-09)

### Verifioitu simulaattorissa (iPad Pro 13", Week 9 vs ATL, sää: SNOW) — BUILD SUCCEEDED ×2
- [x] SÄÄ: lumihiutaleet ohuita/pieniä, ei jättipalloja kameran vieressä; taivaan pisteet ovat LIIKKUVAA lunta (frame-diff 0.86 % / 1 s — ei staattista tähtitaivasta); kenttä ja pelaajat selvästi pääosassa. (`02-coached-entry.png`, `03-snow-frame1/2.png`)
- [x] PELAAJAT: paitanumerot näkyvät selässä ja rinnassa molemmilla joukkueilla (GB 72/75/76/64/68/34/18, ATL 92/75/78/79/96/98/99), mittasuhteet tanakat, billboard-numerot pienet ja toissijaiset; erotuomari kentällä playn takana ja liukuu LOS:n mukana. (`crop-los.png`, `crop-tackle2.png`, `04-state.png`)
- [x] TAKLAUS: Inside Run päättyi wrap+gang-pileen — 3 taklaajaa eri kulmissa, yksi kaatunut poikittain, kasa asettui satunnaisiin kulmiin. (`crop-tackle1.png`, `07-play2-f6.png`)
- [x] HUD: feedin uusin rivi isompi ja korostettu (laatta + kirkkaampi teksti), vanhemmat portaittain himmeämpiä; skoripelillä kultainen aksentti ("Justin Clark kicks a 43-yard field goal. It's GOOD!"); yläpalkin TO·3/Manage/Stats/Sim to End erottuvat plate-napteina info-chipeistä. (`13-play3-f8.png`, `17-skipdrive.png`, `crop-hud-fixed.png`)
- [x] COACH'S BOARD: Manage → koko ruudun board; muodostelmanäkymä arvosanakortteineen (värikoodit + fatigue-rengas + legend); pelaajan valinta → oikea paneeli (OVR, persoona-chip, day grade + trendi, kategoria-W-L-palkit, fatigue/morale, statsirivi); penkiltä SUB IN → QUEUED-chip + kello-badge + "Sub at next whistle" -yläpalkkichip + PENDING-kortti peruutus-x:llä → vaihto toteutui seuraavassa katkossa (feed: "Sub: I. King in for M. Dixon", King ilmestyi muodostelmaan). Arvosanat elävät pelin edetessä: alussa kaikki 60 → myöhemmin C. Coleman 58, C. Allen 58 "Trending down" + punainen PASS RUSH 0-1 -palkki, D. Jenkins 63. (`09`–`11`, `18`, `19-board-defense.png`)
- [x] KAMERA: molemmat kehykset (hyökkäys `04-state.png`, puolustus `14-punt-f8.png`/`15-defplay-f5.png`) hieman kauempana mutta luettavat; pre-snap push-in toimii (f1→f2 -vertailu `07-play2-*`).

### Korjattu verifioinnissa
- [x] `CoachedGameView.actionButtonLabel`: "Manage" rivittyi kahdelle riville ("Manag e") kun "Sub at next whistle" -chip ahtautti yläpalkin → lisätty `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical: false)` — napit eivät enää purista tekstiään; chipit joustavat ensin. Rebuild + reverify OK (`crop-hud-fixed.png`).

### Auki / havainnot (ei korjattu — designin mukaisia tai pieniä)
- [ ] Puolustajan tyhjä statsirivi näyttää "No touches yet" — sanamuoto hieman outo defenssille (TKL/SACK-rivi tulee kyllä `compactStatLine`:sta kun dataa on); harkitse "No stats yet" defenssipuolelle.
- [ ] Day grade -statsikomponentti päivittyy drive-granulariteetilla (design): keskellä drivea kantajan 7 yd juoksu ei vielä näy statsirivillä eikä BALL CARRY -palkissa jos battle attribuoitui OL:lle — dokumentoitu rajaus, ei bugi.
- [ ] Lumessa taivaalla näkyy stillikuvassa tähtimäisiä pisteitä pimeää taustaa vasten — liikkuvat oikein, mutta jos halutaan vielä rauhallisempi tausta, kaukohiutaleiden opacityä voi laskea taivaan (ei-kentän) alueella.
- [ ] Clear-sään sumusyvyys jäi verifioimatta — testipeli oli lumisade (viikon 9 sää); verifioi seuraavassa clear-pelissä.

Screenshotit: `/tmp/snd-screenshots/madden-graphics/` (00–25 + crop-*). Peli jätetty pelaamattomaksi (Abandon Game), jonotettu QB-vaihto peruttu — career-tila puhdas.

## Coach's Board: koko ruudun pelaajahallinta muodostelmanäkymällä ja päivän arvosanoilla (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Engine (`LiveGameEngine`) — kategoriakohtainen matchup-kirjanpito: `MatchupCategory`-enum (Pass Pro / Run Block / Routes & Catch / Ball Carry / Pass Rush / Run Defense / Coverage) + `categoryTallies: [UUID: [MatchupCategory: CategoryTally]]` nykyisten matchupWins/Losses-summien RINNALLE, täytetään `step()`:ssä täsmälleen samasta event-loopista (ei uutta resolveria: kategoria johdetaan osallistujan omasta roolislotista + playTypesta — off 2–6=OL→passPro/runBlock, 7–10→receiving, 0–1→ballCarry/receiving; def 0–3=DL→passRush, 4–10→coverage, juoksupelillä kaikki→runDefense; sama attribuutio jonka MatchupResolver teki valitessaan offRole/defRole). Vanha W/L-summakäytös bitti-identtinen (winner/loser-haarat vain kirjoitettu roolikohtaisesti auki).
- [x] Engine — päivän arvosana `playerGameGrade(id) → 0–100`: pohja 60 + roolipainotetut battle-W/L (pass pro +3.5/−3.0, run block +3.25/−2.75, muut +3/−2.5 — OL:llä ei counting-statseja joten trench painaa enemmän) + stat-bonukset statsAccumulatorista (TD +6, säkki tehty +4, INT-koppi +6, heitetty INT −8) + per-play-extrat uusista laskureista (20+ yd peli avainmiehenä +2 `bigPlayCounts`, fumble lost −8 `turnoverCounts`, säkki sallittu QB:lle −2 `sackTakenCounts` — kirjataan step():n pass/run-haarassa). Clamp 0–100. Trendi: `gradeTrend(id)` vertaa drive-ennen-viimeistä-snapshottiin (`gradeSnapshots`/`lastDriveGrades` päivitetään finishDrivessä, vain pelaajan joukkue). Lisäksi Board-apurit: `categoryLines(for:position:)` (roolin relevantit kategoriat aina, muut vain jos dataa), `relevantCategories(for:)`, `personalityArchetype(for:)` (R25-persoona live-modelista), `wentDownThisGame(_:)`, `injuredPlayers(forHome:position:)`. KAIKKI puhtaasti presentaatiota — sim ei lue mitään näistä; nil-pariteetti koskematon.
- [x] UI — uusi `UI/Match/CoachesBoardView.swift` (fullScreenCover, koko ruutu, X sulkee; korvaa kapean sheetin — `InGameManagementView.swift` poistettu): VASEN ~58 % MUODOSTELMATAULU — tumma yönurmi-board (Canvas: LOS-viiva + label, 5 jaardin viivat häivytettyinä, NFL-hash-tickit x 0.44/0.56), kentällinen 11 roolisloteissa (off: QB/RB keskellä syvällä, OL+TE+split end linjassa, flanker+slot irti linjasta; def: 4 DL linjassa, 3 LB, pressaavat CB:t laidoilla, 2 S syvällä). Pelaajakortti: päivän arvosana ISOSTI fatigue-renkaan sisällä (rengas täyttyy ja punertuu väsyessä — samat kynnykset kuin autorotaatiolla), värikoodaus speksin mukaan (kulta ≥80 / vihreä 70–79 / harmaa 55–69 / punainen <55, legend boardin alareunassa), nimi, #numero+positio, badge (punainen risti = loukkaantui tässä pelissä, kello = vaihto jonossa). Tap → valinta (kultareunus+hehku → oikea paneeli). OFFENSE/DEFENSE-toggle yläpalkissa (avautuu siihen yksikköön joka on kentällä).
- [x] UI — OIKEA ~42 % paneeli: valitun pelaajan kortti — nimi/#/positio, persoonallisuus-chip (tier-väri: positive vihreä / risky punainen / neutral harmaa), OVR (forRating-väri), iso arvosana fatigue-renkaassa + trendinuoli ("Trending up/down / Holding steady", ±2 kynnys), päivän statsirivi ("No touches yet" kunnes dataa), KATEGORIA-W-L-PALKIT (vain roolille relevantit + ne joissa dataa; vihreä/punainen split-palkki + W-L-luku; "—" kun ottelematta) otsikossa kokonais-W-L, FATIGUE+MORALE-mittarit. Alla PENKKI samalle positioryhmälle: OVR + fatigue + päivän battle-record jos ehtinyt pelata, yhden napautuksen SUB IN (vihreä, 36 pt) → olemassa oleva `substitute()`-jono → rivin nappi muuttuu QUEUED-chipiksi + kello-badge kentän kortille + yläpalkin "N subs at next whistle" -chip + PENDING-kortti peruutus-x:llä. Loukkaantuneet (OUT) ja holdoutit (HOLDOUT, välitetään CoachedGameView'sta koska eivät pue varusteita → eivät ole engine-rostereissa) harmaina ei-valittavina riveinä.
- [x] Vaihtojen validointi ja "at next whistle" -semantiikka ennallaan (sama engine-jono, subsDisabled = isAnimating || isGameOver lukitsee SUB IN:n ja näyttää "Play is live" -noten). CoachedGameView: Manage-nappi avaa nyt Boardin fullScreenCoverina (sheet poistui), muu flow (call sheet 2.0, READY-SNAP, 4th down/2pt-paneelit) koskematta.

### Rajaukset
- [ ] "Kauden snapit" penkkiriveille jätetty pois — pelimalli ei kirjaa snap-lukumääriä (Player-modelissa ei kenttää); tilalla päivän battle-record + fatigue.
- [ ] Arvosanan stat-komponentti päivittyy drive-granulariteetilla (statsAccumulator kertyy per päättynyt drive, kuten quick sim) — battle-komponentti päivittyy per play; sama totuus kuin muissakin live-näkymissä.
- [ ] Erikoisryhmät (K/P) eivät ole boardilla — kenttäyksiköissä ei ole K/P-slotteja (sama rajaus kuin vanhassa sheetissä).
- [ ] Silmämääräinen simulaattoriverifiointi jää putken verifiointivaiheeseen — build vihreä, layout mitoitettu iPad-portraitille (board 58 % / paneeli 42 %, korttileveys adaptiivinen 52–76 pt).

## Coach-HUD:n luettavuus: isompi selostusfeed + oikeat toimintanapit yläpalkkiin (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Selostusfeed (`CoachedGameView.miniPlayFeed`) uusiksi broadcast-tickeriksi: 2 → 3 riviä (korkeus 56 → 96 pt, bottom-ankkuroitu niin uusin rivi istuu aina samassa kohdassa call-paneelin yllä); VIIMEISIN pelirivi korostettu — 16 pt semibold (ennen 12 pt regular), tapahtumaväri koko rivin aksenttina (teksti + isompi 9 pt dotti + kevyt värilaatta `accent.opacity(0.14)` RoundedRectanglessa), neutraali peli 16 pt textPrimary himmeällä laatalla; vanhemmat rivit portaittain alas: 13 pt textSecondary, opacity 0.65 → 0.4, 6 pt dotti. Tapahtuma-aksentit (`feedAccentColor`): TD/pisteet kulta, käännytys TAI säkki punainen (danger; säkki uusi — outcome == .sack), first down sininen (accentBlue, ennen vihreä dotti), tavallinen neutraali. Tyhjä tila ("Kickoff…") 12 → 15 pt.
- [x] Yläpalkin toimintanapit (`situationStrip`): TO · N / Manage / Stats / Sim to End nostettu oikeiksi napeiksi — jaettu `actionButtonLabel`-plate: min 44 pt tap-target (ennen ~26 pt kapseli), 14 pt bold teksti + 14 pt ikoni (ennen 11 pt), RoundedRectangle-tausta backgroundTertiary + surfaceBorder-reunus; TO-nappi prominenttina accentGold-pesulla (opacity 0.16 tausta + 0.45 reunus). Disabled-tila (isAnimating) himmentää 0.45:een. Ryhmittely vahvistettu: tilachipit vasemmalla matalina kapseleina, toimintanapit omana HStack-ryhmänään (spacing 8) oikealla — kaksi selvästi eri korkuista ja muotoista kieltä (kapseli = info, kulmikas plate = nappi).
- [x] Tilachipit: maltillinen luettavuusnosto 12 → 13 pt (padding 9/4 → 10/5) — jäävät tarkoituksella nappeja matalammiksi informaatiochipeiksi.
- [x] Tulostaulu linjaan: Q-label 12 → 14 pt ja textTertiary → textSecondary, kello 24 → 27 pt heavy. 2 min -pulssilogiikka (phaseAnimator), PLAYOFFS/DIVISION/sää-badget ja timeout-pipit koskematta — vain kokoluokka.

### Rajaukset
- [ ] Call-paneeli menettää ~55 pt korkeutta (feed +40, strip +16) — pelikortit ovat ScrollView'ssa joten call sheet skrollautuu; ei toiminnallista muutosta.
- [ ] Kenttäoverlayt (snap-plate, matchup-calloutit, banderollit) ennallaan — speksi rajasi feedin ja yläpalkin.
- [ ] Silmämääräinen simulaattoriverifiointi jää putken verifiointivaiheeseen — build vihreä, mitat laskettu iPad-katseluetäisyydelle (~60–70 cm: 16 pt selostus ja 14 pt napit).

## Madden 2000 -tarkkuus: paidannumerot, tanakka look, taklaukset, erotuomari, kamera kauemmas (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Numerot pelipaitoihin: rinta- JA selkänumero decal-planeina (`FootballFieldScene.addNumberDecals`) — SCNPlane 0.34² "body"-noden lapsena (kulkee torson twist-animaation mukana), positiot torson OMASTA bounding boxista → istuu sekä kit- että proseduraalifiguuriin; tekstuurit UIImage-renderöityjä ja cachettuja per numero+sävy (`numberTextureCache`, valkoinen tummilla paidoilla / lähes musta valkoisilla — luminanssivalinta `isLightColor`). Numero VAIHTUU vaihdoissa/vammoissa: `updateJerseyNumber` retexturoi decalit (`updateNumberDecals`, jersey-sävy luetaan figuurin JERSEY-materiaalista) ja `applyUniform` päivittää kontrastin jos univormu re-tintataan jälkikäteen (numero parsitaan node-nimestä `player_N`). Leijuva billboard-numero säilytetty mutta toissijaistettu: fontti 0.62→0.38 (~40 % pienempi), opacity 0.6, emission alas — kaukoluettavuus säilyy, lähikuva lukee paidasta.
- [x] Tanakammat mittasuhteet: figure-scale (1.18,1.18,1.18) → (1.28,1.18,1.18) — leveys ylös, korkeus ennallaan (Madden 2000 -stocky; ei-uniformi skaala koko figuurille joten sisäinen geometria/nivelet eivät siirry suhteessa toisiinsa → asennot eivät leikkaa uutta). Kypärä ~8 % isommaksi molemmissa poluissa (kit: helmet-ryhmän scale 1.08; proseduraalinen: (1.0,0.95,1.05)→(1.08,1.03,1.13), facemask skaalautuu kitissä lapsena). BlobShadow 0.42→0.46 leveämmän siluetin alle.
- [x] Taklaustarkkuus: (a) wrap-taklaus — uusi `PlayStep.wraps: [Int]` + `FootballFieldScene.wrapArms`: taklaajan molemmat kädet lyövät eteen-sisään (x −1.25, z ±0.7, kyynärtaive −1.2) osuman alkaessa ja vapautuvat kasan asetuttua; ajetaan "swing"/"bend"-avaimilla joten seuraava snap korvaa saumatta. Kytketty: rush/completion-taklaukset (taklaaja+gang), säkki (rusher), kickoff-palautuksen taklaus. (b) Työntötaklaus — jaettu `PlayChoreographer.tackleSteps`: ~30 % taklauksista kantaja ajautuu 0.5–1 yd taaksepäin (glide-step 0.4 s, molemmat liikkuvat, taklaaja jo wrapissa) ennen kaatumista; gang-pile kohdistuu työnnettyyn pisteeseen. (c) Gang-pile — kaatujat satunnaisiin kulmiin (`fall`: yaw ±0.6 rad random, ennen deterministinen nodeIndex-varianssi) ja porrastettu ylösnousu satunnaisin 0.3–0.7 s välein (`execute`: kumulatiiviset riseDelays käänteisjärjestyksessä — päällimmäinen ensin, ei enää tasatahtia).
- [x] Erotuomari: `buildReferee` — proseduraalinen back judge (raitapaita UIImage-tekstuurilla `refereeStripeTexture` 8px-raidat kapselin ympäri, mustat housut, iho + valkoinen litistetty lippis; hoikempi scale (1.02,1.14,1.02), EI numeroa/varjoa, ei koskaan pelissä). Seisoo ~7 yd hyökkäyksen takana sivussa (x 11) ja liukuu LOS:n mukana: `updateMarkers` sai `offenseDirection`-parametrin (CoachedGameView välittää molemmissa kutsupisteissä; fallback 1st down -viivan suunnasta tai viimeisimmästä tunnetusta) → `moveReferee` glidaa 0.8 s ja kääntää kasvot linjaan. Potkutilanteissa (markerit nil) ref jää paikoilleen.
- [x] Kenttä: turfTexture-sävyt saturoidummiksi (esim. 0.12/0.35/0.13 → 0.11/0.39/0.11, kaikki 4 sävyä) ja mowing-stripe-kontrasti ylös (0.15/0.42/0.15 α0.45 → 0.17/0.49/0.16 α0.55) — lähemmäs PSX-referenssin raidoitusta. EI katsomoita.
- [x] Kamera kauemmas (~15–20 % + korkeutta, coach näkee enemmän kenttää): offense-kehys kamera z-offset 24→29 / h 21→24, target-offset 16→19; defense-kehys 34→39 / 30→33, target 6→7. Pre-snap push-in, defensiveFraming ja kickCamera ennallaan; sumu-/emitterikommentit päivitetty uusiin korkeuksiin.

### Rajaukset
- [ ] Decal-planet ovat litteitä (ei torson kaarevuutta) — tältä kameraetäisyydeltä ero ei lue, ja plane bounding-box-offsetilla välttää z-fightin molemmissa figuuripoluissa.
- [ ] Erotuomari on staattinen hahmo (ei juoksusykliä) — hän vain glidaa uuteen spottiin muodostelmasiirroissa; riittää taustadressingiksi tällä etäisyydellä.
- [ ] Työntötaklauksen 30 % arpoo `Float.random` (ei siemennetty) — puhtaasti visuaalinen haara, ei kosketa simiin/pariteettiin.
- [ ] Silmämääräinen simulaattoriverifiointi jää seuraavaan sessioon — build vihreä, muutokset koodikatselmoitu node-sopimusta vasten (figure/body/arm/leg-nimet ja "swing"/"bend"/"stance"-avaimet säilytetty).

## Sään häivytys: lumi/vesi hienovaraiseksi, tähtitaivas pois (2026-07-09)

### Shipped (BUILD SUCCEEDED, verifioitu simulaattorissa)
- [x] Jättihiutaleet pois kameran vierestä: sade- ja lumiemitterin spawn-slab pudotettu matalaksi (y 4–12, emitterinode y 8, box 70×8×70) — selvästi play-kameroiden (y 21–30) alapuolelle, joten yksikään partikkeli ei synny linssin viereen. `FootballFieldScene.addWeatherEmitter` + `weatherEmitterHeight`-vakio.
- [x] Tähtitaivas pois: (1) slab seuraa kameran fokusta — uusi `moveWeatherEmitter(toZ:animated:duration:)` kutsutaan `focusCamera`sta (clampedZ) ja `kickCamera`sta (sign×30, askel syvemmälle kentälle matalan potkukameran edestä), joten sadetta/lunta on vain ±35 yksikköä pelipaikan ympärillä eikä koko stadionin syvyydeltä horisonttikaistaa vasten; (2) matalan slabin hiutaleet jäävät visuaalisesti kentän takareunan alapuolelle; (3) scene.background sävytetään sumun väriin (`applyFog` asettaa myös `background.contents`) — SceneKit-sumu ei kosketa partikkeleita, joten taustan sävytys on ainoa tapa upottaa kaukaiset hiutaleet taivaaseen.
- [x] Partikkelireseptit alas: lumi birthRate 220→130, lifeSpan 16→8, particleSize 0.18→0.15 (variation 0.05), alpha 0.9→0.62; sade birthRate 400→240, lifeSpan 1.6→0.7, particleSize 0.32→0.2 (variation 0.08), alpha 0.3→0.22. Sama resepti molemmille (sade tarkistettu kooditasolla, lumi silmin).
- [x] Etäisyyssumu sääkohtaiseksi: `applyFog(color:start:end:)`-apuri; clear/wind 70–210 yönsininen (0.03/0.05/0.09), rain 65–180 viileä (0.04/0.06/0.10), snow 62–165 lumisen harmaansininen hehku (0.09/0.11/0.15). Fog alkaa vasta pelialueen takaa (kamera ~35–45 yks. pelistä), joten kenttä ei sumene pelialueella; kaukainen pääty pehmenee ja kuvaan tulee syvyyttä. `setWeather` resetoi sumun ja asettaa säänsä mukaisen; lumihuntu (addSnowBlanket) säilyy ennallaan.
- [x] Silmämääräinen verifiointi simulaattorissa (viikko 9 vs ATL, lumi): 3 iteraatiota screenshotein — v1 (matalampi slab + pienemmät koot) poisti jättipallot, v2 (taustan sävytys) ei vielä riittänyt horisonttikaistan pisteisiin, v3 (fokusta seuraava matala slab) → taivas käytännössä puhdas, lumi erottuu selvästi nurmea vasten, snap → play → uusi tilanne rullasi normaalisti (emitteri seurasi kameraa). Screenshotit scratchpadissa (w2/w4/w5/w6).

### Rajaukset
- [ ] Sadepeliä ei osunut testisessioon (viikon 9 ottelu on deterministisesti lumi) — sade sai täsmälleen saman rakenteellisen korjauksen (slab, seuranta, koot, sumu) ja buildaa vihreänä; silmäys seuraavassa sadepelissä.
- [ ] Kaukana horisontin tuntumassa voi yhä näkyä yksittäisiä himmeitä hiutaleita slabin yläreunasta — tarkoituksellinen jäännös, lukee lumihuuruna eikä tähtinä.

## Play-call flow — sim-verifiointi (2026-07-09)

### Verifioitu simulaattorissa (iPad, build OK, ei committoitu)
- [x] Build vihreä (xcodebuild, scheme dynasty) molemmat vaiheet sisältävällä puulla; asennus + käynnistys + navigointi coached-peliin (Continue Career → Coach the Game, viikko 9 vs ATL home, lumisade) toimi annetuilla koordinaateilla.
- [x] (a) HYÖKKÄYS / 4th down: paneeli VALITSEE eikä commitoi — 4th & 9 own 31: Punt esivalittu, FG-kortti oikein piilossa kantaman ulkopuolella, "Selected: Punt" + SNAP-bar; "Go For It" avasi pelikirjan "‹ 4th Down" -chevronilla; Back palautti erikoisvalintaan valinta säilyttäen; SNAP suoritti puntin (55 yd). Sama flow testattu toisella 4th downilla (own 22, Go For It → pelikirja → medium-heitto).
- [x] (b) PUOLUSTUS: kategoriavälilehdet COVERAGE / PRESSURE / MAN / PACKAGES näkyvät ja selattavissa X&O-kortteineen (Pressure: Zone/Safety/Corner/LB Blitz + uudet Double A-Gap, All-Out; Man: Man Press / Man Free / 2-Man Under lukituslinjoin; Packages: Nickel / Dime / Goal Line / Bear Front dimmed-not-installed-tilassa). EI auto-etenemistä: 12 s odotus ilman kosketusta → kello pysyi 13:38, paneeli ennallaan ("ATL ball — they wait for you"). READY — SNAP ajoi täsmälleen yhden pelin ja jäi taas odottamaan.
- [x] (c) KAKSIPISTEINEN (pelaajan TD): Dixonin 6 yd TD → kuutoset heti taululle (GB 6) → paneeli "Touchdown! Kick the point or go for two?" (Kick XP esivalittu / Go for 2) → Go for 2 → nappi muuttui "CALL THE PLAY" → call sheet 2 jaardin viivalta "‹ Try Options" -chevronilla (Back → paneeli → uudelleen sisään OK) → Inside Run → SNAP → "Marcus Dixon is stopped short on the two-point conversion attempt" → pisteet oikein 6+0, yritys ajaton (kello 12:35 ennen ja jälkeen), kickoff + pallonvaihto normaalisti. Onnistunutta 6+2-tulosta ei osunut tähän sessioon (yksi yritys, ~47 % baseline) — kirjanpito kulkee samaa bookPoints-polkua kuin verifioitu 6+0.
- [x] (c2) AI:n try: ATL:n molemmat TD:t → "Justin Clark kicks the extra point. Good!" automaattisesti (jaettu kaavio, alkupeli → XP) sekä liveissä että Skip Driven sisällä; pisteet 7/14 oikein.
- [x] Pariteettimittaus ajettu: DEBUG-mittausputki (GameSimulator.debugSimulate, n=50) väliaikaisella app-launch-kutsulla (lisätty → ajettu → POISTETTU, puu puhdas): points/team mean 21.6 std 9.3 (haarukka 20–25 OK — 2pt-kaavio ei vääristä), yards/team mean 343, penalties 9.8/game, margin 11.0, schedule integrity 2025–2032 OK. XP-onnistumis-% ennallaan (simulateExtraPoint-polkuun ei koskettu).
- [x] Korjauksia ei tarvittu — ei punaista buildia, ei kaatumisia, ei havaittuja flow-virheitä.

### Auki (pieniä, ei korjattu tässä)
- [ ] FG-kortin valintaa kantaman SISÄLLÄ ei osunut sessioon (molemmat 4th downit omalla kenttäpuoliskolla → kortti oikein piilossa); koodipolku identtinen puntin kanssa (fourthDownChoice-esivalinta canAttemptFieldGoal:lla + snap(forcedType: .fieldGoal)) — verifioitu koodikatselmoinnilla, sim-verifiointi jää seuraavaan FG-etäisyyden 4th downiin.
- [ ] Havainto: J. Love heitti 3 INT:iä ~10 medium/deep-yrityksessä lumisateessa (wet ball -modifierit); juoksupeli kulki 6–8 yd/kanto. Seurataan — jos toistuu selkeällä säällä, pass-INT-painot syyniin.

### Screenshotit (/tmp/snd-screenshots/play-call-flow/)
06_after_play3.png (4th down -paneeli, Punt esivalittu), 07_goforit_playbook.png ("‹ 4th Down" -chevron), 08_back_to_4thdown.png (Back palautti valintaan), 09_defense_panel.png (Coverage-ryhmä + READY-bar), 10_defense_no_autoplay.png (12 s, kello ei liikkunut), 11_defense_pressure.png / 12_defense_man.png / 13_defense_packages.png (uudet pelit korteilla), 14_defense_after_ready.png (READY ajoi yhden pelin), 38_run10.png (TD + XP/2pt-paneeli), 39_gofor2_selected.png (Go for 2 valittu, CALL THE PLAY), 40_2pt_callsheet.png ("‹ Try Options" + muodostelma 2 jaardilta), 41_back_to_try_options.png (Back toimii), 42_2pt_play_selected.png (Inside Run valittu tryyn), 43_2pt_snap_plate.png / 44_2pt_result.png (yritys torjuttu, GB 6, kello 12:35 ajaton, kickoff flippasi pallon).

## Kaksipisteinen: TD:n jälkeinen XP/2pt-valinta + yritys livenä ja quick simissä (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Jaettu AI-päätöskaavio `GameSimulator.shouldGoForTwo(scoreDiffAfterTD:quarter:timeRemaining:)`: 2pt kun Q4 (tai Q3 ≤2:00) ja erotus TD:n kuuden pisteen JÄLKEEN ∈ {−16, −13, −11, −8, −5, −2, +1, +5}; muuten XP. Jaettu suoritusapuri `GameSimulator.rollPointAfterTry(...)` (kaavio + `PlaySimulator.simulateExtraPoint`/`simulateTwoPointConversion`; `forceTwoPoint` ohittaa kaavion pelaajan omalle valinnalle, call/package-biasit tulevat vain live-peleistä) — SAMA apuri molemmissa sim-poluissa → pariteetti.
- [x] `PlaySimulator.simulateTwoPointConversion` uusiksi: baseline 47 % + overall-matchup-etu, clamp 20–75 %; live-shading — syöttöyritys kohtaa coverage+short-coverage+pressure-modifierit ja saa blitzPickup-krediitin, juoksuyritys run-stop-wallin ja runGap-krediitin (dive/sneak voittaa goal linella); eksplisiittinen call päättää run/pass (AI ~60/40); `keyOffensePlayerID` (maalintekijä) talteen koreografiaa varten.
- [x] Quick sim (`GameSimulator.simulate`): jokainen regulation-TD-drive saa ajattoman try-snapin driveen appendattuna ennen kirjanpitoa → pisteet (6+1/6+2/6+0) kulkevat samaa drivePoints-reduce-polkua; myös kotiutettu kickoff-palautus-TD saa tryn (kaavio päättää). Kaavio päättää pelaajan joukkueelle quick-sim-peleissä (speksin kohta 4). OT ennallaan — kumpikaan polku ei tarvitse tryta OT:ssa (sudden death / kuusi ratkaisee).
- [x] `LiveGameEngine`: regulation-scrimmage-TD EI enää sulje drivea heti — `finishOrHoldDrive` kirjaa kuutoset heti tulostaululle (`bookPoints`), pitää driven auki (`pendingConversion`/`pendingConversionDrive`) ja esittää tilanteen 2 jaardin viivalta (yardLine 98, 1st & 2, goal-to-go). `attemptConversion(goForTwo:offensiveCall:defensivePackage:)` ratkoo yrityksen (nil = jaettu kaavio; kello EI kulu), kirjaa try-pisteet ja sulkee driven normaalisti (`finishDrive(scoreAlreadyBooked:)` → kickoff + pallonvaihto kuten ennen). `step()` purkaa odottavan tryn automaattisesti kaaviolla → nil-argumenttipeli (simToEnd/skipDrive) rullaa samat tryt kuin quick sim. Kotiutettu palautus-TD saa auto-tryn kaaviolla (feed-rivi + pisteet). XP:t pois highlight-listoilta molemmissa poluissa (2pt-yritykset jäävät).
- [x] Box score: 2pt ei kirjaudu XP:ksi — `PlayerGameStats`issa ei ole XP-kenttää ja `accumulateStats` ohittaa `extraPointGood/Missed` + `twoPointGood/Failed` (tarkistettu); potkijan FG-statsit eivät liiku. Pisteet vain joukkuetasolle (`pointsScored`-polku).
- [x] UI (`CoachedGameView`): pelaajan TD:n jälkeen post-TD-paneeli samalla korttikielellä kuin onside-valinta — "Kick XP" (+1) / "Go for 2" -kortit, mikään ei snappaa ennen eksplisiittistä nappia; "Go for 2" avaa normaalin call sheetin 2 jaardin viivalta chevron-Back-napilla ("‹ Try Options") takaisin valintaan; spike/kneel piilossa tryn aikana. Onside-kysymys seuraa OMANA paneelinaan heti tryn jälkeisessä kickoffissa (Q4-häviötilanne) — XP/2pt ensin, sitten onside, kuten speksattiin. Vastustajan TD: AI:n XP potkaistaan automaattisesti; jos kaavio vie kahteen, puolustuspaneeli odottaa pelaajan kutsua (ready-barissa keltainen "going for TWO — call your stop") ja READY snappaa puolustuksen yritystä vastaan.
- [x] Presentaatio: snap-plate "2-PT TRY · <PELI>" / "EXTRA POINT"; onnistuneesta 2pt:stä kultainen "TWO-POINT CONVERSION — GOOD!" -plate, epäonnistuneesta "TWO-POINT TRY — NO GOOD"; XP käyttää olemassa olevaa FG-muodostelmaa + kick-kameraa (`playType == .extraPoint` -polut olivat jo koreografiassa). PlayChoreographer: 2pt-try ajaa normaalin scrimmage-koreografian 2 jaardilta — kutsuttu syöttöpeli animoituu heittona (`Context.call` → touchdownSteps passLike), tyrmätty juoksuyritys nielaistaan viivan eteen (rushSteps ~1 yd) incompletion-heiton sijaan. Tulostaulu animoituu 6 → +1/+2 erillisinä (bookPoints TD:llä ja tryllä).

### Rajaukset
- [ ] Kotiutetun kickoff-palautus-TD:n try ratkeaa automaattisesti kaaviolla myös pelaajan joukkueelle (~2 % potkuista; ei valintapaneelia/koreografiaa — feed-rivi ja pisteet kertovat tuloksen).
- [ ] OT:ssa tryta ei yritetä kummassakaan polussa (live-OT on sudden death, quick simin OT ei koskaan tarvitse kahta pistettä tasoitukseen) — tarkoituksella.
- [ ] Quick simin pistetaso nousee ~1 p/TD/joukkue (XP:tä ei aiemmin mallinnettu missään — TD oli 6). Muutos on speksin ydin ja identtinen molemmissa poluissa; jakauman muu muoto ennallaan.
- [ ] Sim to Final kesken pelaajan try-valinnan ratkoo tryn kaaviolla (ei pelaajan keskeneräisellä valinnalla) — johdonmukaista, koska loppusimi on AI-vs-AI.

## Call-sheet 2.0: back-navigointi, puolustuksen rauha + ryhmittely, isompi pelikirja (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] 4th down valinnaksi, ei välittömäksi toiminnoksi (`CoachedGameView.fourthDownPanel`): Punt/FG-kortit vain VALITSEVAT (`fourthDownChoice`, korostus + oletusesivalinta FG jos maalipotku ulottuvilla, muuten punt) ja snap lähtee vasta eksplisiittisestä SNAP-napista; "Go For It" avaa pelikirjan JA hyökkäyspaneeliin tulee chevron-Back-nappi ("‹ 4th Down", sama kapselikieli) jolla pääsee takaisin erikoisvalintaan — mikään ei lukitu ennen snapia (`wentForIt` on peruttavissa).
- [x] Onside-valinta dialogista call-paneeliksi (`kickoffChoicePanel`): Kick Deep / Onside Kick -kortit valitaan vapaasti (ei tap-ulkopuolelle-commitointia, ei ajastinta) ja potku lähtee vasta KICK-napista; confirmationDialog poistettu (`awaitingKickoffDecision` + `onsideSelected`).
- [x] Puolustuksen rauha: vastustajan hyökkäys EI enää snappaa ajastimella (`proceed()`-defense-haara ei aikatauluta `runPlay`ta) — joukkueet ryhmittyvät (`syncFieldToSituation`) ja peli odottaa "READY — SNAP" -nappia puolustuspaneelin snap-barissa ("PLAY IS LIVE…" + disabled animaation ajan). Skip Drive säilyy pikakelauksena.
- [x] Puolustuksen ryhmittely kuten hyökkäyksessä: `DefensiveCall` sai `category`-jaon COVERAGE / PRESSURE / MAN / PACKAGES + samat kapselivälilehdet (`defenseCategoryTab`), installed-first-järjestys schemen mukaan, kuvaus + X&O-kortti jokaisella.
- [x] Puolustuspelikirja 10 → 19 kutsua: Cover 1, Cover 4 Match, Prevent, Double A-Gap, Safety Blitz, Man Free, 2-Man Under, Nickel, Dime, Bear Front (+ vanhat). Uudet `DefensivePlayCall`-dimensiot: coverage .cover1/.prevent, blitz .doubleAGap/.safetyBlitz, front .bear modifiereineen; PREVENT saa syvyyspainotetun coveragen (`deepCoverageModifier +0.14` / `shortCoverageModifier −0.08` → `DefensivePackage.totalDeep/ShortCoverageModifier`, PlaySimulatorin syöttöpolku soveltaa VAIN kun package != nil → quick sim -pariteetti ennallaan). PlayChoreographer: bear-front-, cover1-/prevent-shell- ja doubleAGap-/safetyBlitz-pre-snap-lookit; DefenseDiagramView: single-high-dome (Cover 1), prevent-sateenvarjo, A-gap- ja safety-blitz-nuolet, `manUnder`-lukituslinjat Man-kategorialle.
- [x] Hyökkäyspelikirja +6 peliä olemassa oleviin kategorioihin: Goal Line Dive, Jet Sweep (Run), Stick, Mesh (Short), Wheel (Medium), Play Action Deep (Deep) — kaikilla blurb, scheme-jäsenyys, SimulatorHint (esim. dive runGap +0.28/yac 0.7; PA deep blitzPickup −0.15/yac 1.15), X&O-kortti (PlayDiagramView) ja formaatiomappaus (PlayChoreographer: dive→I-form, jetSweep→outside-look, stick/mesh→quick-game, PA deep→spread). MatchupResolver: dive lisätty interior-POA-listaan.
- [x] AI-puolustuskutsut käyttävät uusia pelejä tilannepainoin (`LiveGameEngine.aiDefensivePackage`): Q4 ≤4:00 johdossa 1–16 pist. ja kenttä >25 yd → PREVENT+dime; lyhyt yardage → BEAR-front cover 1; blitzFrequency >0.85 → Double A-Gap (ei koskaan prevent-shellin päälle). Red zone/3rd&long ennallaan.

### Rajaukset
- [ ] Quick sim (GameSimulator) ei mallinna puolustuskutsuja per snap — uudet kutsut vaikuttavat vain live-peleihin (nil-package-pariteetti säilytetty tarkoituksella, ks. PARITEETTI-sääntö); user-todon "molemmissa sim-poluissa" toteutettiin siis vain live-polkuun.
- [ ] Legacy PlayCallView (MatchView-polku) näyttää uudet DefensivePlayCall-dimensiot automaattisesti sarakkeissaan, mutta sen kolmen sarakkeen mix-and-match-UI:ta ei uudistettu — coached-pelin call sheet on ensisijainen flow.
- [x] TD:n jälkeinen 1 vs 2 pisteen valinta ei kuulunut tähän vaiheeseen — toteutettu seuraavassa vaiheessa (ks. "Kaksipisteinen"-osio ylhäällä).

## User todos — play-call flow (2026-07-09, jonossa)
- [x] Back-nappi pelivalintaan: 4th downin "Go for it" -valinnasta takaisin FG/punt-valintaan; sama kaikkiin lukittuviin valintapolkuihin (onside-dialogi, call-sheet-kategoriat)
- [x] Puolustusvalinta liian nopea — sama rauha kuin hyökkäysvalintaan (ei aikapainetta, snap vasta vahvistuksesta)
- [x] Puolustuspelit ryhmiteltävä call-sheetiin kategorioittain kuten hyökkäyspelit
- [x] Lisää pelejä pelikirjaan (Cover-variantit, zone blitzit, nickel/dime, prevent; AI käyttää samoin painoin molemmissa sim-poluissa) — HUOM: AI käyttää uusia kutsuja live-polussa; quick sim ei mallinna puolustuskutsuja per snap (pariteettisääntö), joten sen jakauma pidettiin ennallaan
- [x] TD:n jälkeen valinta 1 vai 2 pisteen yrityksestä + 2 pisteen yrityksen toteutus (pelaaja kutsuu pelin 2 jaardin viivalta; quick simiin AI-päätöskaavio) — ks. "Kaksipisteinen"-osio ylhäällä

## 3D Visual Upgrade + In-Game Management — sim-verifiointi (2026-07-09)

### Verifioitu simulaattorissa (iPad Pro 13" M5, build OK, ei committoitu)
- [x] Build vihreä (xcodebuild, scheme dynasty) ja PlayerKit.usdc mukana app-bundlessa; asennus + käynnistys + navigointi coached-peliin (Continue Career → Coach the Game, viikko 8 @ CHI) toimi annetuilla koordinaateilla.
- [x] (a) Pelaajahahmot: Blender-kypärät facemaskeineen, hartiasuojat ja pallo näkyvät (palloa kantava palauttaja #30 kickoffissa, pallo maassa/pelaajalla play-frameissa); joukkuevärit oikein — GB vieraissa valkoinen/kulta, CHI poltettu oranssi (primary navy hylätään tarkoituksella liian tummana yökenttää vasten → secondary C83803, TeamColors.fieldSafePrimary); numerot lukevat billboard-teksteinä molemmilla joukkueilla.
- [x] (b) Hyökkäyskehys: oma ryhmitys ruudun alaosassa (OL+QB #19+RB), puolustus LOS:n takana, kenttä edessä; SNAP-nappi toimi — pelianimaatio pyörii ("Play is live…", syöttö + juoksu + taklaus-anim downfieldissä, kamera seuraa palloa; 18 yd pass Terrell Washingtonille verifioitu).
- [x] (c) Puolustuskehys (puntin jälkeen CHI ball): muodostelma ruudun yläkolmanneksessa, oma kenttä täyttää kuvan — ei 60 jaardia tyhjää; stance-kortit (Cover 3 / Cover 2 Shell / Quarters / Man Press / LB Blitz) + Skip Drive näkyvissä.
- [x] (d) Manage-sheet: avautuu situationStripin Manage-napista; statsit, OVR, fatigue-palkit ja forme-nuolet näkyvät (Offense/Defense-segmentit, positioryhmäkortit); vaihto tehty (I. King in for M. Dixon RB-rivin inline-penkkilistasta + confirmationDialog) → pending-chip sheetissä (PENDING · AT NEXT WHISTLE) JA yläpalkissa (Sub at next whistle) → seuraavan snapin jälkeen feed "Sub: I. King in for M. Dixon" ja #36 kentällä #34:n tilalla.
- [x] Korjattu: sateen partikkelit renderöityivät jättimäisinä sumeina pylväinä kameran lähellä (particleSize 0.55 + stretchFactor 0.12 × velocity 24 ≈ 3 m -viirut) → FootballFieldScene.rainSystem(): particleSize 0.32, sizeVariation 0.12, stretchFactor 0.06, alpha 0.3; rebuild + reinstall → sade ohuita luettavia viiruja, slabit poissa.
- [x] Bonus-havainnot okeina: 4th down -päätöspaneeli (Punt/Go For It), FLAG-holding-toast, matchup-callout ("D. Foster beats D. Davis around the edge"), 1ST & 10 -plate, timeout/TO-chipit.

### Auki (pieniä, ei korjattu tässä)
- [ ] resultBanner-toast (kiinteä .padding(.bottom, 352), hit-testing pois) osuu hetkellisesti pelikorttien/4th down -nappien päälle — kosmeettinen, poistuu 2,6 s:ssa eikä estä syötteitä; jos halutaan siistiä, bottom-padding dynaamiseksi alapaneelin korkeuden mukaan.
- [ ] Yksittäinen puolustaja renderöityi yhdessä framessa vaaleanpunertavana additiivisen sadepartikkelin osuessa kohdalle — sadefixin pitäisi käytännössä poistaa tämä; seurataan.

### Screenshotit (/tmp/snd-screenshots/visual-upgrade/)
01_main_menu.png, 02_career_hub.png, 03_coached_game_start.png, 04_after_stance.png, 04b_presnap_crop.png, 05_snap_t1–t3.png, 06_after_play.png, 07_manage_sheet.png, 08_manage_expanded.png, 09_manage_sub_made.png, 10_manage_pending.png, 11_after_sub_play.png, 12_drive_progress.png, 13_defense_frame.png, 14_rain_fixed_game.png, 14b_ball_closeup.png

## Pelinaikainen pelaajahallinta: statsit, kunto, vaihdot (FM-tyyli) (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Engine-API (`LiveGameEngine`): (a) `benchPlayers(forHome:position:)` — rosterin terveet pelaajat jotka eivät ole kummassakaan kenttäyksikössä, per positioryhmä (`LineupGroup`-enum: QB/RB/WR/TE/OL/DL/LB/DB/ST; nimi LineupGroup koska RosterView varasi jo PositionGroupin), OVR-järjestyksessä; (b) `substitute(benchPlayerID:forFieldPlayerID:)` — validoi (sama positioryhmä, penkkimies terve eikä kentällä, kohde pelaajan yksikössä) ja JONOTTAA vaihdon `pendingSubstitutions`-listaan; toteutus seuraavassa kuolleessa pallossa (`step()`-defer → `applyPendingSubstitutions`) R16:n korvausmekanismilla: `manuallyBenchedIDs` → `sidelinedIDs` → `rebuildFieldUnits()` + role-slot-override (`manualOffenseOverrides`/`manualDefenseOverrides` säilyvät vamma/rotaatio-rebuildien yli) → numerot päivittyvät seuraavassa ryhmityksessä automaattisesti; feed-rivi "Sub: X in for Y" (vain playLog, EI drivetuloksiin → ei stats-vaikutusta); `cancelSubstitution(id:)` perumiseen; (c) `liveLine(for:)` — per-pelaaja live-rivi statsAccumulatorista (passing/rushing/receiving/tackles+sacks, vain kertyneet kategoriat) + fatigue + morale + matchupWins/Losses. VAIN pelaajan joukkueelle.
- [x] Sim-integriteetti: `simAvailablePlayers` — manuaalisesti hallitun positioryhmän penkkimiehet piilotetaan similtä (`overrideShadowedIDs`), jotta PlaySimulatorin best-at-position-valinnat (QB/RB/targetit) osuvat kentällä oleviin miehiin (esim. QB3 sisään → sim käyttää QB3:a eikä QB2:ta). Turvaventtiilit: alle 11 pelaajan fallback; `releaseManualBenchIfNeeded` vapauttaa penkitetyn jos vammat jättävät hänen positionsa ilman muuta tervettä miestä; RB-autorotaatio väistyy kun valmentaja on itse vaihtanut RB-slotin (`manualOffenseOverrides[1]`); loukkaantunut sisääntulija pudottaa overriden → rebuildin paras-saatavilla täyttää aukon (FieldUnit = totuus, speksin kohta 4). Nil-pariteetti: kaikki uusi on no-op ilman vaihtoja — AI ei koskaan vaihda.
- [x] UI: situationStripiin "Manage"-nappi (Stats-viereen, person.2.fill) + warning-chip "Sub at next whistle" kun jono ei ole tyhjä → uusi `UI/Match/InGameManagementView.swift` (sheet, sisältö max 640 pt): Offense/Defense-kapselisegmentti, positioryhmäkortit (QUARTERBACKS/BACKFIELD/…); rivi = #numero+nimi+positiotagi, OVR, fatigue-palkki (success <40 / warning 40–69 / danger ≥70), live-statsirivi ("12/18 · 145 YDS · 1 TD | 3 CAR…"), W-L-matchupit (vihreä/punainen), forme-nuoli (morale+freshness-komposiitti: ≥65 ylös / ≤45 alas / muuten vaaka). Kenttärivin tap → penkkiehdokkaat inline (sama ryhmä, OVR+fatigue) → confirmationDialog → pending-chip riville + PENDING-kortti (peruutus-x). Vaihdot disabloitu kun peli pyörii (`subsDisabled = isAnimating || isGameOver`, "Play is live…" -note) eikä vastustajaa näytetä.
- [x] Tyyli: sama tumma korttikieli kuin LiveBoxScoreSheet — Theme-tokenit (backgroundPrimary/Tertiary, accentGold, success/warning/danger, textPrimary/Secondary/Tertiary, `.cardBackground()`), ei uusia värejä.

### Rajaukset
- [ ] Vaihto toteutuu seuraavan pelatun pelin JÄLKEEN (vihellys) — kuolleessa pallossa jonotettu vaihto ei ehdi saman snapin ryhmitykseen (speksin "Sub at next whistle" -chip kertoo tämän käyttäjälle).
- [ ] Manuaalivaihdon jälkeen simin skill-valinnat rajautuvat hallitun ryhmän osalta kentällisiin (shadow-mekanismi) — pieni ero baseline-simiin, mutta vain käyttäjän omasta vaihdosta seuraava ja pitää animaation/statsit/feedin samassa todellisuudessa.
- [ ] Erikoisryhmät (K/P) eivät ole hallittavissa — kenttäyksiköissä ei ole K/P-slotteja.

## Liike & kamera: Madden-tason liikevaikutelma coach-näkymään (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Pre-snap-asennot: `stanceCrouchIndices` (bool-crouch) → `PlayChoreographer.stances(offenseIsHome:)` + `FootballFieldScene.Stance`-enum (threePoint/twoPoint/split/upright). OL/DL/TE syvä 3-point (figure pitch 0.62 + sink −0.17, oikea käsi maahan armR x 0.95, vapaa käsi polvelle, jalat porrastettu ja ladattu), RB/LB/S 2-point (pitch 0.3, kädet polvia kohti kyynärtaipeella), WR/CB pysty split (etujalka edessä, kevyt noja). Roolit node-indeksisopimuksesta; QB jää pystyyn (upright puuttuvana avaimena, ja upright-asento resetoi aiemman asennon kaikilta muilta, mm. kickoff-ryhmityksissä). Purku snapissa: raaja-poseet ajetaan samoilla "swing"/"bend"-avaimilla joita juoksusykli käyttää → `swingLimbs` korvaa ne saumatta, ja `run()` poistaa figure-tason "stance"-actionin lähtiessä (myös `resetGait` siivoaa).
- [x] Juoksusykli: `swingLimbs` nopeusskaalattu — askeltiheys `strideTime(forSpeed:)` (0.16–0.34 s/sykli, nopeampi juoksu = tiheämmät askeleet; bob synkattu samaan sykliin) ja heilahduslaajuus 0.45–0.8 rad nopeuden mukaan. Eteenpäinnojaus skaalautuu ~8–12,6° (figure x 0.14–0.22 rad), palautuu pysähtyessä (straighten ennallaan). Kevyt ylävartalon vastakierto: "body"-node ±0.1 rad y-oskilaatio jalkasyklin tahtiin ("twist"-avain, neutraaliin lopussa, resetGait resetoi). Suunnanmuutos-bank: run() laskee käännöksen (yaw-delta normalisoituna) ENNEN facing-rotaatiota; > 0.6 rad käännös play-stepissä kallistaa figuren hetkellisesti käännöksen sisään (z ≤ 0.32 rad, vapautus 0.3 s) — yksi kirjoittaja figure-eulereille (bank osana gait-sekvenssiä, ei kilpailevaa actionia).
- [x] QB dropback: `PlayStep.backpedals: [Int]` — merkityt siirrot ajetaan peruuttaen: node EI käänny liikesuuntaan (facing säilyy alalinjaan), kevyt takanoja (x −0.1), lyhyt tasainen askellus (stride 0.3, swing 0.4). Käytössä QB:llä completion/incompletion/sack/interception-skriptien dropback-stepeissä (0.8–0.9 s ≈ 3 askelta); heitto käy kuten ennen (`runBallArc` → `throwMotion`).
- [x] Kamera: (a) pre-snap push-in — `focusCamera(pushIn: true)` ajaa framing-siirron jälkeen hitaan ~2 jaardin dollyn kohti LOSia (2,5 s, easeInEaseOut, kevyt −0.4 lasku) "pushIn"-avaimella; keskeytyy snapissa (`runPlay` poistaa actionin), uudella focuksella ja kickCameralla, ja seuraava absoluuttinen focus-move korjaa kertyneen offsetin. Kutsutaan runPlayn pre-snapissa ja syncFieldToSituationissa (pelinvalinnan aikana). (b) Seurantakameran pehmennys: refocus per step → `followCamera(toZ:stepDuration:)` — kesto max(step, 0.7 + 0.03×panoroitava matka, katto 1.7 s) eli lyhyet hypähdykset saavat suhteessa pidemmän eased-liikkeen eikä kamera nyi. defensiveFraming- ja kickCamera-logiikka ennallaan.
- [x] Viimeistely: TD-juhlinta — `PlayStep.celebrates` + `celebrationJump` (skoraaja hyppää 0.85 yd kädet ylhäällä, mob-step + toinen pulssi + pallon spike-kaari maahan kuten ennen); myös kickoff-palautus-TD juhlii. Gang-tackle-kasa purkautuu porrastetusti: falls kaatuvat listajärjestyksessä (0.12 s välein) ja nousevat käänteisessä — päällimmäinen (viimeisenä kaatunut) ensin (`fall(getUpDelay:)` 0.22 s/porras).

### Rajaukset
- [ ] Bank-kallistus vain play-stepeissä (formation-siirrot eivät kallistele) ja vain ≥ 0.6 rad käännöksissä — pienet driftit eivät heilauta.
- [ ] Ei muutoksia LiveGameEngineen/GameSimulatoriin — puhtaasti presentaatiota (choreografia + scene).
- [ ] 3-pointin käsi ei osu pikselintarkasti maahan joka figuurivariantilla — asento luetaan kameraetäisyydeltä silhuettina (pitch+sink+käsi alas), sama kompromissi kuin vanhassa crouchissa.

## 3D-asset-integraatio: Blender-osat pelaajahahmoihin ja palloon (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] PlayerKit.usdc bundleen: kopioitu `dynasty/dynasty/Resources/PlayerKit.usdc` (file-system synced group vei sen resurssiksi automaattisesti — varmistettu DerivedDatan .app-paketista, tiedosto bundlen juuressa). Lataus `Bundle.main.url(forResource:)` + `SCNScene(url:)`.
- [x] Generaattorikorjaus: `player_kit.py` export ei vienyt FOOTBALL_LACES-lasta (`selected_objects_only` ei valinnut parentoituja lapsia) → lapset mukaan valintaan ja kit ajettu uudelleen Blenderillä; laces (LACES-materiaali) nyt FOOTBALL-noden lapsena.
- [x] Kit-loader `FootballFieldScene`en: `static let playerKit` lataa scenen kerran, poimii 9 osaa nimillä ja rakentaa niistä prototyypit. USD tuo meshit Blender-akseleissa (Z-up, +Y-etu) -90° X-juurirotaation alla, ja `flattenedClone()` palauttaa USD-mesheille tyhjän geometrian (todettu macOS-SceneKit-testillä) → prototyyppi on nimetty kontti, jonka sisempi "orient"-node bakettaa akselikäännön (euler ZYX = Ry(π)·Rx(-π/2): mesh (x,y,z)→(-x,z,y), kasvot +Z:aan). Kloonaus `instantiate(_:name:retint:)`: `clone()` jakaa vertex-datan, ja re-tint-osille `SCNGeometry.copy()` (jakaa edelleen sourcet) + per-figuuri-materiaalit.
- [x] `makePlayerNode` → kit-haara `buildKitFigure` + fallback `buildProceduralFigure` (vanha koodi siirretty sellaisenaan, EI poistettu). Samat node-nimet ja nivelpisteet: kit-raajojen origo on segmentin YLÄPÄÄSSÄ, joten vanhat pivotit korvautuvat suoraan node-positioilla — leg/legR (THIGH) hip-saranassa (±0.14, 0.12, 0), shin (SHIN) polvessa (0, −0.51, 0) = sama maailmasarana kuin vanhan kapselin pivot, CLEAT shinin lapsena nilkassa, body (TORSO) (0, 0.42, 0), arm/armR (UPPER_ARM) (±0.38, 0.76, 0) + lepokulma z ∓0.25, forearm (FOREARM) kyynärpäässä (0, −0.42, 0) + lepo x −0.15. Pää-sphere jää kypärän sisään ja näkyy kasvoaukosta; helmet = HELMET_SHELL + FACEMASK yhdessä "helmet"-ryhmänoden alla (0, 1.04, 0). Numero-billboard ja blobShadow ennallaan.
- [x] Väripolku: `applyUniform` uusiksi materiaalislottien nimillä (JERSEY/PANTS/HELMET; SKIN/MASK/SHOE ei kosketa) — enumeroi hierarkian, joten sama koodi tintaa sekä kit- että proseduraalifiguurit (fallback-materiaaleille lisätty samat nimet). Per-figuuri kloonatut slot-materiaalit (torso + molemmat olkavarret jakavat yhden JERSEY-kopion; SKIN per pelinumero kuten ennen) → home/away-re-tint ja `setUniforms` toimivat ilman vuotoa joukkueiden välillä.
- [x] Pallo: `buildBall` → FOOTBALL-prototyyppi nauhoineen, uniformi 2× skaala (half-length 0.34 / r 0.19 ≈ vanha ellipsoidi). Pituusakseli = Z kuten ennen → syöttöspiraali (`rotateBy z`) pyörii nimenomaan pituusakselin ympäri ja potkut tumblaavat end-over-end (`rotateBy x`) prolaattimuodolla; lento/kanto/spin-koodiin ei tarvittu muutoksia. Proseduraalinen pallo jäi fallbackiksi.
- [x] Suorituskyky: kaikki 22 hahmoa jakavat prototyyppien vertex-datan (clone/geometry.copy), MASK/SHOE/BALL/LACES jakavat myös materiaalit; ~1 050 trik./hahmo → ~23 k trik. koko kentälliselle, draw call -määrä ~sama kuin proseduraalisella (13 vs 12 geometrianodea/hahmo).
- [x] Verifiointi: macOS-SceneKit-dumppi (node-nimet, materiaalinimet, bboxit — raajaorigot yläpäässä ✓) + offscreen-renderi bundlesta ladatulla kitillä: kypärä+maski kasvot +Z ✓, juoksuasento (swingLimbs-kulmat käsin: polvi/kyynärtaive taipuvat saranasta oikein) ✓, home/away-tintit ja ihonsävyt erillään ✓, pallo nauhat ylöspäin ✓. Animaatiokoodin katselmointi: swingLimbs/reach/fall/throwMotion/resetGait/crouch-stance hakevat nodet nimillä figure-tasolta ja asettavat vain euler-kulmia → toimivat kit-figuurilla muuttumattomina ("orient"-node ei ole animaatioiden tiellä).

### Left out (perustelut)
- [ ] Laitteella ajettu FPS-mittaus — arvio koodista riittää speksin mukaan (23 k kolmiota on murto-osa SceneKitin budjetista tällä kameralla); ei simulaattoriajoa tässä vaiheessa.
- [ ] `env_light`/textures-viite USD:ssä — Blenderin world-dome vientiartefakti; ei käytetä (osat poimitaan nimillä), eikä puuttuva exr estä latausta (todettu bundle-kopiolla). Voi siivota generaattorista jatkossa.
- [ ] Kit-osien LOD/varjogeometria — ei tarvetta tällä etäisyydellä; blobShadow hoitaa ankkuroinnin kuten ennenkin.

## Round 25: Persoonat & pukuhuone — kemiat, konfliktit, viikkotapahtumat (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Persoonallisuudet: EI uutta järjestelmää — pelaajilla on jo persistoitu `PlayerPersonality` (9 arkkityyppiä + motivaatio), joten speksin "deterministinen persoona" täyttyy olemassa olevalla datalla. Uutta: trait-badge rosteririville (`PlayerRowView` statusbadge-riviin `archetype.shortLabel` tier-värillä: positive=vihreä, risky=keltainen, neutral=harmaa); pelaajakortissa arkkityyppi näkyi jo ennestään (PlayerDetailView Personality-osio).
- [x] Kemiat (`LockerRoomEngine`-laajennus, ei duplikointia): `activeMentorships` — Mentor/Team Leader -veteraani (4+ v, leadership ≥ 65) + nuorin saman position pelaaja (≤ 2 v) pariutuvat, yksi protégé/mentori; `activeConflicts` — (1) kaksi hothead-arkkityyppiä (Fiery/Drama) samassa positioryhmässä joista väh. yksi turhautunut (morale < 65), (2) tähti+tähti SAMALLA positiolla (molemmat ≥ 82 OVR, ero ≤ 2 → ei selvää ykköstä); `positionGroupChemistry` — per positioryhmä good/neutral/tense-tuomio (konflikti tai avg morale < 45 = tense; mentorointi tai avg ≥ 70 = good).
- [x] Mentoroinnin kehitysbonus: `PlayerDevelopmentEngine.applyGameExperience` sai `experienceBoost`-parametrin (clamp 0.9–1.1 = speksin max ±10 %); WeekAdvancerin viikkokokemus-loop antaa aktiivisen mentoroinnin protégéille ×1.1 XP:n koko liigassa (symmetrinen ja selitettävä — AI-joukkueiden mentorit toimivat samoin). Offseason-`applyMentoring` ennallaan.
- [x] Viikkotapahtumat: `LockerRoomEngine.rollWeeklyEvent` (25 % viikoista, vain käyttäjän joukkue kuten EventEnginessäkin) — painotettu pooli persoonista+moralesta+tuloksista: tappio + turhautunut hothead → pukukoppiryöpytys (VALINTA: Step In = kohde −2 / tiimi +2 vs Let It Play Out = kohde +1 / tiimi −3); voitto + Team Leader → players-only meeting (auto: leader +3, tiimi +2); mentori + nuori → mentor moment (auto: protégé +3); tähtikonflikti → Tension in the Room (VALINTA: Define Roles vs Let Them Compete); Class Clown tappion jälkeen → mood lift (auto). Kaikki morale-deltat ≤ 5.
- [x] Persistointi kevytmigraatiolla: `Career.lockerRoomLogData/pendingLockerRoomEventData: Data? = nil` + JSON-sillat (`lockerRoomLog` max 12, `pendingLockerRoomEvent`), uusi Codable-malli `Domain/Models/League/LockerRoomEvent.swift` (+ optiot). WeekAdvancer `processLockerRoomWeek`: viikon yli vastaamatta jäänyt valintatapahtuma resolvautuu itsestään passiivisella optiolla (reagoimattomuuskin on päätös), vain yksi avoin tilanne kerrallaan, jokainen tapahtuma tuottaa inbox-viestin (OC/DC lähettäjänä, valintatapahtumissa actionRequired + deeplink Locker Roomiin).
- [x] Pukuhuonenäkymä: olemassa oleva `LockerRoomView` laajennettu (ei uutta näkymää): pending-tapahtumakortti valintanappeineen ja delta-pillereineen ylimpänä (resolve → morale-efektit + loki + save), positioryhmäriveihin Good/Neutral/Tense-kemiabadge enginestä, uusi "Mentorships & Conflicts" -kortti (mentoriparit +10 % XP -selitteellä, konfliktiparit syineen), "Recent Events" näyttää nyt persistoidun viikkolokin viikkoleimoin (fallback vanhoihin laskennallisiin kemianotteisiin).

### Left out (perustelut)
- [ ] Kapteenivalinnat — speksin rajaus (SquadDynamicsView'n heuristinen "Team Captain" -näyttö ennallaan).
- [ ] Media-persoonat ja presser-kytkökset — speksin rajaus, PressConferenceEngineen ei koskettu.
- [ ] Sopimustyytymättömyyskytkös — speksin rajaus (R22-holdoutit hoitavat; holdout-pelaajat on rajattu mentor/protégé-pareista ja outburst-kohteista pois päällekkäisyyden välttämiseksi).
- [ ] Uusi persoona-taksonomia (Leader/Hothead/Free Spirit...) — olemassa olevat 9 arkkityyppiä kattavat samat roolit (teamLeader≈Leader, fieryCompetitor≈Hothead, loneWolf≈Free Spirit); rinnakkaisen luokittelun johtaminen player.id:stä olisi rikkonut "laajenna, älä duplikoi" -sääntöä.
- [ ] `weeklyMoraleUpdate`/`applyMoraleEffects`-dead coden kytkentä viikkorytmiin — jätetty tekemättä: koko rosterin viikoittainen morale-heilunta olisi muuttanut quick sim -pariteettia (mood-dependent-sakot GameSimulatorissa) selvästi speksin tapahtumapohjaista ±5-vaikutusta laajemmin. Viikkotapahtumat käyttävät samoja morale-mekanismeja pistemäisesti.
- [ ] Konflikteille ei automaattista viikkosakkoa — konfliktit vaikuttavat vain tapahtumien kautta (pelaaja näkee ja voi reagoida); jatkuva näkymätön drain olisi vaikeasti selitettävä.
- [ ] Simulaattoriverifiointi — vihreä buildi + logiikkakatselmointi (tapahtumat vaativat runkosarjaviikkojen pelaamista).

## Round 24: Draft-huone 2.0 — trade up/down, war room, AI-draft, UDFA (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Pick-kaupat draftin sisällä: uusi `Engine/Draft/DraftDayTradeEngine.swift` — kaikki arvotus R21:n `TradeValueEngine.pickTradeValue`-käyrillä (JJ-chart, EI rinnakkaista arvologiikkaa). `PickSwapOffer` viittaa OIKEISIIN kuluvan draftin `DraftPick`-riveihin molemmin puolin → hyväksyntä = `currentTeamID`-flip + save, ja draft jatkuu oikeassa järjestyksessä uusilla omistajilla. Paketinrakennus: partnerin aikaisin myöhempi pick ankkurina + halvimmat sweetenerit jotka kurovat chart-arvon umpeen (max 3 pickiä, 98–145 % käyttäjän pickin arvosta = klassinen move-up-preemio).
- [x] AI-trade-up pelaajan pickiin: kun käyttäjä on 1–3 pickin päässä vuorostaan (~20 % portti/pick), AI-joukkue joka omistaa myöhemmän pickin (slide 2–24) JA himoitsee julkisen boardin top-6-prospektia top-3-tarvepositioonsa tarjoutuu nousemaan käyttäjän pickiin — motiivi kerrotaan bannerissa ("SEA want to jump up to #14 — targeting a QB"). Decline muistetaan per pick (ei nagailua). Vanha Vaihe 3 -placeholder-flow (TradeEvaluator + feikki-tulevaisuuspick jota ei koskaan siirretty = ilmaista arvoa) korvattiin kokonaan tällä.
- [x] Trade down -nappi: PickSheetView'n toimintorivissä, yksi haku per pick (`requestTradeDown`). Halukkuus per kandidaatti: ~65 % jos top-8-board-prospekti istuu kandidaatin top-3-tarpeeseen, ~20 % muuten, +5 %/liukuva top-lahjakkuus (max +15 %) — eli todennäköisyys kasvaa kun hyviä nimiä on jäljellä, ja syy näkyy motiivitekstissä. Ei halukkaita → selkeä feedback-viesti. Tarjous renderöityy myös sheetin SISÄLLÄ (päänäkymän banneri jää modalin alle); hyväksytty trade down vaihtaa kellotetun pickin AI:lle ja flow jatkuu välittömästi (`beginCurrentPick`).
- [x] TradeOfferBanner: arvoyhteenvetorivi ("you send X pts · receive Y pts") + pick-labelit kierroksineen; DraftDayView kytketty uuteen `pendingPickOffer`-flowhun, stale-tarjoukset vanhenevat automaattisesti kun assetit draftataan/vaihtavat omistajaa (`isOfferStillValid` joka pickin alussa).
- [x] War Room 2.0 (`WarRoomPanel.swift` uusiksi): (1) "Your Picks" -kortti — ON THE CLOCK / seuraava vuoro ("Next: R3 · #78 — 12 picks away") + edellinen oma pick gradella; (2) "Best Available" — top-10 jäljellä olevaa OMAN scout-graden mukaan (`effectiveOverallGrade.midGrade`, EI koskaan piilo-OVR; skouttaamattomat pohjalle), NEEDS-suodatin (teamNeedScores ≥ 0.5), trendinuoli olemassa olevasta `stockTrajectory`-datasta, SLEEPER-badge vain scoutatuista signaaleista (nouseva trendi + oma grade ≥ B- + julkinen konsensus ≥ 12 sijaa skeptisempi kuin oma skouttaus — piilo-OVR ei vuoda); (3) draft capital -pistekortti ennallaan; (4) Trade Radar elää: pöydällä oleva tarjous motiiveineen tai max 2 potentiaalista trade-down-partneria (joukkue + pick + positio jota kyttäävät).
- [x] AI-draft-logiikka: `DraftEngine.aiMakePick` oli jo tarve+arvo-painotettu mutta deterministinen argmax → nyt painotettu arvonta top-4:stä (65/20/10/5 %) — pienet reachit/steali säilyttävät yllätykset, scoring-logiikka ennallaan ja selitettävä. Koskee sekä live-draftia että quick sim -polkuja (sama funktio).
- [x] UDFA-vaihe draftin päätteeksi: `mode == .complete` → uusi `UI/Draft/Components/DraftUDFAPanel.swift` — vasemmalla oma draft-luokka gradeineen (draft-yhteenveto), oikealla undrafted-pooli AIDOSTI draftaamatta jääneistä (availableProspects; scout-grade-järjestys, trendinuolet, NEED-badget, ei piilo-OVR:ää). Käyttäjä signaa max 5 halvoilla 1–2 v / $450–750K diileillä (uusi `DraftEngine.convertUDFAToPlayer` — rookie-käyrän pohjapää, ei draftPickNumberia; cap-käyttö päivittyy). "Finish" → AI-joukkueet round-robinaavat parhaat loput (~10/joukkue) ja koko ikkuna suljetaan (`isDeclaringForDraft = false` kaikille käsitellyille → persistoituu).
- [x] Tuplasignausten esto: `WeekAdvancer.udfaStageCompletedSeasons` + .otas-vaiheen vanha bulk-UDFA-blokki skippaa kun interaktiivinen vaihe hoiti markkinan; fallback säilyy ennallaan jos draft quick-simmataan ilman Draft Day -näkymää. Kokonaan pelattu draft ei myöskään enää lataudu `.preDraft`-tilaan uudelleen avattaessa (aiemmin olisi alkanut draftata valmiita pickejä alusta) vaan suoraan UDFA/yhteenveto-tilaan.

### Left out (perustelut)
- [ ] Draft-kello/aikapaine trade-päätöksiin — speksin rajaus; olemassa oleva pick-kello ennallaan.
- [ ] Pelaajakaupat kesken draftin — speksin rajaus, vain pick-kaupat.
- [ ] Draft-day-media — speksin rajaus.
- [ ] Tulevien vuosien pickit draft-paketeissa — kuluvan draftin `DraftPick`-rivit ovat ainoat olemassa olevat (WeekAdvancer generoi poolin vain currentSeasonille), joten future-pickit olisivat vaatineet pick-poolin elinkaariremontin; rajattu pois ja kaikki paketit rakennetaan oikeista jäljellä olevista pickeistä. Sopii jatkokierrokseen (sama pohja kuin R23:n comp-pick-havainto pick-poolin alkuperästä).
- [ ] TradeEvaluator/GM-persoonat draft-tarjousten portteina — R21:n TradeValueEngine-käyrät + eksplisiittiset halukkuustodennäköisyydet ajavat saman asian selitettävämmin; TradeEvaluator jää ennalleen muiden käyttöjen varalta.
- [ ] Simulaattoriverifiointi — vihreä buildi + logiikkakatselmointi (draft-vaiheeseen pääsy vaatii offseason-pelitilan).

## Round 23: Free agency -syvennys — tampering-huhut, vierailut, interest meter, comp picks (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Tampering-ikkuna: uusi `Engine/FreeAgency/TamperingRumorEngine.swift` — FA-vaiheeseen siirryttäessä (WeekAdvancerin `nextPhase == .freeAgency` -reset-kohta) generoidaan top-8 tulevan FA:n huhut: hintaprojektio SAMASTA mallista jota markkina käyttää (uusi jaettu `FreeAgencyEngine.projectedAskingPrice` = estimateMarketValue × motivaatiokerroin; generateFreeAgentMarket refaktoroitu käyttämään samaa), kiinnostuneet joukkueet samasta need-mallista (`assessPositionNeed` critical/high + cap-riittävyys, max 3 abbrs) ja motivaatioblurbi. Ulostulot: "League Insider" -inbox-digest + 3 NewsItem-huhua ("Sources: X expected to command $YM per year; DEN and NYJ reported interested"). UI: FinalPushView'hun "Legal Tampering Buzz" -kortti (omat päättyvät pelaajat kullalla + YOURS-badge — näkee kilpailutilanteen ennen re-sign-päätöksiä).
- [x] Vierailut: `Career.faVisitsUsed: Int = 0` (default-arvo → kevyt migraatio; reset FA-vaiheen alussa), max 3/FA-vaihe. FAWeeklyView'n FA-riviin "Host Visit" -nappi (headerissa "Visits left: X/3") — vierailu persistoi olemassa olevan `FAVisit`-mallin rivin (48h, .active; ruokkii samalla BiddingHeatEnginen heat/ticker-logiikkaa), kuluttaa slotin ja avaa uuden `UI/FreeAgency/FAVisitResultSheet.swift` -tulosdialogin: paljastaa todelliset prioriteetit (motivaatioajuri selityksineen, PlayerPreferenceEnginen piilotetut preference-tagit revealLabel/ikoni/selite-copyllä, rooliodotus omaa rosteria vasten) + interest-mittarilukeman visit-boostilla. Signaus meille merkitsee vierailun .converted-tilaan.
- [x] Interest meter: uusi `Engine/FreeAgency/SigningInterestEngine.swift` — 0–1-lukema + 5 tieria (Cold→Scorching) neljästä tekijästä motivaatiopainoin: raha vs pyyntihinta (tarjouksesta), joukkueen viime kauden voittoprosentti (recordit nollautuvat vasta seuraavan runkosarjan alussa → FA:ssa validi), rooli (`roleScore`: oma OVR vs paras saman positioryhmän pelaaja rosterissa — selkeä starttipaikka 1.0 … hautautunut 0.15) ja scheme-fit (olemassa oleva `CoachingEngine.schemeFit` OC/DC/HC-skeemoilla kun saatavilla, muuten neutraali) + visit-boost +0.12. UI: FAOfferSheetiin live-päivittyvä "Signing Interest" -kortti (gradient-mittari + tekijärivit selitteineen, jaettu `InterestMeterBar`), FA-riviin interest-chip kun tarjous jätetty tai vierailu isännöity.
- [x] AI-signauslogiikka samoilla tekijöillä: `resolvePlayerDecision` sai `allPlayers`/`userTeamID`/`hostedVisit`-parametrit — roolikerroin KAIKILLE bideille (stats-motivaatio ±15 %, muut ±6 %; AI-joukkueiden rosterit mukaan lukien) ja visit-boost ×1.15 käyttäjän tarjoukselle; `simulateAIFreeAgency` (skip/fallback-polku, aiemmin puhtaasti cap-järjestys + random) järjestää nyt ehdokkaat position tarpeen mukaan (critical > high > moderate) kun rosteridata annettu.
- [x] Comp picks: uusi `Engine/Contract/CompensatoryPickEngine.swift` + WeekAdvancer-kytkennät. Departure-ledger (UserDefaults, FASigningTracker-kuvio) kirjaa VAIN sopimuksen umpeutumiset (viikon 18 vanheneminen + executeNewLeagueYear; cutit eivät koskaan kirjaudu). FA-vaiheesta poistuttaessa `settleCompensatoryPicks`: yksinkertaistettu NFL-kaava — kvalifioituva CFA = umpeutunut sopimus + signaus MUUALLE ≥ 0,6 % capista; nettomenetykset = menetykset − hankinnat (kpl); max 4 pickiä/joukkue kalleimmista menetyksistä; kierros UUDEN sopimuksen palkasta % capista (≥5,0 % → R3, ≥3,5 % → R4, ≥2,25 % → R5, ≥1,25 % → R6, ≥0,6 % → R7). Pickit luodaan R21:ssä käytetyllä DraftPick-mallilla ja sijoitetaan kierroksen loppuun koko poolin uudelleennumeroinnilla: suoraan persistoituun tulevaan pooliin jos sellainen on (≥32 keskeneräistä pickiä), muuten pending-varastoon joka puretaan draft-orderin generointikohdassa (case .draft). Inbox-viesti käyttäjän saaliista ("Round 4 — for losing X") + uutinen liigan suurimmasta comp-haalarista. FACompleteView'n "Expected Compensatory Picks" -estimaatti vaihdettu heuristiikasta (value-delta/5000k) oikean kaavan projektioon (`projectedAwards`) — näyttö vastaa nyt täsmälleen myönnettävää.

### Left out
- [ ] Monipäiväinen FA-aaltorakenne — EI TARVITTU: nykyflow on jo monikierroksinen (Day 1–3, Week 2–4), speksin ohje "älä riko olemassa olevaa" täyttyi sellaisenaan.
- [ ] RFA/ERFA-tenderit — speksin mukaisesti rajattu pois.
- [ ] `DraftPick.isCompensatory`-lippu + "COMP"-badge draft-order-näkymiin — jätetty pois jotta DraftPick-malliin ei kosketa; comp-pickit erottuvat inbox/news-kautta ja istuvat kierrosten hännille numeroinnin puolesta. Sopii jatkokierrokseen.
- [ ] VisitTrackerin reaaliaikaiset rajat (1/pv, 3/vko rullaava) eivät koske käyttäjän R23-vierailuja — speksin raja on 3/FA-vaihe vuoropohjaisesti (`Career.faVisitsUsed`); FAVisit-rivit persistoituvat silti ja ruokkivat heat/ticker-järjestelmiä.
- [ ] Ledger on UserDefaults-pohjainen eli laitekohtainen, ei per-career (sama tunnettu rajoite kuin FASigningTracker/NegotiationLockRegistry R22:ssa).
- [ ] Havainto (ei korjattu, ei R23-scopea): WeekAdvancer generoi draft-orderin `case .draft` -haarassa eli draft-VAIHEESTA POISTUTTAESSA, mutta DraftDayCoordinator lukee pickit vaiheen AIKANA — kausi 2+:n pick-poolin alkuperä näyttää epäselvältä (mahdollinen off-by-one seasonYear-tagissa). Comp-pickit kytkettiin molempiin putkiin (persistoitu pooli + generointikohta), joten ne seuraavat peruspickejä kumpi tahansa on totuus.
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi (FA-vaiheeseen pääsy vaatii offseason-pelitilan; kierroksen säännöt sallivat tyytyä buildiin).

## Round 22: Sopimusneuvottelut 2.0 — agenttipersoonat, holdoutit, franchise tag (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Agenttipersoonat: uusi `Engine/Contract/AgentPersona.swift` — deterministinen persoona pelaajan UUID:sta (GameWeather.forGame-kuvio, tavut 8–15, EI hashValue; ei uusia SwiftData-kenttiä): hardliner 30 % / cooperative 40 % / loyalist 30 % + deterministinen agentin nimi 24 nimen poolista (tavut 0–7). Persoona-API: `demandFactor` (avauspyyntö ±10–15 %: hardliner ×1.13, cooperative ×0.90 floor 1.0×market, loyalist ×0.97), `maxRounds` (kärsivällisyys 2/4/3 kierrosta), `lowballCutoff`, `reSignThresholdShift`, tyylilabel + kuvaus + SF-symboli.
- [x] Neuvottelukierrokset: `ContractNegotiationEngine` päivitetty — avauspyyntö skaalautuu persoonalla, loyalist painottaa `loyaltyYears` (+1 %/v max +9 % extensioissa), kävely `roundNumber >= persona.maxRounds`, persoonakohtaiset perusteluviestit ("X wants starter money" / "He took a discount to stay"). Uusi `NegotiationOutcome.negotiationsBrokenOff`: liian matala tarjous (effectiveRatio < 0.72) hardlinerille katkaisee neuvottelut koko offseasoniksi — persistoituu `NegotiationLockRegistry`-rekisteriin (UserDefaults; nollataan `WeekAdvancer.startNewSeason`issa). ContractNegotiationView näyttää agentin nimen + tyylichipin headerissa ja chat-kuplissa, estää lukitun pelaajan neuvottelun avauksen ("not returning your calls").
- [x] Final Push -re-sign-flow parannettu (ei rinnakkaista uutta): agenttichip per pelaajakortti, tarjouskierroslaskuri (`PlayerDecisionState.offerRounds`) — agentin kärsivällisyyden ylitys hylkää, hardlinerin lowball (< 60 % markkinasta) katkaisee puheet offseasoniksi (uusi `ReSignResponse.brokenOff` + lukko + "isn't returning your calls" -tila kortissa), hyväksymiskynnys elää persoonalla (`reSignThresholdShift`), vastatarjousperustelut persoonan mukaan.
- [x] Holdout: `Player.isHoldingOut: Bool = false` (default-arvo → kevyt migraatio) + `Holdout.weeksActive: Int = 0` + uusi `HoldoutResolution.playerCaved`. `HoldoutEngine.detectStarHoldoutCandidates` — tähti (OVR ≥ 85 TAI joukkueen top-3) jolla sopimus päättymässä (1 v jäljellä) TAI selvästi alipalkattu (< 85 % markkinasta, yearsPro ≥ 3; rookie-diilit eivät laukaise), tagatut/loukkaantuneet pois, suurin palkkakuoppa ensin. Käynnistys OTAs-vaiheeseen tullessa (CareerShellView; aiempi trainingCamp-trigger siirretty), persoona määrää todennäköisyyden (hardliner 65 % / loyalist 30 % / cooperative 15 %), max yksi aktiivinen kerrallaan. Holdoutin aikana pelaaja EI pelaa (GameSimulator + LiveGameEngine suodattavat `isHoldingOut` roster-snapshotista), EI kehity (game experience-, scheme learning-, fatigue-, injury- ja trainingCamp `processOffseason` -suodattimet WeekAdvancerissa) ja joukkuekaverit −1 morale/vko, holdouttaaja −2.
- [x] Holdout-draama & sovinto: WeekAdvancerin viikkotikki (`processHoldoutWeek`) — agentin eskalaatioviestit inboxiin (playerAgent-lähettäjä agentin oikealla nimellä), pelaaja taipuu ~viikolla 3–4 (50 % vko 3, varmasti vko 4: morale −10, `playerCaved`, inbox + negatiivinen uutinen), sovinto auto-resolvaa jos GM korjasi rahat (palkka ≥ 95 % markkinasta tai 2+ sopimusvuotta) → positiivinen uutinen. HoldoutDialogin `.extend` maksaa nyt oikeasti (palkka → markkina-arvo, ≥ 3 v, cap-delta ei-sandboxissa, morale +10) ettei sama tähti triggeröidy uudelleen heti; rosterlistaan "Holdout"-badge (PlayerRowView).
- [x] Franchise tag: morale −10 tagatessa (`ContractEngine.applyFranchiseTag` molemmat cap-mode-polut; poisto palauttaa +10) ja tag-toiminto suoraan re-sign-näkymään — FinalPushView:n pelaajakorttiin "Tag ($X)" -nappi (top-5 palkkojen keskiarvo positiolle liigadatasta, sama laskenta kuin FranchiseTagView; 1/offseason, piilotettu kun käytetty; sandbox = $0). Tagattu pelaaja ei holdouttaa (detektori ohittaa).
- [x] Pariteetti/AI: AI-joukkueiden re-sign-mekanismi (FreeAgencyEngine) täysin koskematon; holdoutit ja tagit vain käyttäjän joukkueelle; quick sim -polut muuttuvat vain aktiivisen holdoutin osalta (speksin mukaista).

### Left out
- [ ] Monivuotiset bonus-rakenteet ja incentive-lausekkeet — speksin mukaisesti rajattu pois.
- [ ] AI-joukkueiden holdoutit ja franchise tagit — speksi rajaa AI:n nykymekanismiin; lisäys muuttaisi simulaatiopariteettia.
- [ ] ContractExtensionSheet (PlayerContractView/FreeAgencyView-polku) ei saanut persoonakäsittelyä — se on yksinkertaistettu kertatarjouslomake ilman kierroksia; persoona elää chat-neuvottelussa (PlayerDetailView) ja Final Pushissa. Sopii jatkokierrokseen.
- [ ] HoldoutDialog ei avaudu uudelleen jos käyttäjä sulkee sen resolvoimatta — draama jatkuu viikkotikillä ja ratkeaa taipumiseen/sovintoon; erillinen "aktiivinen holdout" -paneeli dashboardille sopisi jatkokierrokseen.
- [ ] Neuvottelulukon UserDefaults-toteutus ei ole per-career (usean tallennuksen rinnakkaiskäytössä lukko jaettu) — nollautuu joka kauden alussa; Career-kenttä olisi siistimpi jos multi-save-tuki laajenee.

## Round 21: Kauppajärjestelmä — AI-tarjoukset, arvokäyrät, deadline-draama (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Arvokäyrät: uusi `Engine/Contract/TradeValueEngine.swift` (nimi TradeValueEngine, koska `TradeEngine` on jo olemassa samassa hakemistossa) — pelaajan kauppa-arvo Jimmy Johnson -pisteskaalalla: eksponentiaalinen OVR-käyrä `32 × 1.128^(OVR−60)` (75 OVR ≈ 194 pts, 90 ≈ 1188, 99 ≈ 3510 eli yli #1-varauksen), positiokerroin (QB 1.3 … RB 0.85 … K/P 0.5), positiokohtainen ikäkäyrä (RB romahtaa 26+ −16 %/v, QB kestää 33:een −7 %/v; nuoruuspreemio ≤ 24 v) ja sopimuskerroin (halpa pitkä diili +5 %/v max +20 %, päättyvä "rental" ×0.85, ylihinnoiteltu ×0.8). Pick-arvot: olemassa oleva `PickValueChart` × 0.8^(vuotta tulevaisuuteen). Pickit oli jo mallinnettu per joukkue (`DraftPick.currentTeamID`) — uutta pick-mallia ei tarvittu.
- [x] AI-kauppatarjoukset viikoittain: WeekAdvancer heittää ~15 % nopan viikoilla 1–8; contender (voitot−tappiot ≥ 2) OSTAA käyttäjän hyvän pelaajan (OVR ≥ 74, AI:n top-need-positio, ei koskaan käyttäjän ainoaa QB:tä) pickeillä + tarvittaessa täytepelaajalla; rebuilder (tappiot−voitot ≥ 2) MYY veteraanin (28+, 75+ OVR) käyttäjän need-positioon ja pyytää pickejä. Tarjoukset persistoidaan `Career.pendingTradeOffersData` (uusi optionaalinen Data-kenttä + Codable-silta → kevyt migraatio, sama konventio kuin gamePlanData) ja saapuvat inbox-viestinä (Pro Personnel, actionRequired, linkki Trade Centeriin). Tarjoukset erääntyvät deadlinellä ja nollataan uuden kauden alussa; TradeView karsii tarjoukset joiden assetit ovat ehtineet liikkua (`isProposalStillValid`).
- [x] Pelaajan aloittamat kaupat: olemassa oleva TradeView ("Trade Center", navigointi dashboard-tiilestä ja shell-destinaatiosta säilyi) päivitettiin uusiin käyriin — 5-portainen vastapuolen verdict ilman tarkkoja lukuja ("They love it" / "They like it" / "They're on the fence" / "They'll want more" / "They'll hang up", need-adjustoitu vastapuolen silmin), assetrivien arvot pisteinä (myös ikä + sopimusselite breakdownissa), willingness-rivi johdettu samasta verdictistä kuin oikea vastaus (ennuste = lopputulos).
- [x] Neuvottelu: `TradeValueEngine.respond` — AI hyväksyy kun saa ≥ 105 % antamastaan (need-preemio +15 % tarvepositioiden tulokkaille), hylkää < 90 %, välillä 90–105 % rakentaa deterministisen vastatarjouksen (pyytää lisäpickin joka kattaa vajeen TAI vetää pienimmän oman assetin pois diilistä); vastatarjous esiladataan trade-builderiin. Saapuvissa tarjouksissa uusi "Negotiate"-nappi esilataa tarjouksen builderiin muokattavaksi. AI ei koskaan myy ainoaa QB:tään (selitettävä hylkäysviesti).
- [x] Validointi & toteutus: `validationErrors` — rosterikoot (40–75 molemmille), cap-tarkistus CapMode huomioiden (sandbox ohittaa; simple/realistic: kummankin joukkueen uusi cap-käyttö ≤ salaryCap) sekä propose- että accept-poluissa; kauppaikkuna `isTradeWindowOpen` (regular season viikkoon 8 asti + offseason-vaiheet; kiinni playoffs/proBowl/superBowl) — TradeView-gating päivitetty (aiemmin auki koko runkosarjan, ei offseasonissa). Toteutunut kauppa kirjaa inbox-viestin (league office) molemmista suunnista `onInboxMessage`-callbackilla shellin inboxiin.
- [x] Deadline-draama: viikon 8 päätteeksi (olemassa oleva deadline-tägäyskohta WeekAdvancerissa) 2–4 AI-vs-AI-kauppaa — rebuilder myy veteraanin contenderille pickeistä, arvosuhde validoitu 0.85–1.2× + samat roster/cap-tarkistukset, siirrot toteutetaan oikeasti (TradeEngine.executeTrade; pick-omistuksen paikallinen kirjanpito pitää peräkkäiset diilit koherentteina, max yksi splash per ostaja). Jokaisesta kaupasta NewsItem (.trade) ja koko päivästä league officen "Trade Deadline Day" -inbox-kooste.
- [x] Tehtäväintegraatio: CareerShellView:n `hasPendingTradeOffers` kytketty oikeaan dataan (`!career.pendingTradeOffers.isEmpty`) — TaskGeneratorin deadline-tehtävät reagoivat nyt oikeisiin tarjouksiin (vanha TODO-kommentti poistettu).

### Left out
- [ ] Monen joukkueen kaupat, ehdolliset pickit, no-trade-lausekkeet — speksin mukaisesti rajattu pois.
- [ ] Vanhan `TradeEngine.generateAITradeOffers`/`aiWouldAccept`-polun poisto — jätetty paikoilleen (ei enää kutsuta TradeViewistä), poisto olisi kosmeettinen refaktorointi ja kasvattaisi riskiä committoimattoman R15–R20-työn päällä.
- [ ] Dashboardin trade-tiilen "Trade window open" -teksti on staattinen eikä seuraa uutta ikkunalogiikkaa — itse Trade Center näyttää suljetun tilan oikein; tiilen dynaaminen teksti sopii seuraavaan UI-kierrokseen.
- [ ] Pysyvä kauppahistoria yli sessioiden (CompletedTrade on edelleen @State) — vaatisi oman SwiftData-mallin; session sisäinen historia + inbox-kirjaukset kattavat kierroksen speksin.
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi; deadline-polun ajaminen vaatisi 8 viikon pelitilan advancea.

## Round 20: Persona-auditin UI-siivous (2026-07-09)

### Shipped (BUILD SUCCEEDED)
Puhtaasti visuaaliset/copy-korjaukset persona-auditin Fix-riveihin. 40 riviä käsitelty: 26 toteutettu tällä kierroksella, 13 todennettu jo-korjatuiksi aiemmilla kierroksilla (#112–#123 ym.), 1 jätetty väliin. Yksityiskohtaiset kuittaukset kunkin näytön omassa auditointiosiossa alempana (R20-sulkuselitteet).

- [x] [MainMenu] 4 toteutettu (tagline-kontrasti+varjo, bottom padding 16→36, sekundäärinappien tumma pohja + vahvempi stroke, kultamonogrammi wordmarkin ylle) + 5 todennettu jo-korjatuiksi (Continue/Load, footer, yläscrim, How to Play -toiminnot, titteliladder) — MainMenuView.swift
- [x] [TeamSelection] 2 toteutettu (3-portainen situaatioväripaletti kaikkiin kolmeen situationColor-kohtaan; AFC/NFC-togglen joukkuemäärächipit) + 5 todennettu jo-korjatuiksi (#115/#117: rivitiheys, tier-label-duplikaatti, sarakeotsikot, hero-rajaus, filter-palkki) — TeamSelectionView.swift
- [x] [TeamDetail] 7 toteutettu (logon kehystys, "CAREER DIFFICULTY" -skaalalabel, vaikeuden perustelucaption, väriyhtenäistys 3-tierillä, statsRow'n promootio + 24pt-arvot, coaching-budjetin liigakeskiarvo, rivaalien Roster OVR) — TeamSelectionView.swift (TeamDetailSheet)
- [x] [PressConfIntro] 7 toteutettu (subtitle/caption-kontrasti, suuntavinjetti + kirkkaampi kuva, eyebrow-hierarkia, isompi CTA, yläscrim, titteliblokin nosto ~15 %, mikin drop-shadow) — PressConferenceView.swift
- [x] [PressConfQ1] 8 toteutettu (stats-stripin "CURRENT STANDING" -subhead, effects-selitteen koko/kontrasti, 12/13pt-deltapillit, vaaleampi virhepunainen negatiiveille, ikoni/delta-värierottelu, outlet-duplikaatin korvaus sävypillillä, sävyaksenttipalkit vastauskortteihin, reporter/kysymys-korttien erottelu) + 1 todennettu jo-korjatuksi (segmentoitu progress-palkki) — PressConferenceView.swift

### Left out
- [ ] [MainMenu] Hero-kuvan korvaus key artilla — vaatii uuden taideassetin, ei koodikorjaus.
- [ ] Kaikki "Game:"- ja "Bug:"-rivit näillä näytöillä — kierrosspeksi rajasi vain Fix-alkuisiin visuaali/copy-korjauksiin.
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi (kierroksen säännöt sallivat; New Career -polku ja presser vaativat pelitilan alusta).

## Round 19: Kausi-integraatio ja panokset (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Dashboard] Panosrivi regularSeasonHeroCardiin — `computeSeasonStakes` (CareerDashboardView, ajetaan loadAllDatassa StandingsCalculatorin tuloksista) tuottaa `SeasonStakes`-rivin VAIN kun väite on todistettavasti tosi pelkistä voittomääristä: (1) "Win clinches the NFC North" — olen divisioonajohtaja, yksikään kilpailija ei yllä voitollani syntyvään voittosaldoon edes voittamalla kaikki loput pelinsä, eikä divari ole jo varmistettu (voiton pitää oikeasti merkitä); (2) "Division lead on the line vs CHI" — viikon vastustaja on divisioonarivaali täsmälleen samalla W-L-saldolla ja olemme divarin kärkikaksikko (voittaja yksin kärkeen); (3) "Must win to stay in the hunt" — tappio jättäisi kattoni (wins + jäljellä) alle lähimmän playoff-maalin (divisioonajohtaja tai seed 7) NYKYISEN voittomäärän, voitto pitää sen ulottuvilla. Konservatiivisuusvartijat: vain viikko ≥ 10, vain regularSeason/tradeDeadline, vain kun oma peli pelaamatta tällä viikolla, tasapelit missä tahansa relevantissa recordissa ⇒ ei riviä. UI: liekki-/varoituskapseli otsikon alla (kulta; must-win punaisella).
- [x] Feature: [Coach Mode] Playoff-kehystys — CoachedGameView sai `isPlayoff: Bool = false` -parametrin (dashboard välittää `session.game.isPlayoff`): kultainen "PLAYOFFS"-badge tulostaulun kellon alle, "WIN OR GO HOME" -plate (trophy-ikoni, possession-bannerin visuaalinen kieli, 3,4 s) kentän ylle avauspotkussa, final-overlayn tuomio playoff-pelissä "Advancing, coach." / "Season over." (`finalVerdictText`). Puhdasta presentaatiota — engine ei koskaan lue lippua.
- [x] Feature: [Coach Mode] Divisioonapelit — `isDivisionGame` (Team.conference+division-vertailu): pieni "DIVISION"-chip tulostaulun keskelle kellon alle (playoff-badge ohittaa sen kun molemmat pätevät — playoff-peli divarivastustajaa vastaan lukee PLAYOFFS).
- [x] Feature: [Presser] Divisioonavariantit R18:n faktamekanismiin — `GameFacts.divisionOpponentAbbr` (uusi kenttä, default nil ⇒ vanhat kutsujat ennallaan; WeekAdvancer.pressGameFacts päättelee sen boxScoren joukkue-id:istä + teamsByID-divarivertailusta). Voittokysymys vaihtuu "A win over CHI inside the division..."-varianttiin ja tappiokysymys "Losing to CHI hurts twice..."-varianttiin (3 sävyvastausta kummassakin, samat PressEffects-haarukat kuin olemassa olevissa); niukan tappion R18-kysymys säilyttää etusijan divisioonatappioon nähden.

### Left out
- [ ] Playoff-kaavion parannus (kohta 4) — playoff-bracket-NÄKYMÄÄ ei ole olemassa: dashboardin playoffBracketTile on pelkkä staattinen tiili joka linkittää StandingsViewiin, eikä playoff-Game-rivejä edes generoida kantaan (advancePlayoffWeek hakee isPlayoff-pelejä joita mikään ei luo). Kierrossääntö kieltää uuden näkymän rakentamisen tässä kierroksessa — raportoitu.
- [ ] Wild card -panoslause ("Win clinches a wild card spot") — seed 5-7 -klinssin todistaminen vaatisi täyden usean joukkueen tiebreaker-simuloinnin; konservatiivisuusvaatimus (mieluummin ei riviä kuin väärä rivi) rajasi divisioonapohjaisiin väitteisiin + seed-7-kattoon must-winissä.
- [ ] Playoff-kehystyksen näkyminen pelissä — playoff-pelejä ei nykyisellään voi coachata koska playoff-Game-rivejä ei luoda eikä playoffsHeroCardissa ole Coach the Game -nappia; kehystys on valmiina ja aktivoituu heti kun playoff-pelit generoidaan (session.game.isPlayoff kulkee jo läpi).
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi (panosrivi vaatii pelitilan viikolla ≥ 10 sopivalla sarjataulukolla; kierroksen säännöt sallivat tyytyä buildiin).

## Round 18: Kehitys ja narratiivi coached-peleistä (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Engine] Matchup-moraali pelin päättyessä — `LiveGameEngine.applyMatchupMorale()` (kutsutaan kerran `persist`istä, joka ajetaan VAIN pelaajan omista coached-peleistä): R14:n matchup-tallyt (`matchupWins`/`matchupLosses`) puretaan pelaajan joukkueen live-Player-malleihin `livePlayerByID`-write-backissä. Top-3 battle-voittajaa (wins desc, losses asc — sama järjestys kuin `topPerformers`) saavat morale +3 (clamp 1...100, sama raja kuin LockerRoomEnginessä); 2+ häviötä ILMAN vähintään yhtä montaa voittoa keränneet −1 (top-3-nostetut eivät koskaan saa samalla miinusta). AI-vastustaja ja quick-sim-joukkueet koskemattomia — auto-sim-pariteetti ennallaan.
- [x] Decision: [Engine] Ei XP-tickiä — `PlayerDevelopmentEngine` ei tarjoa per-peli-XP/progression-apia: `applyGameExperience` on kausitason API jonka gain pyöristyy nollaan yhdellä pelillä (gamesFactor 1/17 ⇒ 0 pistettä), joten speksin ohjeen mukaan vaikutus on pelkkä moraali.
- [x] Feature: [Engine] Merkkipaalubannerit — `LiveGameEngine.MilestoneEvent` + `@Published lastMilestones`: `finishDrive` kutsuu `publishMilestones()` heti `accumulateStats`in perään (statsit päivittyvät per drive ⇒ drive-granulariteetti on tarkin totuudenmukainen hetki). Kynnykset: 100 juoksujaardia, 100 vastaanottojaardia, 300 syöttöjaardia; `announcedMilestones`-avainsetti ("playerID|kind") takaa että kukin paalu laukeaa kerran per peli. Molempien joukkueiden pelaajat (broadcast-tyyli). Puhtaasti presentaatiota — sim ei koskaan lue.
- [x] Feature: [UI] Kultainen milestone-banneri — CoachedGameView: `.onChange(of: engine.lastMilestones)` näyttää "MILESTONE: M. Dixon — 100 rushing yards" -kapselin (star.fill, Color.accentGold-tausta, backgroundPrimary-teksti) bannerpinossa injury-bannerin ja result-bannerin välissä; useampi samalla drivellä porrastetaan 3,4 s välein, näkyvissä 3,2 s.
- [x] Feature: [Presser] Faktapohjaiset kysymykset — `PressConferenceEngine.GameFacts` (won/margin/sacksAllowed/100yd-juoksija) + `generateWeeklyPressConference(facts:)`-parametri (default nil = täsmälleen vanha valinta, preview-kutsu ennallaan). Kolme uutta varianttia jotka valitaan VAIN ehdon täyttyessä: (1) tappio ≤ 3 pisteellä → "A N-point loss that came down to the final possession..." post-loss-kysymyksen tilalle; (2) ≥ 4 sallittua säkkiä → "Your line gave up N sacks — is protection a concern?" tilannekysymyksen slottiin; (3) oman joukkueen 100 jaardin juoksija → "X ran for N yards — is he your workhorse now?". Sävyvastaukset (3 kpl/kysymys) samalla PressResponse/PressEffects-rakenteella ja samoissa vaikutushaarukoissa kuin olemassa olevat.
- [x] Feature: [Wiring] `WeekAdvancer.pressGameFacts` tislaa faktat `lastPlayerGameResult`ista (toimii sekä quick-sim- että live-coached-polulla — molemmat jättävät tuloksensa samaan staattiin): joukkuejäsenyys ratkaistaan live-rostereista koska PlayerGameStats ei kanna team-id:tä; sacksAllowed = vastustajan puolustajien sacks-summa (0.5-osuudet summautuvat oikein), 100yd-juoksija = oman rosterin max rushingYards ≥ 100.

### Left out
- [ ] XP/progression-tick matchup-voittajille — PlayerDevelopmentEnginessä ei ole per-peli-apia (ks. Decision yllä); uuden XP-järjestelmän rakentaminen ei kuulunut kierroksen speksiin.
- [ ] Milestone-banneri quick-sim-peleihin / GameSummaryyn — speksi rajasi bannerit live-näkymään (CoachedGameView).
- [ ] Presser-viittaus vastustajan tähtipelaajaan tai puolustuksen säkkeihin — speksin kolme varianttia (säkit sallittu, 100yd-juoksija, niukka tappio) toteutettu; lisävariantit paisuttaisivat kierrosta.
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi (milestonen/presserin ehdot vaativat täyden pelin pelaamisen ja sopivan tilastojakauman; kierroksen säännöt sallivat tyytyä buildiin).

## Round 17: Puoliaika-analyysi ja valmentajan työkalut (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Engine] `halftimePending`-lippu — `LiveGameEngine.endRegulationDrive` nostaa @Published-lipun täsmälleen kerran, samassa `quarter == 3` -haarassa jossa halftime-recovery ja R12:n aikalisäreset jo tapahtuvat (⇒ reset ja overlay ovat luonnostaan synkassa, molemmat tasan kerran per peli). Engine ei koskaan blokkaa lippuun — `simToEnd`/nil-parametripeli ajaa suoraan läpi ja nollaa lipun lopuksi (auto-sim-pariteetti GameSimulator.simulaten kanssa säilyy).
- [x] Feature: [Engine] `HalftimeAdjustment`-enum (3 valintaa) + uusi `PlaySimulator.Adjustments`-struct (sackChanceReduction / completionBonus / runYardageBonus): "Tighten Pass Protection" → sack-todennäköisyys −0.05, "Attack Their Corners" → completion +0.03, "Commit to the Run" → juoksujaardit +0.5. `step()` soveltaa valintaa VAIN pelaajan joukkueen hyökkäyspeleihin kun `quarter >= 3`; `resolveHalftime(choosing:)` lukitsee valinnan (nil = ei muutosta). AI ei koskaan valitse ⇒ nil-parametripariteetti ennallaan.
- [x] Feature: [Engine] 1. puoliskon battle-keräys — `firstHalfMatchupEvents` kerää Q1–Q2-pelien `lastMatchups.events`-rivit (cap 30 kpl); `topFirstHalfMatchupEvents(limit: 3)` järjestää star > bust > decisive (magnitude-laskeva) halftime-korttia varten. Puhtaasti presentaatiota, ei feedbackiä simiin.
- [x] Feature: [UI] `HalftimeView.swift` (uusi) — koko ruudun halftime-raportti: HALFTIME-badge, 1. puoliskon pistetaulu per neljännes (Q1/Q2/T, pelaajan joukkue kullalla), molempien total yards (StatComparisonRow), "Battles of the Half" top-3 (star/bust/normal-ikonein) ja kolmen säätökortin valitsin (ikoni + nimi + coach-speak-blurbi, toggle-valinta, valinta valinnainen) + "Continue to 2nd Half" -nappi.
- [x] Feature: [UI] CoachedGameView-integraatio — `proceed()` pysähtyy `engine.halftimePending`-lippuun ENNEN pending-kickoffin kulutusta ja näyttää overlayn; jatka-nappi kutsuu `resolveHalftime` → banneri valitusta säädöstä → proceed ajaa 2. puoliskon avauspotkun. `skipDrive` pysähtyy myös halftimeen (ei ohita raporttia kun vastustajan drive päättää puoliskon); `simToEnd` ohittaa raportin tarkoituksella ja nollaa lipun.
- [x] Feature: [UI] 2 min drill -presentaatio — tulostaulun kello pulssaa punaisena (Color.danger + phaseAnimator-opacity/scale-pulssi) kun Q2/Q4 ja timeRemaining ≤ 120; situationStripiin "2-MINUTE WARNING" -chip (danger, scale+opacity-transitio, 5 s) kerran per puolisko (`twoMinuteWarnedQuarters`-setti).
- [x] Verify: [R12-yhteispeli] Aikalisäreset ja halftime-overlay laukeavat samasta kertaluonteisesta quarter==3-siirtymästä — reset tasan kerran, aikalisiä ei toteutettu uudelleen; timeout-pipit näyttävät restockin overlayn sulkeuduttua.

### Left out
- [ ] Puolustuksen halftime-säädöt — speksin 3 korttia ovat hyökkäyspainotteisia; puolustussäätö vaatisi vastaavan Adjustments-laajennuksen defense-polkuun (ei speksissä).
- [ ] OT-kello ei pulssaa — speksi rajasi 2 min drillin Q2/Q4:ään.
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi (halftimeen pääsy vaatii ~puolen pelin pelaamisen livenä; kierroksen säännöt sallivat tyytyä buildiin).

## Round 16: Vammat ja rotaatio live-peleissä (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Live] Per-play-vammat — `LiveGameEngine.rollInjuries(for:)`: joka kontaktipelillä (juoksut/sackit/kompletit; TD:llä vain kantaja, ei taklaajaa) vammanoppa kantajalle (keyOffensePlayerID) ja yhdelle taklaajalle (juoksuilla front seven -rooli 0–6, syötöillä LB/DB 4–10, sackeissa pass rusher 0–3). Riskikaava peilaa `MedicalEngine.injuryCheck`iä (fatigue-, durability- ja team doctor -modifierit) per-play-skaalattuna: base 0,3 %/osallistuminen — ~45 kantaja- + ~45 taklaajakontaktia/joukkue/peli ⇒ sama odotusarvo kuin quick simin viikkorullassa (53 pelaajaa × 0,5 % base).
- [x] Feature: [Live] Vammautunut poistuu kentältä — `injuredPlayerIDs` pois sekä PlaySimulatorille annettavista rostereista (`availablePlayers`, sim valitsee aidosti seuraavan RB/WR:n) että FieldUniteista (`rebuildFieldUnits` = sama best-at-position-valinta kuin avauksessa ⇒ korvaaja on seuraavaksi paras samalta positiolta). Safety valve: ei koskaan alle 12 pelaajan rosteria. `lastPlayInjuries: [LiveInjuryEvent]` (@Published: nimi, positio, puoli, kenttänoden indeksi, vammatyyppi) julkaistaan näkymälle joka steppi.
- [x] Feature: [UI] Vamman presentaatio — CoachedGameView: punainen "INJURY: T. Hill (WR) — leaves the game" -banneri (cross.fill, Color.danger, oman result-bannerin yläpuolella); loukkaantunut hahmo jää makaamaan (`fieldScene.stayDown(nodeIndex:)` → `fall(stayDown: true)` ilman nousua); proceed viivästetään 1,7 s jotta kaatunut ehtii näkyä, ja seuraava formaatiosiirto nostaa noden pystyyn korvaajan numerolla (FieldUnit päivittyi ⇒ updateJerseyNumber hoitaa loput). Yksiköt kaapataan runPlayssa ENNEN engine.step-kutsua, jotta vammapeli animoituu vielä loukkaantuneen numerolla. skipDrive näyttää bannerin myös ohitetuista pelaajista.
- [x] Feature: [Persistointi] Pelin päättyessä `LiveGameEngine.persist` kirjaa vammat live-Player-malleihin täsmälleen samalla mekanismilla kuin quick sim (`MedicalEngine.applyInjury` ko. joukkueen doctor/physio-staffilla ⇒ isInjured + injuryType + injuryWeeksRemaining/Original) fatigue-writebackin (buildResult/finalizeGameResult) rinnalla.
- [x] Feature: [Pariteetti] Ei tuplavammoja — quick sim generoi vammat viikkotasolla (WeekAdvancer step 6: yksi `MedicalEngine.injuryCheck` per pelaaja), joten `LiveGameEngine.persist` rekisteröi molemmat joukkueet uuteen `WeekAdvancer.liveGameInjuryTeamIDs`-settiin ja viikkorulla ohittaa niiden pelaajat sillä advancella (setti nollataan jokaisen advanceWeekin lopussa). Live-valmentaja kärsii vammoja samalla kokonaistodennäköisyydellä kuin simmaaja — ei tuplana.
- [x] Feature: [Live] Väsymysrotaatio (vain RB) — drivejen välissä (`beginDrive` → `updateRBRotation`, VAIN pelaajan joukkue ⇒ AI-käytös ja nil-parametripariteetti ennallaan): kun RB1:n fatigue ≥ 75 ja terve RB2 on ≥ 10 pistettä pirteämpi, RB1 lepää (`restingRBID` pois simistä + FieldUnitista) ja RB2 ottaa seuraavan driven; paluu kun RB1 on taas selvästi pirteämpi tai palautunut alle 55:n (halftime recovery). `lastRotation` (@Published) → vihreä "Fresh legs: J. Cook in at RB" -kapseli kentän yläkulmaan (.onChange).
- [x] Fix: [Live] `topPerformers` hakee nimet koko rostereista FieldUnitien sijaan, jotta loukkaantuneena poistunut pelaaja säilyy listalla tallyineen.

### Left out
- [ ] Kohta 5 (vammageneraatio quick simiin) — EI TARVITTU: quick sim tuottaa jo vammoja viikkosimissä (WeekAdvancer step 6), joten pariteetti hoidettiin skip-setillä eikä GameSimulatoria muutettu.
- [ ] Rotaatio muille positioille kuin RB — kierrosspeksi rajasi eksplisiittisesti vain RB:hen.
- [ ] AI-joukkueen väsymysrotaatio — muuttaisi AI-käytöstä ja rikkoisi nil-parametripariteetin GameSimulator.simulaten kanssa; kierros ei sitä vaatinut.
- [ ] Vammojen näyttö final-overlayssa / GameSummaryssa — banneri + persistointi (roster-UI:n INJ-badget) kattavat speksin; yhteenvetolistaus vaatisi jaetun GameResult-tyypin laajentamista live-only-datalla.
- [ ] Simulaattoriverifiointi — vihreä buildi + koodikatselmointi kierroksen sääntöjen mukaan (live-peliin navigointi vaatii yhteistyökykyisen pelitilan; ~0,3 %/play-vamman todistaminen käsipelillä vaatisi kymmeniä pelejä).

## Round 15: Sää ja tunnelma — deterministinen sää, sim-vaikutukset, 3D-sadevisualisointi, sää-chipit (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Domain] `GameWeather` (Domain/Enums/GameWeather.swift) — clear/rain/snow/wind + `forGame(id:week:)`: deterministinen arvonta Game.id:n RAW-tavuista (ei `hashValue`a, jonka siemen vaihtuu joka käynnistyksellä). Jakauma clear 55 / rain 20 / wind 15 / snow 10; viikot 12+ siirtävät clearista lumeen +4 %-yks/viikko, katto +20 (viikolla 16 lunta 30%). Ei SwiftData-kenttiä — puhdas funktio, joten quick sim, live-engine ja UI saavat aina saman vastauksen samalle ottelulle. UI-apurit `label`/`symbolName`.
- [x] Feature: [Sim] `PlaySimulator.simulatePlay(..., weather: GameWeather? = nil)` — nil/.clear = täsmälleen nykykäytös. Rain: completionChance -0.05, fumbleChance +0.005, FG makeChance -0.05. Snow: samat kuin rain + breakaway-juoksut ×0.5 + run-bias (decidePlayCall pass-todennäköisyys -0.08 → molempien AI-koordinaattorien pelinvalinta nojaa maapeliin). Wind: syvät heitot -0.08, yli 45 jaardin FG:t -0.10. Kaikki clampattuina olemassa oleviin rajoihin; satunnaislukujen määrä/järjestys ei muutu nil-sään suhteen.
- [x] Feature: [Sim] Sään läpivienti — `DriveSimulator.simulateDrive` ja `GameSimulator.simulate` (+ `simulateOvertime`) saavat valinnaisen weather-parametrin ja välittävät SAMAN säätilan molemmille joukkueille joka snapille (symmetrinen vaikutus, pariteetti kunnossa). `WeekAdvancer` laskee pelaajan ottelulle `GameWeather.forGame(id: game.id, week: game.week)`.
- [x] Feature: [Live/Parity] `LiveGameEngine(..., weather:)` — tallettaa säätilan ja välittää sen `step()`-kutsun simulatePlay'lle ja `aiOffensiveCallHint()`-ehdotukselle. CareerDashboardView laskee liveottelulle täsmälleen saman deterministisen arvon samasta game.id/week-parista kuin quick sim → koutsattu ja simattu peli pelataan aina samassa säässä. Nil-parametreilla käytös identtinen GameSimulator.simulaten kanssa.
- [x] Feature: [3D] `FootballFieldScene.setWeather(_:)` — rain: proseduraalinen SCNParticleSystem koodilla (pieni valkoinen viirusprite UIGraphicsImageRendererillä, birthRate 400, velocity 24 alaspäin, stretchFactor 0.12, additive-blend, kenttä + apronit kattava volume-emitter y 32:ssa) + tummennettu valaistus (main 1200→850, fill 400→300, ambient 500→420); snow: hitaat leijailevat hiutaleet (birthRate 220, velocity 2.4, lifeSpan 16 — kattaa koko pudotuksen) + lumihuntu (valkoinen läpikuultava taso alpha 0.15, y 0.014 — mowing-raitojen päällä mutta maaliviivamaalausten alla) + vaalennettu ambient 620; wind/clear: ei visuaalia. Idempotentti (poistaa edelliset weather-nodet ja resetoi valot), valonodet nimetty buildLightingissä. Kutsutaan CoachedGameView.startGamesta.
- [x] Feature: [UI] Sää-chip tulostaulun keskelle kellon alle (SF Symbol cloud.rain.fill/snowflake/wind + lyhyt teksti, accentBlue-kapseli; piilossa selkeällä säällä) ja GameSummary-headeriin FINAL-badgen viereen Label-kapseli (uusi valinnainen `weather`-parametri, CareerDashboard välittää molemmissa poluissa: quick sim nappaa Game-olion ennen advanceWeekia, koutsattu peli session.gamesta).

### Left out
- [ ] Tuulen visuaali (kevyt hiutale/viiva-ajelehtiminen) — speksi salli jättää pois; tästä kamerakulmasta yksittäiset ajelehtivat partikkelit lukisivat kohinana ilman koko kentän ruohoanimaatiota.
- [ ] Sään vaikutus puntteihin/extra pointeihin — speksi listasi vain completion/fumble/kick accuracy/breakaway/run-bias/deep pass/FG-vaikutukset; XP:t eivät ole mallinnettuina drive-loopissa (TD = 6 pistettä), joten muutos olisi kuollutta koodia.
- [ ] Sää AI-vs-AI-otteluihin — WeekAdvancer simuloi muiden ottelut pelkkänä lopputuloksena (`simulateGameScore`), ei play-by-play'nä, joten säällä ei ole niissä mihin tarttua.
- [x] Simulaattoriverifiointi — sade/lumi-visuaalit katsottu silmin ja viritetty hienovaraisiksi lumipelissä (ks. "Sään häivytys" -osio ylhäällä); sadepelin silmäys jää seuraavaan sadesessioon.

## Round 12: Simulaation eheys ja luottamus (2026-07-09)

- [x] Mittausputki: DEBUG-only `GameSimulator.debugSimulate(n:)` (n peliä geneerisillä rostereilla, keskiarvot/hajonnat + aikataulun eheystarkistus 8 kaudelle) — ajettu simulaattorissa väliaikaisella app-launch-kutsulla, kutsu poistettu. Tulokset (100 peliä): pisteet/joukkue ka 22.3 (σ 9.8), jaardit/joukkue ka 371 (σ 97), rangaistuksia/peli 9.5, voittomarginaali ka 13.6
- [x] Balanssi: EI breakaway-muutosta — kriteerit (>30 p/joukkue tai >450 yd/joukkue) eivät täyttyneet. Ensimmäinen mittaus näytti 625 yd/joukkue, mutta syy oli kirjanpitobugi: punttien 35–55 jaardia valui totalYards/pass-jaardeihin → korjattu (`buildTeamBoxScore` + `LiveGameEngine.totalYards` laskevat vain scrimmage-pelit), jonka jälkeen 371 yd on terve
- [x] Tupla-bye-bugi korjattu (`ScheduleGenerator`): kolme juurisyytä — (1) inter-conference-rotaatio parasi KAIKKI 4 AFC-divisioonaa samaan NFC-divisioonaan (sen joukkueille ~26 ottelua, muille liian vähän) → nyt siirretty bijektio (i + vuosi) % 4; (2) intra-conference-parit eivät olleet symmetrinen täyspariutus → nyt kiertävä perfect matching (3 vuosirotaatiota); (3) 3 "jäljelle jäävää" ottelua → deterministinen 3-säännöllinen bipartiittigraafi konferenssin puolikkaiden välillä. Yhteensä täsmälleen 17 ottelua/joukkue
- [x] Viikkosijoittelu: 17 ottelua / 18 viikkoa on maksimaalisen tiukka → greedy + Kempe-ketjukorjaus (vuoroviikkosiirrot kahden viikon välillä + täysi verifiointi ennen committia), bye-viikkojen PARITEETTIkorjaus (pariton bye-määrä viikossa = mahdoton viikko) ja byet arvotaan uudelleen joka retry-kierroksella (80 yritystä). DEBUG-`validate(games:teams:)` vahvisti: kaudet 2025–2032 kaikilla 32 joukkueella täsmälleen 1 tyhjä viikko (oma bye) ja 17 ottelua
- [x] Syöttökohteet kentän 11:een: `PlaySimulator.weightedReceiverSelection` ohjaa 85 % kohteista ryhmään top-3 WR + paras TE + paras RB (loput 15 % syvyysmiehille); ryhmän sisällä edelleen route/catch-painotus. Lisäksi `GameSimulator.accumulateStats` kirjaa tilastot pelin nimeämälle key-pelaajalle (`keyOffensePlayerID`/`keyDefensePlayerID`) — feed, 3D-kenttä ja box score osoittavat nyt samoihin nimiin (QB-scramblet kirjautuvat QB:lle, ei satunnaiselle RB:lle)
- [x] Rangaistukset: ~6 % scrimmage-snapeista (`PlaySimulator.rollPenalty`): offensive holding -10, false start -5, defensive offside +5, DPI +15 spotissa (automaattinen 1. yritys; offside voi konvertoida jaardeilla). Down EI kulu (replay down `DriveSimulator.advanceDownAndDistance`issa), kello pysähtyy (4–8 s), penalty-jaardit eivät likaa hyökkäysjaardeja (box score kirjaa penalties/penaltyYards). Sama polku quick simissä ja livessä (jaettu simulatePlay/advanceDownAndDistance). Mitattu ~9.5 rangaistusta/peli (molemmat joukkueet yhteensä)
- [x] Rangaistuskoreografia: `FootballFieldScene.throwFlag(atZ:)` — keltainen liina lentää kaarella sivurajalta spotille, pyörii, jää turffiin ja häipyy; CoachedGameView heittää liinan .penalty-pelin snapissa; PlayChoreographerin `.penalty → defaultSteps` oli jo olemassa. Banneri näyttää "FLAG — ..." -kuvauksen
- [x] Aikalisät: `LiveGameEngine.homeTimeouts/awayTimeouts` (3/puoliaika, resetoi halftimessa), `useTimeout(home:)` asettaa lipun jonka seuraava `step()` kuluttaa nollaamalla pelin kellonkulutuksen. AI ei koskaan käytä aikalisiä → nil-parametripariteetti GameSimulatorin kanssa säilyy. CoachedGameView: kultainen "TO · N" -nappi situationStripissä (näkyy kun aikalisiä jäljellä, disabloitu animaation ajan) + kolme timeout-pipsiä molempien joukkueiden alle tulostauluun
- [ ] OT-aikalisät: NFL antaa 2 aikalisää jatkoajalle — jätetty pois (speksi määritteli vain 3/puoliaika + halftime-reset); OT jatkaa 2. puoliajan jäljellä olevilla
- [ ] Rangaistukset erikoistilanteissa (puntti/FG-blokkaukset, kickoff-rangaistukset) jätetty pois — speksin neljä rangaistustyyppiä koskevat vain scrimmage-pelejä, erikoistilanteiden flow olisi vaatinut oman down-logiikkansa
- [ ] Half-distance-to-goal -sääntö (holding omalla 5:llä = -10 → clampataan 1-jaardiviivalle, ei puoleen väliin) — yksinkertaistus, vaikutus marginaalinen

- [x] Fix: GamePlanView oli kytketty vakiobindingiin (`.constant(.balanced)`) CareerShellView'ssa — sliderit eivät liikkuneet eikä mikään tallentunut. Nyt aito binding joka lukee/kirjoittaa `career.gamePlan` ja tallentaa modelContextiin joka muutoksella
- [x] Career-malliin uusi optionaalinen `gamePlanData: Data?` (kevyt migraatio) + `gamePlan`/`savedGamePlan` computed-avut (JSON-koodaus, fallback .balanced)
- [x] Sim-kytkentä: `PlaySimulator.decidePlayCall` sai valinnaisen `gamePlan`-parametrin — runPassRatio siirtää pass-todennäköisyyttä (±0.15), fourthDownAggressiveness laajentaa (>0.65: go for it 4&≤3 midfieldin jälkeen) / supistaa (<0.35: punttaa/FG herkemmin) 4. yrityksen ehtoja. nil = täsmälleen vanha käytös
- [x] `GameSimulator.simulate` sai `homeGamePlan/awayGamePlan`-parametrit (myös OT), `DriveSimulator.simulateDrive` välittää planin; WeekAdvancer syöttää pelaajan tallennetun planin vain pelaajan joukkueelle
- [x] LiveGameEngine: `pendingPlayerGamePlan`-hand-off (CoachedGameView UI/Match-kiellossa, joten static hand-off kuten WeekAdvancerissa) — plan vaikuttaa pelaajan hyökkäyksen AI-kutsuihin, aiOffensiveCallHintiin ja aiDefensivePackage-blitz/coverage-sävyyn pelaajan puolustaessa
- [x] Visuaalinen uudistus: kaksipalstainen iPad-leiska (vasen: 3 yhteenvetochipiä + presetit + vastustajapaneeli; oikea: Offense/Defense-sliderikortit), viiden minipalkin duplikaatio poistettu
- [x] Väripaletti yhtenäistetty: offense-sliderit accentBlue, defense-sliderit danger, presetit/chipit kulta
- [x] Header-konteksti: "Week N · vs OPP" (seuraavan pelaamattoman pelin viikko) + OC:n scheme-badge + automaattitallennuksen "Saved ✓" -väläys
- [x] Presetit: aktiivinen korostuu kultareunuksella + checkmarkilla (±0.01 vertailu), yhden rivin kuvaus per preset
- [x] Slidereille risk/reward-alarivit (esim. 4th Down: "More TDs on the table — more turnovers on downs.")
- [x] Vastustajapaneeli (Scouting Report): nimi, record, Pass/Run Defense weak/average/strong (puolustusyksiköiden OVR-keskiarvosta) + yhden rivin vinkki
- [x] Tehtäväkuittaus: "Set game plan..." -tehtävät kuittautuvat kun plania muokataan (markTaskCompleted binding-setterissä); OTAs-vaiheen "Set game plan" kuittautuu pysyvästi `gamePlanData != nil` -ehdolla
- [x] Verifioitu simulaattorissa: sliderit liikkuvat, arvot säilyvät relaunchissa, presetit toimivat, tehtävä kuittautuu (screenshotit /tmp/snd-screenshots/)
- [ ] Playoff-viikkojen sim käyttää satunnaista `simulateGameScore()`-generaattoria myös pelaajan pelille — game plan ei vaikuta playoff-pikasimiin ennen kuin playoff-pelit siirretään täyteen play-by-play-simiin
- [ ] Dashboardin yläpalkin "Game Plan" -pikachip navigoi Week Prep -näkymään (gameWeekPrep) eikä Game Planiin — harkitse otsikon tai kohteen korjausta
- [ ] LiveGameEnginen blitzFrequency voisi jatkossa vaikuttaa myös täysin AI-simuloituihin puolustussnappeihin (nyt vain aiDefensivePackage-ehdotukseen/oletukseen)

## Press Conference auto-analyze findings (2026-04-29)

### [PressConfIntro] Visual Design
- [x] Fix: [PressConfIntro] "Introductory Press Conference" subtitle and "The media is waiting..." caption have low contrast on the dark photo — bump opacity / use lighter gray for iPad reading distance (R20: molemmat nostettu textPrimary @ 78%/72% -opasiteettiin)
- [x] Fix: [PressConfIntro] Background coach photo is so dark the podium/microphone context disappears — add a subtle vignette or directional gradient so the focal area reads while keeping atmosphere (R20: suuntagradientti — tumma ylä/ala, vaaleampi keskikaista; kuvan opacity 0.25→0.32)
- [x] Fix: [PressConfIntro] Gold "PRESS CONFERENCE" eyebrow text and the gold mic icon are the same hue with too-tight letterspacing — widen tracking and/or shrink eyebrow to establish a clearer 3-step hierarchy (eyebrow > title > subtitle) (R20: eyebrow 16→13pt, tracking 6→8, gold @ 90%)
- [x] Fix: [PressConfIntro] "Take the Podium" CTA pill is small and lonely at the bottom — for the only primary action on iPad it should be wider/taller and visually more dominant (R20: title3 bold, minWidth 320, korkeampi padding, vahvempi hehku)
- [x] Fix: [PressConfIntro] No top safe-area scrim — status-bar text (clock, battery) sits flush on the photo with no protection if the asset ever brightens (R20: 90pt musta yläscrim lisätty)
- [x] Fix: [PressConfIntro] Title block "Green Bay Packers" sits dead-center over the coach's face — shift up ~15% so the face reads as backdrop, not subject obstruction (R20: kaksi alaspaceria vs yksi yläspacer siirtää blokin ~15 % ylös)
- [x] Fix: [PressConfIntro] Microphone icon is a flat gold glyph with no shadow / depth — feels detached from the dark photo; add soft glow or subtle drop-shadow (R20: tumma drop-shadow lisätty olemassa olleen kultahehkun alle)

### [PressConfIntro] Game Design
- [ ] Game: [PressConfIntro] No indication of how many questions are coming (Q1 of 4 only revealed after tap) — add "4 questions • ~2 min" hint above the CTA so the player knows the commitment
- [ ] Game: [PressConfIntro] Intro never tells player that answers affect Owner / Morale / Fans / Media — surface this expectation before the first question so the user isn't blindsided by tradeoffs
- [ ] Game: [PressConfIntro] No team-specific context (Packers record? owner expectations? coach archetype reminder?) — a one-line pre-conference brief would frame the right answer choice
- [ ] Game: [PressConfIntro] No archetype reminder of the coach's own personality before answering — easy to drift off-character if user forgets they picked, e.g., "Players' Coach"
- [ ] Game: [PressConfIntro] No "Skip" or "Auto-respond" affordance for users who don't want to engage with press cycles — consider an optional "Let media team handle it" path with average outcomes

### [PressConfIntro] Decision Support
- [ ] Game: [PressConfIntro] No baseline preview of Owner / Morale / Fans / Media gauges on the intro — player can't strategize ("I need to boost Fans this week") before stepping up
- [ ] Game: [PressConfIntro] No reminder of which reporters are scheduled / what tone they bring — knowing "today is Pelissero, probing tone" lets the player prepare answers vs blind reactive picks

### [PressConfQ1] Visual Design
- [x] Fix: [PressConfQ1] Top stats strip ("0 Legacy / 0 Media / 70% Satisfaction") is ambiguous — Legacy and Media at 0 read like errors. Add "Starting values" subhead or progress denominator (0 / 100) so player understands these are baselines (R20: "CURRENT STANDING · BEFORE THIS SESSION" -alaotsikko lisätty)
- [x] Fix: [PressConfQ1] The 3-line effects explanation under the stats strip is tiny and very low contrast — bump font-size + opacity, or move it into an info popover triggered by an "i" icon (R20: caption2/tertiary → caption/secondary)
- [x] Fix: [PressConfQ1] Answer-card delta badges (Owner / Morale / Fans / Media) read at ~10pt — too small for iPad viewing distance. Bump to 12-13pt and add a slight pill background for contrast (R20: eksplisiittiset 12/13pt-koot; pill-tausta oli jo #116:sta)
- [x] Fix: [PressConfQ1] Negative deltas use a saturated red on dark navy that sits at the borderline WCAG contrast threshold — switch to a lighter error red (e.g. #FF6B6B) or use an outlined pill for legibility (R20: negatiivit vaaleammalla virhepunaisella + vahvempi ääriviiva isoille miinuksille; korvasi opacity-himmennyksen joka heikensi kontrastia entisestään)
- [x] Fix: [PressConfQ1] Category icon color and value-delta color are too similar (both green-tinted on positives), making rapid scanning sluggish — separate icon hue from delta hue (R20: ikoni+label neutraali textSecondary, vain delta-arvo värillinen)
- [x] Fix: [PressConfQ1] Reporter card duplicates outlet ("NFL Network" appears twice — once under name, once as a pill on the right) — drop one or repurpose the right pill for tone (probing / friendly / hostile) (R20: oikea pilli näyttää nyt reporterin sävyn, outlet vain kerran nimen alla)
- [x] Fix: [PressConfQ1] Four answer cards are visually almost identical (same height, layout, border weight) — emphasize the personality color (Confident=gold, Humble=blue, Aggressive=red, Diplomatic=green) on the card stroke or accent bar so user can pre-scan by archetype (R20: sävyvärinen vasen aksenttipalkki + sävyyn tintattu oletusreunus)
- [x] Fix: [PressConfQ1] Question text "What's your vision for this franchise?" sits in the same card as the reporter name — separate them visually (reporter card on top, question card below) so the question reads as the prompt, not metadata (R20: jaettu kahdeksi pinotuksi kortiksi — reporter-kaista ylhäällä, kysymyskortti alla)
- [x] Fix: [PressConfQ1] No visible graphical progress fill — "Question 1 of 4" text exists but no progress bar/arc shows how far through the user is (R20: todennettu — segmentoitu kultainen progress-palkki oli jo questioningHeaderissa aiemmalta kierrokselta)

### [PressConfQ1] Game Design
- [x] Bug: [PressConfQ1] Effects-row text appears to read "Demo affects job security · Media shapes public narrative · Legacy affects career rating" — "Demo" looks like a typo or empty string-key for "Owner". Audit the source string in PressConferenceView / TaskGenerator (Investigated: source string at PressConferenceView.swift:246 reads "Owner affects job security..." — no "Demo" typo found in current code; likely a stale-build artifact from the user's screenshot)
- [x] Game: [PressConfQ1] Diplomatic answer (Owner +2, Morale +2, Fans +1, Media +1) is strictly weaker than Confident (Owner +4, Morale -2, Fans +12, Media +5) and weaker than the other options on most metrics — it's a dominated choice. Rebalance: Diplomatic should excel somewhere (e.g. zero negatives + larger Owner boost as the "safe" pick) (Rebalanced Q1-Q5: Diplomatic now the only "no-negatives" option with balanced positives across all axes)
- [x] Game: [PressConfQ1] Aggressive (Morale -10, Media +10) and Confident both look stronger than Humble/Diplomatic — re-tune so each archetype has a clear best-for-situation use case rather than a power ranking (Rebalanced Q1-Q5: each archetype now wins at least one metric — Confident=Fans/Legacy, Humble=Owner/Morale, Aggressive=Media, Diplomatic=safest, Funny=Morale/Fans)
- [ ] Game: [PressConfQ1] No way to revisit / undo a previous answer and no "lock in" confirm step — clarify finality (tap-to-select then "Submit" button, OR explicit "this answer is final" hint) so player doesn't fat-finger
- [ ] Game: [PressConfQ1] No way to see locker-room / owner state before answering — pure blind tradeoff. The stats strip exists but doesn't visually tie to the badges below (e.g., highlight "Owner" in the strip when an answer affects Owner)
- [ ] Game: [PressConfQ1] No archetype-consistency feedback — if coach archetype is "Players' Coach", picking Aggressive should warn "off-archetype, may cost extra morale". Surface a small "matches your archetype" or "off-character" tag on each card

### [PressConfQ1] Decision Support
- [ ] Game: [PressConfQ1] Badge deltas show raw numbers but no scale context — is +12 huge or trivial vs a 0-100 meter? Add a tier indicator (small/medium/large pill) or relative-percentage label
- [ ] Game: [PressConfQ1] No highlight of which metric is currently weakest — player can't make an informed "boost what I need" decision. Pulse / glow the badge of the most-needed metric across all four answer cards
- [ ] Game: [PressConfQ1] No reporter persona / tone tag (friendly vs hostile vs probing) — same answer lands differently. Add a small tone tag on the reporter card so player can adjust
- [ ] Game: [PressConfQ1] No preview of likely media headline / quote that will result from each answer — even a one-word outcome hint ("'rebuilding'", "'overconfident'") would let the user pick with intent
- [ ] Game: [PressConfQ1] No running "session total" delta after each answer — player can't course-correct across Q2-Q4 without seeing aggregate impact

## Team Selection + Team Detail auto-analyze findings (2026-04-29)

### [TeamSelection] Visual Design (AFC + NFC tabs)
- [x] Fix: [TeamSelection] Row density too high — five data columns (rating, label, cap, +num, icon) collide on iPad; tighten widths or move detail to Team Detail screen (R20: todennettu — jo korjattu #117:ssä: kompakti rivi, tier-label poistettu, sarakeotsikot)
- [x] Fix: [TeamSelection] Tier labels (CONTENDER / REBUILDING / RISING / DYNASTY / WIN NOW) use 5+ colors (yellow, blue, orange, gold, red) — collapse to a 3-tier color system with consistent semantics (R20: 3-portainen paletti — sininen=rakentaa, vihreä=nousussa, kulta=kilpailee; punainen/amber varattu varoituksille; kaikki 3 situationColor-kohtaa)
- [x] Fix: [TeamSelection] Star rating and tier label duplicate the same signal — pick one or differentiate (e.g., stars = current talent, label = trajectory) (R20: todennettu — jo korjattu #117:ssä, tier-label poistettu riviltä)
- [x] Fix: [TeamSelection] Number column right of label is unlabeled (cap remaining? OVR?) — add header row or icon for at-a-glance meaning (R20: todennettu — jo korjattu #117:n columnHeaderRow'lla)
- [x] Fix: [TeamSelection] Stadium hero image bleeds into bottom third of list — content gets cut behind gradient on smaller iPads; shrink hero or scroll content above it (R20: todennettu — jo korjattu #117:ssä, hero rajattu 180pt yläkaistaan)
- [x] Fix: [TeamSelection] Filter / Division pickers are cramped top-left — promote to a proper segmented control or sticky header (R20: todennettu — jo korjattu #115:ssä: kapseli-filter/sort-palkki + segmentoitu konferenssikontrolli)
- [x] Fix: [TeamSelection] AFC/NFC pill toggle has good gold-accent affordance but no count indicator (e.g., "AFC 16 / NFC 16") (R20: joukkuemäärächip lisätty molempiin toggle-nappeihin)

### [TeamSelection] Game Design
- [ ] Game: [TeamSelection] No way to sort by difficulty / cap / draft picks / rebuild stage — add sort menu so user can rank by what matters
- [ ] Game: [TeamSelection] Division grouping is good but no clear visual division header — add colored division header bars or fold-able sections
- [ ] Game: [TeamSelection] Show user-readable "easy / medium / hard" career start signal explicitly (currently inferred from tier label only)
- [ ] Game: [TeamSelection] Show franchise prestige / fan expectations / market size on the row, not buried in detail
- [ ] Game: [TeamSelection] Show last season record + trajectory arrow inline (record is small, trajectory only appears in detail)

### [TeamSelection] Decision Support
- [ ] Game: [TeamSelection] Cannot compare two teams side-by-side — add a "compare" mode or "shortlist" to evaluate 2-3 finalists
- [ ] Game: [TeamSelection] Cap space, draft picks, and roster strength use different scales/colors across rows, making cross-team comparison hard
- [ ] Game: [TeamSelection] No surfacing of "challenge level" or "fit for your playstyle" — user has to read tier + record + cap and infer
- [ ] Game: [TeamSelection] Add "recommended for first-time players" / "recommended for veterans" tag

### [TeamDetail] Visual Design (Green Bay Packers)
- [x] Fix: [TeamDetail] GB logo + helmet hero image disappears into background — increase contrast or add subtle frame so the team identity is the visual anchor (R20: logo backgroundSecondary-levylle + rengas + varjo)
- [x] Fix: [TeamDetail] 2-of-5 stars rating with no scale label (talent? difficulty? prestige?) — add header text like "Roster Talent" (R20: "CAREER DIFFICULTY" -skaalalabel tähtien ylle — tähdet mittaavat vaikeutta, ei talenttia)
- [x] Fix: [TeamDetail] "Easy" badge is tiny and ambiguous — what makes this team easy? Show the reason on tap/hover (R20: perustelucaption rivin alle: "Difficulty weighs roster talent, cap room, and draft capital.")
- [x] Fix: [TeamDetail] "RISING" badge color (green) and "Very Patient" owner (green) are visually identical to "Detroit Lions CONTENDER" — unify color semantics (R20: 3-portainen situaatiopaletti yhtenäistää — Contender nyt kulta, vihreä tarkoittaa aina suotuisaa statusta)
- [x] Fix: [TeamDetail] Three footer stats (Roster OVR 78 / Cap Space $25M / Draft Picks 7) are critical decision data but sized smallest on screen — promote them (R20: statsRow nostettu heti difficulty-rivin alle molemmissa layouteissa + arvot 18→24pt)
- [x] Fix: [TeamDetail] "Coaching Budget $27M" warning icon is unclear — is $27M low, average, high? Add comparison ("league avg $30M") or remove the warning if not actionable (R20: "League average: $NNM" -vertailurivi laskettuna staattisesta 32 joukkueen datasta)
- [x] Fix: [TeamDetail] Division Rivals card lists 3 teams but no record vs them, no head-to-head context, no rivalry intensity — feels like filler (R20: rivaalien Roster OVR lisätty riveille — kortti kertoo nyt divisioonan kovuuden; head-to-head-recordit vaatisivat uutta dataa)

### [TeamDetail] Game Design
- [ ] Game: [TeamDetail] "Last Season: 11-6" alone — show playoff result (lost wild card? missed?) and multi-season trajectory
- [ ] Game: [TeamDetail] Starting QB shown (J. Love, 83 OVR) but no other key roster info — add 2-3 stars / weakest position so user knows what they're inheriting
- [ ] Game: [TeamDetail] Owner expectations "Very Patient — 5 seasons tolerance" is great UX but isolated — show consequences (fired? trade demands?)
- [ ] Game: [TeamDetail] Market & Media flavor text doesn't translate to mechanics — does it affect FA signings? Cap? Show numerical impact
- [ ] Game: [TeamDetail] No info about rookie/young core, expiring contracts, dead cap, scheme fit with current coach
- [ ] Game: [TeamDetail] Bottom CTA "SELECT THIS TEAM" looks good but no secondary "compare" or "shortlist" affordance

### [TeamDetail] Decision Support
- [ ] Game: [TeamDetail] Critical decision data (cap space, OVR, picks, coaching budget) are on screen but in different visual treatments — unify into a "Franchise Vitals" card readable in 5 seconds
- [ ] Game: [TeamDetail] No comparison to league average (Cap $25M — is that top-5? bottom-10?)
- [ ] Game: [TeamDetail] No "what to expect in Year 1" summary — projected wins, key roster moves needed, owner pressure timeline
- [ ] Game: [TeamDetail] No way to preview the 53-man roster from this screen before committing — user picks blind aside from QB
- [ ] Game: [TeamDetail] No surfacing of upcoming UFA stars on the team or rival division strength — major career-difficulty factors
- [ ] Bug: [TeamDetail] Verify "Coaching Budget $27M" warning icon — if budget < league min the warning is correct, otherwise the icon is misleading

## Main Menu auto-analyze findings (2026-04-29)

### Visual Design
- [x] Fix: [MainMenu] No "Continue Career" / "Load Save" button — returning players have to go through "New Career" to reach existing saves, breaking flow. (Game/Flow critical) (R20: todennettu — Continue Career / Continue-Load + save-slot-picker jo toteutettu aiemmalla kierroksella)
- [x] Fix: [MainMenu] No version number, build tag, or copyright/credit line anywhere on the menu — typical for shipping iPad games and useful for QA/feedback. Add small footer. (R20: todennettu — versio/build/copyright-footer jo toteutettu aiemmalla kierroksella)
- [x] Fix: [MainMenu] "NFL FOOTBALL MANAGER" tagline tracking is overly tight and gray-on-busy-photo is hard to read. Increase letter-spacing further or add subtle text shadow / gradient scrim behind the title block. (R20: tracking 6→7.5, opacity 0.7→0.85 + tekstivarjo)
- [x] Fix: [MainMenu] Background photo has near-zero darkening at the top half — status bar text ("11.28 Thu 30. Apr", battery) sits on a white sky and is hard to read. Add a top vignette or status-bar safe-area scrim. (R20: todennettu — 110pt yläscrim jo toteutettu aiemmalla kierroksella)
- [x] Fix: [MainMenu] Bottom button stack sits very close to the home-indicator safe area. Add ~16-24pt extra bottom padding so primary CTA doesn't visually collide with the iPad gesture bar. (R20: pystysuunnan bottom padding 16→36pt)
- [x] Fix: [MainMenu] Settings button uses dark translucent fill with thin white text — contrast against the busy photo behind it is borderline. Either deepen the fill alpha or add a 1pt subtle stroke for definition. (R20: sekundäärinapit tumma pohja + frosted-kerros, stroke 0.25→0.35)
- [x] Fix: [MainMenu] Only two actions shown — menu feels sparse for a deep management sim. Consider adding entries for "Tutorial / How to Play", "Stats / Hall of Fame", and "About" to communicate scope without overwhelming. (R20: todennettu — How to Play -tutoriaali + Settings + Continue/New jo toteutettu aiemmalla kierroksella)
- [x] Fix: [MainMenu] Title hierarchy is good but "SUNDAY NIGHT" gold kicker and the "NFL FOOTBALL MANAGER" subtitle are similar in size — kicker should be visibly smaller than the subtitle or vice versa to establish a clearer 3-step ladder. (R20: todennettu — nykyinen ladder 22/64/14pt on jo selvästi eriytetty aiemman kierroksen jäljiltä)
- [x] Fix: [MainMenu] No app logo / mark — only typographic title. For brand recall on home screen vs main menu, consider a simple monogram or icon glyph above the wordmark. (R20: kultarenkainen jalkapallomonogrammi lisätty wordmarkin ylle)
- [ ] Fix: [MainMenu] Hero image is a generic celebration with no team branding or in-game context — feels like a stock photo. Replace with rendered/illustrated key art or in-engine moment to reinforce game identity. (R20: jätetty väliin — vaatii uuden taideassetin, ei koodikorjaus)

### Game Design / Decision Support
- [ ] Game: [MainMenu] No "last played" hint (team name, season, week) on the main menu — players returning after days won't know where they left off until after tapping through. Surface a small "Continue: 49ers — Week 6, 2026 season" line above the buttons.
- [ ] Game: [MainMenu] No save-slot picker visible — multi-career players can't see how many active dynasties they have. Add a save-list affordance behind a Continue/Load button.
- [ ] Game: [MainMenu] No onboarding hook for new players — first-time users get no preview of what the game offers (scouting, draft, FA, coaching). Consider a one-line value-prop subtitle or a "Tutorial" entry for first launch.
- [ ] Game: [MainMenu] No quick-access to settings prior to starting a career (difficulty, league size, season length presets) — these get buried inside Settings. Consider showing a "Quick Start" vs "Custom League" split on New Career.

## New Career Step 1 + Step 2 auto-analyze findings (2026-04-29)

### [NewCareerStep1] Visual Design (Player Name + Career Role + Salary Cap)
- [ ] Fix: [NewCareerStep1] Background player silhouette is barely visible and adds noise without identity — either darken with stronger overlay or replace with brand mark / blurred stadium scrim.
- [ ] Fix: [NewCareerStep1] "General Manager" half of the Career Role segmented control reads as disabled (dark gray) next to gold "GM & Head Coach" — strengthen the inactive vs disabled distinction (e.g., light text on translucent fill, never look like a dead button).
- [ ] Fix: [NewCareerStep1] Career Role checkmark columns have no header — user has to infer which column is GM vs GM & HC. Add tiny "GM | GM+HC" headers above the green-dot columns.
- [ ] Fix: [NewCareerStep1] Salary Cap Mode checkmark columns have the same problem — Simple/Realistic header is on the segmented toggle, not over the dot columns. Add column headers or move toggle to align directly above its column.
- [ ] Fix: [NewCareerStep1] "Player Name" helper text "This is how you'll be known across the league." competes visually with the input — reduce to caption size or italicize so the input is clearly primary.
- [ ] Fix: [NewCareerStep1] "Next" CTA stays enabled with empty Player Name field — disable until a non-empty name is entered, or show inline validation.
- [ ] Fix: [NewCareerStep1] Step indicator is split awkwardly: "Step 1 of 2" left, "Your Career" right — read as two separate labels. Consolidate into one tagline above the progress bar.

### [NewCareerStep1] Game Design
- [ ] Game: [NewCareerStep1] GM-only role disables Game-day play calling and Manage coaching staff but never explains WHY — add a one-liner under the role title clarifying responsibility split (GM = roster owner, HC = sideline).
- [ ] Game: [NewCareerStep1] Simple cap mode is described only by what Realistic does, not what Simple omits — write a concrete blurb under "Simple" (e.g., "Soft cap, no franchise tags, no dead money").
- [ ] Game: [NewCareerStep1] No "Recommended" badge on the default selection — first-time users have no decision support. Mark default Career Role and default Cap Mode with a "Recommended for first run" badge.
- [ ] Game: [NewCareerStep1] No Sandbox / Off / Custom option for cap mode — power users want to ignore cap entirely; add a third toggle option or a hidden advanced toggle.
- [ ] Game: [NewCareerStep1] Career Role choice is irreversible without starting a new career, but no warning is shown — surface a small "you can't change this later" hint near the toggle.

### [NewCareerStep1] Bugs
- [ ] Bug: [NewCareerStep1] Verify "Next" enables only with a valid Player Name — if it currently allows progress on empty input, that's a state-validation bug.

### [NewCareerStep2] Visual Design (Coaching Style + Avatar Look)
- [ ] Fix: [NewCareerStep2] Avatar grid 3x5 has multiple truncated names ("The Strateg…", "The Old So…", "The Motivat…", "The Innovat…", "The Profess…", "The Trailbla…", "The Tactici…", "The Comma…") — either shorten archetype names to ≤12 chars or reduce font size to fit two-line names.
- [ ] Fix: [NewCareerStep2] Selected avatar ("The Veteran") is indicated only by gold name text — circle/portrait gets no border or ring. Add a 2pt gold ring around the selected avatar circle for clear feedback.
- [ ] Fix: [NewCareerStep2] No visible Male/Female toggle in the screenshot although both genders' avatars appear — verify the gender selector is rendered and discoverable; if absent, this is a missing UI control.
- [ ] Fix: [NewCareerStep2] Helper text "Cosmetic only — does not affect gameplay" is tiny and low-contrast — bump size or contrast so users actually read it (currently easy to miss and trust archetype names instead).
- [ ] Fix: [NewCareerStep2] "Recommended" badge on "The Tactician" appears next to the "+10 Play calling" stat — looks like it's labeling the stat rather than the option. Move the badge to the option title row instead.
- [ ] Fix: [NewCareerStep2] Coaching Style list shows 5 options without a scroll indicator — if more exist, surface a scroll hint or scrollbar. If only 5, fine.
- [ ] Fix: [NewCareerStep2] Each style shows "+10 [attribute]" but no scale anchor — user has no idea if +10 is a small or huge bonus. Show the underlying scale ("+10 of 100") or show before/after numbers.
- [ ] Fix: [NewCareerStep2] Primary CTA "Choose Your Team →" breaks the 2-step flow shown by the progress bar — Step 2 of 2 should land on confirmation, not on a third destination. Either rename to "Save & Continue" or update the progress bar to 3 steps.
- [ ] Fix: [NewCareerStep2] "Your Identity" page mixes Coaching Style (gameplay choice) with Look (cosmetic) — these are different concerns. Either rename page "Coaching & Look" or move Coaching Style to Step 1.

### [NewCareerStep2] Game Design
- [ ] Game: [NewCareerStep2] 15 named archetypes ("The Veteran", "The Legend", "The Prodigy", "The Captain"...) read as gameplay archetypes, contradicting the "cosmetic only" helper — either neutralize names ("Coach 1") or actually wire light gameplay flavor (no balance impact, just dialog tone).
- [ ] Game: [NewCareerStep2] All 5 coaching styles appear to give a flat +10 to one attribute — feels balanced on paper but offers no trade-offs. Consider +10/-5 or specialization vs cost so the choice has weight.
- [ ] Game: [NewCareerStep2] No explanation of how Coaching Style interacts with the Career Role chosen in Step 1 — if the user picked GM-only (no game-day play calling) and then sees "+10 Play calling" as a Recommended option, the synergy is unclear. Conditionally tailor recommendations to the selected role.
- [ ] Game: [NewCareerStep2] "Recommended" badge has no rationale — show why ("Best for first run" / "Matches GM & HC") on long press or as caption.

### [NewCareerStep2] Bugs
- [ ] Bug: [NewCareerStep2] If Step 1 selected GM-only, Coaching Style options like "The Tactician (+10 Play calling)" are mostly meaningless because the GM doesn't call plays — verify whether the screen filters/disables irrelevant styles based on Career Role; if it doesn't, that's a logic bug.
- [ ] Bug: [NewCareerStep2] Verify all 15 avatar slots are filled — last-row truncation suggests two or three may be placeholder labels rather than real archetypes; confirm content completeness.

## Open (ei vielä toteutettu)

- [ ] CareerShellView: Wire up hasPendingTradeOffers when TradeOffer model exists (odottaa Trade-järjestelmää)
- [ ] PlayerDetail: career stats from prior seasons (vaatii uuden PlayerSeasonStats-mallin + tallennuksen vuosittain)
- [ ] PlayerDetail: performance trend rising/falling (vaatii season-over-season OVR-historian)
- [ ] HireCoachView: salary spread — top 40% kalliimpia kuin halvimmat (laske bottom alaspäin LeagueGenerator.salaryForCoach:ssa)
- [ ] HireCoachView: name column truncation iPadilla
- [ ] HireCoachView: TOP badge tooltip / role-specific key attrs / personality filter / coach career history / win contribution

## Toteutettu 2026-04-29

### Performance: Draft & Hire Coach optimisointi
- [x] HireCoachView: onAppear → task() async generation (Task.yield ennen blokkaavaa generointia)
- [x] HireCoachView: cached top3IDs, sortedCandidates, availableSchemes (poistettu O(n²) per-row sort)
- [x] HireCoachView: cached currentCoachOVR (poistettu per-row OVR-laskenta)
- [x] BigBoardView: O(1) rank-map (cachedRankMap) — rankFor() O(n) → O(1)
- [x] BigBoardView: kaikki computed pipeline -kutsut (orderedBoard, customOrderedBoard, tieredBoard) bodyssä korvattu cache-versioilla
- [x] MockDraftView: cached strategyRecommendation, targetAvailability, tradeHints, picksForRound
- [x] DraftOrderView: cached picksByRound, teamLookup, abbreviationLookup, userPickNumbers, userTotalPicks

## Toteutettu (agentit 1-13, 2026-03-23)

- [x] Game: Kaikki prospect-listat - oma arvosana/tähti (context menu, UserProspectGradeStore, badge kaikissa näkymissä)
- [x] Game: Draft Order -näkymä (7 kierrosta, omat pickit korostettu, traded picks, pick value, team records)
- [x] Bug: Big Board QB-dominanssi korjattu (0.85 + 0.15×posValue + max 4 per positio per tier)
- [x] Fix: Tähti-toggle ensimmäisessä sarakkeessa kaikissa 5 listassa (suora klikki)
- [x] Fix: "Oma / Scout" dual grade kaikissa listoissa, Staff→Scout nimetty uudelleen
- [x] Game: Manuaalisen siirron indikaattori Big Boardilla ("↑ from #15" vihreänä / "↓ from #8" punaisena)

## Toteutettu (agentit 1-13, 2026-03-23)

### Agentti 0: Palkkajärjestelmä
- [x] Cap-suhteelliset palkkavaatimukset, realistiset sopimusrakenteet, vuosikohtainen cap hit -erittely

### Agentti 1: Draft Realism
- [x] Fyysiset statsit skaalattu (Rd1: 82-96), positional draft value, draft class strength
- [x] Combine-ajat korreloivat SPD:n kanssa, position drill A-F skaala, top performers 1-2 per positio
- [x] Kaikki top prospects eivät enää Rd 1, hajontaa projektioissa

### Agentti 2: Scouting UI
- [x] FIT/NEED/RISK selkeämmät, position-filtterit erotettu data-tabeista
- [x] Scouting report dots, starter-vertailu, position needs, draft picks näkyvissä
- [x] Big Board sort+notes, Interviews priority+capacity+bust risk, Combine CTA

### Agentti 3: Sopimukset & Key Decisions
- [x] Extend contract +vuodet, vuosierittely, chat ei häviä
- [x] Vanhenevat max sopimuspituudet, eläköityminen Key Decisionsissa
- [x] Natural position palkanlaskennassa, pelaajan ikä + View Details nappi

### Agentti 4: Dashboard & Coaching
- [x] Satisfaction scoret (Owner/Morale/Media/Legacy) dashboardilla
- [x] Position coach statsit realistiset (1-5 hyvää, loput 40-60)
- [x] hasExpiringContracts, hasScoutsAssigned, playoffRoundName, coach seasonsOnTeam

### Agentti 5: Free Agency UI
- [x] Starter-vertailu, scheme fit, team needs, 6 sortausta, cap impact, OVR trend
- [x] Multi-signing planner, competition intensity, guaranteed-arviot, draft-vertailu
- [x] Numberformatting, Day labels, motivation-badget, contract clarity

### Agentti 6: Interview Report
- [x] Personality-badget värikoodattu, Football IQ grade, interview grade A-F
- [x] Bust risk before/after, shortlist+red flag togglet, 36 personality-kuvausta
- [x] Combine inline, scout recommendation, interview results ProspectDetailView:ssä

### Agentti 7: FA Complete
- [x] Cap breakdown, before/after, FA Grade, signing details+steal/overpay
- [x] Players lost, league signings, remaining needs, comp picks, media reaction

### Agentti 8: Pro Days
- [x] Scout-kortit (specialty, accuracy, assignments), expandable koulut
- [x] Priority indicators, recommended schools, scout-koulu matching, "Send All Recommended"

### Agentti 9: FA Bidding War
- [x] AI need-based bidding, player auction/shopping around, instant signing overpay
- [x] Day-by-day updates, motivation affects decisions, bidding war escalation

### Agentti 10: Mock Draft
- [x] P/K/FB ei top 10, position diversity, letter grades, own pick highlight
- [x] Team needs, media comments, rounds 1-3, trade scenarios, BPA vs Need, target availability

### Agentti 11: Scouting & Flow Fixes
- [x] Scout modal (specialty, prospects, recommendations), pro day capacity 3-4
- [x] Dashboard task completion, personal workouts, interview filtering+select all
- [x] Football IQ generation fix (Rd1: 70-95)

### Agentti 12: Big Board
- [x] Composite score (OVR × positional value), 7 tieriä, FIT/NEED korjattu
- [x] Haku, suodatus, auto-rank, value pick indicator, context menu reorder
- [x] Available at pick probability, tier summaries, shortlist visible

### Agentti 13: Combine + Data Consistency
- [x] Risers/Fallers layout korjattu (uusi arvo ylös, vanha alas)
- [x] Data consistency audit: yhtenäinen grade/color/projection kaikissa näkymissä

## [Dashboard] auto-analyze findings
_Source: /tmp/snd-screenshots/auto_19_dashboard.png — Career Dashboard hub. The most-used decision-support screen in the game._

### Visual Design (7 checks)

#### 1. Information density vs hierarchy
- [ ] Fix: Dashboard is a uniform 2-column card grid with **no visual hierarchy** — TEAM, ROSTER, STAFF, SCOUTING, SALARY CAP, LOCKER ROOM, KEY PLAYERS, POSITION GRADES, CONTRACTS, OWNER all have the same card weight, font size, and chrome. The eye has no entry point. Introduce a hero tile (e.g. "Next Action / Week Status") that dominates the top-right and demote secondary cards (LOCKER ROOM, POSITION GRADES) to a smaller summary row.
- [ ] Fix: All section header icons are the same yellow tint and same size — they compete for attention instead of guiding it. Use accent color only on the 1–2 sections that need attention this week (e.g. Coaching Changes, Contracts expiring), neutral grey otherwise.
- [ ] Fix: Card titles ("TEAM", "ROSTER", "STAFF", "SALARY CAP", etc.) are tiny all-caps labels — actual content (numbers, player names) dominates. Yet several cards waste a full row on the title alone. Consider inline header-with-value layout to recover ~15% vertical space.

#### 2. Visual flow / where the eye lands first
- [ ] Fix: The top-right metric strip "OWNER 95% / MORALE 66% / MEDIA Respected / LEGACY" is the largest, brightest cluster on screen and pulls the eye away from actionable items. These are passive status metrics — they should be smaller / collapsed under a single "Reputation" pill so the eye lands on the team card and pending tasks instead.
- [ ] Fix: The left rail "YOUR OFFSEASON" task list is the single most decision-relevant element on this screen but renders in low-contrast grey on dark grey, making it nearly invisible. The user is pulled to the right column instead of to the next thing they need to do. Bump left-rail text to high-contrast white and use a colored progress bar.
- [ ] Fix: 0-0 record bar shows a green progress bar at "85%" with no label — what does 85% represent? Reads as "85% of season done" which is wrong (the team is 0-0). Either remove the progress bar pre-season or label it (e.g. "Roster Strength 85%").

#### 3. Color & contrast
- [ ] Fix: Position Grades grid uses tightly clustered colored letter chips (B+, B-, C+ etc.) at small size — at iPad reading distance the +/- modifiers are almost unreadable. Either bump font size, drop the +/- and use color shade alone, or split into two visual rows (offense / defense) with bigger chips.
- [ ] Fix: "STAFF" card shows red "RETIRED" pill but the rest of the card is normal weight, so the warning is easy to miss. Outline the entire STAFF card in red/amber when staff is incomplete — make it obviously broken at a glance.
- [ ] Fix: "Contains 2 required tasks to advance" warning at left rail uses red text on dark — too small. Promote to a full-width amber banner above the grid when blocking tasks exist.

#### 4. Spacing & alignment
- [ ] Fix: Right-column cards (ROSTER, SCOUTING, LOCKER ROOM, POSITION GRADES, OWNER) are noticeably narrower than left-column cards (TEAM, STAFF, SALARY CAP, KEY PLAYERS, CONTRACTS). Asymmetric column widths look unintentional — pick a 50/50 grid or a clear 60/40 hero+rail split.
- [ ] Fix: KEY PLAYERS list shows player names truncated/clipped (e.g. "DeSean Simmons" fills the row to its OVR badge with no breathing room). Add right padding so OVR badges align in a tidy column.
- [ ] Fix: SALARY CAP card has the only progress bar that is full-width and colored amber — visually it reads as "alarm" but the team has $34.5M available which is healthy. Use green when cap is healthy, amber 90%+, red 99%+.

#### 5. Typography
- [ ] Fix: Numeric values use multiple scales without a clear ramp: "0-0" is mid-size, "$230.5M" is large, "53" is large, "84/83/80" are small. Establish a typography scale (Display / Title / Body / Caption) and apply consistently.
- [ ] Fix: "MORALE 66%" label sits below the 66% number but "OWNER 95%" label sits above its number — inconsistent label placement across the four stat tiles.

#### 6. Iconography
- [ ] Fix: Several cards have no icon (TEAM card icon column is empty in some sections) while others have generic star/chart icons that don't tell the user what kind of card they are looking at. Adopt a consistent icon vocabulary (helmet=Team, jersey=Roster, whistle=Staff, magnifier=Scouting, dollar=Cap, heart=Locker Room, chart=Grades, doc=Contracts, person=Owner, envelope=Messages).

#### 7. Empty/zero states
- [ ] Fix: SCOUTING card shows only "Visit scouts to begin scouting" — no count, no CTA button, no preview of what's available. Add a primary "Open Scouting" button and surface "X scouts available to hire", "Y prospects to evaluate".
- [ ] Fix: ROSTER card shows just "Players 53 / Cap Space $34.5M" — no signal about roster health, position holes, or what to do next. Add a "Review Roster" CTA and a 1-line health summary ("Needs: WR, EDGE").
- [ ] Fix: MESSAGES shows only 2 entries (League Office welcome + Owner roster assessment) but card height is fixed and big — dead space below. Either compact the card or pull weekly recap / draft news / FA news mock items so the inbox always feels alive.
- [ ] Fix: DIVISION standings preview shows "0-0 / 0-0 / 0-0 / 0-0" with no week label — pre-season this is meaningless filler. Replace with "Week 1 vs CHI — Sun 7 Sep" countdown until games begin, then swap to standings.

### Game Design (5 checks)

- [ ] Game: The "YOUR OFFSEASON" left rail mixes completed (greyed checks) with pending tasks but doesn't tell the user **which task unlocks the next phase**. User sees "Hire Offensive Coordinator REQUIRED" + "Hire Defensive Coordinator REQUIRED" but the dependency isn't explicit ("Combine starts after both coordinators hired"). Add a "Next milestone: NFL Combine — needs 2 hires" footer.
- [ ] Game: 4 distinct "Coaching Changes" sub-tasks (Hire OC, Hire DC, Review coaching staff, Review coordinator schemes) collapse the entire staff phase into a checklist. Players don't get the **strategic weight** of the choice — show the impact of each pending hire ("OC hire affects offense scheme + +X% playbook fit").
- [ ] Game: KEY PLAYERS shows 3 players (Love 84, Simmons 83, Robinson 80) but no signal of why they are "key" (captains? highest paid? best at position? expiring?). Add a tag per player: "QB1", "Top Cap Hit", "Expiring 2027". Also: only 3 is too few for an NFL roster — show 5-7 with role tags.
- [ ] Game: CONTRACTS card lists "10 expiring contracts" with 3 sample names (Robinson, Lewis, Green) and dollar amounts. Missing: WHEN they expire (end of this season? next?), priority order (re-sign vs let walk), and a single CTA "Review Free Agent List". This is the single highest-leverage decision in pre-season — give it more space.
- [ ] Game: POSITION GRADES grid is purely descriptive ("QB B+, RB B-, WR C+...") — no actionable hook. Click into a position to see depth chart? Compare to league average? Weakness positions (anything ≤ C) should have a small alert dot, and tapping should jump to that position group on the roster.

### Decision Support

- [ ] Game: "What should I do next?" answer is buried. The left rail has it, the warning banner hints at it, but no single "Next Action" card. Add a top-row "RECOMMENDED NEXT" hero card that names the single best next action with a primary button (e.g. "Hire Offensive Coordinator — required to advance week").
- [ ] Game: User cannot tell what week / phase of the season they are in from the dashboard alone. Top bar shows "12.00 Thu 30. Apr" (real device time) but not the in-game week ("Week 0 — Off-season — 14 weeks until Week 1"). Add an in-game date + phase chip next to the team name.
- [ ] Game: No quick-access to common actions. Common pre-season actions (Sign FA, Open Scouting, Review Roster, Trade Block) require navigating into separate tabs. Add a small "Quick Actions" row of 4-5 chips beneath the metric strip.
- [ ] Game: Top nav shows 6 destinations (Roster / Staff / Schedule / Standings / Draft / Scouting / Cap) but dashboard cards duplicate most of them with the same labels. Either drop the top tab bar on Dashboard (cards = navigation) or stop labelling cards with the same words (TEAM card does not navigate to Team — confusing).
- [ ] Game: OWNER card shows Jed Ross with stars, satisfaction "85%" green and an inline value but no expectations / upcoming demands. Owner satisfaction is most useful when it shows **what would change it** ("+5 if you hire OC this week", "-10 if you miss playoffs"). Without that, 85% is just a vanity number.

### Bugs / Data
- [ ] Bug: SALARY CAP card shows "Used $230.5M" / "Available $34.5M" / total ~$265M but NFL 2026 cap is ~$255M. Either the displayed total is the projected cap incl. carryover, or the math is off — surface the breakdown ("Cap $X + Carryover $Y = $Z").
- [ ] Bug: STAFF card shows "0/20" with a yellow "RETIRED" pill and budget "$27.3M / $32.7M" — but if the count is 0/20 the budget used should be $0, not $27.3M. Likely showing committed/contracted budget while count shows "filled positions"; either align the labels or show "Spent: $27.3M (committed) / Used positions: 0/20".
- [ ] Bug: TEAM card shows "0-0 #2" — pre-season ranking #2 makes sense, but no source label for the rank ("Power Rank #2 — Vegas Odds" or "Preseason Media Rank #2"). Without label, users will assume it is current standings rank, which contradicts 0-0.
- [ ] Bug: "Advance to Review Roster" CTA at the bottom of left rail is the only red/destructive-styled button on screen. Red usually = destructive — change to primary blue/green since "advance" is the desired action.
- [ ] Bug: MESSAGES shows "2" badge but only 2 unread? Confirm whether the badge counts ALL or only unread. Inbox tabs (All / News / Tasks) are visible but no counts on each — add per-tab counts.
- [ ] Bug: Onscreen date "Thu 30. Apr" suggests late April. In NFL calendar terms that is post-draft / OTA period. But task list talks about "Send scouts to Combine" (Combine = February) and "Sign Free Agents" (FA = March). The task list is out of phase with the date — verify the offseason scheduler is firing tasks in the right month.

---
**Summary: 31 findings (16 Fix / 10 Game / 5 Bug)**

Top 5 most critical:
1. **No visual hierarchy / no "Next Action" hero** — every card is equal weight, user has to read the entire screen to find what to do next. (Fix + Game)
2. **Left rail task list is low-contrast** — the most decision-relevant content on the page is the hardest to read. (Fix)
3. **CONTRACTS / FA decisions are under-served** — 10 expiring is the highest-stakes pre-season choice and gets the same card real estate as POSITION GRADES. (Game)
4. **Offseason task list is out of phase with the date** — Combine/FA tasks shown in late April. (Bug)
5. **STAFF card 0/20 vs $27.3M committed mismatch + ambiguous "Advance to Review Roster" red button** — both data and CTA semantics likely wrong. (Bug)

---

## Onboarding Flow Analysis (auto_14 - auto_18)

### [PressConfSummary] (auto_14_press_summary.png)
Note: Screenshot shows in-progress "Question 4 of 4" with a Diplomatic answer selected and the bottom "NFL Network" media-reaction footer. There is no separate post-conference summary visible — findings reflect what is on screen.

Visual Design:
- [ ] Fix: Non-selected answer cards (Confident / Honest / Combative) are nearly illegible — text is washed out against the dark photo background. Either dim less, or add a translucent panel behind each card to keep text readable while still de-emphasising.
- [ ] Fix: Header metric pills show "Legacy 0, Media 0, Satisfaction 70%" with a tiny gold star/leaf glyph but no scale/context. Add unit/range (e.g. "0 / +5", "+0 pts") so values read as deltas, not stats.
- [ ] Fix: Footer caption ("Stars affect job security, Image affects public narrative, Legacy affects career rating") is truncated/low-contrast. Bump to ~11pt and increase opacity, or move to an info popover.
- [ ] Fix: Background reporter photo is busy under the answer cards; add a darker scrim (0.7+ alpha) so cards do not float over facial features.
- [ ] Fix: Selected (Diplomatic) card has a clear green border, but other cards have NO visible border — affordance "tap to select" is lost. Add subtle borders to all answer cards.
- [ ] Fix: "NFL Network: Packers putting emphasis on the draft." footer block has no header label; clarify with a "Media reaction" label or small mic icon.
- [ ] Fix: Yellow "NFL Network" badge on the question card competes with yellow page header text — pick one yellow accent per region.

Game Design:
- [ ] Game: After answering, the metric pills still read 0/0/70% — no visible delta. Animate the pill change (+1 Media, +2 Legacy) so player sees immediate consequence.
- [ ] Game: Only 4 questions x 4 archetypes — combinations repeat quickly. Add reporter-specific follow-ups or a "wildcard" question seeded from team state (expiring contracts, weak position group).
- [ ] Game: Showing all four archetypes (Confident / Honest / Combative / Diplomatic) every time makes the meta obvious. Consider showing 3 of 4, gated by personality unlocks or randomization.
- [ ] Game: Media reaction "Packers putting emphasis on the draft" mirrors the question topic, not the answer. Should reflect the chosen answer ("Coach playing it safe on draft talk" for Diplomatic).
- [ ] Game: Initial 70% Satisfaction is unexplained — owner / media / career? Add a tooltip or legend.

Decision Support:
- [ ] Game: Player needs a "what each archetype affects" cheat sheet visible during selection. Currently the chips inside each answer card (Career +2, Morale +1) are blurred until selected, so options cannot be compared before committing.

### [OwnerMeeting] (auto_15_owner_meeting.png)
Visual Design:
- [ ] Fix: Owner portrait is a generic blonde stock photo but name is "Jed Ross" (typically male). Either rename to a female owner or swap the portrait so name + image align.
- [ ] Fix: "OWNER MEETING" header label is yellow uppercase but very thin — bump weight or letter-spacing so it reads as a clear section title.
- [ ] Fix: All four trait rows (Vision / Patience / FA Budget / Involvement) use the same yellow icon — no semantic hierarchy. Encode sentiment via icon hue (green = positive, amber = neutral, red = restrictive).
- [ ] Fix: "Conservative" budget and "Highly Controlling" involvement are restrictive but rendered in neutral yellow — should tint amber/red to telegraph friction.
- [ ] Fix: Pull-quote at bottom ("I trust you, but I'd like to stay close to the operation. Don't shut me out. — Jed") shows a warning triangle plus "Failure may result in: budget cuts, forced trades, or termination..." but the warning text is truncated. Show full text or make expandable.
- [ ] Fix: Vertical breathing room between trait rows and their sub-bullets is tight — add 6-8pt spacing.
- [ ] Fix: "SEASON GOALS" card sits orphaned between trait list and quote; tighten the layout or merge into a single card with header sections.

Game Design:
- [ ] Game: Owner traits should affect mid-season events (e.g. Highly Controlling owner pings on big trade decisions). Confirm a gameplay hook exists, otherwise this becomes flavor text only.
- [ ] Game: "Free Agency Budget: Conservative — Budget $27M (league avg $38.5M)" is good context, but show the practical limit ("No single contract over $20M AAV without owner approval") so the player feels the constraint.
- [ ] Game: "Expects results within 6 seasons" — is the countdown surfaced on the dashboard? If not, add a Year X / 6 chip so the patience timer is felt.
- [ ] Game: Goals "Win the division" + "Build depth through the draft" are clear but lack measurable success criteria (how many draftees stick? what counts as "depth"?). Add specific KPIs.
- [ ] Game: Owner personalities should vary by team — verify Jed Ross is procedurally generated, not hardcoded for the Packers.

Decision Support:
- [ ] Game: Add a "What this means for you" panel summarising in 2-3 bullets the practical limits (cap room available, FA budget cap, owner-veto threshold) so the player understands constraints before continuing.

### [TeamOverview] (auto_16_team_overview.png)
Visual Design:
- [ ] Fix: "Average Overall 71 (avg: 71)" — parenthetical "(avg: 71)" duplicates the value with no clarification (league avg? team avg?). Label as "(League: 71)" or remove.
- [ ] Fix: "Average Age 27.5 (Avg: 26.0)" — same ambiguity, plus 27.5 vs 26.0 should be color-coded (red/amber if older than league).
- [ ] Fix: Position group cards show a "B+ / C+" two-grade format (current/projected? scout/true?) without a legend. Add a header tooltip explaining the two grades.
- [ ] Fix: ST (Special Teams) card shows "B+ / F" — F grade is alarming yet the card is bordered green. Either explain (kicker missing? returner missing?) or recolor for consistency.
- [ ] Fix: WR card shows "B- / C, 73 OVR, 7/8 players", but the Roster summary's Weakest Group says "WR (C+, 67 OVR)". Numbers conflict (73 vs 67, C vs C+) on the same screen.
- [ ] Fix: "Coaching Staff 0 / 15 filled" in red is correct urgency but visually equal to the Roster summary — separate it into a dedicated action card with a "Hire Now" CTA.
- [ ] Fix: Salary cap progress bar fills almost full, yet "$34.5M Available" green text is the eye magnet to the right — the bar appears to encode Used. Add cap floor markers (rule of 51, dead cap) and label the bar.
- [ ] Fix: "League Avg Cap Space: ~$25.0M" caption under the bar is very small and barely visible.

Game Design:
- [ ] Game: Key Players list shows 3 players (Robinson, J. Love, DeSean Simmons) — what selects them? Top 3 by OVR? Make the list tappable to expand and add a tag (QB1 / Top Cap / Expiring).
- [ ] Game: "Expiring Contracts: 10 players" is high-impact info — should be tappable to drill into who. Currently dead text.
- [ ] Game: Position group "X/Y players" implies depth chart slots — clarify whether that's starters filled or roster slots, and surface positional needs ("Need: 1 OL, 2 DL").
- [ ] Game: With 53 players and avg OVR 71, the team profile should suggest a meta-strategy ("Veteran roster, retool or reload?") to anchor the dynasty narrative.
- [ ] Game: Salary cap section is purely informational — add a "Cap Health" verdict (Healthy / Tight / Crisis) for at-a-glance reading.

Decision Support:
- [ ] Game: Add a "First Moves Recommended" panel: e.g. "Hire OC, OL coach (priority), then re-sign RB Robinson before FA opens." This screen has all the data; surface 3 concrete next-step recs.
- [ ] Bug: Conflicting WR metrics between Position Group card (73 OVR, B-) and Roster summary (67 OVR Weakest Group, C+). One calculation is wrong or uses different scope — reconcile.

### [Roadmap] (auto_17_roadmap.png)
Visual Design:
- [ ] Fix: All calendar items below "Coaching Changes" are dimmed and date labels are illegible. Even if locked, dates should be readable so the player knows the schedule.
- [ ] Fix: "Coaching Changes — CURRENT" pill plus "Apr — May" date range conflicts with the device showing "Thu 30. Apr" — clarify whether dates are calendar dates or relative weeks.
- [ ] Fix: "YOUR FIRST TASKS" card overlaps a silhouette background image awkwardly. The silhouette is mostly hidden and adds visual noise without storytelling. Either fade more or remove.
- [ ] Fix: Numbered task circles (1/2/3) are small; bump diameter and use a yellow fill on the active task only.
- [ ] Fix: Calendar list has 9 phases but only the first has a sub-description ("Hire new coaches, set coordinator schemes, build your staff"). Either add tap-to-expand for all phases or remove the lone description for consistency.
- [ ] Fix: No estimated time / week count per phase — player has no sense of how long offseason takes.
- [ ] Fix: "OFFSEASON CALENDAR" header is yellow micro-caps; same style as the page heading "YOUR ROADMAP" — too many small yellow labels stacked together.

Game Design:
- [ ] Game: "Your First Tasks" item 3 ("Prepare for the Combine and Free Agency") is two distinct things — split into atomic tasks.
- [ ] Game: Locked future phases (Roster Eval, FA, Draft, OTAs, Camp, Preseason, Cuts, Regular Season) should preview a single key decision per phase ("Cut day: 53-man") to build anticipation.
- [ ] Game: No phase shows expected outcomes ("Free Agency: ~5 signings, $20M committed") — the player doesn't know what good looks like.
- [ ] Game: Tasks should map to tappable destinations on the next screen — confirm "Hire coaching staff" deep-links to Hire Coach view.
- [ ] Game: Roadmap is offseason only — show a hint that regular season is the destination, not just another bullet at the bottom.

Decision Support:
- [ ] Game: Add a short "Why this order?" tooltip — players new to NFL ops won't know that staff hires affect FA targeting and draft scheme fit.

### [Ready] (auto_18_ready.png)
Visual Design:
- [ ] Fix: Stadium background image is very dark — almost reads as black void with a thin band of stadium lights. Add subtle field-line pattern or boost ambient lighting so the setting reads.
- [ ] Fix: "Build Your Dynasty." subtitle in yellow + "Write your legacy." italic gray below feel redundant. Pick one tagline.
- [ ] Fix: Football icon at top is small and centered — could be larger and have a subtle pulse animation on this hero "go" screen.
- [ ] Fix: "with the Green Bay Packers" copy is good but Packers green/gold branding is missing — this is the moment to apply team colors and logo.
- [ ] Fix: CTA "Enter the Front Office →" is the right copy and size, but bottom-pinned with lots of dead space above. Either pull the CTA up or fill mid-screen with a hype stat ("53 players, 12 staff openings, 16 weeks until kickoff").
- [ ] Fix: Yellow accent radial glow behind football icon is very subtle — commit harder or remove.
- [ ] Fix: No "Onboarding complete" indicator — a small checkmark or progress complete chip would close the loop from earlier setup screens.

Game Design:
- [ ] Game: This screen is a pure transition — could be the moment to stamp "Year 1, Week 1" to anchor the dynasty timeline.
- [ ] Game: Missing summary of choices: coach name, owner expectations, roster summary in 1 line each before the final CTA — players forget their setup otherwise.
- [ ] Game: No achievement / first-time-only animation — onboarding should celebrate.
- [ ] Game: Could surface 1 randomized "rookie GM mistake" tip ("Don't blow FA budget in Week 1") for first-run only.
- [ ] Game: Confirm CTA is one-way — if user backs out from front office, do they re-enter this screen? Edge case to verify.

Decision Support:
- [ ] Game: Add a "What's next" hint under the CTA: "First stop: Hire your coaching staff" so the player knows their first concrete action.

---
**Onboarding flow summary: 64 findings**
- [PressConfSummary]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [OwnerMeeting]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [TeamOverview]: 15 (8 Fix / 5 Game / 1 Decision Support / 1 Bug)
- [Roadmap]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [Ready]: 12 (7 Fix / 5 Game / 1 Decision Support — 0 Bug, includes onboarding-complete polish)

Top cross-screen themes:
1. **Yellow accent overuse** — every screen labels page headings, section labels, and CTAs in the same yellow micro-caps; hierarchy collapses.
2. **Truncated/low-contrast helper text** — press conference footer captions, owner warning details, and roadmap dates all suffer the same legibility issue.
3. **Data conflicts** — WR position grade conflict on Team Overview is a real bug to chase down.
4. **Decision support gaps** — every onboarding screen could end with a "What this means / What to do next" mini panel; right now the player must remember everything they read.
5. **Owner avatar/name mismatch** — Jed Ross with a female stock photo is the most jarring visual issue in the flow.

---

# AUTO-ANALYZE: Coaching Staff + Roster + Player Detail Pass (2026-04-29)

## [CoachingStaff] — Coaching Staff initial vacant view (auto_20)

Visual Design:
- [ ] Fix: Yellow underline under "Staff" tab header is fine, but Schemes/Review tabs are unreadable (very dim grey on dark) — looks disabled, not just inactive.
- [ ] Fix: "Coaching Budget" row reads "$0.0M / $27.0M used" with the green "$27.0M remaining" right-aligned — the "/ $27.0M used" wording is confusing because $0 has been used. Should be "$0.0M used of $27.0M" or pick one phrasing.
- [ ] Fix: Section number badges (1 Head Coach, 2 Coordinators, 3 Position Coaches) are small dim circles — the "1" on Head Coach is barely visible. Up the contrast or color them by tier.
- [ ] Fix: HC card uses a yellow "HC" chip but the avatar is also a yellow circle — visual collision. Pick one accent shape.
- [ ] Fix: "Vacant — Tap to hire" rows have no obvious affordance (no chevron, no button). Right-side "+" circles look secondary; the entire row should feel tappable with a subtle highlight on press.
- [ ] Fix: Section subtotals "$2.3M-$25.5M  0/3" right-aligned in coordinator header — the dash range is good info, but the "0/3" is ambiguous (filled/total). Add a label like "filled" or use a progress bar.
- [ ] Fix: Position Coach mini-cards are tightly packed and text starts mid-row — vertical alignment looks off (QB Coach text floats). Tighten cell padding.

Game Design:
- [ ] Game: Three "High Priority" red badges on all 3 coordinators — that priority signal is now meaningless. Differentiate (e.g. OC=High because Spread is your scheme, DC=Medium, ST=Low) based on actual gap analysis.
- [ ] Game: The "+10 Play-Calling" / "+12% offensive efficiency" boost lines are abstract. Show what 12% efficiency means in concrete terms ("approx 1.5 extra wins") so the player understands the value.
- [ ] Game: HC card already shows player as the HC ("You (Test GM)") with description — but it's labeled as if the player is also a tactician. If user is GM-only, this is confusing role-mixing.
- [ ] Game: No indication that hiring order matters (HC affects coordinator chemistry, coordinators affect position coach pool). Add a tooltip or subtle stepper.
- [ ] Game: Budget pacing: $27M is full but no warning that hiring an elite HC at $8M leaves only $19M for 11 remaining slots. Add a "projected remaining" preview as you click into hire flows.

Decision Support:
- [ ] Game: Add a "Recommended next hire" highlight (e.g. star next to OC because it's highest-impact). Right now every vacancy looks equal.

## [HireAHCList] — Hire Assistant Head Coach list (auto_21b)

Visual Design:
- [ ] Fix: Modal title "Hire Assistant Head Coach" is clear, but "Close" link in upper-left is small and easy to miss. Use an X icon.
- [ ] Fix: TOP 3 yellow chips next to candidate names are good, but the existing scheme/personality chips (LongTimeCoach, etc.) push the row to wrap on smaller widths. Tighten chip styles.
- [ ] Fix: Filter pill row (Scheme / Personality / Colors / Affordable) is squashed and the "Colors" toggle is unclear — does it mean "show team color preference"? Label it "Team Colors" or use an icon.
- [ ] Fix: Column headers (Age, Scheme, OVR, Pers, Sav) are tiny and right-aligned, hard to scan. The "Sav" abbreviation isn't obvious (Savings? Salary? Save?).
- [ ] Fix: Numerical columns mix yellow, green, and white with no consistent meaning — color-code by metric quality (good=green, neutral=white, bad=red) consistently.
- [ ] Fix: Modal sits on top of the dimmed parent screen but there's no clear elevation/shadow — modal feels flat against the bg.
- [ ] Fix: "26 candidates" count is hidden in the top-right of the budget area — promote it to a header pill so user knows total pool size.

Game Design:
- [ ] Game: TOP 3 ranking is good, but show *why* they're top 3 inline (e.g. "Best scheme fit" / "Best value"). Currently they're just yellow-badged.
- [ ] Game: "Affordable" toggle is binary — would be more useful as a slider for max salary, or auto-respect remaining budget.
- [ ] Game: No way to compare 2 candidates side by side. Add a "compare" check on rows.
- [ ] Game: Personality archetype shown as colored chip but the meaning is invisible until detail view. Hover/long-press tooltip for archetype effect.
- [ ] Game: Budget remaining ($27M) shown but no preview of "after hire" delta when row is selected.

Decision Support:
- [ ] Game: Add a "Best Available" sort/filter that highlights candidate with highest expected impact given current staff (none yet, so this is wide open).

## [CandidateDetail] — Candidate Profile Trevon Jenkins (auto_22)

Visual Design:
- [ ] Fix: Layout is dense and information-rich (good!) but the "Solid Ceiling" / "Option" / "Plays Sup" chips wrap and clip — give them a fixed pill style.
- [ ] Fix: "Best Available" badge in upper right is yellow on dark — good, but redundant with TOP 3 from list view.
- [ ] Fix: Attributes block uses yellow numbers + green "Great"/"Avg" subtags — but every metric has a different rating word ("Great", "Good", "Avg"), and reading them inline crowds the column. Use a single color-coded bar.
- [ ] Fix: Scheme Expertise bars (Pro/Spread/RPO/etc.) are great but the right-side letter grade column (A/B/C/D/F) is overlapping with the bars on smaller widths.
- [ ] Fix: "Coaching Style" section repeats personality info already shown in header chips — consolidate.
- [ ] Bug: "HC Chemistry: Unknown" with sub-text "No Head Coach hired to evaluate chemistry" — but the player IS the HC ("You (Test GM)"). Logic error in chemistry display when GM == HC.
- [ ] Fix: "Negotiate" section's slider and "Acceptance: Very High" feedback is the right pattern, but the slider thumb is a thin gold bar — hard to grab on iPad. Use a larger circular handle.

Game Design:
- [ ] Game: "Projected Contribution: Projected wins +0.1 / season" — that's a tiny number. If accurate, hires feel pointless. If sandbag, it's misleading.
- [ ] Game: Career History card is ONE line. For 18 years of experience, show team history, win rate, ring count.
- [ ] Game: "Background" paragraph is good color, but every coach can't have unique copy — verify generation quality across all 26.
- [ ] Game: Scheme Fit graph isn't visible/labeled in the screenshot — the "Scheme Expertise" bars look like the only graph. Confirm "Scheme Fit" graph spec is implemented.
- [ ] Game: "Roster-wide dev -0.1% / season" is a NEGATIVE for a hire — surprising and unflagged. Either correct the calc or warn the user.

Decision Support:
- [ ] Game: Acceptance: Very High + Budget after $21.6M is great. Add "if rejected, next best candidate" preview to soften loss aversion when proposing low.

## [CoachingStaffFull] — Coaching Staff after all 8 position coaches hired (auto_46)

Visual Design:
- [ ] Fix: Banner "Trey Jenkins hired as Strength & Conditioning!" is a green strip — solid pattern but appears persistent. Auto-dismiss after 3s.
- [ ] Fix: STC card row shows "Joe Anderson, Age 50, 19 yrs exp, $200K/yr" with star rating + "Good Fit" — the small star row and "Good Fit" both communicate the same thing. Pick one.
- [ ] Fix: Position Coach grid (8/8 filled, $6.1M total) — coach names + ratings render but the OVR number is large yellow on the right and not aligned with name. Tighten vertical alignment.
- [ ] Fix: Support Staff section split between Medical and Scouting — Scouting has 6 vacant rows ALL with red "High Priority" + "Recommended" — same priority overuse as before. Differentiate.
- [ ] Fix: Medical Staff shows DOC and PHY chips with color codes — these are unique abbreviations not used elsewhere; spell out on first appearance.

Game Design:
- [ ] Game: Position coach OVRs range 73–88 but no aggregate "position coaching strength" rating. Add a roll-up.
- [ ] Game: STC ($200K) vs position coaches ($613K–$1.18M) — pricing curve seems inverted (STC should be higher tier than some position coaches). Verify economy.
- [ ] Game: 6 regional scouts all "Recommended" with same +5% effect — diminishing returns aren't communicated. Show that hiring all 6 isn't necessarily optimal.
- [ ] Game: Chief Scout marked High Priority and the regionals "Recommended" — good differentiation. Reinforce by showing the cap on parallel scout effectiveness.
- [ ] Game: No "save staff template" feature for replays — sandbox depth idea worth tracking.

Decision Support:
- [ ] Game: Bottom of page has no "you spent $X of $27M" total, just per-section spend. Add a final summary bar with "X budget remaining → Z impact projected".

## [ReviewRosterPhase] — Dashboard with Review Roster phase tasks visible (auto_57)

Visual Design:
- [ ] Fix: Coaching Staff Review modal overlays the full dashboard — backdrop dimming is decent but the underlying content is busy and bleeds through. Increase opacity.
- [ ] Fix: Modal header "Coaching Staff Review" + sub-label "STAFF" + "12/14 hired" — three labels stacked, kill at least one.
- [ ] Fix: Each staff row (HC, AHC, OC, DC, etc.) shows green check + name + OVR + sometimes a tag like "Spread" or "Multiple" — tags only on coordinators, inconsistent.
- [ ] Fix: SCHEMES & EXPERTISE section is cut off at the modal bottom edge — modal needs to be scrollable or larger.
- [ ] Fix: Behind-modal NEW WEEK ribbon ("ALL TASKS COMPLETED! READY TO ADVANCE") in upper-left is hidden — important state info is occluded.

Game Design:
- [ ] Game: 12/14 hired but the modal lets player advance — should we block "Confirm & Advance" until all critical roles filled? Or show what's missing.
- [ ] Game: Staff OVRs listed (71, 64, 76, etc.) but no aggregate "Staff Power" rating to compare against league average.
- [ ] Game: "Spread" and "Multiple" scheme tags appear next to coordinators — but no indication if those match each other (offense + defense compatible?). Add fit warning.
- [ ] Game: No "if you advance now, you can re-hire later for $X penalty" disclosure. This phase feels final but mechanics aren't spelled out.
- [ ] Game: Calendar advancement consequence: does any staff become unavailable next week? No info on time pressure.

Decision Support:
- [ ] Game: Add a "Confidence rating" verdict at top of modal ("Your staff is ready for a Spread offense — confident HC & OC fit, weak ST coordinator").

## [StaffReviewModal] — Coaching Staff Review modal scrolled (auto_58)

Visual Design:
- [ ] Fix: "OFFENSIVE SCHEME: Spread" with bars for "Coach Fit 52%" and "Roster Fit 45%" — bar lengths look correct but both are mid-yellow (warning). No baseline marker for "good vs bad threshold".
- [ ] Fix: "Alternative: Pro Passing — Coach: 46%, Roster: 53%" — already shown but the alternative recommendation could be more visually highlighted (suggested arrow or chevron).
- [ ] Fix: "DEFENSIVE SCHEME: Multiple" — Coach Fit 80% is good but Roster Fit 35% is RED — this contrast is excellent, keep it.
- [ ] Fix: Staff chemistry "Poor" red badge is alarming and good, but no actionable hint ("Hire AHC with Mentor archetype to improve").
- [ ] Fix: Confirm CTA is locked (padlock icon) with "Confirm & Advance to Review Roster" — locked state isn't visually differentiated from enabled state. Use disabled grey.

Game Design:
- [ ] Game: "Consider switching — Pro Passing may be a better fit" — actionable, but switching scheme post-hire should have a stated cost (chemistry hit). State it.
- [ ] Game: 35% defensive Roster Fit is bad — this should trigger a "draft/FA priority" tag for matching defenders, surfaced later.
- [ ] Game: "Staff chemistry: Poor" — what drives this? Personality clashes? Show top 1–2 culprits.
- [ ] Game: 52% / 45% scheme fits feel like punishment for the player's earlier HC choice. If user can't fix it now, the gate creates frustration.
- [ ] Game: No "lock in scheme" alternative path — locked HC = locked scheme implicitly. Make explicit.

Decision Support:
- [ ] Game: Add "Project this staff over 3 years" preview — current snapshot is harsh, but projection gives hope/realism.

## [RosterOffense] — Roster Offense tab (auto_60)

Visual Design:
- [ ] Fix: Top KPI strip (53 Players / 53 Healthy / 0 Injured / 71 Avg OVR / $230M cap) is dense — labels are tiny, values readable. Group with subtle dividers.
- [ ] Fix: List View / Formation toggle yellow pill is good. "Overview / Contracts / Development / Physical / Position Skills / Depth" sub-tabs are dim grey. They look disabled.
- [ ] Fix: Position Group headers (QB Room / Backfield / Wide Receivers) include a dense info row "B+ / C+ $26.6M [Aging] [Solid starters] [Review]" — too many chips, unclear hierarchy. The grade letter A–F system is good; ditch the labels.
- [ ] Fix: Player rows: position chip (QB/RB/WR), helmet logo, name, age, trend arrow, OVR, salary, years, status emoji, green check, chevron. That's 10 elements — too busy. Drop redundant info.
- [ ] Fix: Trade arrow icons (red ↓, green ↑, yellow→) inconsistent — sometimes after age, sometimes after OVR. Standardize column.
- [ ] Fix: Heart and Smiley emoji status indicators are cute but unclear semantics. Use clear icons.
- [ ] Fix: "Tap column headers to sort" hint is in tiny yellow text mid-screen — easy to miss. Show after first scroll.

Game Design:
- [ ] Game: Position group grades (B+ / C+) are a great quick-scan signal, but no explanation of formula. Tap-to-explain.
- [ ] Game: Wide Receivers labeled "Project Need" — good roster intel. Show what the project means (need 2 more WRs by Week X).
- [ ] Game: "Trade Watch" tag on certain players — implies the AI is generating trade rumors. Surface what the player can DO with this info.
- [ ] Game: 53/53 healthy but no fatigue/training load indicator at season start.
- [ ] Game: Cap usage $230M / $265M — does $35M include dead cap? Break down on tap.

Decision Support:
- [ ] Game: Add "Top 3 priority decisions" pill at top ("1. Cut aging WR Malik Taylor, 2. Extend J. Love, 3. Promote Andre Walker"). Right now player must hunt.

## [RosterDefense] — Roster Defense tab (auto_61)

Visual Design:
- [ ] Fix: Same dense row chrome as Offense — see [RosterOffense] notes.
- [ ] Fix: Defensive Line group rated B / C+ — first time we see two grades. Confirm meaning (talent/depth?) and label.
- [ ] Fix: "1 exp" tag on DL header — what does "exp" mean here? Expiring? Experience? Spell out.
- [ ] Fix: Linebackers shows "B+ / C+ $32.2M 1/7 1 exp [Aging] [Review]" — "1/7" appears to be starters? Add label.
- [ ] Fix: Trend arrows pointing down (red) on James King (79), Sam Sanders (78), and others — large amount of red on starters is alarming and may be misleading; soften visual weight.

Game Design:
- [ ] Game: 9 DL rows but no clear "starters vs depth" division — 4-3 vs 3-4 needs different counts. Show formation alignment.
- [ ] Game: "Trade Watch" on Darius Jenkins (ML 77) — what's the trade value? Surface inline.
- [ ] Game: Khalil Carter (67 OVR, 24 yo, $750K) is a developing player — flag as "stash" or "development priority" not generic.
- [ ] Game: Defensive scheme fit (35% from prior screen) should be reflected per-player here as a column or color coding.
- [ ] Game: No indication of which players struggle in current scheme — opportunity for clearer sim narrative.

Decision Support:
- [ ] Game: Show "if you cut [DT Travis Turner], cap savings = $X, dead cap = $Y" in a hover/tap preview — already in player detail but could surface earlier.

## [RosterSpec] — Roster Spec Teams tab (auto_62)

Visual Design:
- [ ] Fix: Specialists section has only 2 players (K and P? unclear from chips) — vast empty space below. Use it for ST coverage units (gunners, returners, long snapper) or collapse.
- [ ] Fix: "Project Need" red chip on Specialists header — but only 2 specialists shown. Either show needed slots as ghost rows or explain the need.
- [ ] Fix: Sub-tabs (Overview/Contracts/Development/Physical/Position Skills/Depth) at top still rendered — do they all apply to specialists? Some likely don't; hide.
- [ ] Fix: Bottom 60% of screen is nearly empty — layout doesn't adapt for sparse tabs.

Game Design:
- [ ] Game: Special teams in NFL include kick/punt return units, blocking, gunners. This view treats it as just K/P which under-represents the unit.
- [ ] Game: Long snapper, holder, returners — mini-roles invisible. Add them.
- [ ] Game: Kicker rated 85 OVR (Terrell Robinson) — good info but no field goal range / accuracy split.
- [ ] Game: "Trade Watch" on both specialists is suspicious — special teamers rarely trade. Verify generator logic.
- [ ] Game: No indicator of where specialists fit in cap — most teams sub-$5M total here, would be useful context.

Decision Support:
- [ ] Game: Add an "ST coverage rating" (A–F) for the unit as a whole, since individual specialists alone don't tell the story.

## [PlayerDetailTop] — J. Love Player Detail top (auto_63)

Visual Design:
- [ ] Fix: Header card uses yellow OVR ring (84) with "Top 11% QB" subtext — strong visual, good. The "Rising" green pill near Offense chip is small; promote.
- [ ] Fix: Header strip (79 Morale / OK Health / $23.27M Salary / 3yr Contract) is excellent dense info — great pattern.
- [ ] Fix: Overview + Contract cards are side-by-side — good iPad use. But "Cap %: 9.0%" yellow value vs "Salary $23.27M" yellow value — every key number is yellow, lose impact.
- [ ] Fix: "Top 5 QB · $39.2M-$48.9M" is critical comparison data buried small at bottom of Contract card. Promote.
- [ ] Fix: Development bar (green gradient) with "Rising  Peak 28-30" — clean. But "Entering prime in ~2 years. Expect improvement." copy is in yellow. Use neutral text color.
- [ ] Fix: Season Stats: "No stats recorded this season" in greybox is fine, but this is week 1 — communicate that more clearly ("Season starts Week 1").
- [ ] Fix: Trade Value card: "2nd Round Pick" yellow icon + Overall/Age/Contract checkmarks — what do the checkmarks mean (favorable factors?)? Label.
- [ ] Fix: "If Love leaves: Coleman starts at QB - 70 OVR (-14)" — KILLER feature, but the dash separator and "(-14)" formatting could be a clear red badge.
- [ ] Fix: Action grid: 5 buttons (Set as Starter, Extend Contract, Propose Trade, Cut/Release, Change Position) — Cut/Release red is good. Extend Contract sub-text "$26.34M / 5yr" is a teaser of negotiation — great.

Game Design:
- [ ] Game: "Top 11% QB" is great signal. Show position rank within team and within league side-by-side.
- [ ] Game: Contract section shows Years 3, Salary $23.27M, Cap % 9%, Market $28.31M — Market value is a stat I love. Show "underpaid by $5M" in a positive accent.
- [ ] Game: "Fair Value" check on contract — green; clarify what "Fair Value" actually flags.
- [ ] Game: "Set as Starter" — but if he's already starting, button should toggle to "Bench". Verify state.
- [ ] Game: "Change Position" button on a 84 OVR QB is unusual — should be disabled or hidden for non-versatile players.

Decision Support:
- [ ] Game: Replacement preview is the best decision-support pattern in the app — extend to "If you trade Love: cap relief $X, draft capital Y, roster impact -14 OVR". Already partially shown; complete the loop.

## [PlayerDetailMid] — J. Love Player Detail mid scroll (auto_64)

Visual Design:
- [ ] Fix: Position Versatility section: QB 100% (yellow), RB 20% (orange-yellow), WR 27% (orange-yellow). Sub-text on each is helpful but the visual bars are barely-tinted. Lift contrast.
- [ ] Fix: "Athletic QB can line up as WR in trick plays. Max ceiling: 40%" — tiny copy. Consider a tooltip pattern instead of inline.
- [ ] Fix: Scheme Familiarity section uses 4 distinct color bars (yellow/green/blue/red) for ProPassing/Spread/RPO/WestCoast — and 4 grey rows for AirRaid/PowerRun/Shanahan/Option (0%). Mixing colors-by-scheme with bar lengths makes it hard to compare values. Pick one encoding (length or color, not both).
- [ ] Fix: "0%" rows are visually dead — collapse into a "Not familiar with: AirRaid, PowerRun, Shanahan, Option" footnote.
- [ ] Fix: Injury History card: green check + "No injury history" + Durability 83 score on right — clean. Keep.
- [ ] Fix: Physical Attributes 2-col grid (Speed 82 / Acceleration 78, etc.) — green numbers across the board. If they're all in the green band the color stops adding meaning.

Game Design:
- [ ] Game: Versatility 27% as WR is interesting "trick play" depth. But there's no surfacing in game ("Use Love as a WR decoy this week"). Wire it to playbook.
- [ ] Game: Scheme Familiarity 83% ProPassing on a player on a Spread team (per current scheme) — that's the misfit story to amplify. Add "Mismatch: -8% efficiency in current scheme".
- [ ] Game: Durability 83 / no injury history — should also show "career games missed: 2" for context.

Decision Support:
- [ ] Game: Add a "Scheme transition cost" if user is considering changing schemes — Love loses 25% efficiency until he rebuilds Spread familiarity. Currently invisible.

## [PlayerDetailBot] — J. Love Player Detail bottom scroll (auto_65)

Visual Design:
- [ ] Fix: Mental Attributes 2-col grid (Awareness 83 / Decision Making 77, etc.) — same issue as Physical: all green so color stops carrying signal.
- [ ] Fix: Quarterback Skills: Arm Strength 87 (79), Accuracy Mid 85 (88), etc. — the second number in parens (true rating vs scout rating?) needs a legend. This is a scouting accuracy feature buried.
- [ ] Fix: Pocket Presence 89 (89), Scrambling 87 (87) — when scout matches truth, do we still need parens? Show only when they differ.
- [ ] Fix: Personality block: "Archetype: Fiery Competitor" with description — copy is good but stuffed in a grey box. Consider making this a feature card with a portrait flair.
- [ ] Fix: "Can generate media drama" yellow warning chip — great signal. Make it tappable to see what events could trigger.
- [ ] Fix: Scheme Fit final card: Best Scheme ProPassing 83%, Position Group QB, Physical Profile Above Average (83), Mental Profile Football IQ Genius (85) — strong analytical close. Tighten copy.

Game Design:
- [ ] Game: Scheme Fit "Best Scheme: ProPassing" but team is running Spread per earlier screens — this is the central player-management story. Surface a CTA: "Recommend HC scheme switch" or "Trade Love".
- [ ] Game: "Football IQ Genius" archetype label — gameplay effect not stated. Tooltip with "+5% audible success" or similar.
- [ ] Game: "Wants volume and usage, unhappy if production drops" — Motivation = Stats. Connect this to actual gameplay (if Love throws < 30 attempts/game, morale drops).
- [ ] Bug: Personality "Fiery Competitor" + Motivation "Stats" + "Can generate media drama" — three traits feels like one too many; verify these are not double-applying penalties. Consolidate display into 1–2 actionable indicators.

Decision Support:
- [ ] Game: Add "Manager Notes" panel at the very bottom — "Love is a top-12 QB locked into a Spread that doesn't fit. Recommended: extend now ($28M/4yr) and bring in Pro Passing OC next year."

---
**Coaching/Roster/Player Detail pass summary: 137 findings**
- [CoachingStaff]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [HireAHCList]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [CandidateDetail]: 13 (6 Fix / 5 Game / 1 Decision Support / 1 Bug — HC Chemistry "Unknown" when player IS the HC)
- [CoachingStaffFull]: 11 (5 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [ReviewRosterPhase]: 11 (5 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [StaffReviewModal]: 11 (5 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [RosterOffense]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [RosterDefense]: 11 (5 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [RosterSpec]: 10 (4 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [PlayerDetailTop]: 14 (8 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [PlayerDetailMid]: 9 (5 Fix / 3 Game / 1 Decision Support — 0 Bug)
- [PlayerDetailBot]: 10 (5 Fix / 3 Game / 1 Decision Support / 1 Bug — personality trait stack verification)

Top cross-screen themes for this pass:
1. **Yellow accent overuse continues** — every key number, label, and CTA across coaching staff and player detail uses the same gold; hierarchy collapses under heavy info density.
2. **Priority badge inflation** — every coordinator and most scout vacancies marked "High Priority" / "Recommended". Either differentiate or remove.
3. **Scheme mismatch story is buried** — J. Love is best at ProPassing but team runs Spread; this is the central long-term decision and it's shown as a percentage chart, not a CTA. Surface "Manager's dilemma" callouts.
4. **Replacement / consequence preview is the strongest pattern** — the "If Love leaves: Coleman starts at QB -14" line is the best decision-support UI in the app. Replicate everywhere (cut/trade/extend confirmations).
5. **Scout rating vs true rating parens** — surfaces in QB Skills section without a legend. Whole game has a scouting-accuracy mechanic but it's invisible to first-time players.
6. **Position-group grades (B+/C+ etc.)** are an excellent at-a-glance signal in the roster lists; make sure tap-to-explain is wired.

What's working well (keep):
- "If Love leaves: Coleman starts at QB - 70 OVR (-14)" replacement preview pattern.
- KPI strip on roster pages and player header (Morale / Health / Salary / Contract) is the right density for iPad.
- Position-group letter grades + chip-style annotations on roster lists.
- TOP 3 ranking + filter bar in Hire AHC list — big improvement.
- Scheme Fit card on player detail bottom is analytical and meaningful.
- Coach detail Career History / Background / Negotiate pattern is well structured.

---

## Roster Eval / Cap / Franchise Tag / Scouting / Combine / Interviews / Inbox auto-analyze findings (2026-04-29)

### [RosterEvalGrades] (auto_68_position_grades.png) — Roster Evaluation Phase 1

Visual Design:
- [ ] Fix: [RosterEvalGrades] Two grade columns "Strt / Depth" sit side-by-side with slash-separated micro letters (B+ / C+) — at iPad reading distance the slash glyphs look like noise; convert to two clearly labeled stacked columns "Starter Grade" / "Depth Grade" with their own headers
- [ ] Fix: [RosterEvalGrades] Column headers "Grou P" wrap awkwardly across two lines — widen the column or shorten label to "Pos"
- [ ] Fix: [RosterEvalGrades] "Staff" and "You" columns at far right have no grades populated for the user (em-dashes everywhere) — either drop the empty "You" column until grades are entered, or pre-fill placeholder "Tap to grade"
- [ ] Fix: [RosterEvalGrades] Row striping is invisible — alternate row backgrounds at ~3% white to scan 9 positions faster
- [ ] Fix: [RosterEvalGrades] "Cap $" column has no thousands grouping consistency vs. Cap Outlook screen ($26.6M vs $5.9M alignment) — right-align numbers and use tabular-nums
- [ ] Fix: [RosterEvalGrades] Staff status pills "Solid" / "Aging + plus ahead" / "Depth needed" have inconsistent widths; "Aging + plus ahead" almost overlaps the "You" column — fix max width and truncate
- [ ] Fix: [RosterEvalGrades] Header banner "Setting priorities affects draft board rankings and scouting focus / Priorities set: 0/9 position groups" mixes two concepts — split into two lines or use a progress chip ("0/9 priorities set")

Game Design:
- [ ] Game: [RosterEvalGrades] Player has not set any priorities (0/9) yet the Confirm Evaluation button on Phase 2 is enabled — block confirm until at least 1–3 priorities are picked, or warn "No priorities set — scouting will use generic weighting"
- [ ] Game: [RosterEvalGrades] No tap-target on a row to drill into the position group's depth chart — make every row tap → opens RosterPositionDetail with starter/depth players
- [ ] Game: [RosterEvalGrades] "Avg OVR / Avg Age / Cap $" alone don't tell the manager whether a 67 OVR is actually weak — add league-average comparison ("WR 67 vs lg avg 71 -4")
- [ ] Game: [RosterEvalGrades] ST grade is 83 but staff status is "Depth needed" (red) — this contradicts and confuses; add tooltip explaining starter is great but no backups
- [ ] Game: [RosterEvalGrades] Key Decisions list mixes RETIRED / EXPIRING but no sort/filter; long list of EXPIRING items with similar copy — group by tag or add filter chips

Decision Support:
- [ ] Game: [RosterEvalGrades] Add a "Recommended priorities (3)" auto-suggestion above the table — e.g., "WR (weakest), DL (aging core), DB (cap heavy + low OVR)" to teach new players how to triage
- [ ] Game: [RosterEvalGrades] Each Key Decision row has a one-line recommendation ("Re-sign at or slightly above market") but no inline action — add "Negotiate" / "Let walk" / "Tag" quick buttons inline

### [RosterEvalCap] (auto_70_roster_eval_bot.png) — Roster Evaluation Phase 2 (Cap Outlook + Scenarios A/B/C)

Visual Design:
- [ ] Fix: [RosterEvalCap] Cap Outlook 4-up KPI strip ($265M / $230.5M / $34.5M / $1.1M) has no labels visible without squinting — bold the labels and consider an icon for each (Total / Used / Available / Dead)
- [ ] Fix: [RosterEvalCap] Yellow horizontal Cap Usage bar at 87.0% is alarming yellow but no contextual color (87% is high but not red) — green<80, yellow 80–92, red>92
- [ ] Fix: [RosterEvalCap] "League avg ~78%" tiny gray text below the bar is invisible — promote to a tick mark on the bar at 78% with a label
- [ ] Fix: [RosterEvalCap] Cap Scenarios A/B/C use horizontal bar charts but the green fills look identical at 74% / 79% / 89% — vary the green saturation or add a "best for cap" badge on the longest bar
- [ ] Fix: [RosterEvalCap] Scenario rows say "Available: $70.1M / $56.0M / $30.4M" mid-row in tiny text — promote these to the right side as primary numbers, push percentages to a smaller secondary slot
- [ ] Fix: [RosterEvalCap] "Confirm Evaluation Complete" button at bottom is full-width gold — but it's the same gold as every other CTA in the app and competes with the cap warnings above; tone down or use a confirmation modal
- [ ] Fix: [RosterEvalCap] "Biggest Need: WR" yellow warning card sits between the players list and Cap Outlook with no visual rule above/below — add separator or shift to top of section

Game Design:
- [ ] Game: [RosterEvalCap] Three scenarios (A/B/C) are presented but selecting one has no apparent commitment — does picking A actually queue "Release All Expiring" actions? Make it a real lever with a confirmation, not a passive analytical view
- [ ] Game: [RosterEvalCap] Projected 2027 cap uses "+5% increase" — make this configurable or show historical cap growth (avg 7%) so player understands assumption
- [ ] Game: [RosterEvalCap] "Est. Replacement Cost +$39.6M" — what's this estimate based on (avg market for those positions)? Add tooltip
- [ ] Game: [RosterEvalCap] No scenario for "Restructure top contracts" — common NFL move missing; add scenario D
- [ ] Game: [RosterEvalCap] No "what if we franchise tag X?" preview from this screen — would link nicely to Franchise Tag flow

Decision Support:
- [ ] Game: [RosterEvalCap] Add a "Recommended scenario" highlight on whichever of A/B/C the GM Director suggests (with reasoning) so first-time players have a default

### [FranchiseTag] (auto_73_franchise.png) — Franchise Tag screen

Visual Design:
- [ ] Fix: [FranchiseTag] Top KPI strip "Available Cap Space $34.5M / Expiring Contracts 10" — green vs white contrast is fine but no icons; consider shield/clock icons for instant scan
- [ ] Fix: [FranchiseTag] Every row has a gold "Apply Tag" pill — 10 gold pills stacked vertically is visual noise and de-emphasizes the elite players who actually warrant the tag
- [ ] Fix: [FranchiseTag] "Tag Cost" label is tiny and below the dollar amount — flip so $5.0M is large with "Tag Cost" tiny above
- [ ] Fix: [FranchiseTag] Player rows mix recommendation copy ("Elite player — strongly consider tagging" / "Solid contributor — tag if you can't afford to lose him" / "Role player — better to let walk") in same gray text — color-code these strings (green / yellow / gray) to scan
- [ ] Fix: [FranchiseTag] "Cap after tag: $30.9M" is repeated on every row but it's not cumulative — each row assumes you only tagged that one player, which is misleading; add a sticky "Running cap if tagged: $30.9M" header that updates live
- [ ] Fix: [FranchiseTag] No visual indicator that you can only apply 1 tag per season — info banner says it but layout shows 10 buttons; disable 9 of them once one is selected
- [ ] Fix: [FranchiseTag] Star icon on Terrell Robinson is gold but other elite players have no star — clarify what star means or apply consistently

Game Design:
- [ ] Game: [FranchiseTag] Franchise Tag Rules banner says "average of top 5 salaries at their position" but tag costs vary wildly ($5.0M for QB Lewis vs $23.9M WR Malik Taylor) — add per-position tag value tooltip
- [ ] Game: [FranchiseTag] Aging veterans like Malik Taylor (32, $23.9M tag) have an explicit warning — good — but no warning on Khalil Diggs (30, $14.7M tag, 71 OVR) which is borderline — extend the warning logic
- [ ] Game: [FranchiseTag] No "Transition Tag" option — NFL also has transition tag at lower cost; missing realism feature
- [ ] Game: [FranchiseTag] No "Tag-and-trade" angle — common GM move; add a follow-up CTA after tagging
- [ ] Game: [FranchiseTag] "Apply Tag" should fire a confirmation modal showing 1-year contract terms before committing cap

Decision Support:
- [ ] Game: [FranchiseTag] Add at top: "Director of Player Personnel recommends: Tag Terrell Robinson ($5M, retains your TE1)" so the right answer is teachable

### [DashCombinePhase] (auto_77_combine_phase.png) — Dashboard during NFL Combine phase

Visual Design:
- [ ] Fix: [DashCombinePhase] Left rail Combine task "Send scouts to Combine — Required" shown with red REQUIRED tag — good — but "Update Big Board" below has no tag and looks similar; differentiate optional vs required tasks more clearly
- [ ] Fix: [DashCombinePhase] "Complete 4 required tasks to advance" warning text is gray on dark — promote to a colored alert bar above the task list
- [ ] Fix: [DashCombinePhase] "Advance to Free Agency" button is dimmed/disabled but still the same gold — use truly disabled gray and add a "Why disabled?" tooltip
- [ ] Fix: [DashCombinePhase] Right column tile "POSITION GRADES" duplicates the data already on Roster Eval screen — either remove or condense to top 2 weaknesses
- [ ] Fix: [DashCombinePhase] "MESSAGES (1 unread badge)" but list shows 5 messages with 2 yellow Action Required tags — header badge count contradicts visible count
- [ ] Fix: [DashCombinePhase] "OWNER" / "MORALE" / "RESPECTED" tabs at top — only one is selected at a time but all 3 always show progress bars; collapse the unselected ones
- [ ] Fix: [DashCombinePhase] "View All" gold pill in Messages section — same gold as every other CTA; tone down for nav links

Game Design:
- [ ] Game: [DashCombinePhase] "Send scouts to Combine — 0 scouts will evaluate" — should warn that with 0/8 scouts hired you CANNOT send anyone; tie this to the staff hire flow
- [ ] Game: [DashCombinePhase] "Scouts: 0/8 hired" — the entire scouting system is no-op until staff is hired but the dashboard never blocks the user; add a hard prereq
- [ ] Game: [DashCombinePhase] "Update Big Board" task is open-ended — when is it considered "done"? Define a completion criterion (e.g. star ≥3 prospects, set position priorities)
- [ ] Game: [DashCombinePhase] No timer / pace pressure during Combine — add "Combine ends in 14 days" countdown so the phase feels temporal
- [ ] Game: [DashCombinePhase] "Schedule" header tab and "Standings" exist but offseason has neither — hide or repurpose during offseason

Decision Support:
- [ ] Game: [DashCombinePhase] Add a "Today's recommended action" hero card at top of dashboard so each phase has one clear next step

### [ScoutingBigBoard] (auto_78_scouting_hub.png) — Scouting Hub Big Board

Visual Design:
- [ ] Fix: [ScoutingBigBoard] Green CTA banner "Send Scouts to NFL Combine — 0 scouts will evaluate ~330 prospects" — green positive color but message is negative (0 scouts) — switch to amber/warning treatment
- [ ] Fix: [ScoutingBigBoard] Tab bar (Scout Team / Prospects / Big Board / Combine / Interviews / Mock Draft / Draft) is 7 tabs wide on iPad — works at this width but on smaller iPads will overflow; consider grouping
- [ ] Fix: [ScoutingBigBoard] Recommendations section uses warning triangle for "Your #1 need" (red) but green check for "Best available" — emoji-style icons feel inconsistent; use a unified badge system
- [ ] Fix: [ScoutingBigBoard] "Position Depth Analysis" subsection has DE/CB/WR rows with green check but the same green is used for "Safe" risk pills below — overloaded color
- [ ] Fix: [ScoutingBigBoard] Prospect rows have 5 trailing chips (AGE / FIT / NEED / RISK / OVR / PROJ) plus star + tier label — at iPad width it's dense; consider hiding NEED/PROJ behind tap
- [ ] Fix: [ScoutingBigBoard] "Blue Chip" / "First Rounder" tier dividers use small colored dots — increase prominence with a sticky tier header bar
- [ ] Fix: [ScoutingBigBoard] "Boom / Bust" risk pill on Gordon is red — but Gordon is the team's #1 — color implies bad without context; add tooltip

Game Design:
- [ ] Game: [ScoutingBigBoard] "Your #1 need: DE (weakest group)" but earlier Roster Eval said "Biggest Need: WR" — sources disagree; reconcile from one source of truth
- [ ] Game: [ScoutingBigBoard] "Your #1: Michael Gordon vs Media #1: Cole Coleman" — great realism callout; add a "why we differ" tap target
- [ ] Game: [ScoutingBigBoard] "Gordon available at Rd 2 #63: 15%" — what does 15% mean? Probability he falls? Tooltip needed
- [ ] Game: [ScoutingBigBoard] No "Add to watch list" multi-select; only single star — add bulk operations for prep before mock draft
- [ ] Game: [ScoutingBigBoard] "Scouted: 71% of prospects" — what unlocks the remaining 29%? Tie to scouts hired / phases

Decision Support:
- [ ] Game: [ScoutingBigBoard] Add "Set Priorities" CTA inside Recommendations card linking back to Roster Eval since priorities are zero

### [CombineReportModal] (auto_85_send_modal.png) — Combine Report modal (Standout / Stock-Faller)

Visual Design:
- [ ] Fix: [CombineReportModal] Modal header "Combine Report / Done" — Done button on the right is a small pill; for iPad use a clearer top-bar X close affordance
- [ ] Fix: [CombineReportModal] "NFL COMBINE REPORT / 4 notable performances" heading inside a floating card inside the modal — double-card creates visual noise; flatten to single card
- [ ] Fix: [CombineReportModal] Standout / Stock Faller sections use star and red-flag icons but same body weight; differentiate with green-tinted vs red-tinted backgrounds
- [ ] Fix: [CombineReportModal] Player rows in the modal don't show grades or projected round — manager can't tell if "Andre Bryant elite numbers" matters for their draft slot; add minimal context
- [ ] Fix: [CombineReportModal] Behind-modal background is dimmed but still legible — bump scrim opacity
- [ ] Fix: [CombineReportModal] Modal content is short (4 names) — modal dominates ~60% of screen; could be a sheet from bottom instead

Game Design:
- [ ] Game: [CombineReportModal] No tap-through to open the prospect's detail from the modal — add tap target on each name
- [ ] Game: [CombineReportModal] "Stock Faller" players — what's the actual game effect? Their grade dropped, projection slid? State the delta
- [ ] Game: [CombineReportModal] Only 4 notables shown — a real combine has dozens; either say "Top 4 surprises" or expand
- [ ] Game: [CombineReportModal] No "Star" / "Add to watch" inline action — modal is read-only; should be actionable
- [ ] Game: [CombineReportModal] No "Compare to mock draft" — tie risers/fallers to where they sit on Big Board

Decision Support:
- [ ] Game: [CombineReportModal] Add a footer "These changes have been applied to your Big Board" so the player knows the data flowed through

### [CombineResults] (auto_88_combine_tab.png) — Combine Results full table

Visual Design:
- [ ] Fix: [CombineResults] Excellent dense table — but the column headers (40yd / Bench / Vert / Broad / 3-Cone / Shuttle / Pos Drill) need a sticky header on scroll
- [ ] Fix: [CombineResults] Each measurable shows raw value + a percentile badge in tiny gray text below — promote the percentile to a small colored chip (green for top quartile)
- [ ] Fix: [CombineResults] Pos column shows position chip + sometimes a red dot indicator — what does the red dot mean? Add legend
- [ ] Fix: [CombineResults] GRD (grade) column uses A+/A/B+/etc. with color coding but no header explanation — tap header should reveal grading scale
- [ ] Fix: [CombineResults] Star column at far left has no header — label it or remove if redundant with Big Board star
- [ ] Fix: [CombineResults] Filter chips at top (All / QB / RB / WR …) are gold when active — use a clearer pill state
- [ ] Fix: [CombineResults] Numeric columns are not all right-aligned; "4.85" vs "4.45" align off — use tabular-nums and right-align

Game Design:
- [ ] Game: [CombineResults] No way to sort by column (tap header to sort by 40-time, vert, etc.) — critical for a results table
- [ ] Game: [CombineResults] "330 of 330 prospects invited" — but only top 14 shown without scrolling; add pagination or virtual scroll indicator
- [ ] Game: [CombineResults] No "Overall combine score" composite — manager wants a single rank; consider adding RAS-like metric column
- [ ] Game: [CombineResults] Some rows show red dots near position label that look like "needs attention" — clarify
- [ ] Game: [CombineResults] No filter for "Risers / Fallers / Held" so manager can quickly find storyline players post-combine

Decision Support:
- [ ] Game: [CombineResults] Highlight rows where the combine result moved the projected round (e.g., bg tint when Rd1 → Rd2 or Rd3 → Rd2)

### [InterviewsTab] (auto_92_interviews_tab.png) — Interviews tab pre-selection

Visual Design:
- [ ] Fix: [InterviewsTab] "0/60 selected" + "60/60 interviews remaining" — two parallel meters that confuse; merge into a single progress "Selected 0 of 60 interview slots"
- [ ] Fix: [InterviewsTab] Each prospect row has 5 trailing chips (OVR / Rd / Risk / NEED / FIT) — same density problem as Big Board; consider collapsing
- [ ] Fix: [InterviewsTab] "Select All Recommended" button at top right is gold pill near the filter chip — visually competes; move to a sticky bottom action bar
- [ ] Fix: [InterviewsTab] Empty checkbox circles on every row — once you have 60 slots used, they should fill; visual feedback on tap unclear
- [ ] Fix: [InterviewsTab] "RECOMMENDED" header section title is yellow; below it the player chips are also yellow accents — color collision
- [ ] Fix: [InterviewsTab] No visible cap on slot count beyond "60/60" — once you select 60, what happens? Disable other rows? Show error
- [ ] Fix: [InterviewsTab] Bottom CTA "Select Prospects to Interview" is gold but disabled state — same gold as enabled CTAs elsewhere; use disabled gray

Game Design:
- [ ] Game: [InterviewsTab] Info banner: "NFL teams typically interview 15–20 prospects" but UI gives you 60 slots — disconnect; reduce slot count or explain why this team gets 60
- [ ] Game: [InterviewsTab] No way to differentiate "formal combine interview" vs "informal team visit" — could add 2 buckets
- [ ] Game: [InterviewsTab] Risk pills shown but no indication that interviewing reduces bust risk — banner mentions it once; reinforce on each row hover
- [ ] Game: [InterviewsTab] No filter for "Top of Big Board" / "Need positions" / "Character flags" — selection without filters means manual scroll through 60 prospects
- [ ] Game: [InterviewsTab] "Matches team needs with top-half talent" subheading — hard-coded heuristic; expose the rule

Decision Support:
- [ ] Game: [InterviewsTab] Add a "Smart pick 15" auto-select button that picks based on need + top tier so first-time players get a sane default

### [InterviewReport] (auto_94_interview_results.png) — Interview Report (60 interviewed, A/B/C cards)

Visual Design:
- [ ] Fix: [InterviewReport] Excellent card design — Grade A label top-right of each card, Football IQ chip, Exemplary Character chip, Bust risk delta line, micro-stats — keep this pattern
- [ ] Fix: [InterviewReport] Summary header "60 interviewed / 18 low / 25 med / 17 high risk / 8 off-field concerns / Best: Cameron Davis - Grade A" packed into one strip — split into a 2-row metrics grid for readability
- [ ] Fix: [InterviewReport] "Bust risk: 50% → 40% after interview" — the arrow-and-percent pattern is great; promote with green color on the new value
- [ ] Fix: [InterviewReport] Player names #1, #2, #3 use small gray rank — make the rank larger / colored
- [ ] Fix: [InterviewReport] Card border colors don't differ between Grade A / B / C cards — only the right-side letter differs; tint the card border too
- [ ] Fix: [InterviewReport] "Star" / "Red Flag" actions at the bottom of each card use pill chips but they're the same gold/gray — make Red Flag red
- [ ] Fix: [InterviewReport] "Complete Review → Return to Scouting Hub" full-width gold CTA — same gold as everything; this should be the primary action

Game Design:
- [ ] Game: [InterviewReport] Bug priority: "Review interview report" task in dashboard does NOT get marked complete after viewing this report. Logic must mark task complete when Complete Review CTA is tapped (or when the report is opened past the summary)
- [ ] Game: [InterviewReport] Cards include "Football IQ: C (76)" — combining letter + number is helpful but inconsistent with player detail which uses A-/B+/etc. — align grading scales
- [ ] Game: [InterviewReport] "Affects scheme learning speed" hint on each card — great game mechanic; surface the actual numeric effect (+10% scheme learning rate)
- [ ] Game: [InterviewReport] "Off-field concerns: 8" in summary but no way to filter to just those 8 — add filter chip
- [ ] Game: [InterviewReport] No way to sort by Grade / Bust Risk / Position from this view

Decision Support:
- [ ] Game: [InterviewReport] Add a "Director of Scouting recommendation" callout at top: "Star these 3 Grade-A players for Round 1 priority"

### [ProspectDetail] (auto_112_prospect_detail.png) — Prospect Detail (Michael Gordon QB)

Visual Design:
- [ ] Fix: [ProspectDetail] Header is clean (name, position chip, age/height/weight, A- grade, 1 report, Rd 1) — solid pattern
- [ ] Fix: [ProspectDetail] Tags row "High Ceiling / Fit: Fair / Above Average" — three different concept chips in same gold-bordered style; differentiate (Ceiling = blue, Fit = orange because Fair is mediocre, Athleticism = green)
- [ ] Fix: [ProspectDetail] Scouting Report 4-row table (Overall / Potential / Scout Grade / Personality) — Overall A- and Scout Grade A differ but no explanation of what "Scout Grade" means vs "Overall" — tooltip
- [ ] Fix: [ProspectDetail] "Interview" button green / "Pro Day" button dimmed grey — green is positive but here it's just an action; consider neutral tertiary style
- [ ] Fix: [ProspectDetail] "vs Current Starter" comparison card is excellent (Gordon A- vs J. Love B+ → "Upgrade") — keep this pattern across roster
- [ ] Fix: [ProspectDetail] Combine measurables column far-right shows percentile chip ("88th %ile for QB") in tiny text — promote to colored chip
- [ ] Fix: [ProspectDetail] "Add to Board" CTA at bottom-left is small text + star — should be a primary button
- [ ] Fix: [ProspectDetail] "Bench Press 13 reps / 28th %ile" — 28th percentile is below average; chip color should reflect that (yellow/red), currently looks neutral

Game Design:
- [ ] Game: [ProspectDetail] "Personality: Mentor" is shown — what does Mentor do for a QB? Tie to scheme learning system / locker room
- [ ] Game: [ProspectDetail] Scouting Report A- but no breakdown of position skills (Arm, Accuracy, IQ, Mobility) — add expandable skills section
- [ ] Game: [ProspectDetail] No "scout reports" tab — multiple scouts should give different opinions; only 1 report shown
- [ ] Game: [ProspectDetail] No projected contract cost / draft pick value — manager wants "if I take him at #2, his rookie deal is $X / 4yr"
- [ ] Game: [ProspectDetail] "vs Current Starter" only compares vs starter — should also show vs free-agent options at QB

Decision Support:
- [ ] Game: [ProspectDetail] Add a "Director's Take" 2-sentence summary tying scouting + interview + combine into a recommendation: "Worth #2 overall — fit risk if we keep Spread scheme"

### [Inbox] (auto_106_msg_open.png) — Inbox (5 messages)

Visual Design:
- [ ] Fix: [Inbox] Filter chips at top (All / Owner 2 / Staff / Scouting 1 / Media 1) — counts differ between chips and visible items (header says "5 unread" but chip totals add to 4); reconcile
- [ ] Fix: [Inbox] Yellow "5 unread" pill in top-right corner is the only indicator of unread state — also show unread dots or bold sender names
- [ ] Fix: [Inbox] All 5 messages have nearly identical visual weight — no separation between Action Required (red) and informational (none); promote Action Required rows with left border accent
- [ ] Fix: [Inbox] Message metadata "Offseason - NFL Combine, 2026" repeated identically on every row — collapse to relative time ("2h ago", "Yesterday")
- [ ] Fix: [Inbox] Sender icons are tiny mailbox/scope/etc. glyphs — increase size for iPad and use distinct colors per sender role
- [ ] Fix: [Inbox] Tab "All" is highlighted gold but the visual treatment is the same as filter pills below — strengthen selected state
- [ ] Fix: [Inbox] No bulk actions (mark all read / delete) — add overflow menu

Game Design:
- [ ] Game: [Inbox] "Action Required" badge implies blocker but tapping the message just shows text — actions need to be embedded in the message body or open a flow
- [ ] Game: [Inbox] No timestamp distinction — Combine Results and Welcome message both say "Offseason - NFL Combine, 2026" but Welcome should be older; track real game-time
- [ ] Game: [Inbox] "Mock Draft: Green Bay Packers Projected to Select…" message with no Action Required — should it have a "View Mock Draft" CTA?
- [ ] Game: [Inbox] No archive or pin — important messages get buried fast in a long save
- [ ] Game: [Inbox] No reply / response options for messages from staff (Coach can email back?)

Decision Support:
- [ ] Game: [Inbox] Add a sticky "1 action required" bar at top that jumps to the next unresolved message

### [MessageDetail] (auto_107_msg_combine_results.png) — Message detail (Director of Scouting combine results)

Visual Design:
- [ ] Fix: [MessageDetail] Modal/sheet shows over inbox list with the sender icon and Close button at top — Close pill is purple, not standard; align with system patterns
- [ ] Fix: [MessageDetail] "Scouting" green chip + "Action Required" red chip side-by-side at top of message — inconsistent corner radii / heights; normalize
- [ ] Fix: [MessageDetail] Body copy is plain text bullets — long para then "- Several prospects… - There are some… - A few highly-rated…" — convert to actual bulleted list with icons
- [ ] Fix: [MessageDetail] "Coach," salutation but no signature visible (cuts off) — ensure the message ends with sender name + role
- [ ] Fix: [MessageDetail] No CTA buttons in the message body — "I'd recommend reviewing the full scouting reports" should be a "Open Combine Results" button
- [ ] Fix: [MessageDetail] Background inbox rows are still slightly visible / readable behind sheet — increase scrim opacity

Game Design:
- [ ] Game: [MessageDetail] Action Required tag but reading the message doesn't clear the requirement — messages should be tied to a real task with completion criteria
- [ ] Game: [MessageDetail] Director of Scouting message text is generic ("Several prospects at positions of need tested exceptionally well") — should name actual prospects from this team's needs
- [ ] Game: [MessageDetail] No "Reply / Discuss" affordance — closes the loop one-way only
- [ ] Game: [MessageDetail] No deep-link CTAs ("Open Combine Results", "Open Big Board") inside the body — text references "full scouting reports" but doesn't link
- [ ] Game: [MessageDetail] Same Director of Scouting personality should send messages with consistent voice; verify tone matches their hired profile

Decision Support:
- [ ] Game: [MessageDetail] Bottom of message: "Recommended next 3 actions" auto-list (Send scouts to Pro Days / Update Big Board / Schedule interviews) so the message is actionable, not just informative

### [DashTaskCompletion] CRITICAL BUG — Dashboard task-completion logic

- [ ] Bug: [DashTaskCompletion] HIGH PRIORITY — "Review interview report" task in the dashboard does NOT get marked complete even after: viewing the Interview Report (auto_94), opening prospect details, navigating to Interviews tab, tapping individual prospect cards. Task remains REQUIRED indefinitely, blocking advance to Free Agency. Repro: complete interviews → open report → tap "Complete Review → Return to Scouting Hub" → return to dashboard → task is still red REQUIRED. Investigate WeekAdvancer / TaskGenerator completion-event wiring for the interview-report task; likely missing a completion hook on the Complete Review CTA or the InterviewReportView dismissal. Same risk on other "review X" tasks — audit all dashboard tasks for completion event coverage.
- [ ] Bug: [DashTaskCompletion] Verify "Send scouts to Combine" task completion fires correctly (auto_77 still shows REQUIRED tag after navigation).
- [ ] Bug: [DashTaskCompletion] Verify "Update Big Board" task — completion criterion undefined; user cannot tell when it's done.
- [ ] Bug: [DashTaskCompletion] "Complete 4 required tasks to advance" counter — confirm this counter decrements correctly when each task IS completed.

---

**Roster Eval / Cap / Franchise / Scouting / Combine / Interviews / Inbox pass summary: 162 findings across 12 screens + 1 critical bug cluster**
- [RosterEvalGrades]: 14 (7 Fix / 5 Game / 2 Decision Support — 0 Bug)
- [RosterEvalCap]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [FranchiseTag]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [DashCombinePhase]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [ScoutingBigBoard]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [CombineReportModal]: 12 (6 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [CombineResults]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [InterviewsTab]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [InterviewReport]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug, 1 task-completion item flagged at the bottom)
- [ProspectDetail]: 14 (8 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [Inbox]: 13 (7 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [MessageDetail]: 12 (6 Fix / 5 Game / 1 Decision Support — 0 Bug)
- [DashTaskCompletion]: 4 Bugs (HIGH PRIORITY)

Top 5 critical issues for this pass:
1. **[DashTaskCompletion] Dashboard task-completion is broken** — "Review interview report" never marks complete, blocks Free Agency advancement permanently. Hardest blocker for first-time playthrough. Audit all task completion events.
2. **Source-of-truth conflict on team needs** — Roster Eval says "Biggest Need: WR" but Scouting Hub recommends "Your #1 need: DE". One must drive the other; reconcile via PositionPriorityService.
3. **Yellow accent overuse continues** — every CTA, badge, tab, and chip across new screens uses the same gold; visual hierarchy fully collapsed (especially on Franchise Tag with 10 identical gold "Apply Tag" buttons, Cap Outlook KPI strip, Inbox "All" tab vs filter pills).
4. **Cap Scenarios A/B/C are presented but non-actionable** — picking a scenario should queue the actions (release / re-sign), not just be analytical. Currently the most powerful decision-support UI is read-only.
5. **Scouts: 0/8 hired blocks the entire scouting flow but UI doesn't gate it** — combine, interviews, big board all run with 0 scouts. Either auto-assign placeholder scouts during onboarding or hard-block the offseason until staff is hired.

What's working well (keep — newly observed):
- "vs Current Starter" comparison on ProspectDetail (Gordon A- vs Love B+ → "Upgrade") — best decision-support pattern in the new screens; clone to all transactions.
- Interview Report cards with Bust Risk delta ("50% → 40%") and Football IQ + Character chips — great info density and clear narrative.
- Combine Results table density is excellent for power users; just needs sortable columns and percentile chip emphasis.
- Position Group Grades letter-grade table in Roster Eval is scannable and the right starting point for offseason planning.
- "Director of Scouting" Combine Report message shows good role-based comms framing — extend to all staff messaging.
- Cap Outlook 2026 / 2027 projection split is the right financial narrative for a multi-year sim; fix the comparative visualization and it becomes a flagship screen.

## Round 1 full-playthrough findings (2026-07-08) — career start → FA → Draft → OTAs (soft-lock)

Playthrough evidence: ~213 screenshots in /tmp/snd-screenshots/ (r1_001–r1_213). Regular season was NOT reachable legitimately — the run soft-locks in OTAs. Debug skip reaches the Week 1 dashboard but freezes the UI and does not persist. These findings drive Round 1 implementation.

### [P0 Blockers] Progression-breaking bugs (fix before anything else)
- [x] Bug: [OTAs] "Set depth chart" required task can NEVER complete — completion appears to require every starter slot filled, but the roster has 0 kickers and the K starter picker shows "Candidates (0) — No viable players for K" (r1_192). Hard soft-lock before Training Camp. (Fixed 2026-07-08: root cause was NO completion check at all — refreshTaskCompletionStatus had no case; now completes when a chart is persisted (edit or Auto-Set), never requires unfillable slots. Verified in sim: OTAs → Training Camp → Preseason → Roster Cuts → Regular Season Week 1.)
- [x] Bug: [OTAs] "Set training focus" required task does not complete even after a successful save (r1_201–r1_202). (Fixed 2026-07-08: added game-state completion check — TrainingPlan row exists for (team, season, week, phase) → done; wired onAppear/onDisappear refresh on both destinations + refresh on shell load.)
- [x] Bug: [TrainingPlan] Save does not persist — saved 60/20/20, reopened shows 34/33/33 (r1_178 vs r1_200). (Fixed 2026-07-08: the row WAS saved but the editor never loaded it back (hardcoded @State 34/33/33) and save() always inserted duplicates. Now loads existing plan on appear and upserts.)
- [x] Bug: [Save] In-phase actions are lost on app restart (r1_209). (Fixed 2026-07-08: DepthChart now persisted to Career.depthChartData on every mutation — it was pure ephemeral @State regenerated on each view appearance; explicit save after WeekAdvancer.advanceWeek in performShellAdvance; scenePhase background/inactive save in DynastyApp. Verified: phase + tasks survive terminate/relaunch.)
- [ ] Bug: [Roster] No kicker on roster after FA + draft and no way to acquire one afterwards — no street free agency / post-FA signing flow exists (Roster, Cap, Scouting all checked). Roster construction guardrail missing: FA phase "Skip Remaining FA" + draft let the user finish with 48 players and 0 K. Add (a) street FA signing screen available year-round, (b) FA-exit warning "You have no kicker" blocking or auto-fill.
- [x] Bug: [Debug] "Skip → FA" debug button mislabeled, freezes UI in "Skipping…", result never saved (r1_203–r1_209). (Fixed 2026-07-08: root cause — loop target .freeAgency is unreachable from OTAs without simulating a full season synchronously on @MainActor, and the advanceWeek branch never saved while the blocked run loop prevented autosave. Loop now also stops at .regularSeason, saves every iteration + final save, label is dynamic "Skip → Reg. Season"/"Skip → FA".)
- [ ] Bug: [Dashboard] Gated "Advance to Training Camp" button gives zero feedback on tap — no toast, no shake, nothing (r1_199). Disabled actions must explain themselves.
- [x] Bug: [Draft] "Enter the Draft" required task never completes after the draft ends. (Fixed 2026-07-08: isDraftComplete was hardcoded default false and never passed; added completion check — team has a player with draftPickNumber != nil && yearsPro == 0.)
- [ ] Bug: [FA] FA Complete screen infinite layout-loop hang (carried from FA phase; required app restart).
- [ ] Bug: [Draft] Post-draft war room soft-lock: "ROUND 1 — Pick 0/32 · Overall 0", frozen timer, "Your next pick: #0 (-1 picks away)"; only the back button escapes.

### [Dashboard] Stale / contradictory data (destroys trust in the sim)
- [ ] Bug: [Dashboard] OTAs dashboard hero shows Training Camp content: "Training Camp · Day 7/21", "18% overloaded", "3 active battles", "Top camp grade Moore · A+" — while the phase rail says OTAS NOW and the workload heatmap is all-green "Healthy". Hero must render the CURRENT phase's data.
- [ ] Bug: [Dashboard] Week 1 hero (post-skip): "2 OUT, 3 questionable" while the Injuries card on the same screen says "0 out"; "Streak W3" with an 0-0 record; opponent is "vs TBD" and Opponent Scout shows "Vs —" (schedule not generated/bound).
- [ ] Bug: [Dashboard] Team rank fluctuates between renders with identical 0-0 record (#4 → #1 → #4 observed). Rank should be deterministic.
- [ ] Bug: [Dashboard] Hero quick-chips (Training / Battles / Camp Grades) ALL navigate to the generic Roster screen — dedicated Battles and Camp Grades views are unreachable from the dashboard (r1_210–r1_213). Wire correct destinations or hide chips whose screens don't exist.
- [ ] Bug: [Dashboard] Owner rating changed 76% → 66% and player OVRs changed silently (Love 83→84, Moore 83→80) during the debug skip with no event feed entries — every rating change needs a visible cause (news item / recap).
- [ ] Fix: [Dashboard] "Advance to Regular Season" button text renders overlapped with the "TRADE DEADLINE — Oct" sidebar label (r1_203) — z-order/layout collision in the left rail.
- [x] Fix: [TrainingPlan] "WEEK 0 FOCUS" label — week numbering starts at 0 in player-facing copy. (Fixed 2026-07-08: header now shows the phase name during offseason — "OTAs Focus", "Training Camp Focus" — and Week N (min 1) only in regular season/playoffs. Added SeasonPhase.displayName. NOTE: the Workout Request weekly modal still says "WEEK 0 — PICK ONE" — separate view, fix in round 2.)

### [DepthChart] Findings (designer + hardcore lens)
- [x] Bug: [DepthChart] Auto-fill wand button (top-right) does nothing — no action, no feedback (r1_179–r1_180). (Fixed 2026-07-08: it re-ran the same idempotent autoGenerate the view runs on appear, so nothing visibly changed; now the chart loads from the persisted copy and Auto-Set regenerates + persists, making it a real "confirm auto lineup" action.)
- [x] Game: [DepthChart] KR/PR candidate list ranks the entire roster by raw Overall — recommends QB1/MLB1 as returners (r1_193–r1_194). (Fixed 2026-07-08: Overall sort for KR ranks by physical.speed, PR by physical.agility — mirrors autoGenerate's returner logic.)
- [x] Game: [DepthChart] Same player can hold two POSITION depth slots simultaneously (DeSean Howard = DT backup AND MLB backup). (Fixed 2026-07-08: assign() now removes the player from all other non-returner slots; KR/PR double-duty deliberately still allowed.)
- [ ] Fix: [DepthChart] Candidate picker "In Chart" tag only marks players already in THIS position's slots — players holding slots elsewhere (e.g., Khalil Taylor = LOLB starter offered for MLB backup) carry no indicator, so picking them silently strips another position.
- [ ] Fix: [DepthChart] Group completion badges count starters only ("2/2" green while backup slots are empty) but task completion appears to require more — the two signals disagree; unify the definition of "complete" and show it (e.g., "Starters 2/2 · Backups 1/2").
- [ ] Game: [DepthChart] Position-change suggestions have no cost/risk display — assigning LG Kwame Coleman as FB backup or DT as MLB backup shows a small icon but no fit penalty %, no learning curve. Surface "out-of-position: -X OVR" like FM does.

### [Draft] Carried-forward bugs from the draft phase (r1_115–r1_175)
- [ ] Bug: [Draft] Big Board generated 100% QBs → every recommendation is a QB flagged "Position not a top need" and every actual pick grades "C REACH". Big Board generation is broken for this career; grades cascade from it.
- [x] Bug: [Draft] Pick modal position chips REORDER between renders and drafting is instant on chip tap with no confirmation — caused 3 of 6 picks to select the wrong player. (Fixed 2026-07-08: all three draft surfaces (list row, comparison DRAFT button, position chip) now route through a "Confirm Pick" alert showing pos/name/OVR/college; chip ordering made deterministic with a position tiebreaker — chips visibly reshuffled every clock tick because of unstable dictionary sort + OVR ties.)
- [ ] Bug: [Draft] "My Pick" fast-forward advances only ~1 pick; 1x/2x/4x speed buttons inert; only "Next Round" works. Draft sim runs near real-time otherwise.
- [ ] Bug: [Draft] Round recap appears one round late, repeats stale content, and "Your picks this round" lists cumulative picks from all rounds.
- [ ] Bug: [Draft] Draft-time OVR vs roster OVR mismatch (Zach Allen 72 at pick → 57 on roster). One rating pipeline, not two.
- [ ] Bug: [Draft] A+ STEAL toast and C+ ticker grade shown simultaneously for the same pick; media toasts stay on screen for minutes.
- [ ] Fix: [Draft] "NFL Draft 2 026" number formatting (locale group separator applied to a year).
- [ ] Fix: [Draft] Dashboard draft card contradicts the war room: "Round 1 Pick 14", top targets, "2 active trade offers" vs actual first pick #63 and no trade engine. Localization leak: "Trade engine arrives in Vaihe 3".

### [Training audit] FM-style training verdict (user request: "vastaa football manager -tyylistä harjoittelua?")
Skeleton is FM-like and GOOD: 100-point Tactical/Physical/Technical team split + presets, weekly workout-request choice with scheme/locker-room/injury tradeoffs, mentoring pairs with leadership + compatibility, per-player workload list, game-plan sliders. The wiring behind it is NOT:
- [x] Bug: [Training] Per-player workload/injury data is static — every player shows identical "4% inj"; WorkloadEngine.injuryRiskPct never called. (Partially fixed 2026-07-08: injuryRiskLabel now calls WorkloadEngine.injuryRiskPct (durability + workload status), wiring up the dead engine formula — values vary once camp workload ticks accrue. VoluntaryWorkoutEngine dead-code wiring still open for round 2.)
- [ ] Game: [Training] No per-player individual training focus (FM's core loop: pick attribute targets per player, see weekly deltas). Add "Individual Focus" per player (e.g., +Tackling for a rookie LB) consuming a shared coach-hours budget.
- [ ] Game: [Training] No feedback loop — after a training week there is no "gains report" (who improved what, who's overworked). Without visible deltas the whole system feels cosmetic. Add a weekly Training Report inbox item.
- [ ] Game: [Training] Mentoring flow is one-pair-at-a-time — mentor selection clears after each mentee assignment; assigning 5 pairs takes 10 round-trips.
- [ ] Game: [Training] Coach quality has no visible effect on training output — surface "position coach rating × focus = expected gain" so staff hiring matters.

### Persona summaries (round 1)
**Designer:** Visual system (dark navy + gold, card grid, letter grades) is genuinely strong and consistent. What breaks it: contradictory numbers on one screen (hero vs cards), dead buttons without state feedback, stale phase content, "Week 0", "2 026", localization leaks, overlapping labels. Ship-quality visuals, prototype-quality data binding.
**Himopelaaja:** The sim promise collapses on correctness — wrong-player drafting, fake injury %, rank that changes on re-render, ratings that move without cause, and an unfillable K slot mean the hardcore player cannot trust or optimize anything. Fix determinism + persistence first; depth of systems second.
**Casual:** The required-task rail is the casual player's guide, and it points at an impossible task with no help ("Complete 1 required task" forever, silent disabled button). Auto-fill depth chart, task auto-complete on save, and an explanatory toast would fix 90% of casual frustration. The KR-picker recommending the starting QB is a trap a casual player WILL fall into.

**Loading speed (user request):** App cold start → menu ~6s (acceptable, splash could mask it). Dashboard and sub-screens render <1s; navigation is snappy. The only real "loading" problems are the FA Complete infinite hang and the frozen "Skipping…" debug state — both functional bugs, not performance. No screen needed a spinner beyond these. Draft sim pace is a UX problem (real-time), not a rendering one.

**Top 5 for Round 1 implementation:**
1. Task-completion event system (one bug class, three instances: training focus, depth chart, Enter the Draft, review interview report) — audit every required task's completion trigger.
2. Persistence: save after every user mutation (depth chart, training plan) + fix debug skip to persist and clear its busy flag.
3. Kicker hole: street FA signing + FA-exit roster-composition warning + task logic that can't demand the impossible.
4. Draft pick confirmation + stable chips (prevents wrong-player picks).
5. Dashboard data binding: hero must show current-phase real data; injuries/streak/rank from one source of truth.

## Round 2 findings (2026-07-08, post-fix playthrough — IN PROGRESS)

### [P0 Blocker] Regular-season week advance takes minutes at 100% CPU on the main thread
- [x] Bug: [GameSim/Perf] Tapping "Advance to Week 2" freezes the app FOREVER at 100% CPU. (Fixed 2026-07-08, TWO stacked root causes found via CPU samples: (1) **GameSimulator's regulation loop could never terminate** — at Q4 time-expiry `quarter < totalRegulationQuarters` fails to increment and the `quarter > total` exit was dead code, so the loop spun on zero-length drives forever; the game sim had NEVER completed a game. Fixed by breaking on `quarter >= total && timeRemaining <= 0`. (2) Every player-attribute read in the play-by-play hot loop went through SwiftData @Model getter machinery (swift_dynamicCast + conformance lookups per access) — fixed with the SimPlayer snapshot refactor: rosters snapshotted to plain structs once per game (new Engine/Simulation/SimPlayer.swift; GameSimulator/DriveSimulator/PlaySimulator now run on snapshots; fatigue applied back post-sim; SimPlayer overloads added to CoachingEngine.schemeFit + VersatilityDevelopmentEngine.schemePerformanceModifier; also fixes a latent bug where "transient" morale modifiers permanently degraded live models). VERIFIED: week advance now completes in ~2s — Week 1 game simmed, won, post-game press conference fired, Week 2 dashboard shows 1-0.) Still open: run the advance off the main actor with a progress overlay for slower devices.
- [ ] Fix: [Dashboard] Advance button gives no busy feedback — during the minutes-long sim the button looks idle and invites double-taps (risking double advance). Disable + spinner while advancing.
- [ ] Bug: [Dashboard] Week 1 hero says "vs TBD" and Opponent Scout "Vs —" while the sidebar task correctly names "Minnesota Vikings" — the schedule exists but the hero/opponent-scout cards don't resolve the opponent from upcomingGames.
- [ ] Fix: [Camp] Workout Request weekly modal header still says "WEEK 0 — PICK ONE" (VoluntaryWorkoutPrompt — the TrainingPlanView header was fixed in round 1, this view was not).
- [ ] Bug: [Tasks] Regular-season sidebar tasks don't refresh between weeks — regenerateTasks guards on `phase != lastGeneratedPhase`, so "Set game plan for Minnesota Vikings" persists into week 2+ (CONFIRMED on Week 2 dashboard). Guard must also compare week during .regularSeason.
- [x] Bug: [Dashboard] Week 2 hero still shows "@ MIN (Away)" (same opponent as Week 1) — either the schedule really has back-to-back MIN or the hero reads a stale upcomingGames snapshot. (Fixed 2026-07-08 in round 3: hero card now describes the CURRENT week's game — played or not — via currentWeekPlayerGame ?? lastGame(week==current) ?? upcomingGames.first, instead of always upcomingGames.first, which skipped to next week's opponent the moment the game finished. Played state shows "W/L xx–yy — advance when ready" with win/loss color.)
- [x] Bug: [Dashboard] Hero "Streak W3" shown with a 1-0 record (was also W3 at 0-0) — streak binding reads placeholder/wrong data. (Fixed 2026-07-08 in round 3: regularSeasonHeroCard now shows real team.record and real injury count "Fully healthy / N OUT" instead of hardcoded "W3"/"2 OUT, 3 questionable".)
- [ ] Game: [Presser] Post-game press conference flow is EXCELLENT (reporter tone tag, per-answer effect previews, running impact, summary with generated headlines + Promises Tracked) — carried the whole post-game narrative. Keep as the pattern for other narrative moments; old PressConf TODO items about tone tags/running totals are now largely implemented in this flow.

**What's working well (keep):**
- Depth chart candidate picker layout (Overall/Position Fit/Age tabs, Clear Slot, personality tags) — right pattern, wrong default sort for ST.
- Training Plan preset chips (Balanced/Scheme Heavy/Camp Hard/Recovery Mode) — casual-friendly with hardcore sliders underneath; exactly FM-lite done right.
- Salary Cap screen: Cap freed / Est. replacement / Net math on expiring contracts is excellent decision support.
- Roster room grades (S:/D: letter pairs) + "Key FA pending" / "Depth thin" badges — the game KNOWS about the kicker hole; it just doesn't act on it.
- Special Teams group warning badges (1/2 amber) correctly flagged the K/KR gaps visually.

## Round 3: Coach Mode — live 3D play-calling (2026-07-08, user request: "valmentaja valitsee pelit, näytetään yksinkertaisella 3D grafiikalla")

### Shipped (all verified end-to-end in simulator, home + away games)
- [x] Feature: [Engine] LiveGameEngine (Engine/Match/LiveGameEngine.swift) — @MainActor per-play wrapper around the existing sim: step(offensiveCall:forcedPlayType:defensivePackage:), quarter/clock/downs/possession @Published state, AI call hints, simToEnd, buildResult + persist(to:context:) with full parity vs GameSimulator (records, fatigue writeback, WeekAdvancer.lastPlayerGameResult so the presser works on pre-played games).
- [x] Feature: [Engine] PlaySimulator.simulatePlay accepts optional OffensivePlayCall (.simulatorHint: passDepth/runGap/blitzPickup/yac) + DefensivePackage (coverage/pressure/runStop mods); nil = byte-identical legacy behavior. findQB/findRB pick best-overall starter (play feed no longer stars 3rd-string QBs).
- [x] Feature: [3D] FootballFieldScene extended: goalposts, camera pan/focus rig, sequential PlayStep timeline (runPlay/cancelPlay, playGeneration guard), ball carry/arc/slide, pulse highlights, team-tinted end zones, upright yard numbers for the broadcast camera.
- [x] Feature: [3D] PlayChoreographer — pure formation + step builder for every PlayOutcome (rush/completion/incompletion/sack/INT/fumble/TD/punt/FG/safety/kneel/spike), 3.5–6s per play, offense-perspective yardLine → world-Z mapping.
- [x] Feature: [3D] Stylized humanoid players (legs/torso+shoulder pads/arms/head/team-colored helmet) replacing capsule blobs; run gait = face movement direction + forward lean + bob, straighten on arrival; both sides square up across the LOS on formation set. (User request: "tee pelaajista enemmän oikeamman näköisiä")
- [x] Feature: [3D] All-22 choreography — every snap animates all 22: OL/DL engage (run surge vs pass pocket+rush), WR routes vs CB/S coverage shells, LB drops/run fits, pursuit convergence on the carrier, punt coverage lanes + return wall, FG line surge, TD celebration mob. (User request: "kaikkien pitäisi liikkua kuin oikeassa pelissä")
- [x] Feature: [UI] CoachedGameView — scoreboard, situation chips, 52% 3D field, 2-row play feed, call panel: category tabs + play chips + AI suggestion chip + gold SNAP; defense stance panel (Balanced/Blitz/Run Stop/Prevent) stays live during opponent drives; 4th-down decision panel (Punt/FG with distance/Go For It); Spike/Kneel late-half; Skip Drive (works mid-animation); Sim to End → FINAL overlay (win/loss line) → GameSummary sheet → dashboard.
- [x] Feature: [UI] Dashboard hero "Coach the Game" (gold, headset) + "Game Plan" secondary for the current week's unplayed game; played state shows "W/L xx–yy — advance when ready" (loss in red). OpponentPrepWeek boosts flow into the engine.
- [x] Fix: [UI] MatchTeamColors palette + grass-contrast fallback (GB dark green → gold secondary; very-dark primaries → secondary; similar matchup colors → away swaps). Away-team abbreviation no longer hidden under the exit button.
- [x] Fix: [UI] fullScreenCover(item:) session struct (was isPresented: + stale @State = black screen).
- [x] Verified: away game (@ DET) start→final, presser fires with correct win/loss context after pre-played week, Advance to Week N works, owner/morale/legacy impacts land.

### Open polish (round 4 candidates)
- [ ] Balance: [CoachSim] One sim-to-end produced GB 60–21 / 833 total yards (later game was a realistic 15–33); audit whether audible/defRead + OpponentPrepWeek boosts stack too hard in LiveGameEngine.simToEnd, and cap per-game scoring drift.
- [ ] UX: [CoachUI] Skip Drive button occupies the same screen area as the "Special" category tab — when the opponent drive ends naturally right before the tap, the tap lands on the tab row. Debounce panel swaps (~300ms) or move Skip Drive out of the tab row's footprint.
- [ ] UX: [CoachUI] Category tab stays where the user left it when a new AI suggestion is preselected from another category (selection + SNAP stay correct; only the visible tab can point elsewhere). Consider snapping the tab to the suggestion's category on preselect... already done in proceed(); repro only via stray tab tap — low priority.
- [x] Polish: [3D] Kick/punt ball spiral/tumble (DONE R6/R10 — ball stripes + pass spiral + kick tumble). Still open: slight shadow blob under the pass arc for depth reading.
- [x] Polish: [3D] TD celebration camera push-in + confetti (DONE R10).
- [ ] Perf: [3D] 22 humanoids × ~8 geometries each — fine on M-series simulator; profile on device, consider flattenedClone if needed.

## Round 4: Coach Mode — matchups, playbooks, X&O art, NFL look (2026-07-09, user request: "coachi näkee miten pelaajat pärjäävät toisiaan vastaan, pelikirjapohjaiset pelit, X&O-kuviot, NFL-näköiset pelaajat")

### Shipped (verified in simulator, GB vs CHI week 6)
- [x] Feature: [Engine] MatchupResolver (Engine/Match/MatchupResolver.swift) — attributes every resolved play to named player-vs-player battles, rating-weighted so stars win more reps: sack → "X beats Y around the edge/up the middle" (+ credited rusher role for the 3D pocket collapse), completion → WR-vs-CB separation (0.4 blanket … 4yd wide open, drives how far the corner trails at the catch), incompletion → coverage-win callout, run → hole size drives the DL surge (blown back vs penetration) + credited stuffer, INT → credited ball-hawk. keyOffense/DefensePlayerID added to PlayResult (set by PlaySimulator) so the field, feed, and callouts reference the SAME player.
- [x] Feature: [Engine] Scheme-familiarity busts — a player under 45% familiarity (or a call outside the installed playbook) can bust an assignment; surfaced as a purple-book callout ("C. Coleman cuts the route short — still learning the playbook", "X blows the assignment — the gap never opens"). VERIFIED live with feed-consistent naming.
- [x] Feature: [Engine] FieldUnit — role-ordered 11 starters per side (best-by-position), stable pseudo jersey numbers from UUID in position-correct ranges (QB 1-19, RB 20-49, OL 60-79, DL 90-99…); the 3D field now shows the real starters and the sim's INT defender pick is weighted to ball-hawking starters (was randomElement over the whole roster).
- [x] Feature: [UI] Matchup callout capsules over the field (green sword = your rep won, red = lost, purple book = scheme bust, gold star = star play) + winner pulse on the 3D figure; auto-dismiss 3.4s.
- [x] Feature: [UI] Playbook-driven call sheet — header "WEST COAST PLAYBOOK · 32% LEARNED" (scheme from OC + avg starter familiarity), plays tagged per scheme (OffensivePlayCall.schemes), out-of-playbook plays dimmed with a book icon and raise bust risk, AI suggestion constrained to installed plays. Defense panel titled by scheme ("HYBRID DEFENSE · STANCE") and presets flavored by scheme (Press Man blitzes out of man/DB pressure, Tampa 2 sits in two-deep…).
- [x] Feature: [UI] X&O chalkboard diagrams (UI/Match/PlayDiagramView.swift) — per-play route art (gold primary route + arrowheads, dashed gray secondaries, O-line dots) shown for the selected play next to the chips; defensive stance drawn as X's + translucent zone shells / man lines / red blitz arrows next to the stance buttons.
- [x] Feature: [3D] NFL uniform conventions — home wears team color + white pants, road team white jersey + team-color pants/helmet (instant contrast on grass); helmets + gray facemasks; 4 deterministic skin tones. Verified close-up: figures read as padded football players from broadcast height.
- [x] Fix: [Dashboard] Bye-week hero state — "Week 4 · Bye Week" + "Bye — next up vs CHI (Home) in Week 6" (was showing the next opponent's title with a bogus "Game played" line). Schedule has GB byes at weeks 4-5 — verify schedule generator produces exactly one bye per team (pre-existing issue, logged below).
- [x] Fix: [Choreography] QB scrambles now animate the QB keeping the ball (was always handing to the RB); pocket-collapse speed scales sack timing; completion ball goes to the sim's actual target when he's on the field.

### Open polish (round 5 candidates)
- [ ] Bug?: [Schedule] GB has no games in weeks 4 AND 5 (two byes) — verify schedule generator; teams should get exactly one bye.
- [ ] Polish: [CoachSim] Pass targets can be bench receivers not on the 3D field (callouts are guarded, but the ball animates to a different player's node than the feed names). Consider weighting sim receiver selection to the on-field 11 (stat-distribution impact needs a look).
- [ ] Polish: [CoachUI] Matchup callouts could also land in the play feed history (currently transient capsules only).
- [x] Polish: [3D] Lineman stances (R6), kick spiral (R6), TD camera push-in (R10) — all done.

## Round 5: Coach Mode — smoothness, Madden-98 look, call-driven formations, clipboard call sheets (2026-07-09, user requests: "smoothimpaa, ei töksähtelyä", "Madden 1998 -tyyli kauempaa", "puolustukseen enemmän pelejä", "pelit vaikuttavat formaatioihin", "clipboard-kortit kuvauksineen, enemmän pelejä per section")

### Shipped (verified in simulator)
- [x] Fix: [3D/Perf] Play-step movement no longer eases in/out at EVERY step boundary — playMove actions are linear so velocity stays continuous across chained steps (formation moves keep easing). This was the primary töksähtely.
- [x] Feature: [3D] Madden-98 framing — camera raised/pulled back (y46, z-36, ~45yd visible), player figures scaled 1.18 chunky, floating numbers enlarged, mowing stripes every 5yd, raked grandstands on all four sides with a procedural crowd-speck texture (no assets).
- [x] Feature: [Choreography] Formations are CALL-DRIVEN both ways: offense aligns per play (I-form under center for Inside Run/Sneak, offset back for Outside Run, deep gun for Draw/Screen, spread wide splits for deep shots, victory formation for kneels) and defense shows its call (nickel walks a backer over the slot, dime two out, goal-line squeeze, press-man corners on the line, cover-2/4 safety shells, blitz creep for LB/DB/all-out). Verified live: QB under center + lone deep back on Inside Run.
- [x] Feature: [UI] Live pre-snap preview — browsing the call sheet realigns the 3D formation immediately (onChange selectedCall / defCall); the play then runs from that same look (call+package threaded into preSnapStep/steps/Context).
- [x] Feature: [UI] Defensive call sheet: 10 named calls (Cover 3 / Cover 2 Shell / Quarters / Man Press / LB Blitz / Zone Blitz / Corner Blitz / All-Out Blitz / Goal Line / Dime Prevent) as clipboard cards with X&O diagram + blurb, scheme-tagged with installed-first ordering and book-icon dimming; replaces the old 4-preset row. AI defense also plays real packages vs the user (engine.aiDefensivePackage per situation).
- [x] Feature: [UI] Offense call sheet as clipboard cards — every play card carries its chalkboard diagram, name, badges (brain/check/book) and a one-line coach blurb; 5-column grid per category tab.
- [x] Feature: [Content] 6 new offensive plays (Counter, Toss Sweep, Hitch, TE Seam, Deep Cross, Flood) with hints, scheme tags, diagrams, blurbs — sections now hold 5-6 plays each; PlayCallView hints unified to OffensivePlayCall.blurb.
- [x] Fix: [CoachSim] FieldUnit RB pick mirrors PlaySimulator.findRB (RB first, FB fallback) — carrier on the field now always matches the play-feed name (was: FB with higher OVR hijacked the node while the feed named the RB).
- [x] Fix: [UI] Stable playbook-first card ordering (partition instead of non-strict sort predicate).

### Open polish (round 6 candidates)
- [x] Polish: [3D] Stands removed entirely in R6 per user feedback (apron walls replaced them in R9) — obsolete.
- [ ] Polish: [CoachUI] Defense card grid: 10 cards in a 5-col grid needs a scroll on smaller heights — consider 2 rows fixed.
- [x] Polish: [Choreography] Route art vs actual on-field routes still generic per depth — could read the diagram geometry to drive receiver paths 1:1. → TEHTY: RouteSpec on nyt yksi totuus (kortti = specin 2D-projektio, kenttä ajaa samat waypointit), ks. "Reittiaito koreografia" -osio ylhäällä.

## Round 6: Coach Mode — Madden 98 graphics leap (2026-07-09, user: "grafiikka ei vastaa Madden 98 -tasoa, enemmän ja parempi 3D" + reference screenshot + "katsomot turhat, kauempaa kuvattuna")

### Shipped (verified: full game played GB 9–6 CHI)
- [x] Feature: [3D] Articulated run cycle — legs/arms are hip/shoulder-hinged nodes that scissor while a player moves (opposite-phase swings, neutral return); combined with the bob+lean this finally reads as RUNNING, not sliding.
- [x] Feature: [3D] Lineman stances — OL + DL drop into a crouched 3-point lean when the formation settles (choreographer exposes stanceCrouchIndices; formation moves carry crouch sets).
- [x] Feature: [3D] Madden-98 camera: LOW behind the offense (y21, z-24, FOV 52) looking downfield — players big in the foreground, whole field visible to the far end zone, slightly farther than the PSX reference per user.
- [x] Feature: [3D] Speckled procedural turf texture (dark 4-tone noise, tiled), darker end zones/border, mow stripes as subtle translucent bands, distance fog so the far field falls into the night.
- [x] Feature: [3D] Field dressing: end zone wordmarks (CHI/GB), muted midfield logo disc, broadcast-yellow first-down line + blue LOS line (live-updated per situation incl. goal-to-go hiding), orange pylons.
- [x] Feature: [3D] Ball: bigger, white stripes, pass spiral / kick tumble rotation, orientation reset on landing.
- [x] Feature: [3D] Blob shadows under every player (PSX-style drop shadow anchor).
- [x] Feature: [UI] Field expands to 68% of the screen while the play is live (no more dead spinner panel), shrinks back for the call sheet.
- [x] Removed: stadium stands (user: turhat) — replaced by clean dark surround + fog. (Round-6a stands attempt left floating boxes in the camera path; removed entirely.)

### Self-analysis — what could STILL look better (round 7 candidates)
- [x] 3D: Tackle falls (DONE R7).
- [x] 3D: Ball-carry arm tuck (R7) + catch reach (R9) — done.
- [x] 3D: Two-segment limbs with knee/elbow bend (DONE R8).
- [x] 3D: Follow-cam on long gains (DONE R7).
- [x] 3D: Apron walls with white lips (DONE R9).
- [x] UI: Callouts lifted clear of the broadcast plate (DONE R9).

## Rounds 7–10: Coach Mode — tackles, poses, follow-cam, joints, broadcast layer (2026-07-09, user: "Toteuta R7 ja R8-R10")

### Shipped (verified in simulator: GB 21–3 MIN, week 7)
- [x] R7 Feature: [3D] Tackle falls — carrier and tackler rotate to the turf on the tackle step (staggered), lie for a beat and get up; sacks bury the QB under the rusher. VERIFIED: Dixon horizontal on the turf under three defenders after a 45-yard run.
- [x] R7 Feature: [3D] Ball-carry pose — the ball rides tucked under the carrier's left arm (elbow flexed, no pumping) instead of floating at the chest; releases on detach.
- [x] R7 Feature: [3D] Follow camera — when a carry or pass arc moves >11yd past the current focus, the camera pans downfield with it. VERIFIED: 45-yard breakaway tracked to the MIN 30.
- [x] R8 Feature: [3D] Two-segment limbs — thigh+shin hinged at hip and knee, upper arm+forearm hinged at shoulder and elbow; knees/elbows bend during the run cycle and release at rest. Forearms in skin tone read as jersey sleeves.
- [x] R9 Feature: [3D] Catch reach — the target (and pick-jumping DB) throws both arms up as the ball arrives; incompletions show the lunge.
- [x] R9 Feature: [3D] Apron walls with white lips on the sidelines + far end zone finish the frame without stands; matchup callouts lifted clear of the broadcast plate.
- [x] R10 Feature: [UI] Retro broadcast plate — "2ND & 10" in black/red-trim monospace flashes at every snap, Madden-98 style. VERIFIED on-field.
- [x] R10 Feature: [3D] Touchdown presentation — camera pushes to the end zone and a 42-piece gold/white/team-color confetti burst tumbles over it (deterministic, no particle assets).
- [x] Field dressing adapts per opponent (purple MIN end zone + wordmark at week 7 after red CHI at week 6).

### Open polish (round 11 candidates)
- [x] 3D: Pile-up on tackles — bring 1-2 pursuit defenders into the fall for gang-tackle reads. (DONE R11)
- [x] 3D: QB throwing motion (arm cock + release timed to the arc start). (DONE R11)
- [x] 3D: FG camera behind the posts. (DONE R11 — kick meter itself still open)
- [x] UI: Broadcast plate could carry the play call name ("2ND & 10 · DIG"). (DONE R11)

## Round 11: Coach Mode — 3D-pelimomenttien viimeistely (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [3D] Gang tackles — the 1-2 nearest chasing defenders (ranked by distance to the tackle spot, primary tackler excluded) get short closing moves onto the pile and join the falls list; the existing staggered fall delays (0.12s per slot) turn the stop into a proper pile-up on both rush and completion tackles. (PlayChoreographer: gangTacklers/pileOnMoves + rushSteps/completionSteps tackle steps)
- [x] Feature: [3D] QB throwing motion — when the ball leaves a carrier into an .arc flight, the passer's right arm ("armR", shoulder pivot) cocks back (rotateTo x +2.2), snaps forward (x -2.6) and settles to neutral, hooked to the start of runBallArc. Also fires on the TD ball spike, which reads correctly.
- [x] Feature: [3D] Kick camera — new scene API kickCamera(towardZ:) parks the camera low behind the goalposts (pos (0, 8, ±72), target (0, 4, ±40)) looking back up the field; CoachedGameView uses it for fieldGoal/extraPoint in runPlay and hands the shot back via focusCamera in finishPlay. A kickCameraActive flag keeps the follow-cam from stealing the shot during the kick arc (focusCamera always clears it).
- [x] Feature: [UI] Broadcast plate carries the called play — "2ND & 10 · DIG" (downDistanceText + " · " + call name) whenever the coach dialed an offensive call; AI/forced plays keep the plain situation plate.
- [x] Feature: [3D] Arc flight shadow — a small dark blob (flat cylinder, alpha 0.3, lightingModel constant) slides along the turf under every .arc flight using the same lerp without the apex term, removes itself at landing; cancelPlay sweeps any stragglers.
- [x] Feature: [3D] Catch leap — reach() adds a small hop (figure moveBy y +0.25 and back, easeOut/easeIn) under the arms-up reach so catches and pick attempts leave the ground.

### Left out
- [ ] Simulator verification — settled for green build + code review per round rules (navigation to a live coached game needs cooperative game state); visuals should be eyeballed in the next play session.
- [ ] Kick meter UI (only the FG camera angle was in scope this round).

## Round 13: Kickoffs & special situations — kickoff distribution, live kickoff choreography, FG blocks, onside kicks (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Sim] Shared kickoff distribution — `GameSimulator.rollKickoff()` / `kickoffStartYardLine()`: ~55% touchback out to the 30 (2024 dynamic-kickoff rule), otherwise a return to the 20–35, ~2% housed return TD (post-score kicks only). Used by BOTH engines so quick sim and live stay statistically identical: opening kick, post-score kicks (`determineNextPossession` now rolls the kickoff and carries a `KickoffResult` in `NextPossession`), second-half kick, and OT kick all draw from it.
- [x] Feature: [Sim] Kickoff return touchdowns — on a housed post-score kick the receiving team gets a synthetic one-play drive (`kickoffReturnTouchdownPlay`: playType .kickoff, 6 pts like every TD in this sim, yardsGained 0 so scrimmage yardage stays clean), momentum shift, highlight + play-log entry, then the ensuing kickoff hands the ball back to the original scorers. Identical bookkeeping in `GameSimulator.simulate` and `LiveGameEngine.endRegulationDrive`; gated on time remaining (no kick after the gun). `accumulateStats` skips QB/RB attribution for .kickoff TDs.
- [x] Fix: [Sim/Parity] OT after the first possession no longer force-teleports to the 25 — it uses `determineNextPossession`'s real start (kickoff draw after scores, actual field position after punts/turnovers), matching what the live engine already did.
- [x] Feature: [Live] `LiveGameEngine.pendingKickoff: KickoffEvent` (kicking side, start yard, touchback?, housed?) published at game start, after scores, at halftime, and at OT start; consumed by the view via `clearPendingKickoff()`.
- [x] Feature: [3D] Kickoff choreography — `PlayChoreographer.kickoffFormation` (kicker + 10-man coverage line on the 35 vs front line / wedge wave / upback / deep returner) and `kickoffSteps`: ball to the tee, kicker run-up, high hanging boot (apex 16) with lane coverage flying down and the wedge folding back, catch, then return-to-spot with converging tacklers and a gang-tackle finish — or a touchback kneel, or a full-field housed return (coverage trails, view adds camera push + confetti + banner). CoachedGameView runs it before the first snap of every kick-started drive (opening, post-score, second half, OT), opening lineup now starts in kickoff formation.
- [x] Feature: [Sim] Field-goal blocks — ~2.5% of FG attempts are swatted at the line before accuracy matters (`PlaySimulator.simulateFieldGoal`, outcome .fieldGoalMissed, "The kick is BLOCKED!" description). Applies identically to quick sim and live via the shared PlaySimulator path; no MatchupResolver change needed.
- [x] Feature: [Live/UI] Onside kick — when the player's team scores in Q4 (or later) while still trailing, the deep-kick animation is replaced by a confirmationDialog ("Onside Kick" vs cancel-role "Kick Deep", outside-tap = deep so the game can't stall). `LiveGameEngine.attemptOnsideKick()`: ~12% recovery keeps the ball at the player's own 48, failure gives the receivers a short field (their 55). Live-game player choice only — quick sim never onsides and the AI never gets the option, so nil-parameter parity is intact.

### Left out
- [ ] Kickoff return TDs on opening/second-half/OT kicks — restricted to post-score kickoffs; the non-loop call sites (pre-loop opening draw, halftime `continue` branch, OT possession rules) would each need their own scoring/possession plumbing for a ~1-in-100 event. Distribution position draw is identical everywhere, so parity holds.
- [ ] Kickoff clock consumption — kickoffs still take 0 game seconds in both engines (identical behavior, so no parity risk); could burn 5–10s later.
- [ ] Onside kick 3D choreography — the onside choice resolves with banners + formation sync; a bespoke short-hop kick animation was out of scope.
- [ ] Blocked-FG bespoke animation — blocked kicks reuse the missed-FG script (wide of the posts); a swat-at-the-line visual would need a new choreography step.
- [ ] Simulator verification — settled for green build + code review per round rules (a live coached game needs cooperative game state); kickoff visuals should be eyeballed in the next play session.

## Round 14: Ottelutilastot ja live-HUD coach-modeen (2026-07-09)

### Shipped (BUILD SUCCEEDED)
- [x] Feature: [Live] Stat leaders — `LiveGameEngine.passingLeader/rushingLeader/receivingLeader/sackLeader(forHome:)` return a `StatLeader` (id, short name, compact stat line like "18/25 · 245 YDS · 2 TD") computed from the per-drive `statsAccumulator`; team split via new `homePlayerIDs`/`awayPlayerIDs` roster snapshots. `totalYards(forHome:)` sums completed-drive yardage with the same accounting as `GameSimulator.buildTeamBoxScore`.
- [x] Feature: [UI] Box score sheet — new "Stats" button in the situation strip opens `LiveBoxScoreSheet` (private, CoachedGameView.swift): quarter-by-quarter line score (dashes for unreached quarters, OT column appears in overtime), total-yards comparison via the existing `StatComparisonRow`, and both teams' passing/rushing/receiving/sack leaders side by side. Same dark card style (`.cardBackground()`, accentGold section titles), medium/large detents.
- [x] Feature: [UI] Drive chip — situation strip shows a compact "Drive: 5 plays, 42 yds" chip for the drive in progress (`currentDrivePlays`; yards counted from scrimmage plays only so punts/kicks don't inflate it).
- [x] Feature: [Live] Player grades — `matchupWins`/`matchupLosses: [UUID: Int]` published on the engine, tallied in `step()` from every `MatchupResolver` event (offRole/defRole mapped to FieldUnit player ids at resolve time, before possession flips). Presentation-only: never feeds back into the sim, so nil-parameter parity with GameSimulator.simulate is intact.
- [x] Feature: [UI] Top performers — final overlay shows the 3 players with the most matchup wins (ties broken by fewer losses) as "name + W-L battles + team abbr" cards, player's own team highlighted in gold (`topPerformers(limit:)` + `topPerformersRow`).

### Left out
- [ ] Top performers in GameSummaryView — not trivial: GameSummary is built from `GameSimulator.GameResult`/`BoxScore` (shared with quick sim, which has no matchup data), so surfacing matchup W-L there would mean widening the shared result type for a live-only stat. GameSummary already has its own stats-based topPerformersCard; final-overlay-only per the round spec's fallback.
- [ ] Live leaders including the in-progress drive — stats accumulate per completed drive (mirrors the quick sim's accumulateStats cadence); recomputing mid-drive would double-count once the drive finishes. Sheet documents the cadence in a comment.
- [ ] Simulator verification — settled for green build + code review per round rules (a live coached game needs cooperative game state); the sheet/chip/overlay should be eyeballed in the next play session.

## Visual design loop: coach-mode 3D (2026-07-09, /visual-design-loop, 2 iteraatiota)
- [x] Iter 1: goalposts thicker + duller gold (glow-stick look fixed); end zone tint deepened; dark apron strips ground the sideline walls; defense-card zone bubbles tightened (PlayDiagramView)
- [x] Iter 2: end zones deepened further (darken 0.45 — no more neon vs muted turf); floating jersey numbers 0.75→0.62 + calmer emission (no more label collisions in line traffic); helmets shaded 20% darker than jerseys (heads read as gear, NFL look); broadcast plate / result toast vertical separation
- [x] Away-game camera verified in the same pass: view from behind the player's unit, field text re-oriented, kickoff + Stats button + drive chip (R13/R14) all confirmed live
- Quality: ~8/10 for the Madden-98 retro target. Remaining candidates: horizon glow behind far end zone, number decluttering in pile-ups (fade overlapping), goalpost neck anchoring.
