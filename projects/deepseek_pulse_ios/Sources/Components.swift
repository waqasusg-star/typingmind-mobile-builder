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
        label.font = Typography.scaled(11, UIFont.Weight.bold, style: .caption1)
        label.textColor = UIColor.white
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppColors.surfaceElevated
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        textColor = AppColors.text
        tintColor = AppColors.accentSoft
        font = Typography.scaled(14, UIFont.Weight.medium, style: .subheadline)
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        clearButtonMode = .whileEditing
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
    var availabilityColor: UIColor = AppColors.textDim
    var granted = "—"
    var toppedUp = "—"
    var stateText = "STANDARD"
    var stateColor: UIColor = AppColors.textDim
    var detailLine = ""
    var noteLine = ""
    var clockLine = ""
    var updatedLine = ""
}

final class WidgetCardView: UIView {

    private let gradient = CAGradientLayer()
    private let brandLabel = UILabel()
    private let pill = PillView(frame: .zero)
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
        brandLabel.font = Typography.scaled(11, UIFont.Weight.bold, style: .caption1)
        brandLabel.textColor = UIColor.white.withAlphaComponent(0.85)

        totalLabel.font = Typography.digits(38, UIFont.Weight.bold)
        totalLabel.textColor = UIColor.white
        totalLabel.adjustsFontSizeToFitWidth = true
        totalLabel.minimumScaleFactor = 0.55
        totalLabel.numberOfLines = 1

        availabilityLabel.font = Typography.scaled(12, UIFont.Weight.semibold, style: .footnote)
        availabilityLabel.numberOfLines = 0

        detailLabel.font = Typography.scaled(13, UIFont.Weight.semibold, style: .subheadline)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.94)
        detailLabel.numberOfLines = 0

        noteLabel.font = Typography.scaled(11, UIFont.Weight.medium, style: .caption1)
        noteLabel.textColor = UIColor(hex: 0xFFC46B)
        noteLabel.numberOfLines = 0

        clockLabel.font = Typography.scaled(11, UIFont.Weight.medium, style: .caption1)
        clockLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        clockLabel.numberOfLines = 0

        updatedLabel.font = Typography.scaled(11, UIFont.Weight.medium, style: .caption1)
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

        let separator = UIView(frame: .zero)
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
        titleLabel.font = Typography.scaled(10, UIFont.Weight.bold, style: .caption2)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.62)

        valueLabel.font = Typography.digits(15, UIFont.Weight.semibold)
        valueLabel.textColor = UIColor.white
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
        backgroundColor = UIColor.clear
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
            let dayLength = CGFloat(PricingSchedule.minutesPerDay)
            for segment in segments {
                let x = barRect.minX + barRect.width * CGFloat(segment.startMinute) / dayLength
                let width = barRect.width * CGFloat(segment.endMinute - segment.startMinute) / dayLength
                var alpha: CGFloat = 0.45
                if segment.state == .peak { alpha = 0.75 }
                if segment.state == .offPeak { alpha = 0.9 }
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
        let marks: [String] = ["00", "06", "12", "18", "24"]
        let fractions: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let labelTop = rect.height - 14
        for index in 0..<marks.count {
            let text = marks[index] as NSString
            let size = text.size(withAttributes: attributes)
            var x = rect.width * fractions[index] - size.width / 2
            x = min(max(x, 0), max(0, rect.width - size.width))
            text.draw(at: CGPoint(x: x, y: labelTop), withAttributes: attributes)
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
                let divider = UIView(frame: .zero)
                divider.backgroundColor = AppColors.surfaceElevated
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(divider)
            }
            let nameLabel = UILabel()
            nameLabel.text = model.displayName
            nameLabel.font = Typography.scaled(13.5, UIFont.Weight.bold, style: .subheadline)
            nameLabel.textColor = AppColors.accentSoft
            nameLabel.numberOfLines = 0
            stack.addArrangedSubview(nameLabel)

            stack.addArrangedSubview(rateRow(component: .cacheHit, model: model, offPeakActive: offPeakActive, discountEnabled: discountEnabled))
            stack.addArrangedSubview(rateRow(component: .cacheMiss, model: model, offPeakActive: offPeakActive, discountEnabled: discountEnabled))
            stack.addArrangedSubview(rateRow(component: .output, model: model, offPeakActive: offPeakActive, discountEnabled: discountEnabled))
        }
    }

    private func headerRow(offPeakActive: Bool, discountEnabled: Bool) -> UIView {
        let blank = UILabel()
        blank.text = "USD / 1M tokens"
        blank.font = Typography.scaled(10, UIFont.Weight.semibold, style: .caption2)
        blank.textColor = AppColors.textDim

        let peakActive = discountEnabled && !offPeakActive
        let offPeakActiveColumn = discountEnabled && offPeakActive
        let peak = columnLabel("PEAK", active: peakActive, color: AppColors.peak)
        let offPeak = columnLabel("OFF-PEAK", active: offPeakActiveColumn, color: AppColors.offPeak)
        if !discountEnabled { offPeak.alpha = 0.4 }

        return assemble([blank, peak, offPeak])
    }

    private func rateRow(component: RateComponent, model: ModelRate, offPeakActive: Bool, discountEnabled: Bool) -> UIView {
        let title = UILabel()
        title.text = component.title
        title.font = Typography.scaled(12, UIFont.Weight.medium, style: .footnote)
        title.textColor = AppColors.textDim
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let peakActive = discountEnabled && !offPeakActive
        let offPeakActiveColumn = discountEnabled && offPeakActive
        let peak = columnLabel(MoneyFormat.rate(component.value(in: model.standard)), active: peakActive, color: AppColors.text)
        let discounted = discountEnabled ? MoneyFormat.rate(component.value(in: model.offPeak)) : "—"
        let offPeak = columnLabel(discounted, active: offPeakActiveColumn, color: AppColors.text)

        return assemble([title, peak, offPeak])
    }

    private func columnLabel(_ text: String, active: Bool, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        let size: CGFloat = active ? 13.0 : 12.5
        let weight: UIFont.Weight = active ? UIFont.Weight.bold : UIFont.Weight.medium
        label.font = Typography.digits(size, weight)
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
