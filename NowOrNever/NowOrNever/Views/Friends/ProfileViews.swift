import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum ProfileImage {
    /// Reduce una imagen para subirla (lado mayor `maxSide`, JPEG 80 %).
    static func jpeg(_ image: UIImage, maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }

    /// «2026-10-23» → «Viernes, 23 de octubre» (con año si no es el actual).
    static func longDate(_ day: String) -> String {
        guard let date = DateUtils.date(fromDayKey: day) else { return day }
        let sameYear = DateUtils.calendar.component(.year, from: date) == DateUtils.calendar.component(.year, from: Date())
        let style = sameYear ? Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
                             : Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()
        let text = date.formatted(style.locale(Locale(identifier: "es_ES")))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Imagen privada del servidor (foto de perfil o de progreso), descargada con tu sesión.
struct RemoteImage: View {
    let bucket: String
    let path: String?
    var version: String? = nil
    var contentMode: ContentMode = .fill

    @Environment(SocialService.self) private var social
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.cardRaised
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if path != nil {
                ProgressView()
            }
        }
        .task(id: (path ?? "") + (version ?? "")) {
            guard let path else { image = nil; return }
            image = await social.image(bucket: bucket, path: path, version: version).flatMap(UIImage.init(data:))
        }
    }
}

struct Avatar: View {
    let profile: SocialAPI.Profile?
    var local: UIImage? = nil
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let local {
                Image(uiImage: local).resizable().scaledToFill()
            } else if let path = profile?.avatarPath {
                RemoteImage(bucket: "avatars", path: path)
            } else {
                ZStack {
                    Theme.limeDim
                    Text(String(profile?.shownName.prefix(1) ?? "?").uppercased())
                        .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.lime)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.lime.opacity(0.6), lineWidth: 2))
    }
}

/// Seguidores · seguidos.
struct FollowCountsRow: View {
    let followers: Int
    let following: Int

    var body: some View {
        HStack(spacing: 24) {
            count(followers, "seguidores")
            count(following, "seguidos")
        }
    }

    private func count(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.title3.weight(.heavy).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct StatsRow: View {
    let heightCm: Double?
    let weightKg: Double?

    var body: some View {
        HStack(spacing: 10) {
            tile("Altura", heightCm.map { "\(NumberFormat.integer($0)) cm" } ?? "—", "ruler")
            tile("Peso", weightKg.map { "\(NumberFormat.kg($0)) kg" } ?? "—", "scalemass.fill")
        }
    }

    private func tile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Una entrada del historial de fotos: la fecha y las tres vistas.
struct PhotoDayCard<Content: View>: View {
    let date: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date).font(.headline)
            HStack(spacing: 8) { content }
        }
        .card()
    }
}

// MARK: - Mi perfil

struct MyProfileView: View {
    @Environment(SocialService.self) private var social
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: [SortDescriptor(\ProgressPhoto.year, order: .reverse), SortDescriptor(\ProgressPhoto.month, order: .reverse)])
    private var photos: [ProgressPhoto]

    @State private var avatarItem: PhotosPickerItem?
    @State private var shareStats = true
    @State private var sharePhotos = false
    @State private var askPhotos = false
    @State private var message: String?
    @State private var working = false

    private var groupedLocal: [(month: String, date: String, items: [ProgressPhoto])] {
        let order: [PhotoView: Int] = [.front: 0, .side: 1, .back: 2]
        return Dictionary(grouping: photos) { String(format: "%04d-%02d", $0.year, $0.month) }
            .map { month, list in
                let latest = list.map(\.updatedAt).max() ?? Date()
                return (month, SocialAPI.dayString(latest, calendar: DateUtils.calendar), list.sorted { (order[$0.view] ?? 3) < (order[$1.view] ?? 3) })
            }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(profile: social.me, size: 96)
                            Image(systemName: "camera.circle.fill").font(.title).foregroundStyle(Theme.lime)
                                .background(Circle().fill(Theme.background))
                        }
                    }
                    .accessibilityLabel("Cambiar foto de perfil")
                    Text(social.me?.shownName ?? "").font(.title2.weight(.heavy))
                    Text("@\(social.me?.username ?? "")").foregroundStyle(Theme.textSecondary)
                    NavigationLink {
                        PeopleListView()
                    } label: {
                        FollowCountsRow(followers: social.followers.count, following: social.following.count)
                    }
                    .buttonStyle(.plain)
                    if working { ProgressView() }
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.textSecondary) }
                }
                .frame(maxWidth: .infinity)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Estadísticas", subtitle: "Altura del perfil y último pesaje")
                    StatsRow(heightCm: settingsList.first?.heightCm, weightKg: weights.last?.weightKg)
                    Toggle("Mostrar altura y peso a mis seguidores", isOn: $shareStats).tint(Theme.lime)
                        .onChange(of: shareStats) { _, value in Task { await social.setSharesStats(value); await sync() } }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Fotos de progreso", subtitle: "Se añaden aquí cada vez que subes una en Progreso › Fotos")
                    Toggle("Mostrar mis fotos de progreso a mis seguidores", isOn: $sharePhotos).tint(Theme.lime)
                        .onChange(of: sharePhotos) { _, value in Task { await social.setSharesPhotos(value); await sync() } }
                    Text(sharePhotos ? "Solo las ven las personas que aceptas. Si lo desactivas, se borran del servidor (en tu iPhone se quedan)."
                                     : "Ahora solo están en tu iPhone.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .card()

                if groupedLocal.isEmpty {
                    EmptyStateView(symbol: "camera", title: "Sin fotos todavía", message: "Haz tus fotos de frente, lateral y espalda en Progreso › Fotos.")
                        .card()
                }
                ForEach(groupedLocal, id: \.month) { group in
                    PhotoDayCard(date: ProfileImage.longDate(group.date)) {
                        ForEach(group.items) { photo in
                            VStack(spacing: 4) {
                                if let image = PhotoStorage.loadImage(photo.fileName) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(maxWidth: .infinity).frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                Text(photo.view.label).font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Mi perfil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            shareStats = social.sharesStats
            sharePhotos = social.sharesPhotos ?? false
            if social.sharesPhotos == nil && !photos.isEmpty { askPhotos = true }
        }
        .alert("¿Compartir tus fotos de progreso?", isPresented: $askPhotos) {
            Button("Sí, con mis seguidores") { sharePhotos = true }
            Button("No", role: .cancel) { Task { await social.setSharesPhotos(false) } }
        } message: {
            Text("Las verán solo las personas que aceptes, con la fecha de cada foto. Puedes cambiarlo cuando quieras.")
        }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                working = true
                defer { working = false; avatarItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                      let jpeg = ProfileImage.jpeg(image, maxSide: 512) else { message = "No se pudo leer la imagen."; return }
                do { try await social.uploadAvatar(jpeg); message = "Foto de perfil actualizada." } catch { message = error.localizedDescription }
            }
        }
    }

    private func sync() async {
        working = true
        defer { working = false }
        do { try await SocialSync.publish(social: social, health: health, context: context) } catch { message = error.localizedDescription }
    }
}

struct PeopleListView: View {
    @Environment(SocialService.self) private var social

    var body: some View {
        List {
            Section("Te siguen (\(social.followers.count))") {
                if social.followers.isEmpty { Text("Nadie todavía").foregroundStyle(Theme.textSecondary) }
                ForEach(social.followers) { row($0) }
            }
            .listRowBackground(Theme.card)
            Section("Sigues a (\(social.following.count))") {
                if social.following.isEmpty { Text("Aún no sigues a nadie").foregroundStyle(Theme.textSecondary) }
                ForEach(social.following) { person in
                    NavigationLink { FriendDetailView(person: person) } label: { row(person) }
                }
            }
            .listRowBackground(Theme.card)
        }
        .screenBackground()
        .navigationTitle("Seguidores y seguidos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ person: SocialAPI.Profile) -> some View {
        HStack(spacing: 12) {
            Avatar(profile: person, size: 40)
            VStack(alignment: .leading) {
                Text(person.shownName).font(.subheadline.weight(.semibold))
                Text("@\(person.username)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Fotos de un amigo

struct FriendPhotosView: View {
    let rows: [SocialAPI.PhotoRow]

    var body: some View {
        let groups = SocialAPI.groupedByMonth(rows)
        VStack(spacing: 14) {
            if groups.isEmpty {
                EmptyStateView(symbol: "camera", title: "Sin fotos compartidas", message: "Aparecerán aquí cuando comparta sus fotos de progreso.")
                    .card()
            }
            ForEach(groups, id: \.month) { group in
                PhotoDayCard(date: ProfileImage.longDate(group.takenOn)) {
                    ForEach(group.photos, id: \.path) { photo in
                        VStack(spacing: 4) {
                            RemoteImage(bucket: "progress", path: photo.path, version: photo.updatedAt)
                                .frame(maxWidth: .infinity).frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(PhotoView(rawValue: photo.view)?.label ?? photo.view).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
