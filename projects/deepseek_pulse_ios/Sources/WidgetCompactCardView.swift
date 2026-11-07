import UIKit

/// Small-size Home-Screen widget layout: state, countdown and the balance slot.
///
/// 1.0.7 paints the backdrop from the chosen theme and words the balance slot through
/// PulseBalanceWording, matching the real small widget.
final class WidgetCompactCardView: UIView {

    private let backdrop = WidgetBackdropView(frame: .zero)
    private let stateLabel = UILabel()
    private let countdownLabel = UILabel()
    private let captionLabel = UILabel()
    private let balanceLabel = UILabel()

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

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        stateLabel.font = Typography.scaled(13, UIFont.Weight.heavy, style: .headline)
        stateLabel.textColor = UIColor.white

        countdownLabel.font = Typography.digits(22, UIFont.Weight.bold)
        countdownLabel.textColor = UIColor.white
        countdownLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.minimumScaleFactor = 0.6

        captionLabel.font = Typography.scaled(10.5, UIFont.Weight.medium, style: .caption2)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        captionLabel.numberOfLines = 2

        balanceLabel.font = Typography.scaled(12, UIFont.Weight.semibold, style: .footnote)
        balanceLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        balanceLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [stateLabel, countdownLabel, captionLabel, balanceLabel])
        stack.axis = .vertical
        stack.spacing = 3
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

    func apply(snapshot: WidgetPlanner.Snapshot,
               schedule: PricingSchedule,
               now: Date,
               appearance: AppAppearance = .current,
               store: SettingsStore = .shared) {
        backdrop.apply(appearance: appearance, state: snapshot.state)
        stateLabel.text = WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
        if schedule.discountsEnabled, let target = snapshot.nextSwitchAt {
            countdownLabel.text = WidgetPlanner.countdown(from: now, to: target)
        } else {
            countdownLabel.text = schedule.discountsEnabled ? "--" : "STD"
        }
        let caption = WidgetPlanner.countdownCaption(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
        captionLabel.text = caption.isEmpty ? WidgetPlanner.peakLeftLabel(minutes: snapshot.peakMinutesLeftToday) : caption

        if appearance.showBalance {
            if let cached = store.cachedSnapshot, let info = cached.primary {
                balanceLabel.text = MoneyFormat.amount(info.totalBalance, currency: info.currency)
            } else {
                balanceLabel.text = PulseBalanceWording.slot(hasBalance: false, hasAPIKey: store.hasAPIKey)
            }
            balanceLabel.isHidden = false
        } else {
            balanceLabel.isHidden = true
        }
    }
}
