import SwiftUI

struct AgencyPicker: View {
    @Binding var selectedAgencyId: UUID?
    let agencies: [Agency]
    let onAddNew: (String) -> Void
    var onDelete: ((UUID) -> Void)? = nil

    @State private var showAddSheet = false
    @State private var showManageSheet = false
    @State private var manageAgencies: [Agency] = []

    private var selectedName: String {
        guard let id = selectedAgencyId else { return "Select agency" }
        return agencies.first(where: { $0.id == id })?.name ?? "Select agency"
    }

    var body: some View {
        HStack {
            Menu {
                Button("Select agency") {
                    selectedAgencyId = nil
                }
                ForEach(agencies) { agency in
                    Button(agency.name) {
                        selectedAgencyId = agency.id
                    }
                }
                Divider()
                if onDelete != nil {
                    Button {
                        showManageSheet = true
                    } label: {
                        Label("Manage Agencies", systemImage: "pencil")
                    }
                }
            } label: {
                HStack {
                    Text(selectedName)
                        .foregroundColor(selectedAgencyId == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color(Constants.Colors.mintTeal))
            }
            .accessibilityLabel("Add new agency")
        }
        .sheet(isPresented: $showAddSheet) {
            AddAgencySheet { name in
                onAddNew(name)
            }
        }
        .sheet(isPresented: $showManageSheet) {
            ManageAgenciesSheet(agencies: $manageAgencies, onDelete: { id in
                if selectedAgencyId == id {
                    selectedAgencyId = nil
                }
                onDelete?(id)
            })
        }
        .onChange(of: showManageSheet) { _, isPresented in
            if isPresented {
                manageAgencies = agencies
            }
        }
    }
}

struct ManageAgenciesSheet: View {
    @Binding var agencies: [Agency]
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if agencies.isEmpty {
                    Text("No agencies saved")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(agencies) { agency in
                        HStack {
                            Text(agency.name)
                                .font(.subheadline)
                            Spacer()
                            Button(role: .destructive) {
                                let id = agency.id
                                onDelete(id)
                                agencies.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(Color(Constants.Colors.errorRed))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(agency.name)")
                        }
                    }
                }
            }
            .navigationTitle("Manage Agencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
