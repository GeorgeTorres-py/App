

```swift
import UIKit
import AVFoundation
import CoreData

// MARK: - Main App Structure

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
    
    // Core Data stack
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "RecycleTracker")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        return container
    }()
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
}

// MARK: - Models

struct User {
    var id: String
    var username: String
    var totalRecycled: Int
    var totalValue: Double
    var environmentalImpact: Double
}

struct RecycledItem {
    var id: String
    var type: String
    var barcode: String
    var value: Double
    var date: Date
    var userId: String
}

// MARK: - View Controllers

class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scanVC = ScanViewController()
        scanVC.tabBarItem = UITabBarItem(title: "Scan", image: UIImage(systemName: "camera"), tag: 0)
        
        let statsVC = StatsViewController()
        statsVC.tabBarItem = UITabBarItem(title: "Stats", image: UIImage(systemName: "chart.bar"), tag: 1)
        
        let leaderboardVC = LeaderboardViewController()
        leaderboardVC.tabBarItem = UITabBarItem(title: "Leaderboard", image: UIImage(systemName: "list.number"), tag: 2)
        
        let profileVC = ProfileViewController()
        profileVC.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person"), tag: 3)
        
        viewControllers = [scanVC, statsVC, leaderboardVC, profileVC].map { UINavigationController(rootViewController: $0) }
    }
}

// MARK: - Scan View Controller (Main Feature)

class ScanViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var barcodeValueLabel: UILabel!
    private var itemTypeLabel: UILabel!
    private var valueLabel: UILabel!
    private var recycleButton: UIButton!
    
    private var currentBarcode: String?
    private var currentItemType: String?
    private var currentValue: Double?
    
    private let recycleDatabase = RecycleDatabase()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan Recyclables"
        view.backgroundColor = .white
        setupUI()
        setupCamera()
    }
    
    private func setupUI() {
        // Camera preview container
        let previewContainer = UIView()
        previewContainer.backgroundColor = .black
        previewContainer.layer.cornerRadius = 12
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)
        
        // Info panel
        let infoPanel = UIView()
        infoPanel.backgroundColor = .systemGray6
        infoPanel.layer.cornerRadius = 12
        infoPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoPanel)
        
        // Labels
        barcodeValueLabel = UILabel()
        barcodeValueLabel.text = "Scan a barcode"
        barcodeValueLabel.textAlignment = .center
        barcodeValueLabel.translatesAutoresizingMaskIntoConstraints = false
        infoPanel.addSubview(barcodeValueLabel)
        
        itemTypeLabel = UILabel()
        itemTypeLabel.text = "Item type: Unknown"
        itemTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        infoPanel.addSubview(itemTypeLabel)
        
        valueLabel = UILabel()
        valueLabel.text = "Value: $0.00"
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        infoPanel.addSubview(valueLabel)
        
        // Recycle button
        recycleButton = UIButton(type: .system)
        recycleButton.setTitle("Record Recycling", for: .normal)
        recycleButton.backgroundColor = .systemGreen
        recycleButton.setTitleColor(.white, for: .normal)
        recycleButton.layer.cornerRadius = 8
        recycleButton.translatesAutoresizingMaskIntoConstraints = false
        recycleButton.addTarget(self, action: #selector(recycleButtonTapped), for: .touchUpInside)
        recycleButton.isEnabled = false
        view.addSubview(recycleButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            previewContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),
            
            infoPanel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 20),
            infoPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            infoPanel.heightAnchor.constraint(equalToConstant: 150),
            
            barcodeValueLabel.topAnchor.constraint(equalTo: infoPanel.topAnchor, constant: 20),
            barcodeValueLabel.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 20),
            barcodeValueLabel.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor, constant: -20),
            
            itemTypeLabel.topAnchor.constraint(equalTo: barcodeValueLabel.bottomAnchor, constant: 20),
            itemTypeLabel.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 20),
            itemTypeLabel.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor, constant: -20),
            
            valueLabel.topAnchor.constraint(equalTo: itemTypeLabel.bottomAnchor, constant: 20),
            valueLabel.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 20),
            valueLabel.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor, constant: -20),
            
            recycleButton.topAnchor.constraint(equalTo: infoPanel.bottomAnchor, constant: 30),
            recycleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recycleButton.widthAnchor.constraint(equalToConstant: 200),
            recycleButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession?.canAddInput(videoInput) == true else {
            showAlert(title: "Camera Error", message: "Unable to access camera")
            return
        }
        
        captureSession?.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession?.canAddOutput(metadataOutput) == true {
            captureSession?.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        } else {
            showAlert(title: "Camera Error", message: "Unable to process camera input")
            captureSession = nil
            return
        }
        
        if let previewContainer = view.subviews.first {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer?.frame = previewContainer.bounds
            previewLayer?.videoGravity = .resizeAspectFill
            previewContainer.layer.addSublayer(previewLayer!)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .background).async {
                self.captureSession?.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            
            // Prevent continuous scanning
            captureSession?.stopRunning()
            
            // Process barcode
            currentBarcode = stringValue
            barcodeValueLabel.text = "Barcode: \(stringValue)"
            
            // Look up item details
            if let itemInfo = recycleDatabase.lookupItem(barcode: stringValue) {
                currentItemType = itemInfo.0
                currentValue = itemInfo.1
                
                itemTypeLabel.text = "Item type: \(itemInfo.0)"
                valueLabel.text = "Value: $\(String(format: "%.2f", itemInfo.1))"
                recycleButton.isEnabled = true
            } else {
                itemTypeLabel.text = "Item type: Unknown"
                valueLabel.text = "Value: $0.00"
                recycleButton.isEnabled = false
                
                // If unknown barcode, let's prompt to add it
                promptForItemDetails(barcode: stringValue)
            }
        }
    }
    
    @objc private func recycleButtonTapped() {
        guard let barcode = currentBarcode, let itemType = currentItemType, let value = currentValue else {
            return
        }
        
        // Create recycled item record
        let item = RecycledItem(
            id: UUID().uuidString,
            type: itemType,
            barcode: barcode,
            value: value,
            date: Date(),
            userId: UserManager.shared.currentUserId
        )
        
        // Save to database
        RecyclingManager.shared.addRecycledItem(item)
        
        // Show confirmation
        showAlert(title: "Success!", message: "Added \(itemType) to your recycling history") { [weak self] in
            // Reset the scanner
            self?.resetScanner()
        }
    }
    
    private func resetScanner() {
        currentBarcode = nil
        currentItemType = nil
        currentValue = nil
        
        barcodeValueLabel.text = "Scan a barcode"
        itemTypeLabel.text = "Item type: Unknown"
        valueLabel.text = "Value: $0.00"
        recycleButton.isEnabled = false
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession?.startRunning()
        }
    }
    
    private func promptForItemDetails(barcode: String) {
        let alert = UIAlertController(title: "New Item", message: "This item isn't in our database. Help us by providing details:", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Item type (e.g. Plastic Bottle)"
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Value in dollars (e.g. 0.05)"
            textField.keyboardType = .decimalPad
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.resetScanner()
        })
        
        alert.addAction(UIAlertAction(title: "Add Item", style: .default) { [weak self] _ in
            guard let typeField = alert.textFields?[0],
                  let valueField = alert.textFields?[1],
                  let type = typeField.text, !type.isEmpty,
                  let valueText = valueField.text, !valueText.isEmpty,
                  let value = Double(valueText) else {
                self?.resetScanner()
                return
            }
            
            // Add to database
            self?.recycleDatabase.addItem(barcode: barcode, type: type, value: value)
            
            // Update current item
            self?.currentItemType = type
            self?.currentValue = value
            self?.itemTypeLabel.text = "Item type: \(type)"
            self?.valueLabel.text = "Value: $\(String(format: "%.2f", value))"
            self?.recycleButton.isEnabled = true
        })
        
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - Stats View Controller

class StatsViewController: UIViewController {
    private var totalRecycledLabel: UILabel!
    private var totalValueLabel: UILabel!
    private var environmentalImpactLabel: UILabel!
    private var tableView: UITableView!
    
    private var recentItems: [RecycledItem] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your Stats"
        view.backgroundColor = .white
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }
    
    private func setupUI() {
        // Stats panel
        let statsPanel = UIView()
        statsPanel.backgroundColor = .systemGreen.withAlphaComponent(0.1)
        statsPanel.layer.cornerRadius = 12
        statsPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsPanel)
        
        // Stats labels
        totalRecycledLabel = UILabel()
        totalRecycledLabel.text = "Total items recycled: 0"
        totalRecycledLabel.translatesAutoresizingMaskIntoConstraints = false
        statsPanel.addSubview(totalRecycledLabel)
        
        totalValueLabel = UILabel()
        totalValueLabel.text = "Total value: $0.00"
        totalValueLabel.translatesAutoresizingMaskIntoConstraints = false
        statsPanel.addSubview(totalValueLabel)
        
        environmentalImpactLabel = UILabel()
        environmentalImpactLabel.text = "CO₂ saved: 0 lbs"
        environmentalImpactLabel.translatesAutoresizingMaskIntoConstraints = false
        statsPanel.addSubview(environmentalImpactLabel)
        
        // Recent items label
        let recentItemsLabel = UILabel()
        recentItemsLabel.text = "Recent Items"
        recentItemsLabel.font = UIFont.boldSystemFont(ofSize: 18)
        recentItemsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recentItemsLabel)
        
        // Table view for recent items
        tableView = UITableView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            statsPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statsPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statsPanel.heightAnchor.constraint(equalToConstant: 120),
            
            totalRecycledLabel.topAnchor.constraint(equalTo: statsPanel.topAnchor, constant: 20),
            totalRecycledLabel.leadingAnchor.constraint(equalTo: statsPanel.leadingAnchor, constant: 20),
            totalRecycledLabel.trailingAnchor.constraint(equalTo: statsPanel.trailingAnchor, constant: -20),
            
            totalValueLabel.topAnchor.constraint(equalTo: totalRecycledLabel.bottomAnchor, constant: 10),
            totalValueLabel.leadingAnchor.constraint(equalTo: statsPanel.leadingAnchor, constant: 20),
            totalValueLabel.trailingAnchor.constraint(equalTo: statsPanel.trailingAnchor, constant: -20),
            
            environmentalImpactLabel.topAnchor.constraint(equalTo: totalValueLabel.bottomAnchor, constant: 10),
            environmentalImpactLabel.leadingAnchor.constraint(equalTo: statsPanel.leadingAnchor, constant: 20),
            environmentalImpactLabel.trailingAnchor.constraint(equalTo: statsPanel.trailingAnchor, constant: -20),
            
            recentItemsLabel.topAnchor.constraint(equalTo: statsPanel.bottomAnchor, constant: 30),
            recentItemsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            recentItemsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: recentItemsLabel.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func loadData() {
        let stats = RecyclingManager.shared.getUserStats(userId: UserManager.shared.currentUserId)
        
        totalRecycledLabel.text = "Total items recycled: \(stats.totalRecycled)"
        totalValueLabel.text = "Total value: $\(String(format: "%.2f", stats.totalValue))"
        environmentalImpactLabel.text = "CO₂ saved: \(String(format: "%.1f", stats.environmentalImpact)) lbs"
        
        recentItems = RecyclingManager.shared.getRecentItems(userId: UserManager.shared.currentUserId, limit: 20)
        tableView.reloadData()
    }
}

extension StatsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return recentItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = recentItems[indexPath.row]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        
        cell.textLabel?.text = "\(item.type) - $\(String(format: "%.2f", item.value)) - \(dateFormatter.string(from: item.date))"
        return cell
    }
}

// MARK: - Leaderboard View Controller

class LeaderboardViewController: UIViewController {
    private var tableView: UITableView!
    private var segmentedControl: UISegmentedControl!
    
    private var users: [User] = []
    private var leaderboardType = 0 // 0 = Total Items, 1 = Value, 2 = Environmental Impact
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Leaderboard"
        view.backgroundColor = .white
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }
    
    private func setupUI() {
        // Segmented control for leaderboard type
        segmentedControl = UISegmentedControl(items: ["Items", "Value", "Impact"])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        
        // Table view for leaderboard
        tableView = UITableView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        leaderboardType = sender.selectedSegmentIndex
        sortUsers()
        tableView.reloadData()
    }
    
    private func loadData() {
        users = LeaderboardManager.shared.getAllUsers()
        sortUsers()
        tableView.reloadData()
    }
    
    private func sortUsers() {
        switch leaderboardType {
        case 0: // Total Items
            users.sort { $0.totalRecycled > $1.totalRecycled }
        case 1: // Value
            users.sort { $0.totalValue > $1.totalValue }
        case 2: // Environmental Impact
            users.sort { $0.environmentalImpact > $1.environmentalImpact }
        default:
            break
        }
    }
}

extension LeaderboardViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let user = users[indexPath.row]
        
        var detailText = ""
        switch leaderboardType {
        case 0:
            detailText = "\(user.totalRecycled) items"
        case 1:
            detailText = "$\(String(format: "%.2f", user.totalValue))"
        case 2:
            detailText = "\(String(format: "%.1f", user.environmentalImpact)) lbs CO₂"
        default:
            break
        }
        
        cell.textLabel?.text = "\(indexPath.row + 1). \(user.username)"
        cell.detailTextLabel?.text = detailText
        return cell
    }
}

// MARK: - Profile View Controller

class ProfileViewController: UIViewController {
    private var usernameLabel: UILabel!
    private var logoutButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        view.backgroundColor = .white
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUserInfo()
    }
    
    private func setupUI() {
        // User info container
        let userInfoContainer = UIView()
        userInfoContainer.backgroundColor = .systemGray6
        userInfoContainer.layer.cornerRadius = 12
        userInfoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(userInfoContainer)
        
        // Username label
        usernameLabel = UILabel()
        usernameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        usernameLabel.textAlignment = .center
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        userInfoContainer.addSubview(usernameLabel)
        
        // Logout button
        logoutButton = UIButton(type: .system)
        logoutButton.setTitle("Logout", for: .normal)
        logoutButton.backgroundColor = .systemRed
        logoutButton.setTitleColor(.white, for: .normal)
        logoutButton.layer.cornerRadius = 8
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        view.addSubview(logoutButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            userInfoContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            userInfoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            userInfoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            userInfoContainer.heightAnchor.constraint(equalToConstant: 100),
            
            usernameLabel.centerYAnchor.constraint(equalTo: userInfoContainer.centerYAnchor),
            usernameLabel.leadingAnchor.constraint(equalTo: userInfoContainer.leadingAnchor, constant: 20),
            usernameLabel.trailingAnchor.constraint(equalTo: userInfoContainer.trailingAnchor, constant: -20),
            
            logoutButton.topAnchor.constraint(equalTo: userInfoContainer.bottomAnchor, constant: 40),
            logoutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoutButton.widthAnchor.constraint(equalToConstant: 200),
            logoutButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func updateUserInfo() {
        usernameLabel.text = UserManager.shared.currentUsername
    }
    
    @objc private func logoutButtonTapped() {
        UserManager.shared.logout()
        
        // Present login screen
        let loginVC = LoginViewController()
        let navController = UINavigationController(rootViewController: loginVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
}

// MARK: - Login View Controller

class LoginViewController: UIViewController {
    private var usernameTextField: UITextField!
    private var passwordTextField: UITextField!
    private var loginButton: UIButton!
    private var registerButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RecycleTracker"
        view.backgroundColor = .white
        setupUI()
    }
    
    private func setupUI() {
        // Logo/app name label
        let logoLabel = UILabel()
        logoLabel.text = "♻️ RecycleTracker"
        logoLabel.font = UIFont.boldSystemFont(ofSize: 28)
        logoLabel.textAlignment = .center
        logoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logoLabel)
        
        // Username text field
        usernameTextField = UITextField()
        usernameTextField.placeholder = "Username"
        usernameTextField.borderStyle = .roundedRect
        usernameTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameTextField)
        
        // Password text field
        passwordTextField = UITextField()
        passwordTextField.placeholder = "Password"
        passwordTextField.isSecureTextEntry = true
        passwordTextField.borderStyle = .roundedRect
        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordTextField)
        
        // Login button
        loginButton = UIButton(type: .system)
        loginButton.setTitle("Login", for: .normal)
        loginButton.backgroundColor = .systemGreen
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.layer.cornerRadius = 8
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        view.addSubview(loginButton)
        
        // Register button
        registerButton = UIButton(type: .system)
        registerButton.setTitle("Register", for: .normal)
        registerButton.translatesAutoresizingMaskIntoConstraints = false
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        view.addSubview(registerButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            logoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            logoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            logoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            usernameTextField.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 60),
            usernameTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            usernameTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            usernameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            passwordTextField.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 20),
            passwordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            passwordTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            loginButton.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 40),
            loginButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            loginButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
            
            registerButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 20),
            registerButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    @objc private func loginButtonTapped() {
        guard let username = usernameTextField.text, !username.isEmpty,
              let password = passwordTextField.text, !password.isEmpty else {
            showAlert(title: "Error", message: "Please enter username and password")
            return
        }
        
        // Attempt login
        if UserManager.shared.login(username: username, password: password) {
            // Present main app
            let mainTabBarController = MainTabBarController()
            mainTabBarController.modalPresentationStyle = .fullScreen
            present(mainTabBarController, animated: true)
        } else {
            showAlert(title: "Login Failed", message: "Invalid username or password")
        }
    }
    
    @objc private func registerButtonTapped() {
        let registerVC = RegisterViewController()
        navigationController?.pushViewController(registerVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Register View Controller

class RegisterViewController: UIViewController {
    private var usernameTextField: UITextField!
    private var passwordTextField: UITextField!
    private var confirmPasswordTextField: UITextField!
    private var registerButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Register"
        view.backgroundColor = .white
        setupUI()
    }
    
    private func setupUI() {
        // Username text field
        usernameTextField = UITextField()
        usernameTextField.placeholder = "Username"
        usernameTextField.borderStyle = .roundedRect
        usernameTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameTextField)
        
        // Password text field
        passwordTextField = UITextField()
        passwordTextField.placeholder = "Password"
        passwordTextField.isSecureTextEntry = true
        passwordTextField.borderStyle = .roundedRect
        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordTextField)
        
        // Confirm password text field
        confirmPasswordTextField = UITextField()
        confirmPasswordTextField.placeholder = "Confirm Password"
        confirmPasswordTextField.isSecureTextEntry = true
        confirmPasswordTextField.borderStyle = .roundedRect
        confirmPasswordTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(confirmPasswordTextField)
        
        // Register button
        registerButton = UIButton(type: .system)
        registerButton.setTitle("Register", for: .normal)
        registerButton.backgroundColor = .systemGreen
        registerButton.setTitleColor(.white, for: .normal)
        registerButton.layer.cornerRadius = 8
        registerButton.translatesAutoresizingMaskIntoConstraints = false
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        view.addSubview(registerButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            usernameTextField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            usernameTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            usernameTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            usernameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            passwordTextField.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 20),
            passwordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            passwordTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 20),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            registerButton.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 40),
            registerButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            registerButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            registerButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func registerButtonTapped() {
        guard let username = usernameTextField.text, !username.isEmpty,
              let password = passwordTextField.text, !password.isEmpty,
              let confirmPassword = confirmPasswordTextField.text, !confirmPassword.isEmpty else {
            showAlert(title: "Error", message: "Please fill all fields")
            return
        }
        
        if password != confirmPassword {
            showAlert(title: "Error", message: "Passwords do not match")
            return
        }
        
        // Attempt registration
        if UserManager.shared.register(username: username, password: password) {
            showAlert(title: "Success", message: "Registration successful. Please log in.") { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        } else {
            showAlert(title: "Registration Failed", message: "Username already exists")
        }
    }
    
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - Managers

class UserManager {
    static let shared = UserManager()
    
    private var users: [String: (password: String, userId: String)] = [
        "demo": (password: "password", userId: "user1")
    ]
    
    private(set) var currentUserId: String = ""
    private(set) var currentUsername: String = ""
    
    private init() {}
    
    func login(username: String, password: String) -> Bool {
        if let userInfo = users[username], userInfo.password == password {
            currentUserId = userInfo.userId
            currentUsername = username
            return true
        }
        return false
    }
    
    func register(username: String, password: String) -> Bool {
        if users[username] != nil {
            return false
        }
        
        let userId = "user\(users.count + 1)"
        users[username] = (password: password, userId: userId)
        
        // Add user to leaderboard
        LeaderboardManager.shared.addUser(id: userId, username: username)
        
        return true
    }
    
    func logout() {
        currentUserId = ""
        currentUsername = ""
    }
}

class RecyclingManager {
    static let shared = RecyclingManager()
    
    private var items: [RecycledItem] = []
    
    private init() {
        // Add some sample data
        let sampleItems: [RecycledItem] = [
            RecycledItem(id: "1", type: "Plastic Bottle", barcode: "1234567890", value: 0.05, date: Date().addingTimeInterval(-86400), userId: "user1"),
            RecycledItem(id: "2", type: "Aluminum Can", barcode: "0987654321", value: 0.10, date: Date().addingTimeInterval(-43200), userId: "user1"),
            RecycledItem(id: "3", type: "Glass Bottle", barcode: "5678901234", value: 0.15, date: Date(), userId: "user1")
        ]
        
        items.append(contentsOf: sampleItems)
        
        // Update leaderboard stats
        updateLeaderboardStats(userId: "user1")
    }
    
    func addRecycledItem(_ item: RecycledItem) {
        items.append(item)
        updateLeaderboardStats(userId: item.userId)
    }
    
    func getRecentItems(userId: String, limit: Int) -> [RecycledItem] {
        return items.filter { $0.userId == userId }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }
    
    func getUserStats(userId: String) -> (totalRecycled: Int, totalValue: Double, environmentalImpact: Double) {
        let userItems = items.filter { $0.userId == userId }
        
        let totalRecycled = userItems.count
        let totalValue = userItems.reduce(0) { $0 + $1.value }
        
        // Simple environmental impact calculation (CO2 saved in lbs)
        let environmentalImpact = userItems.reduce(0) { total, item in
            let impactFactor: Double
            
            switch item.type.lowercased() {
            case let type where type.contains("plastic"):
                impactFactor = 0.12
            case let type where type.contains("aluminum"):
                impactFactor = 0.22
            case let type where type.contains("glass"):
                impactFactor = 0.16
            default:
                impactFactor = 0.10
            }
            
            return total + impactFactor
        }
        
        return (totalRecycled, totalValue, environmentalImpact)
    }
    
    private func updateLeaderboardStats(userId: String) {
        let stats = getUserStats(userId: userId)
        LeaderboardManager.shared.updateUserStats(
            userId: userId,
            totalRecycled: stats.totalRecycled,
            totalValue: stats.totalValue,
            environmentalImpact: stats.environmentalImpact
        )
    }
}

class LeaderboardManager {
    static let shared = LeaderboardManager()
    
    private var users: [User] = [
        User(id: "user1", username: "demo", totalRecycled: 3, totalValue: 0.30, environmentalImpact: 0.50),
        User(id: "user2", username: "ecoWarrior", totalRecycled: 24, totalValue: 2.35, environmentalImpact: 3.75),
        User(id: "user3", username: "recycleKing", totalRecycled: 52, totalValue: 5.80, environmentalImpact: 8.20),
        User(id: "user4", username: "greenEarth", totalRecycled: 18, totalValue: 1.95, environmentalImpact: 2.90)
    ]
    
    private init() {}
    
    func getAllUsers() -> [User] {
        return users
    }
    
    func addUser(id: String, username: String) {
        let newUser = User(id: id, username: username, totalRecycled: 0, totalValue: 0, environmentalImpact: 0)
        users.append(newUser)
    }
    
    func updateUserStats(userId: String, totalRecycled: Int, totalValue: Double, environmentalImpact: Double) {
        if let index = users.firstIndex(where: { $0.id == userId }) {
            users[index].totalRecycled = totalRecycled
            users[index].totalValue = totalValue
            users[index].environmentalImpact = environmentalImpact
        }
    }
}

class RecycleDatabase {
    private var items: [String: (String, Double)] = [
        "1234567890": ("Plastic Bottle", 0.05),
        "0987654321": ("Aluminum Can", 0.10),
        "5678901234": ("Glass Bottle", 0.15),
        "1357924680": ("Plastic Milk Jug", 0.10),
        "2468013579": ("Glass Beer Bottle", 0.15),
        "9876543210": ("Aluminum Beer Can", 0.10),
        "0123456789": ("Plastic Water Bottle", 0.05)
    ]
    
    func lookupItem(barcode: String) -> (String, Double)? {
        return items[barcode]
    }
    
    func addItem(barcode: String, type: String, value: Double) {
        items[barcode] = (type, value)
    }
}
```


