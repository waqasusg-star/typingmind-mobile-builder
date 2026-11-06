import UIKit

// MARK: - Building blocks

class CardView: UIView {

    let content = UIStackView()

    init(insets: UIEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)) {
        super.init(frame: .zero)
        backgroundColor = AppColors.surface
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous

        content.axis = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class PillView: UIView {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        label.font = Typography.scaled(11, .bold, style: .caption1)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(text: String, color: UIColor) {
        label.text = text
        label.textColor = color
        backgroundColor = color.withAlphaComponent(0.20)
        accessibilityLabel = text
    }
}

final class PaddedTextField: UITextField {

    var insets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: insets) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: insets) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: insets) }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 40)
    }
}

// MARK: - Widget card

struct WidgetContent {
    var hasKey = false
    var totalAmount = "—"
    var currencyCode = ""
    var availabilityText = ""
    var availabilityColor = AppColors.textDim
    var granted = "—"
    var toppedUp = "—"
    var stateText = "STANDARD"
    var stateColor = AppColors.textDim
    var detailLine = ""
    var noteLine = ""
    var clockLine = ""
    var updatedLine = ""
}

final class WidgetCardView: UIView {

    private let gradient = CAGradientLayer()
    private let brandLabel = UILabel()
    private let pill = PillView()
    private let totalLabel = UILabel()
    private let availabilityLabel = UILabel()
    private let grantedBox = StatBoxView(title: "Granted")
    private let toppedBox = StatBoxView(title: "Topped up")
    private let detailLabel = UILabel()
    private let noteLabel = UILabel()
    private let clockLabel = UILabel()
    private let updatedLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        backgroundColor = AppColors.surfaceElevated
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        gradient.colors = [UIColor(hex: 0x2B3BFF).cgColor, UIColor(hex: 0x131A2C).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)

        brandLabel.text = "DEEPSEEK API"
        brandLabel.font = Typography.scaled(11, .bold, style: .caption1)
        brandLabel.textColor = UIColor.white.withAlphaComponent(0.85)

        totalLabel.font = Typography.digits(38, .bold)
        totalLabel.textColor = .white
        totalLabel.adjustsFontSizeToFitWidth = true
        totalLabel.minimumScaleFactor = 0.55
        totalLabel.numberOfLines = 1
        totalLabel.accessibilityLabel = "Account balance"

        availabilityLabel.font = Typography.scaled(12, .semibold, style: .footnote)
        availabilityLabel.numberOfLines = 0

        detailLabel.font = Typography.scaled(13, .semibold, style: .subheadline)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.94)
        detailLabel.numberOfLines = 0

        noteLabel.font = Typography.scaled(11, .medium, style: .caption1)
        noteLabel.textColor = UIColor(hex: 0xFFC46B)
        noteLabel.numberOfLines = 0

        clockLabel.font = Typography.scaled(11, .medium, style: .caption1)
        clockLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        clockLabel.numberOfLines = 0

        updatedLabel.font = Typography.scaled(11, .medium, style: .caption1)
        updatedLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        updatedLabel.numberOfLines = 0

        let topRow = UIStackView(arrangedSubviews: [brandLabel, pill])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 10

        let statsRow = UIStackView(arrangedSubviews: [grantedBox, toppedBox])
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 10

        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let stack = UIStackView(arrangedSubviews: [topRow, totalLabel, availabilityLabel, statsRow, separator, detailLabel, noteLabel, clockLabel, updatedLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(2, after: totalLabel)
        stack.setCustomSpacing(14, after: availabilityLabel)
        stack.setCustomSpacing(14, after: statsRow)
        stack.setCustomSpacing(12, after: separator)
        stack.setCustomSpacing(4, after: detailLabel)
        stack.setCustomSpacing(4, after: noteLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    func apply(_ content: WidgetContent) {
        pill.set(text: content.stateText, color: content.stateColor)
        totalLabel.text = content.totalAmount
        availabilityLabel.text = content.availabilityText
        availabilityLabel.textColor = content.availabilityColor
        grantedBox.value = content.granted
        toppedBox.value = content.toppedUp
        detailLabel.text = content.detailLine
        noteLabel.text = content.noteLine
        noteLabel.isHidden = content.noteLine.isEmpty
        clockLabel.text = content.clockLine
        updatedLabel.text = content.updatedLine
    }
}

final class StatBoxView: UIView {

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    var value: String {
        get { valueLabel.text ?? "" }
        set { valueLabel.text = newValue }
    }

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        titleLabel.text = title.uppercased()
        titleLabel.font = Typography.scaled(10, .bold, style: .caption2)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.62)

        valueLabel.font = Typography.digits(15, .semibold)
        valueLabel.textColor = .white
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - 24 hour timeline

final class DayTimelineView: UIView {

    var segments: [ScheduleSegment] = [] {
        didSet { setNeedsDisplay() }
    }

    var nowSeconds: Int = 0 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 78)
    }

    static func color(for state: PricingState) -> UIColor {
        switch state {
        case .peak: return AppColors.peak
        case .offPeak: return AppColors.offPeak
        case .standard: return AppColors.textDim
        }
    }

    override func draw(_ rect: CGRect) {
        let barHeight: CGFloat = 16
        let barRect = CGRect(x: 0, y: 6, width: rect.width, height: barHeight)
        let barPath = UIBezierPath(roundedRect: barRect, cornerRadius: barHeight / 2)
        AppColors.surfaceElevated.setFill()
        barPath.fill()

        if let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            barPath.addClip()
            for segment in segments {
                let x = barRect.minX + barRect.width * CGFloat(segment.startMinute) / CGFloat(PricingSchedule.minutesPerDay)
                let width = barRect.width * CGFloat(segment.endMinute - segment.startMinute) / CGFloat(PricingSchedule.minutesPerDay)
                let alpha: CGFloat
                switch segment.state {
                case .peak: alpha = 0.75
                case .offPeak: alpha = 0.9
                case .standard: alpha = 0.45
                }
                DayTimelineView.color(for: segment.state).withAlphaComponent(alpha).setFill()
                context.fill(CGRect(x: x, y: barRect.minY, width: width, height: barRect.height))
            }
            context.restoreGState()
        }

        let clamped = max(0, min(nowSeconds, PricingSchedule.secondsPerDay - 1))
        let markerX = barRect.minX + barRect.width * CGFloat(clamped) / CGFloat(PricingSchedule.secondsPerDay)
        let marker = UIBezierPath(ovalIn: CGRect(x: markerX - 5, y: barRect.midY - 5, width: 10, height: 10))
        UIColor.white.setFill()
        marker.fill()
        AppColors.background.setStroke()
        marker.lineWidth = 2
        marker.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: AppColors.textDim
        ]
        let marks: [(String, CGFloat)] = [("00", 0), ("06", 0.25), ("12", 0.5), ("18", 0.75), ("24", 1)]
        let labelTop = rect.height - 14
        for (text, fraction) in marks {
            let size = (text as NSString).size(withAttributes: attributes)
            var x = rect.width * fraction - size.width / 2
            x = min(max(x, 0), max(0, rect.width - size.width))
            (text as NSString).draw(at: CGPoint(x: x, y: labelTop), withAttributes: attributes)
        }
    }
}

// MARK: - Rates table

final class RateTableView: UIView {

    private let stack = UIStackView()
    private let valueWidth: CGFloat = 76

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(models: [ModelRate], offPeakActive: Bool, discountEnabled: Bool) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stack.addArrangedSubview(headerRow(offPeakActive: offPeakActive, discountEnabled: discountEnabled))

        for (index, model) in models.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = AppColors.surfaceElevated
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(divider)
            }
            let nameLabel = UILabel()
            nameLabel.text = model.displayName
            nameLabel.font = Typography.scaled(13.5, .bold, style: .subheadline)
            nameLabel.textColor = AppColors.accentSoft
            nameLabel.numberOfLines = 0
            stack.addArrangedSubview(nameLabel)

            for component in RateComponent.allCases {
                stack.addArrangedSubview(rateRow(component: component,
                                                 model: model,
                                                 offPeakActive: offPeakActive,
                                                 discountEnabled: discountEnabled))
            }
        }
    }

    private func headerRow(offPeakActive: Bool, discountEnabled: Bool) -> UIView {
        let blank = UILabel()
        blank.text = "USD / 1M tokens"
        blank.font = Typography.scaled(10, .semibold, style: .caption2)
        blank.textColor = AppColors.textDim

        let peak = columnLabel("PEAK", active: discountEnabled && !offPeakActive, color: AppColors.peak)
        let offPeak = columnLabel("OFF-PEAK", active: discountEnabled && offPeakActive, color: AppColors.offPeak)
        offPeak.alpha = discountEnabled ? 1.0 : 0.4

        return assemble([blank, peak, offPeak])
    }

    private func rateRow(component: RateComponent, model: ModelRate, offPeakActive: Bool, discountEnabled: Bool) -> UIView {
        let title = UILabel()
        title.text = component.title
        title.font = Typography.scaled(12, .medium, style: .footnote)
        title.textColor = AppColors.textDim
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let peakValue = MoneyFormat.rate(component.value(in: model.standard))
        let offPeakValue = MoneyFormat.rate(component.value(in: model.offPeak))

        let peak = columnLabel(peakValue, active: discountEnabled && !offPeakActive, color: AppColors.text)
        let offPeak = columnLabel(discountEnabled ? offPeakValue : "—", active: discountEnabled && offPeakActive, color: AppColors.text)

        return assemble([title, peak, offPeak])
    }

    private func columnLabel(_ text: String, active: Bool, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.digits(active ? 13 : 12.5, active ? .bold : .medium)
        label.textColor = active ? color : AppColors.textDim
        label.textAlignment = .right
        label.widthAnchor.constraint(equalToConstant: valueWidth).isActive = true
        return label
    }

    private func assemble(_ views: [UIView]) -> UIView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }
}
