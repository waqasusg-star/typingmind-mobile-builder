import UIKit

/// Small Home-Screen widget layout: state and countdown only.
final class WidgetCompactCardView: UIView {

    private let pill = PillView(frame: .zero)
    private let countdownLabel = UILabel()
    private let captionLabel = UILabel()

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

        countdownLabel.font = Typography.digits(22, UIFont.Weight.bold)
        countdownLabel.textColor = WidgetPalette.onWidget
        countdownLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.minimumScaleFactor = 0.5

        captionLabel.font = Typography.scaled(11, UIFont.Weight.medium, style: .caption2)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        captionLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [pill, countdownLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14)
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
    }
}
