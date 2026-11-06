import UIKit

/// Expanding card used by the Live Activity / Dynamic Island layouts.
final class LiveActivityCardView: UIView {

    private let titleLabel = UILabel()
    private let stateLabel = UILabel()
    private let countdownLabel = UILabel()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        backgroundColor = .clear

        titleLabel.text = "DeepSeek pricing"
        titleLabel.font = Typography.scaled(11, UIFont.Weight.semibold, style: .caption1)
        titleLabel.textColor = AppColors.textDim

        stateLabel.font = Typography.scaled(15, UIFont.Weight.bold, style: .headline)
        stateLabel.textColor = AppColors.text

        countdownLabel.font = Typography.digits(24, UIFont.Weight.bold)
        countdownLabel.textColor = AppColors.text
        countdownLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.minimumScaleFactor = 0.6

        captionLabel.font = Typography.scaled(11, UIFont.Weight.medium, style: .caption2)
        captionLabel.textColor = AppColors.textDim
        captionLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, stateLabel, countdownLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(2, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
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
            + " · " + WidgetPlanner.dayTag(daysAhead: snapshot.nextSwitchDaysAhead)
    }
}
