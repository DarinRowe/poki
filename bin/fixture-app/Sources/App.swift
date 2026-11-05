import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: FixtureController())
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class FixtureController: UIViewController, UIScrollViewDelegate {
    private let counter = UILabel()
    private let field = UITextField()
    private var count = 0
    private let zoomContent = UILabel()
    private let canvas = CanvasTarget()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Poki MCP Test"
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 16
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        counter.text = "Count: 0"; counter.textAlignment = .center; counter.accessibilityIdentifier = "counter"
        stack.addArrangedSubview(counter)
        field.placeholder = "Test text"; field.borderStyle = .roundedRect; field.accessibilityIdentifier = "test-field"
        field.autocorrectionType = .no; field.autocapitalizationType = .none
        field.addTarget(self, action: #selector(save), for: .editingChanged)
        stack.addArrangedSubview(field)
        stack.addArrangedSubview(button("Increment", action: #selector(increment)))
        canvas.heightAnchor.constraint(equalToConstant: 44).isActive = true
        canvas.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(canvasTapped)))
        stack.addArrangedSubview(canvas)
        let hold = button("Hold or double tap", action: nil)
        hold.accessibilityIdentifier = "gesture-target"
        hold.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(held(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubled))
        doubleTap.numberOfTapsRequired = 2; hold.addGestureRecognizer(doubleTap)
        stack.addArrangedSubview(hold)
        stack.addArrangedSubview(button("Show Alert", action: #selector(alert)))
        stack.addArrangedSubview(button("Open Detail", action: #selector(detail)))
        stack.addArrangedSubview(button("Open Field List", action: #selector(fieldList)))
        let slider = UISlider(); slider.accessibilityIdentifier = "test-slider"; slider.accessibilityLabel = "Test slider"
        slider.addTarget(self, action: #selector(slid(_:)), for: .valueChanged)
        stack.addArrangedSubview(slider)
        let zoom = UIScrollView(); zoom.delegate = self; zoom.minimumZoomScale = 0.5; zoom.maximumZoomScale = 4
        zoom.heightAnchor.constraint(equalToConstant: 160).isActive = true
        zoom.accessibilityIdentifier = "zoom-area"; zoom.layer.borderWidth = 1; zoom.layer.borderColor = UIColor.systemBlue.cgColor
        zoomContent.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        zoomContent.text = "Pinch to zoom"; zoomContent.textAlignment = .center; zoomContent.backgroundColor = .systemTeal
        zoom.addSubview(zoomContent); zoom.contentSize = zoomContent.bounds.size; stack.addArrangedSubview(zoom)
        for i in 1...18 {
            let label = UILabel(); label.text = "Scroll row \(i)"; label.heightAnchor.constraint(equalToConstant: 46).isActive = true
            stack.addArrangedSubview(label)
        }
        stack.addArrangedSubview(button("Bottom target", action: #selector(increment)))
        stack.addArrangedSubview(button("Create test crash", action: #selector(crash)))
        save()
    }
    private func button(_ title: String, action: Selector?) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        if let action { button.addTarget(self, action: action, for: .touchUpInside) }
        return button
    }
    @objc private func increment() { count += 1; counter.text = "Count: \(count)"; save() }
    @objc private func canvasTapped() { canvas.text = "Canvas activated"; counter.text = "Canvas tapped" }
    @objc private func held(_ recognizer: UILongPressGestureRecognizer) { if recognizer.state == .began { counter.text = "Long press received" } }
    @objc private func doubled() { counter.text = "Double tap received" }
    @objc private func slid(_ slider: UISlider) { counter.text = String(format: "Slider: %.2f", slider.value) }
    @objc private func alert() {
        let alert = UIAlertController(title: "Test Alert", message: "This alert belongs to the disposable test app.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in self.counter.text = "Alert accepted" })
        present(alert, animated: true)
    }
    @objc private func detail() {
        let detail = UIViewController(); detail.title = "Detail"; detail.view.backgroundColor = .systemBackground
        navigationController?.pushViewController(detail, animated: true)
    }
    @objc private func fieldList() { navigationController?.pushViewController(FieldListController(), animated: true) }
    @objc private func crash() { fatalError("Poki MCP intentional fixture crash") }
    @objc private func save() {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fixture-state.json")
        let data = try? JSONSerialization.data(withJSONObject: ["count": count, "text": field.text ?? ""])
        try? data?.write(to: file, options: .atomic)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomContent }
}

// A list of fictional rows for proving where text lands: a new row that opens with the keyboard up, rows
// that keep sliding, and a row that hands its edit to a neighbor. The label on top names every row that changed.
final class FieldListController: UITableViewController, UITextFieldDelegate {
    private struct Row { let name: String; var text: String; let original: String }
    private var rows = (1...14).map { Row(name: "Row \($0)", text: "Fictional \($0)", original: "Fictional \($0)") }
    private let changed = UILabel()
    private var slider: Timer?
    private let redirectRow = 2, redirectTarget = 3
    private let identifier = "field"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Field List"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: identifier)
        tableView.rowHeight = 44
        changed.text = "Changed: none"; changed.frame = CGRect(x: 0, y: 0, width: 300, height: 32); changed.textAlignment = .center
        tableView.tableHeaderView = changed
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Add Row", style: .plain, target: self, action: #selector(addRow)),
            UIBarButtonItem(title: "Slide Rows", style: .plain, target: self, action: #selector(slide)),
        ]
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        let field = cell.contentView.subviews.compactMap { $0 as? UITextField }.first ?? {
            let field = UITextField(frame: cell.contentView.bounds.insetBy(dx: 20, dy: 4))
            field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            field.autocorrectionType = .no; field.autocapitalizationType = .none; field.delegate = self
            field.addTarget(self, action: #selector(edited(_:)), for: .editingChanged)
            cell.contentView.addSubview(field)
            return field
        }()
        let row = rows[indexPath.row]
        field.tag = indexPath.row; field.text = row.text
        field.accessibilityLabel = row.name
        field.placeholder = row.text.isEmpty ? row.name : nil
        return cell
    }
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        guard textField.tag == redirectRow else { return true }
        DispatchQueue.main.async { self.field(at: self.redirectTarget)?.becomeFirstResponder() }
        return false
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
    private func field(at row: Int) -> UITextField? {
        tableView.cellForRow(at: IndexPath(row: row, section: 0))?.contentView.subviews.compactMap { $0 as? UITextField }.first
    }
    @objc private func edited(_ field: UITextField) {
        rows[field.tag].text = field.text ?? ""
        let names = rows.filter { $0.text != $0.original }.map(\.name)
        changed.text = "Changed: " + (names.isEmpty ? "none" : names.joined(separator: ", "))
    }
    @objc private func addRow() {
        rows.append(Row(name: "New Row", text: "", original: ""))
        let path = IndexPath(row: rows.count - 1, section: 0)
        tableView.insertRows(at: [path], with: .automatic)
        tableView.scrollToRow(at: path, at: .bottom, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.field(at: path.row)?.becomeFirstResponder() }
    }
    // Moves by most of a row each second for twelve seconds, then stops, so an old place holds a neighbor.
    @objc private func slide() {
        var ticks = 0
        slider?.invalidate()
        slider = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            ticks += 1
            let direction: CGFloat = ticks <= 6 ? 1 : -1
            self.tableView.setContentOffset(CGPoint(x: 0, y: self.tableView.contentOffset.y + direction * 40), animated: true)
            if ticks == 12 { timer.invalidate() }
        }
    }
}

final class CanvasTarget: UIView {
    var text = "Canvas target" { didSet { setNeedsDisplay() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        text.draw(in: bounds.insetBy(dx: 4, dy: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.systemBlue, .paragraphStyle: style])
    }
}
