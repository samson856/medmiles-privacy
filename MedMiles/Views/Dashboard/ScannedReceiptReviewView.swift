import SwiftUI
import PhotosUI
import AVFoundation
import Auth

struct ScannedReceiptReviewView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var scanVM = ReceiptScanViewModel()
    @StateObject private var mealViewModel = MealViewModel()
    @StateObject private var expenseViewModel = IndividualExpenseViewModel()
    @Environment(\.dismiss) private var dismiss

    // Camera / photo state
    @State private var showOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCameraPermissionAlert = false

    // Meal slot chosen right after a meal scan (Breakfast / Lunch / Dinner)
    @State private var chosenMealSlot: ScanPrefillData.MealSlot?
    @State private var showSlotChooser = false


    var body: some View {
        NavigationStack {
            Group {
                switch scanVM.state {
                case .idle:
                    capturePromptView
                case .scanning:
                    scanningView
                case .review:
                    routedFormView
                }
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Capture Receipt", isPresented: $showOptions) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { requestCamera() }
                }
                Button("Choose from Photos") { showPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable camera access in Settings to capture receipt photos.")
            }
            .sheet(isPresented: $showCamera) {
                CameraView { image in
                    scanVM.processImage(image)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        scanVM.processImage(image)
                    }
                    selectedPhoto = nil
                }
            }
            .task {
                guard let userId = authService.currentSession?.user.id else { return }
                await mealViewModel.loadAll(userId: userId)
                await expenseViewModel.loadAll(userId: userId)
            }
            .confirmationDialog("Which meal is this?", isPresented: $showSlotChooser, titleVisibility: .visible) {
                Button("Breakfast") { chosenMealSlot = .breakfast }
                Button("Lunch") { chosenMealSlot = .lunch }
                Button("Dinner") { chosenMealSlot = .dinner }
                Button("Cancel", role: .cancel) { chosenMealSlot = .lunch }
            }
            .onChange(of: scanVM.state) { _, newState in
                if newState == .review && scanVM.category == .meal && chosenMealSlot == nil {
                    showSlotChooser = true
                }
            }
            .onChange(of: scanVM.category) { _, newCategory in
                if scanVM.state == .review && newCategory == .meal && chosenMealSlot == nil {
                    showSlotChooser = true
                }
            }
        }
    }

    private var navigationTitle: String {
        switch scanVM.state {
        case .idle: return "Scan Receipt"
        case .scanning: return "Scanning..."
        case .review:
            return scanVM.category == .meal ? "Log Meal" : "Log Expense"
        }
    }

    // MARK: - Capture Prompt

    private var capturePromptView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.viewfinder")
                .font(.largeTitle)
                .foregroundColor(Color(Constants.Colors.mintTeal))

            Text("Scan a Receipt")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color(Constants.Colors.graphite))

            Text("Take a photo or choose from your library.\nWe'll extract the details automatically.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showOptions = true
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Capture Receipt")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(Constants.Colors.mintTeal))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()

            if let image = scanVM.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            }

            ProgressView("Reading receipt...")
                .progressViewStyle(.circular)

            Spacer()
        }
        .padding()
    }

    // MARK: - Routed Form

    private var routedFormView: some View {
        VStack(spacing: 0) {
            // Category toggle + meal slot picker
            VStack(spacing: 12) {
                // OCR error message
                if let error = scanVM.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                    }
                    .padding(.horizontal, 24)
                }

                // Category toggle
                Picker("Type", selection: $scanVM.category) {
                    Text("Meal").tag(ReceiptCategory.meal)
                    Text("Expense").tag(ReceiptCategory.expense)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

            }
            .padding(.vertical, 12)
            .background(Color(Constants.Colors.background))

            // The actual form
            if scanVM.category == .meal {
                if let slot = chosenMealSlot {
                    MealLogView(
                        viewModel: mealViewModel,
                        prefillData: buildPrefillData(slot: slot),
                        onSaveComplete: { _ in dismiss() }
                    )
                } else {
                    // Waiting for the user to pick breakfast / lunch / dinner.
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "fork.knife")
                            .font(.largeTitle)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        Text("Which meal is this?")
                            .font(.headline)
                        Text("Choose breakfast, lunch, or dinner to continue.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Choose meal") { showSlotChooser = true }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                            .padding(.top, 4)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                IndividualExpenseLogView(
                    viewModel: expenseViewModel,
                    prefillData: buildPrefillData(),
                    onSaveComplete: { _ in dismiss() }
                )
            }
        }
    }

    // MARK: - Helpers

    private func buildPrefillData(slot: ScanPrefillData.MealSlot? = nil) -> ScanPrefillData? {
        guard let image = scanVM.capturedImage else { return nil }
        return ScanPrefillData(
            date: scanVM.date,
            amount: scanVM.amount.isEmpty ? nil : scanVM.amount,
            merchantName: scanVM.merchantName.isEmpty ? nil : scanVM.merchantName,
            capturedImage: image,
            mealSlot: scanVM.category == .meal ? (slot ?? .lunch) : nil
        )
    }

    private func requestCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true }
                    else { showCameraPermissionAlert = true }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }
}
