import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

struct ReceiptCaptureButton: View {
    let receiptFilenames: [String]
    let onCapture: (UIImage) -> Void
    let onDelete: (String) -> Void
    var onFileImport: ((URL) -> Void)? = nil  // Optional file import handler

    @State private var showOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCameraPermissionAlert = false
    @State private var showFileImportError = false
    @State private var viewingFilename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showOptions = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: receiptFilenames.isEmpty ? "paperclip" : "checkmark.circle.fill")
                            .foregroundColor(receiptFilenames.isEmpty ? Color(Constants.Colors.mintTeal) : Color(Constants.Colors.successGreen))
                        Text(receiptFilenames.isEmpty ? "Attach Document" : "\(receiptFilenames.count) File\(receiptFilenames.count == 1 ? "" : "s") Attached")
                            .font(.subheadline)
                            .foregroundColor(receiptFilenames.isEmpty ? Color(Constants.Colors.mintTeal) : Color(Constants.Colors.successGreen))
                    }
                }
                .accessibilityLabel(receiptFilenames.isEmpty ? "Attach document" : "\(receiptFilenames.count) file\(receiptFilenames.count == 1 ? "" : "s") attached")

                Spacer()

                if !receiptFilenames.isEmpty {
                    Button {
                        showOptions = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                    }
                    .accessibilityLabel("Attach another document")
                }
            }

            // Thumbnail / file strip
            if !receiptFilenames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(receiptFilenames, id: \.self) { filename in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    viewingFilename = filename
                                } label: {
                                    if filename.hasSuffix(".pdf") {
                                        // PDF icon
                                        VStack(spacing: 2) {
                                            Image(systemName: "doc.fill")
                                                .font(.title3)
                                                .foregroundColor(Color(Constants.Colors.errorRed))
                                            Text("PDF")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(width: 56, height: 56)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    } else if let image = LocalStorageService.shared.loadReceipt(filename: filename) {
                                        // Image thumbnail
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 56, height: 56)
                                            .cornerRadius(8)
                                            .clipped()
                                    } else {
                                        // Generic file icon
                                        VStack(spacing: 2) {
                                            Image(systemName: "doc.fill")
                                                .font(.title3)
                                                .foregroundColor(Color(Constants.Colors.mintTeal))
                                            Text(String(filename.suffix(3)).uppercased())
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(width: 56, height: 56)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                }
                                .accessibilityLabel("View \(filename)")

                                Button {
                                    onDelete(filename)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .accessibilityLabel("Remove \(filename)")
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Attach Document", isPresented: $showOptions) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    switch status {
                    case .authorized:
                        showCamera = true
                    case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    showCamera = true
                                } else {
                                    showCameraPermissionAlert = true
                                }
                            }
                        }
                    case .denied, .restricted:
                        showCameraPermissionAlert = true
                    @unknown default:
                        showCameraPermissionAlert = true
                    }
                }
            }
            Button("Choose from Photos") { showPhotoPicker = true }
            Button("Choose File (PDF, etc.)") { showFilePicker = true }
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
                onCapture(image)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onCapture(image)
                }
                selectedPhoto = nil
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.pdf, .png, .jpeg, .heic],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if let handler = onFileImport {
                        handler(url)
                    } else {
                        importFile(from: url)
                    }
                }
            case .failure:
                showFileImportError = true
            }
        }
        .alert("Import Failed", isPresented: $showFileImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unable to import the selected file. Please try again or choose a different file.")
        }
        .fullScreenCover(item: $viewingFilename) { filename in
            ReceiptViewerView(filename: filename)
        }
    }

    private func importFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            if let data = try? Data(contentsOf: url) {
                let entryId = UUID()
                if LocalStorageService.shared.saveFile(data: data, for: entryId, extension: "pdf") != nil {
                    onFileImport?(url)
                }
            }
        } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            onCapture(image)
        }
    }
}

// MARK: - Receipt Viewer (Full Screen)

struct ReceiptViewerView: View {
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if filename.lowercased().hasSuffix(".pdf") {
                    // PDF: show share option since we can't inline-render easily
                    VStack(spacing: 20) {
                        Image(systemName: "doc.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                        Text("PDF Document")
                            .foregroundColor(.white)
                            .font(.headline)
                        ShareLink(item: LocalStorageService.shared.receiptURL(filename: filename)) {
                            Label("Open / Share", systemImage: "square.and.arrow.up")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.2))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                        }
                    }
                } else if let image = LocalStorageService.shared.loadReceipt(filename: filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = value.magnification
                                }
                                .onEnded { _ in
                                    withAnimation { scale = max(scale, 1.0) }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1.0 ? 1.0 : 2.5
                            }
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Unable to load file")
                            .foregroundColor(.gray)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// Make String work with fullScreenCover(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
