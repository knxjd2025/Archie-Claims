import SwiftUI
import MapKit

/// The canvassing map: tap any house to pull its address, storm history, and
/// public contact lookups. Saved leads show as colored pins. A search bar
/// jumps to any typed address or city (tap the dropped pin for its storm
/// report), and +/- buttons zoom without pinching.
struct CanvassMapView: View {
    @EnvironmentObject private var leadStore: LeadStore
    @EnvironmentObject private var locationManager: LocationManager

    /// Charlotte, NC — the default canvassing area for testing.
    static let charlotte = CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CanvassMapView.charlotte,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var tappedCoordinate: TappedSpot?
    @State private var useHybrid = true

    @State private var searchText = ""
    @State private var searchResults: [GeocodingService.Place] = []
    @State private var searchedPlace: GeocodingService.Place?
    @State private var isSearching = false
    @State private var searchFailed = false
    @FocusState private var searchFocused: Bool

    struct TappedSpot: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    if let place = searchedPlace {
                        Annotation(place.title, coordinate: place.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, Color.accentColor)
                                .shadow(radius: 2)
                                .onTapGesture {
                                    tappedCoordinate = TappedSpot(coordinate: place.coordinate)
                                }
                        }
                    }

                    ForEach(leadStore.leads) { lead in
                        Annotation(lead.shortAddress, coordinate: lead.coordinate) {
                            Image(systemName: lead.status.symbolName)
                                .font(.caption)
                                .padding(6)
                                .background(color(for: lead.status), in: Circle())
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                                .onTapGesture {
                                    tappedCoordinate = TappedSpot(coordinate: lead.coordinate)
                                }
                        }
                    }
                }
                .mapStyle(useHybrid ? .hybrid(elevation: .flat) : .standard)
                .mapControls {
                    MapCompass()
                }
                .onMapCameraChange { context in
                    visibleRegion = context.region
                }
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    searchFocused = false
                    tappedCoordinate = TappedSpot(coordinate: coordinate)
                }
            }
            .navigationTitle("Canvass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        useHybrid.toggle()
                    } label: {
                        Image(systemName: useHybrid ? "map" : "globe.americas.fill")
                    }
                    .accessibilityLabel("Toggle satellite view")
                }
            }
            .overlay(alignment: .top) {
                searchOverlay
            }
            .overlay(alignment: .bottomTrailing) {
                zoomControls
            }
            .overlay(alignment: .bottom) {
                if leadStore.leads.isEmpty && !searchFocused {
                    Text("Tap a rooftop to pull its storm report")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
            .sheet(item: $tappedCoordinate) { spot in
                PropertySheetView(coordinate: spot.coordinate)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                if locationManager.authorization == .notDetermined {
                    locationManager.requestPermission()
                } else {
                    locationManager.start()
                }
            }
        }
    }

    // MARK: - Search

    private var searchOverlay: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Address or city — storms anywhere", text: $searchText)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                if isSearching {
                    ProgressView()
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        searchedPlace = nil
                        searchFailed = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)

            if searchFailed {
                Text("No matches — try adding a city or state.")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults.prefix(5)) { place in
                        Button {
                            select(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.title)
                                    .font(.subheadline.weight(.medium))
                                Text(place.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if place.id != searchResults.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }
        isSearching = true
        searchFailed = false
        Task {
            let places = await GeocodingService.geocode(query)
            isSearching = false
            if places.isEmpty {
                searchResults = []
                searchFailed = true
            } else if places.count == 1 {
                select(places[0])
            } else {
                searchResults = places
            }
        }
    }

    private func select(_ place: GeocodingService.Place) {
        searchedPlace = place
        searchResults = []
        searchFailed = false
        searchFocused = false
        searchText = place.subtitle.isEmpty ? place.title : "\(place.title), \(place.subtitle)"
        withAnimation(.easeOut(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: place.spanDegrees, longitudeDelta: place.spanDegrees)
            ))
        }
    }

    // MARK: - Zoom

    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.6)) {
                    cameraPosition = .userLocation(fallback: .automatic)
                }
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Go to my location")
            Divider().frame(width: 40)
            Button { zoom(by: 0.45) } label: {
                Image(systemName: "plus")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Zoom in")
            Divider().frame(width: 40)
            Button { zoom(by: 2.2) } label: {
                Image(systemName: "minus")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Zoom out")
        }
        .font(.body.weight(.semibold))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        .padding(.trailing, 10)
        .padding(.bottom, 90)
        .accessibilityElement(children: .contain)
    }

    private func zoom(by factor: Double) {
        guard let region = visibleRegion else { return }
        let lat = min(max(region.span.latitudeDelta * factor, 0.0008), 120)
        let lon = min(max(region.span.longitudeDelta * factor, 0.0008), 120)
        withAnimation(.easeOut(duration: 0.25)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(latitudeDelta: lat, longitudeDelta: lon)
            ))
        }
    }

    private func color(for status: Lead.Status) -> Color {
        switch status {
        case .newLead: return .blue
        case .notHome: return .gray
        case .interested: return .orange
        case .appointment: return .purple
        case .inspected: return .teal
        case .signed: return .green
        case .notInterested: return .red
        }
    }
}
