import SwiftUI

struct ContractExtensionSheet: View {

    let player: Player
    @Bindable var team: Team
    let capMode: CapMode

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var years: Int = 2
    @State private var annualSalaryThousands: Int = 5000   // $5M default
    @State private var signingBonusThousands: Int = 0       // realistic only
    @State private var guaranteedThousands: Int = 0         // realistic only
    @State private var showConfirmAlert = false
    @State private var showYearlyBreakdown = false

    private let minYears = 1
    private let maxYears = 5
    private let salaryStep = 500       // $500K increments
    private let minSalary = 500        // $500K floor
    private let maxSalary = 75000      // $75M ceiling

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    playerHeaderCard
                    contractTermsCard
                    if capMode == .realistic {
                        realisticFieldsCard
                    }
                    yearlyBreakdownCard
                    capImpactCard
                    actionButtons
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Extend Contract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .alert("Extend \(player.fullName)?", isPresented: $showConfirmAlert) {
            Button("Sign Extension") { signContract() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let totalYears = player.contractYearsRemaining + years
            Text("Extend \(player.fullName) with a \(years)-year extension at \(formatMillions(annualSalaryThousands)) per year. Total contract: \(totalYears) years.")
        }
        .onAppear { seedDefaults() }
    }

    // MARK: - Player Header Card

    private var playerHeaderCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.fullName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))
                    Text("Age \(player.age)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(player.overall)")
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(player.overall))
                Text("OVR")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Contract Terms Card

    private var contractTermsCard: some View {
        VStack(spacing: 16) {
            sectionHeader("Contract Terms")

            // Years stepper
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Years")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Length of new deal")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                HStack(spacing: 16) {
                    stepperButton(systemImage: "minus") {
                        if years > minYears { years -= 1 }
                    }
                    .disabled(years <= minYears)

                    Text("\(years) yr\(years == 1 ? "" : "s")")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .frame(minWidth: 56, alignment: .center)

                    stepperButton(systemImage: "plus") {
                        if years < maxYears { years += 1 }
                    }
                    .disabled(years >= maxYears)
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Annual salary stepper
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Annual Salary")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Per year, in $500K steps")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                HStack(spacing: 16) {
                    stepperButton(systemImage: "minus") {
                        if annualSalaryThousands > minSalary {
                            annualSalaryThousands -= salaryStep
                        }
                    }
                    .disabled(annualSalaryThousands <= minSalary)

                    Text(formatMillions(annualSalaryThousands))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                        .frame(minWidth: 72, alignment: .center)

                    stepperButton(systemImage: "plus") {
                        if annualSalaryThousands < maxSalary {
                            annualSalaryThousands += salaryStep
                        }
                    }
                    .disabled(annualSalaryThousands >= maxSalary)
                }
            }

            // Salary slider for fine control
            Slider(
                value: Binding(
                    get: { Double(annualSalaryThousands) },
                    set: { annualSalaryThousands = roundToStep(Int($0)) }
                ),
                in: Double(minSalary)...Double(maxSalary),
                step: Double(salaryStep)
            )
            .tint(Color.accentGold)
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Realistic Fields Card

    private var realisticFieldsCard: some View {
        VStack(spacing: 16) {
            sectionHeader("Advanced Terms")

            // Signing bonus
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signing Bonus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Fully guaranteed at signing")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                HStack(spacing: 16) {
                    stepperButton(systemImage: "minus") {
                        if signingBonusThousands >= salaryStep {
                            signingBonusThousands -= salaryStep
                        }
                    }
                    .disabled(signingBonusThousands <= 0)

                    Text(formatMillions(signingBonusThousands))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .frame(minWidth: 72, alignment: .center)

                    stepperButton(systemImage: "plus") {
                        if signingBonusThousands < annualSalaryThousands * years {
                            signingBonusThousands += salaryStep
                        }
                    }
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Guaranteed money
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guaranteed Money")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Total guaranteed value")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                HStack(spacing: 16) {
                    stepperButton(systemImage: "minus") {
                        if guaranteedThousands >= salaryStep {
                            guaranteedThousands -= salaryStep
                        }
                    }
                    .disabled(guaranteedThousands <= 0)

                    Text(formatMillions(guaranteedThousands))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.warning)
                        .frame(minWidth: 72, alignment: .center)

                    stepperButton(systemImage: "plus") {
                        let maxGuaranteed = annualSalaryThousands * years
                        if guaranteedThousands < maxGuaranteed {
                            guaranteedThousands += salaryStep
                        }
                    }
                }
            }

            if capMode == .realistic {
                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                HStack {
                    Text("Dead Cap (if cut)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(formatMillions(projectedDeadCap))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.danger)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Yearly Breakdown Card

    private var yearlyBreakdownCard: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showYearlyBreakdown.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                    Text("Yearly Contract Breakdown")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: showYearlyBreakdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(showYearlyBreakdown ? "Collapse yearly breakdown" : "Expand yearly breakdown")

            if showYearlyBreakdown {
                Divider().overlay(Color.surfaceBorder)

                let breakdown = computeYearlyBreakdown()

                // Header row
                HStack(spacing: 0) {
                    Text("Year")
                        .frame(width: 44, alignment: .leading)
                    Text("Base Salary")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Bonus")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Cap Hit")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Dead Cap")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 4)

                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                // Year rows with separator between current contract and extension
                let currentYearsLeft = player.contractYearsRemaining

                ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, year in
                    // Insert separator between current contract and extension years
                    if index == currentYearsLeft && currentYearsLeft > 0 {
                        HStack(spacing: 6) {
                            Rectangle().fill(Color.accentGold.opacity(0.4)).frame(height: 1)
                            Text("EXTENSION")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentGold)
                            Rectangle().fill(Color.accentGold.opacity(0.4)).frame(height: 1)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }

                    HStack(spacing: 0) {
                        Text("Yr \(year.yearNumber)")
                            .frame(width: 44, alignment: .leading)
                        Text(formatMillions(year.baseSalary))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(year.proratedBonus))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(year.capHit))
                            .foregroundStyle(Color.accentGold)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(year.deadCapIfCut))
                            .foregroundStyle(Color.danger.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(index < currentYearsLeft ? Color.textTertiary : Color.textSecondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                }

                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                // Totals row
                HStack(spacing: 0) {
                    Text("Total")
                        .frame(width: 44, alignment: .leading)
                    Text(formatMillions(breakdown.reduce(0) { $0 + $1.baseSalary }))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(formatMillions(breakdown.reduce(0) { $0 + $1.proratedBonus }))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(formatMillions(breakdown.reduce(0) { $0 + $1.capHit }))
                        .foregroundStyle(Color.accentGold)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Cap Impact Card

    private var capImpactCard: some View {
        VStack(spacing: 16) {
            sectionHeader("Projected Cap Impact")

            HStack(spacing: 0) {
                capImpactColumn(label: "Total Value", value: formatMillions(annualSalaryThousands * years), color: .textPrimary)
                capImpactColumn(label: "Cap Hit/yr", value: formatMillions(annualSalaryThousands), color: .accentGold)
                capImpactColumn(label: "Cap After", value: formatMillions(projectedRemainingCap), color: projectedRemainingCap >= 0 ? .success : .danger)
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Cap space indicator
            CapImpactBar(
                currentUsage: team.currentCapUsage,
                newContract: annualSalaryThousands,
                totalCap: team.salaryCap,
                previousSalary: player.annualSalary
            )
        }
        .padding(20)
        .cardBackground()
    }

    private func capImpactColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showConfirmAlert = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "signature")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Sign Contract")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canAfford ? Color.accentGold : Color.textTertiary)
                        .shadow(color: canAfford ? Color.accentGold.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
                )
            }
            .disabled(!canAfford)

            if !canAfford {
                Label("Insufficient cap space", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.danger)
            }
        }
    }

    // MARK: - Computed Properties

    private var projectedRemainingCap: Int {
        // Remove old salary, add new contract
        team.salaryCap - (team.currentCapUsage - player.annualSalary + annualSalaryThousands)
    }

    private var projectedDeadCap: Int {
        guard capMode == .realistic else { return 0 }
        // Dead cap = signing bonus + prorated portion of guaranteed remaining
        let bonus = signingBonusThousands
        let guaranteed = max(0, guaranteedThousands - signingBonusThousands)
        return bonus + Int(Double(guaranteed) * 0.25)
    }

    private var canAfford: Bool {
        projectedRemainingCap >= 0
    }

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Computes yearly breakdown showing both remaining current contract years
    /// AND new extension years, clearly separated.
    private func computeYearlyBreakdown() -> [ContractYearDetail] {
        var result: [ContractYearDetail] = []
        let currentYearsLeft = player.contractYearsRemaining

        // 1. Current contract years (at current salary)
        if currentYearsLeft > 0 {
            for i in 0..<currentYearsLeft {
                result.append(ContractYearDetail(
                    yearNumber: i + 1,
                    baseSalary: player.annualSalary,
                    proratedBonus: 0,
                    capHit: player.annualSalary,
                    deadCapIfCut: 0
                ))
            }
        }

        // 2. Extension years (at new salary with escalating/front-loaded structure)
        guard years > 0 else { return result }

        let baseSalaries: [Int]
        if player.age < 28 {
            baseSalaries = ContractEngine.escalatingBaseSalaries(annualSalary: annualSalaryThousands, years: years)
        } else {
            baseSalaries = ContractEngine.frontLoadedBaseSalaries(annualSalary: annualSalaryThousands, years: years)
        }

        let bonus = capMode == .realistic ? signingBonusThousands : 0
        let proratedPerYear = years > 0 ? bonus / years : 0

        for yearIndex in 0..<years {
            let base = yearIndex < baseSalaries.count ? baseSalaries[yearIndex] : annualSalaryThousands
            let yearCapHit = base + proratedPerYear
            let remainingFromThisYear = years - yearIndex
            let deadCapIfCut = proratedPerYear * remainingFromThisYear

            result.append(ContractYearDetail(
                yearNumber: currentYearsLeft + yearIndex + 1,
                baseSalary: base,
                proratedBonus: proratedPerYear,
                capHit: yearCapHit,
                deadCapIfCut: deadCapIfCut
            ))
        }

        return result
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func roundToStep(_ value: Int) -> Int {
        let rounded = (value / salaryStep) * salaryStep
        return max(minSalary, min(maxSalary, rounded))
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func seedDefaults() {
        // Pre-fill with player's current salary as a starting point
        annualSalaryThousands = roundToStep(player.annualSalary)
        // Default extension length: 2 years (not the remaining contract years)
        years = 2
        if capMode == .realistic {
            guaranteedThousands = roundToStep(Int(Double(annualSalaryThousands) * Double(years) * 0.4))
        }
    }

    // MARK: - Sign Action

    private func signContract() {
        // Update cap: subtract old salary, add new extension salary
        team.currentCapUsage = team.currentCapUsage - player.annualSalary + annualSalaryThousands
        // Extension ADDS years to the current contract, not replaces
        player.contractYearsRemaining = player.contractYearsRemaining + years
        // New salary kicks in for the extension years (cap hit uses new salary)
        player.annualSalary = annualSalaryThousands
        dismiss()
    }
}

// MARK: - Cap Impact Bar

private struct CapImpactBar: View {
    let currentUsage: Int
    let newContract: Int
    let totalCap: Int
    let previousSalary: Int

    private var projectedUsage: Int {
        currentUsage - previousSalary + newContract
    }

    private var usedFraction: Double {
        guard totalCap > 0 else { return 0 }
        return min(1.0, Double(currentUsage - previousSalary) / Double(totalCap))
    }

    private var newFraction: Double {
        guard totalCap > 0 else { return 0 }
        return min(1.0, Double(newContract) / Double(totalCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cap Space Used")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(String(format: "%.1f%%", min(100, Double(projectedUsage) / Double(totalCap) * 100)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(projectedUsage > totalCap ? Color.danger : Color.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 12)

                    // Existing usage (minus old contract)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentGold.opacity(0.6))
                        .frame(width: geo.size.width * usedFraction, height: 12)

                    // New contract increment
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentGold)
                        .frame(
                            width: geo.size.width * min(newFraction, 1.0 - usedFraction),
                            height: 12
                        )
                        .offset(x: geo.size.width * usedFraction)
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContractExtensionSheet(
            player: Player(
                firstName: "Patrick",
                lastName: "Mahomes",
                position: .QB,
                age: 28,
                yearsPro: 7,
                physical: PhysicalAttributes(
                    speed: 72, acceleration: 78, strength: 65,
                    agility: 80, stamina: 85, durability: 88
                ),
                mental: MentalAttributes(
                    awareness: 94, decisionMaking: 92, clutch: 96,
                    workEthic: 88, coachability: 82, leadership: 90
                ),
                positionAttributes: .quarterback(QBAttributes(
                    armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                    accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                contractYearsRemaining: 3,
                annualSalary: 45000
            ),
            team: Team(
                name: "Chiefs",
                city: "Kansas City",
                abbreviation: "KC",
                conference: .AFC,
                division: .west,
                mediaMarket: .large,
                salaryCap: 265_000,
                currentCapUsage: 210_000
            ),
            capMode: .realistic
        )
    }
}
