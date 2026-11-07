import UIKit

/// Lock Screen / accessory style preview: state, live countdown and the switch time.
///
/// 1.0.7 redraws this to match the real accessoryRectangular widget: a two-column card with the
/// pricing state and level on the left, the countdown and the local switch time on the right, on a
/// translucent material instead of a card tinted by the app palette (iOS draws Lock Screen widgets in
/// its own monochrome style, so a coloured card would misrepresent the result).
final class WidgetLockScreenCardView: UIView {

    private let stateLabel = UILabel()
    private let levelLabel = UILabel()
    private let countdownLabel = UILabel()
    private let switchLabel = UILabel()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        backgroundColor = .clear
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        material.translatesAutoresizingMaskIntoConstraints = false
        material.isUserInteractionEnabled = false
        addSubview(material)

        stateLabel.font = Typography.scaled(13, UIFont.Weight.heavy, style: .headline)
        stateLabel.textColor = UIColor.white

        levelLabel.font = Typography.scaled(9.5, UIFont.Weight.semibold, style: .caption2)
        levelLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        levelLabel.numberOfLines = 1

        countdownLabel.font = Typography.digits(21, UIFont.Weight.bold)
        countdownLabel.textColor = UIColor.white
        countdownLabel.textAlignment = .right
        countdownLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.minimumScaleFactor = 0.6

        switchLabel.font = Typography.digits(10.5, UIFont.Weight.semibold)
        switchLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        switchLabel.textAlignment = .right

        let left = UIStackView(arrangedSubviews: [stateLabel, levelLabel])
        left.axis = .vertical
        left.spacing = 1
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let right = UIStackView(arrangedSubviews: [countdownLabel, switchLabel])
        right.axis = .vertical
        right.spacing = 0
        right.alignment = .trailing

        let row = UIStackView(arrangedSubviews: [left, right])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: topAnchor),
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11)
        ])
    }

    func apply(snapshot: WidgetPlanner.Snapshot, schedule: PricingSchedule, now: Date) {
        let headline = WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
        stateLabel.text = headline

        let caption = WidgetPlanner.countdownCaption(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
        levelLabel.text = caption.isEmpty
            ? WidgetPlanner.peakLeftLabel(minutes: snapshot.peakMinutesLeftToday).uppercased()
            : caption.uppercased()

        if schedule.discountsEnabled, let target = snapshot.nextSwitchAt {
            countdownLabel.text = WidgetPlanner.countdown(from: now, to: target)
            switchLabel.text = ClockFormat.localTimeLabel(target)
        } else {
            countdownLabel.text = schedule.discountsEnabled ? "--" : "STD"
            switchLabel.text = schedule.discountsEnabled ? "no window" : "discounts off"
        }
    }
}
