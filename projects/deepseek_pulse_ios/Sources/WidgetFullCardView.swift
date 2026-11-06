import UIKit

/// Medium-size Home-Screen widget layout: state, countdown, next switch, minutes left, 24-hour band.
final class WidgetFullCardView: UIView {

    private let pill = PillView(frame: .zero)
    private let countdownLabel = UILabel()
    private let captionLabel = UILabel()
    private let footnoteLabel = UILabel()
    private let band = DayTimelineView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        backgroundColor = AppColors.surfaceElevated
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        let backdrop = WidgetBackdropView(frame: .zero)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        countdownLabel.font = Typography.digits(26, UIFont.Weight.bold)
        countdownLabel.textColor = WidgetPalette.onWidget
        countdownLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.minimumScaleFactor = 0.6

        captionLabel.font = Typography.scaled(12, UIFont.Weight.semibold, style: .footnote)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        captionLabel.numberOfLines = 0

        footnoteLabel.font = Typography.scaled(11, UIFont.Weight.medium, style: .caption2)
        footnoteLabel.textColor = UIColor.white.withAlphaComponent(0.66)
        footnoteLabel.numberOfLines = 0

        band.translatesAutoresizingMaskIntoConstraints = false
        band.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let brand = UILabel()
        brand.text = "DEEPSEEK PULSE"
        brand.font = Typography.scaled(10, UIFont.Weight.bold, style: .caption1)
        brand.textColor = UIColor.white.withAlphaComponent(0.85)

        let topRow = UIStackView(arrangedSubviews: [brand, pill])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [topRow, countdownLabel, captionLabel, band, footnoteLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(2, after: countdownLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    func apply(snapshot: WidgetPlanner.Snapshot, schedule: PricingSchedule, now: Date) {
        let color = DayTimelineView.color(for: snapshot.state)
        pill.set(text: WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled), color: color)
        if schedule.discountsEnabled, let target = snapshot.nextSwitchAt {
            countdownLabel.text = WidgetPlanner.countdown(from: now, to: target)
        } else {
            countdownLabel.text = schedule.discountsEnabled ? "--" : "STD"
        }
        captionLabel.text = WidgetPlanner.footnote(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
            + " · " + WidgetPlanner.peakLeftLabel(minutes: snapshot.peakMinutesLeftToday)
        band.segments = schedule.segments(for: now)
        band.nowSeconds = PricingSchedule.secondsOfDayUTC(now)
        footnoteLabel.text = ClockFormat.utcDayLabel(now) + " · " + snapshot.weekdayLabel
            + " · " + ClockFormat.localTimeLabel(now) + " local"
    }
}
