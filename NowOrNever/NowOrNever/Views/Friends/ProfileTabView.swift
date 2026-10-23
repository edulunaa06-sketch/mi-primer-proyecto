import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Pestaña Perfil, al estilo de una red social: foto, nombre y @usuario, cuántas fotos, seguidores y
/// seguidos, altura y peso, y la cuadrícula de fotos de progreso por fecha. Desde aquí se edita el perfil
/// (peso, altura, objetivo…) y se entra en Amigos (buscar, solicitudes y los días de quien sigues).
struct ProfileTabView: View {
    @Environment(SocialService.self) private var social
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: [SortDescriptor(\ProgressPhoto.year, order: .reverse), SortDescriptor(\ProgressPhoto.month, order: .reverse)])
    private var photos: [ProgressPhoto]

    @State private var avatarItem: PhotosPickerItem?
    @State private var creatingAccount = false
    @State private var viewing: ProgressPhoto?
    @State private var message: String?

    private var hasAccount: Bool { social.isSignedIn && social.me != nil }
    private var name: String { social.me?.shownName ?? social.pendingStart?.name ?? "Tu perfil" }
    private var username: String? { social.me?.username ?? social.pendingStart?.username }

    /// Fotos agrupadas por mes, con la fecha del día en que se hicieron (la más reciente del grupo).
    private var groups: [(month: String, date: String, items: [ProgressPhoto])] {
        let order: [PhotoView: Int] = [.front: 0, .side: 1, .back: 2]
        return Dictionary(grouping: photos) { String(format: "%04d-%02d", $0.year, $0.month) }
            .map { month, list in
                let latest = list.map(\.updatedAt).max() ?? Date()
                return (month, SocialAPI.dayString(latest, calendar: DateUtils.calendar),
                        list.sorted { (order[$0.view] ?? 3) < (order[$1.view] ?? 3) })
            }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    buttons
                    if !hasAccount { accountCard }
                    photoGrid
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(username.map { "@\($0)" } ?? "Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { if hasAccount { try? await social.refreshFriends() } }
            .task { if hasAccount { try? await social.refreshFriends() } }
            .sheet(isPresented: $creatingAccount) { AccountSetupView { creatingAccount = false } }
            .sheet(item: $viewing) { photo in PhotoViewer(photo: photo) }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task {
                    defer { avatarItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                          let jpeg = ProfileImage.jpeg(image, maxSide: 512) else { message = "No se pudo leer la imagen."; return }
                    do { try await social.uploadAvatar(jpeg); message = nil } catch { message = error.localizedDescription }
                }
            }
        }
    }

    // MARK: Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(profile: social.me, size: 86)
                        if hasAccount {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.lime)
                                .background(Circle().fill(Theme.background))
                        }
                    }
                }
                .disabled(!hasAccount)
                .accessibilityLabel("Cambiar foto de perfil")
                HStack(spacing: 0) {
                    counter(groups.count, "fotos")
                    NavigationLink { PeopleListView() } label: { counter(social.followers.count, "seguidores") }
                        .buttonStyle(.plain).disabled(!hasAccount)
                    NavigationLink { PeopleListView() } label: { counter(social.following.count, "seguidos") }
                        .buttonStyle(.plain).disabled(!hasAccount)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.title3.weight(.heavy))
                if let username { Text("@\(username)").font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
            StatsRow(heightCm: settingsList.first?.heightCm, weightKg: weights.last?.weightKg)
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.danger) }
        }
    }

    private func counter(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.title3.weight(.heavy).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if let settings = settingsList.first {
                NavigationLink { ProfileView(settings: settings) } label: {
                    Label("Editar perfil", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle(filled: false))
            }
            NavigationLink { FriendsView(embedded: true) } label: {
                Label("Amigos", systemImage: "person.2.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LimeButtonStyle())
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if social.pendingStart != nil {
                Text(social.isConfigured ? "Conectando tu cuenta…" : "Tu cuenta se creará sola en cuanto el servidor de amigos esté listo.")
                    .font(.subheadline)
                Text("Mientras tanto, tu perfil y tus fotos se guardan en este iPhone.").font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Crea tu cuenta para que tus amigos te encuentren y os sigáis.").font(.subheadline)
                Button("Crear mi cuenta") { creatingAccount = true }
                    .buttonStyle(LimeButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task {
            // Si ya hay servidor y datos guardados, se intenta crear la cuenta al entrar.
            if social.pendingStart != nil && social.isConfigured {
                do { try await social.completePendingStart() } catch { message = error.localizedDescription }
            }
        }
    }

    // MARK: Fotos de progreso

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "square.grid.3x3.fill").foregroundStyle(Theme.lime)
                Text("Mi progreso").font(.headline)
            }
            if groups.isEmpty {
                EmptyStateView(symbol: "camera", title: "Sin fotos todavía",
                               message: "Haz tus fotos de frente, lateral y espalda en Progreso › Fotos y aparecerán aquí con su fecha.")
                    .card()
            }
            ForEach(groups, id: \.month) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(ProfileImage.longDate(group.date)).font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(group.items) { photo in
                            Button { viewing = photo } label: {
                                Color.clear
                                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                    .overlay {
                                        if let image = PhotoStorage.loadImage(photo.fileName) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else {
                                            Theme.cardRaised
                                        }
                                    }
                                    .clipped()
                                    .overlay(alignment: .bottomLeading) {
                                        Text(photo.view.label).font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.black.opacity(0.55), in: Capsule())
                                            .padding(5)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

/// Una foto de progreso a pantalla completa.
private struct PhotoViewer: View {
    let photo: ProgressPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = PhotoStorage.loadImage(photo.fileName) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Text("No se encuentra la foto.").foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("\(photo.view.label) · \(ProfileImage.longDate(SocialAPI.dayString(photo.updatedAt, calendar: DateUtils.calendar)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
