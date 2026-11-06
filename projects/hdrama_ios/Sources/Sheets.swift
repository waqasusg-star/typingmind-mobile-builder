import UIKit

/// Bottom sheet container that keeps the video visible above it, like the Android sheets.
class BottomSheetViewController: UIViewController {

    let sheet = UIView()
    let content = UIStackView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var sheetHeight: NSLayoutConstraint!

    var sheetTitle: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.18)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        view.addGestureRecognizer(tap)

        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.backgroundColor = AppColors.background
        sheet.layer.cornerRadius = 24
        sheet.layer.cornerCurve = .continuous
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.addSubview(sheet)

        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = AppColors.stroke
        grabber.layer.cornerRadius = 2
        sheet.addSubview(grabber)

        titleLabel.text = sheetTitle
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = AppColors.text
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        closeButton.tintColor = AppColors.text
        closeButton.backgroundColor = AppColors.raised
        closeButton.layer.cornerRadius = 12
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let header = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(header)

        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(content)

        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            grabber.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 10),
            grabber.centerXAnchor.constraint(equalTo: sheet.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 40),
            grabber.heightAnchor.constraint(equalToConstant: 4),
            header.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -18),
            content.bottomAnchor.constraint(equalTo: sheet.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        sheetHeight = sheet.heightAnchor.constraint(equalToConstant: 320)
        sheetHeight.priority = .defaultHigh
        sheetHeight.isActive = true
        sheet.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 40).isActive = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let limit = view.bounds.height * (view.bounds.width > view.bounds.height ? 0.94 : 0.78)
        let needed = content.systemLayoutSizeFitting(CGSize(width: content.bounds.width, height: 0),
                                                     withHorizontalFittingPriority: .required,
                                                     verticalFittingPriority: .fittingSizeLevel).height
        sheetHeight.constant = min(limit, needed + 110)
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }
}

/// Episode grid: 30 per range, five numbered columns, downloaded badges and a download mode.
final class EpisodeSheetViewController: BottomSheetViewController {

    private let series: Series
    private let current: Int
    private let downloadMode: Bool
    private let onEpisode: (Int) -> Void
    private let onDownload: ([Int]) -> Void

    var qualityOptions: [Int] = []
    var onQuality: ((Int) -> Void)?

    private let tabs = UIStackView()
    private let grid = UIStackView()
    private var activeRange = 0
    private var picked: Set<Int> = []
    private var downloadButton: UIButton?
    private var selectionLabel: UILabel?
    private var qualityControl: UISegmentedControl?

    init(series: Series, current: Int, downloadMode: Bool,
         onEpisode: @escaping (Int) -> Void, onDownload: @escaping ([Int]) -> Void) {
        self.series = series
        self.current = current
        self.downloadMode = downloadMode
        self.onEpisode = onEpisode
        self.onDownload = onDownload
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        self.sheetTitle = downloadMode ? "Download episodes" : "Episodes"
        if downloadMode { picked.insert(current) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        activeRange = current / 30

        let name = Theme.label(series.title, size: 18, weight: .semibold, lines: 2)
        let summary = Theme.label("\(series.episodes.count) episodes · " + (downloadMode ? "Choose episodes to save" : "Tap an episode to play"),
                                  size: 12, color: AppColors.muted, lines: 2)
        selectionLabel = summary

        content.addArrangedSubview(name)
        content.addArrangedSubview(summary)

        if downloadMode, qualityOptions.count > 1 {
            let control = UISegmentedControl(items: qualityOptions.map { $0 == 0 ? "Best" : "\($0)P" })
            control.selectedSegmentIndex = 0
            control.addTarget(self, action: #selector(qualityChanged(_:)), for: .valueChanged)
            qualityControl = control
            content.addArrangedSubview(control)
        }

        tabs.axis = .horizontal
        tabs.spacing = 8
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.addSubview(tabs)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            tabs.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor)
        ])

        let ranges = stride(from: 0, to: series.episodes.count, by: 30).map { $0 }
        for (position, start) in ranges.enumerated() {
            let last = min(start + 29, series.episodes.count - 1)
            let first = series.episodes[start].number
            let final = series.episodes[last].number
            let button = UIButton(type: .system)
            button.setTitle("\(first)–\(final)", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
            button.tag = position
            button.addTarget(self, action: #selector(tapRange(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            tabs.addArrangedSubview(button)
        }

        content.addArrangedSubview(scroller)

        grid.axis = .vertical
        grid.spacing = 6
        let gridScroller = UIScrollView()
        gridScroller.showsVerticalScrollIndicator = false
        gridScroller.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: gridScroller.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: gridScroller.contentLayoutGuide.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: gridScroller.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: gridScroller.contentLayoutGuide.trailingAnchor),
            grid.widthAnchor.constraint(equalTo: gridScroller.frameLayoutGuide.widthAnchor)
        ])
        gridScroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        content.addArrangedSubview(gridScroller)

        if downloadMode {
            let selectAll = UIButton(type: .system)
            selectAll.setTitle("Select all", for: .normal)
            selectAll.setTitleColor(AppColors.text, for: .normal)
            selectAll.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            selectAll.backgroundColor = AppColors.raised
            selectAll.layer.cornerRadius = 12
            selectAll.heightAnchor.constraint(equalToConstant: 44).isActive = true
            selectAll.addTarget(self, action: #selector(tapSelectAll), for: .touchUpInside)

            let clear = UIButton(type: .system)
            clear.setTitle("Clear", for: .normal)
            clear.setTitleColor(AppColors.text, for: .normal)
            clear.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            clear.backgroundColor = AppColors.raised
            clear.layer.cornerRadius = 12
            clear.heightAnchor.constraint(equalToConstant: 44).isActive = true
            clear.addTarget(self, action: #selector(tapClear), for: .touchUpInside)

            let row = UIStackView(arrangedSubviews: [selectAll, clear])
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 8
            content.addArrangedSubview(row)

            let download = UIButton(type: .system)
            download.setTitle("Download selected", for: .normal)
            download.setTitleColor(AppColors.background, for: .normal)
            download.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            download.backgroundColor = AppColors.accent
            download.layer.cornerRadius = 12
            download.heightAnchor.constraint(equalToConstant: 48).isActive = true
            download.addTarget(self, action: #selector(tapDownload), for: .touchUpInside)
            content.addArrangedSubview(download)
            downloadButton = download
        }

        populate(activeRange)
    }

    @objc private func qualityChanged(_ control: UISegmentedControl) {
        let value = qualityOptions[control.selectedSegmentIndex]
        onQuality?(value)
    }

    @objc private func tapRange(_ sender: UIButton) {
        populate(sender.tag)
    }

    @objc private func tapSelectAll() {
        picked = Set(series.episodes.indices)
        populate(activeRange)
    }

    @objc private func tapClear() {
        picked.removeAll()
        populate(activeRange)
    }

    @objc private func tapDownload() {
        guard !picked.isEmpty else { return }
        let selected = picked.sorted()
        dismiss(animated: true) { [onDownload] in onDownload(selected) }
    }

    private func populate(_ range: Int) {
        activeRange = range
        guard series.episodes.indices.contains(range * 30) else { return }
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let entries = series.episodes.indices.filter { $0 / 30 == range }
        var row: UIStackView?
        for (cell, index) in entries.enumerated() {
            if cell % 5 == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.distribution = .fillEqually
                newRow.spacing = 6
                grid.addArrangedSubview(newRow)
                row = newRow
            }
            row?.addArrangedSubview(makeCell(index))
        }
        // Keep five equal columns in the last range.
        let remainder = entries.count % 5
        if remainder != 0, let last = row {
            for _ in remainder..<5 { last.addArrangedSubview(UIView()) }
        }
        for (position, view) in (tabs.arrangedSubviews.enumerated()) {
            guard let button = view as? UIButton else { continue }
            let selected = position == range
            button.backgroundColor = selected ? AppColors.raised : AppColors.card
            button.setTitleColor(selected ? AppColors.accent : AppColors.muted, for: .normal)
        }
        if let label = selectionLabel, downloadMode {
            label.text = "\(picked.count) selected · \(series.episodes.count) episodes"
        }
        downloadButton?.isEnabled = !picked.isEmpty
        downloadButton?.alpha = picked.isEmpty ? 0.4 : 1
    }

    private func makeCell(_ index: Int) -> UIView {
        let episode = series.episodes[index]
        let downloaded = DownloadStore.shared.isReady(episode.pageUrl)
        let selected = downloadMode ? picked.contains(index) : index == current
        let button = UIButton(type: .system)
        var title = "\(episode.number)"
        if downloaded { title += "\n✓" }
        button.setTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        button.setTitleColor(selected ? AppColors.accent : AppColors.text, for: .normal)
        button.backgroundColor = selected ? AppColors.selected : AppColors.surface
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        button.tag = index
        button.accessibilityLabel = "Episode \(episode.number)"
            + (downloaded ? ", downloaded" : "") + (selected ? ", selected" : "")
        button.addTarget(self, action: #selector(tapCell(_:)), for: .touchUpInside)
        return button
    }

    @objc private func tapCell(_ sender: UIButton) {
        let index = sender.tag
        if downloadMode {
            if picked.contains(index) { picked.remove(index) } else { picked.insert(index) }
            populate(activeRange)
        } else {
            dismiss(animated: true) { [onEpisode] in onEpisode(index) }
        }
    }
}

/// Simple bottom sheet list used for quality and speed.
final class ChoiceSheetViewController: BottomSheetViewController {

    private let options: [(String, Bool)]
    var onSelect: ((Int) -> Void)?
    var footnote: String?

    init(title: String, options: [(String, Bool)]) {
        self.options = options
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        sheetTitle = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        for (index, option) in options.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(option.0 + (option.1 ? "    ✓" : ""), for: .normal)
            button.setTitleColor(option.1 ? AppColors.accent : AppColors.text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: option.1 ? .semibold : .regular)
            button.contentHorizontalAlignment = .leading
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
            button.backgroundColor = option.1 ? AppColors.raised : AppColors.surface
            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
            button.tag = index
            button.accessibilityLabel = option.0 + (option.1 ? ", selected" : "")
            button.addTarget(self, action: #selector(tapOption(_:)), for: .touchUpInside)
            content.addArrangedSubview(button)
        }
        if let footnote = footnote {
            let note = Theme.label(footnote, size: 12, color: AppColors.muted, lines: 0)
            content.addArrangedSubview(note)
        }
    }

    @objc private func tapOption(_ sender: UIButton) {
        let index = sender.tag
        dismiss(animated: true) { [onSelect] in onSelect?(index) }
    }
}
