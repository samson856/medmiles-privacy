import SwiftUI

struct VisitTypePicker: View {
    @Binding var selectedVisitTypeId: UUID?
    let visitTypes: [VisitType]
    let onAddNew: (String) -> Void
    var onDelete: ((UUID) -> Void)? = nil

    @State private var showAddSheet = false
    @State private var showManageSheet = false

    private var selectedName: String {
        guard let id = selectedVisitTypeId else { return "Select visit type" }
        return visitTypes.first(where: { $0.id == id })?.name ?? "Select visit type"
    }

    var body: some View {
        HStack {
            Menu {
                Button("Select visit type") {
                    selectedVisitTypeId = nil
                }
                ForEach(visitTypes) { vt in
                    Button(vt.name) {
                        selectedVisitTypeId = vt.id
                    }
                }
                Divider()
                if onDelete != nil {
                    Button {
                        showManageSheet = true
                    } label: {
                        Label("Manage Visit Types", systemImage: "pencil")
                    }
                }
            } label: {
                HStack {
                    Text(selectedName)
                        .foregroundColor(selectedVisitTypeId == nil ? .secondary : .primary)
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
            .accessibilityLabel("Add new visit type")
        }
        .sheet(isPresented: $showAddSheet) {
            AddVisitTypeSheet { name in
                onAddNew(name)
            }
        }
        .sheet(isPresented: $showManageSheet) {
            ManageVisitTypesSheet(visitTypes: visitTypes, onDelete: { id in
                if selectedVisitTypeId == id {
                    selectedVisitTypeId = nil
                }
                onDelete?(id)
            })
        }
    }
}

struct ManageVisitTypesSheet: View {
    let visitTypes: [VisitType]
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if visitTypes.isEmpty {
                    Text("No visit types saved")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(visitTypes) { vt in
                        Text(vt.name)
                            .font(.subheadline)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            onDelete(visitTypes[index].id)
                        }
                    }
                }
            }
            .navigationTitle("Manage Visit Types")
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
