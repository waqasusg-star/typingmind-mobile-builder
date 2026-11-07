import UIKit

/// Lock Screen preview: draws the chosen accessory design with the same strings the real widget
/// uses.
///
/// 1.0.9 redraws this from scratch. The previous version imitated a two-column card that no longer
/// exists; the accessory widget now has three rectangular designs (Ribbon, Ring, Compact), and this
/// view switches between them so the preview cannot disagree with the Lock Screen. All wording comes
/// from LockScreenText, and nothing here can say anything about the API key.
final class WidgetLockScreenCardView: UIView {

    private let bandView = LockScreenBandView()
    private let ringView = LockScreenRingView()
    private let stateLabel = UILabel()
    private let captionLabel = UILabel()
    private let countdownLabel = UILabel()
    private let detailLabel = UILabel()
    private let flagLabel = UILabel()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    private var style: LockScreenStyle = .ribbon

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        backgroundColor = .clear
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        material.translatesAutoresizingMaskIntoConstraints = false
        material.isUserInteractionEnabled = false
        addSubview(material)

        stateLabel.font = Typography.digits(11, .heavy)
        stateLabel.textColor = .white
        stateLabel.numberOfLines = 1

        captionLabel.font = Typography.scaled(8.5, .bold, style: .caption2)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        captionLabel.numberOfLines = 1

        countdownLabel.font = Typography.digits(21, .bold)
        countdownLabel.textColor = .white
        countdownLabel.numberOfLines = 1
        countdownLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.minimumScaleFactor = 0.5

        detailLabel.font = Typography.digits(9.5, .semibold)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        detailLabel.numberOfLines = 1

        flagLabel.font = Typography.scaled(8, .heavy, style: .caption2)
        flagLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        flagLabel.numberOfLines = 1

        let topRow = UIStackView(arrangedSubviews: [stateLabel, UIView(), captionLabel])
        topRow.axis = .horizontal
        topRow.spacing = 6
        topRow.alignment = .firstBaseline

        let bottomRow = UIStackView(arrangedSubviews: [countdownLabel, UIView(), flagLabel])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 6
        bottomRow.alignment = .firstBaseline

        let textStack = UIStackView(arrangedSubviews: [topRow, bottomRow, detailLabel, bandView])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.setCustomSpacing(5, after: detailLabel)

        let row = UIStackView(arrangedSubviews: [ringView, textStack])
        row.axis = .horizontal
        row.spacing = 9
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        ringView.translatesAutoresizingMaskIntoConstraints = false
        bandView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: topAnchor),
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            ringView.widthAnchor.constraint(equalToConstant: 34),
            ringView.heightAnchor.constraint(equalToConstant: 34),
            bandView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    /// Renders one accessory design from the same snapshot the widget uses.
    func apply(style: LockScreenStyle,
               snapshot: WidgetPlanner.Snapshot,
               schedule: PricingSchedule,
               now: Date) {
        self.style = style
        let discounts = schedule.discountsEnabled
        stateLabel.text = LockScreenText.stateWord(snapshot: snapshot, discountsEnabled: discounts)
        captionLabel.text = LockScreenText.countdownLabel(snapshot: snapshot, discountsEnabled: discounts)
        countdownLabel.text = LockScreenText.staticCountdown(snapshot: snapshot,
                                                             discountsEnabled: discounts,
                                                             now: now)
        flagLabel.text = LockScreenText.dataFlag(state: .fresh)
        bandView.update(schedule: schedule, date: now, accent: AppColors.peak)

        ringView.isHidden = style != .ring
        bandView.isHidden = style == .compact

        switch style {
        case .ring:
            ringView.update(progress: LockScreenText.peakProgress(minutesLeft: snapshot.peakMinutesLeftToday,
                                                                  totalMinutes: snapshot.totalPeakMinutesToday))
            detailLabel.text = LockScreenText.switchTime(snapshot: snapshot)
        case .compact:
            detailLabel.text = LockScreenText.switchTime(snapshot: snapshot)
        default:
            detailLabel.text = LockScreenText.peakLeft(minutes: snapshot.peakMinutesLeftToday)
        }

        flagLabel.isHidden = legendHidden(style: style)
    }

    private func legendHidden(style: LockScreenStyle) -> Bool {
        // The preview is always fresh data, so the only badge would be empty; the space is kept for
        // the switch time instead.
        true
    }
}

/// The monochrome 24-hour band used inside the accessory preview.
final class LockScreenBandView: UIView {

    private var segments: [ScheduleSegment] = []
    private var accent: UIColor = .white

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(schedule: PricingSchedule, date: Date, accent: UIColor) {
        self.segments = schedule.segments(for: date)
        self.accent = accent
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !segments.isEmpty, rect.width > 1 else { return }
        let radius = rect.height / 2
        UIColor.white.withAlphaComponent(0.16).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()

        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        for segment in segments {
            let start = CGFloat(segment.startMinute) / CGFloat(PricingSchedule.minutesPerDay)
            let end = CGFloat(segment.endMinute) / CGFloat(PricingSchedule.minutesPerDay)
            let slice = CGRect(x: rect.minX + rect.width * start,
                               y: rect.minY,
                               width: max(0.5, rect.width * (end - start)),
                               height: rect.height)
            switch segment.state {
            case .peak:
                UIColor.white.withAlphaComponent(0.9).setFill()
            case .offPeak:
                accent.withAlphaComponent(0.75).setFill()
            case .standard:
                UIColor.white.withAlphaComponent(0.3).setFill()
            }
            UIBezierPath(rect: slice).fill()
        }
        context?.restoreGState()
    }
}

/// The progress ring used by the Ring accessory design.
final class LockScreenRingView: UIView {

    private var progress: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(progress: Double) {
        self.progress = min(1, max(0, progress))
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let lineWidth: CGFloat = 4
        let inset = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let track = UIBezierPath(ovalIn: inset)
        track.lineWidth = lineWidth
        UIColor.white.withAlphaComponent(0.22).setStroke()
        track.stroke()

        guard progress > 0 else { return }
        let arc = UIBezierPath(arcCenter: CGPoint(x: rect.midX, y: rect.midY),
                               radius: inset.width / 2,
                               startAngle: -.pi / 2,
                               endAngle: -.pi / 2 + CGFloat(progress) * 2 * .pi,
                               clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        AppColors.offPeak.setStroke()
        arc.stroke()
    }
}
