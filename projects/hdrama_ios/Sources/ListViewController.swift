import UIKit

/// Favorites and recent history, one poster card per series with resume information.
final class ListViewController: UIViewController {

    enum Mode {
        case favorites
        case history
    }

    private let mode: Mode
    var onOpen: ((SavedDrama) -> Void)?

    private let summary = Theme.label("", size: 12, color: AppColors.muted)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let backButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private var attempt = Set<String>()

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        buildHeader()
        buildList()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
    }

    private func buildHeader() {
        backButton.setImage(UIImage(systemName: "chevron.left",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
                            for: .normal)
        backButton.tintColor = AppColors.text
        backButton.backgroundColor = AppColors.raised
        backButton.layer.cornerRadius = 14
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        backButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = Theme.label(mode == .favorites ? "My List" : "History", size: 24, weight: .bold)
        let titleRow = UIStackView(arrangedSubviews: [backButton, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 14
        titleRow.alignment = .center

        let hint = Theme.label(mode == .favorites ? "Hold a drama to remove it from My List" : "Tap to continue watching · Hold to delete",
                               size: 12, color: AppColors.muted, lines: 2)

        var rows: [UIView] = [titleRow, summary, hint]
        if mode == .history {
            clearButton.setTitle("Clear history", for: .normal)
            clearButton.setTitleColor(AppColors.text, for: .normal)
            clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            clearButton.backgroundColor = AppColors.raised
            clearButton.layer.cornerRadius = 12
            clearButton.layer.cornerCurve = .continuous
            clearButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            clearButton.addTarget(self, action: #selector(tapClear), for: .touchUpInside)
            rows.append(clearButton)
        }

        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        header.addSubview(column)
        column.pinToEdges(of: header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        headerView = header
    }

    private var headerView: UIView!

    private func buildList() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }

    @objc private func goBack() { dismiss(animated: true) }

    @objc private func tapClear() {
        let alert = UIAlertController(title: "Clear history?",
                                      message: "All recently watched series.\nFavorites, downloads and episode resume positions are kept.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            Library.shared.clearHistory()
            self?.render()
        })
        present(alert, animated: true)
    }

    private func render() {
        let items = mode == .favorites ? Library.shared.favorites() : Library.shared.history()
        summary.text = mode == .favorites
            ? (items.count == 1 ? "1 saved series" : "\(items.count) saved series")
            : (items.count == 1 ? "1 recently watched series" : "\(items.count) recently watched series")
        clearButton.isEnabled = !items.isEmpty
        clearButton.alpha = items.isEmpty ? 0.4 : 1
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if items.isEmpty {
            let empty = mode == .favorites
                ? Theme.emptyState(symbol: "heart", title: "Your list is empty",
                                   message: "Tap the heart on a series, or hold the heart in the player, to keep it here.")
                : Theme.emptyState(symbol: "clock", title: "Your next story starts here",
                                   message: "Recently watched series will appear here with your saved episode and time.")
            stack.addArrangedSubview(empty)
            return
        }

        for item in items {
            let subtitle = mode == .favorites ? "Saved series" : "Recently watched"
            var detail = "EP. \(item.episode) · " + Theme.time(item.position)
            if item.duration > 0 { detail += " / " + Theme.time(item.duration) }
            let card = card(item: item, subtitle: subtitle, detail: detail)
            stack.addArrangedSubview(card)
            if !Artwork.shared.hasPoster(item.url), attempt.insert(item.url).inserted {
                Artwork.shared.fetch(Series(title: item.title, url: item.url, episodes: [])) { [weak self] in
                    self?.render()
                }
            }
        }
    }

    private func card(item: SavedDrama, subtitle: String, detail: String) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.stroke.cgColor
        card.isUserInteractionEnabled = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = (mode == .favorites ? "Saved: " : "Continue watching: ") + item.title

        let poster = UIImageView()
        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 12
        poster.backgroundColor = AppColors.raised
        if let image = Artwork.shared.image(item.url) {
            poster.image = image
        } else {
            poster.image = UIImage(systemName: "film")
            poster.tintColor = AppColors.accent
            poster.contentMode = .scaleAspectFit
        }

        let title = Theme.label(item.title, size: 17, weight: .bold, lines: 3)
        let sub = Theme.label(subtitle, size: 12, color: AppColors.muted)
        let info = Theme.label(detail, size: 13, color: AppColors.accent, lines: 2)
        let column = UIStackView(arrangedSubviews: [title, sub, info])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(poster)
        card.addSubview(column)
        NSLayoutConstraint.activate([
            poster.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            poster.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            poster.widthAnchor.constraint(equalToConstant: 72),
            poster.heightAnchor.constraint(equalToConstant: 104),
            column.leadingAnchor.constraint(equalTo: poster.trailingAnchor, constant: 14),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapCard(_:)))
        card.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdCard(_:)))
        card.addGestureRecognizer(hold)
        card.accessibilityValue = item.url
        return card
    }

    @objc private func tapCard(_ gesture: UITapGestureRecognizer) {
        guard let url = gesture.view?.accessibilityValue,
              let item = Library.shared.get(url) else { return }
        onOpen?(item)
    }

    @objc private func holdCard(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let url = gesture.view?.accessibilityValue,
              let item = Library.shared.get(url) else { return }
        if mode == .favorites {
            let alert = UIAlertController(title: "Remove from My List?",
                                          message: item.title + "\nWatch progress stays available.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                Library.shared.removeFavorite(url)
                self?.render()
            })
            present(alert, animated: true)
        } else {
            let alert = UIAlertController(title: "Delete recent history?",
                                          message: item.title + "\nFavorites, downloads and episode resume positions are kept.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                Library.shared.removeHistory(url)
                self?.render()
            })
            present(alert, animated: true)
        }
    }
}
