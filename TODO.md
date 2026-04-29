# Dynasty - TODO

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
