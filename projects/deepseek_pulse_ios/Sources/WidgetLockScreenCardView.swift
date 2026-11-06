import UIKit

/// Lock Screen / accessory style layout: state, countdown and one caption line.
final class WidgetLockScreenCardView: UIView {

    private let stateLabel = UILabel()
    private let countdownLabel = UILabel()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        backgroundColor = UIColor.white.withAlphaComponent(0.08)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        stateLabel.font = Typography.scaled(13, UIFont.Weight.bold, style: .headline)
        stateLabel.textColor = AppColors.text

        countdownLabel.font = Typography.digits(15, UIFont.Weight.semibold)
        countdownLabel.textColor = AppColors.text
        countdownLabel.setContentHuggingPriority(.required, for: .horizontal)

        captionLabel.font = Typography.scaled(10.5, UIFont.Weight.medium, style: .caption2)
        captionLabel.textColor = AppColors.textDim
        captionLabel.numberOfLines = 2

        let spacer = UIView(frame: .zero)
        let row = UIStackView(arrangedSubviews: [stateLabel, spacer, countdownLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let stack = UIStackView(arrangedSubviews: [row, captionLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    func apply(snapshot: WidgetPlanner.Snapshot, schedule: PricingSchedule, now: Date) {
        stateLabel.text = WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
        if schedule.discountsEnabled, let target = snapshot.nextSwitchAt {
            countdownLabel.text = WidgetPlanner.countdown(from: now, to: target)
        } else {
            countdownLabel.text = schedule.discountsEnabled ? "--" : "STD"
        }
        captionLabel.text = WidgetPlanner.footnote(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
    }
}
