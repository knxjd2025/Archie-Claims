import SwiftUI
import MapKit
import UIKit

/// The canvassing map — built to be the fastest door-to-door storm tool:
///  - Storm overlay: recent NOAA SPC hail/wind/tornado reports drawn right on
///    the map for the visible area, so you canvass where the storm actually hit.
///  - Quick Log mode: tap a roof → two taps to log the knock (status saved,
///    address + storm evidence fill in automatically in the background).
///  - Status filter chips and a live "today" tally for door counts.
///  - Search any address or city (tap the pin for its storm report), +/- zoom,
///    satellite toggle, and status-colored lead pins.
struct CanvassMapView: View {
    @EnvironmentObject private var leadStore: LeadStore
    @EnvironmentObject private var locationManager: LocationManager

    @AppStorage(AppSettings.searchRadiusKey) private var radiusMiles = AppSettings.defaultRadiusMiles
    @AppStorage(AppSettings.lookbackDaysKey) private var lookbackDays = AppSettings.defaultLookbackDays

    /// Charlotte, NC — a sensible national fallback only when we have neither a
    /// remembered camera nor a location fix yet.
    static let charlotte = CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)

    @State private var cameraPosition: MapCameraPosition = CanvassMapView.initialCameraPosition()
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var tappedCoordinate: TappedSpot?
    @State private var useHybrid = true
    @State private var showLegend = false

    @State private var undo: UndoState?
    struct UndoState: Identifiable {
        let id = UUID()
        let leadID: UUID
        let status: Lead.Status
        let wasNew: Bool
    }

    @State private var searchText = ""
    @State private var searchResults: [GeocodingService.Place] = []
    @State private var searchedPlace: GeocodingService.Place?
    @State private var isSearching = false
    @State private var searchFailed = false
    @FocusState private var searchFocused: Bool

    @State private var showStormOverlay = true
    @State private var stormMarkers: [NearbyStormReport] = []
    @State private var stormOverlayTask: Task<Void, Never>?
    @State private var isLoadingStorms = false
    @State private var stormFilter = StormFilter()
    @State private var showStormFilter = false

    @State private var quickLogMode = false
    @State private var quickLogSpot: TappedSpot?
    @State private var statusFilter: Lead.Status?

    /// When on, the map re-centers on the canvasser as they walk. Auto-disables
    /// if the user pans the map away themselves.
    @State private var followMe = false

    @AppStorage(AppSettings.onboardingDoneKey) private var onboardingDone = false

    struct TappedSpot: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    private var visibleLeads: [Lead] {
        guard let statusFilter else { return leadStore.leads }
        return leadStore.leads.filter { $0.status == statusFilter }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    if showStormOverlay {
                        ForEach(stormMarkers) { item in
                            Annotation("", coordinate: item.report.coordinate) {
                                stormMarker(item)
                            }
                            .annotationTitles(.hidden)
                        }
                    }

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

                    ForEach(visibleLeads) { lead in
                        Annotation(lead.shortAddress, coordinate: lead.coordinate) {
                            Image(systemName: lead.status.symbolName)
                                .font(.caption)
                                .padding(6)
                                .background(color(for: lead.status), in: Circle())
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                                .onTapGesture {
                                    handleTap(at: lead.coordinate)
                                }
                        }
                    }
                }
                .mapStyle(useHybrid ? .hybrid(elevation: .flat) : .standard)
                .mapControls {
                    MapCompass()
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    visibleRegion = context.region
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    Self.persistCamera(context.region)
                    scheduleStormOverlayRefresh(for: context.region)
                    // If the map drifts away from the user while following, they
                    // panned it themselves — stop following so we don't fight them.
                    if followMe, let here = locationManager.lastLocation {
                        let dLat = abs(context.region.center.latitude - here.coordinate.latitude)
                        let dLon = abs(context.region.center.longitude - here.coordinate.longitude)
                        if dLat > context.region.span.latitudeDelta * 0.5
                            || dLon > context.region.span.longitudeDelta * 0.5 {
                            followMe = false
                        }
                    }
                }
                .onChange(of: locationManager.lastLocation?.timestamp) {
                    guard followMe, let here = locationManager.lastLocation else { return }
                    let span = visibleRegion?.span
                        ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    withAnimation(.easeOut(duration: 0.4)) {
                        cameraPosition = .region(MKCoordinateRegion(center: here.coordinate, span: span))
                    }
                }
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    searchFocused = false
                    handleTap(at: coordinate)
                }
            }
            .navigationTitle("Canvass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { quickLogMode.toggle() }
                    } label: {
                        Image(systemName: quickLogMode ? "bolt.fill" : "bolt")
                            .foregroundStyle(quickLogMode ? Color.orange : Color.accentColor)
                    }
                    .accessibilityLabel(quickLogMode ? "Quick Log on — taps log doors" : "Turn on Quick Log")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showStormOverlay.toggle()
                        if showStormOverlay, let region = visibleRegion {
                            scheduleStormOverlayRefresh(for: region)
                        }
                    } label: {
                        Image(systemName: showStormOverlay ? "cloud.bolt.rain.fill" : "cloud.bolt.rain")
                    }
                    .accessibilityLabel("Toggle storm report overlay")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showStormFilter = true
                    } label: {
                        Image(systemName: stormFilter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter storms")
                    .disabled(!showStormOverlay)
                }
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
                VStack(spacing: 6) {
                    searchOverlay
                    if !leadStore.leads.isEmpty {
                        statusChips
                    }
                    if isLoadingStorms {
                        statusPill(text: "Checking storms…", systemImage: nil, showsSpinner: true)
                    } else if showStormOverlay, !stormMarkers.isEmpty {
                        statusPill(text: "\(stormMarkers.count) storm report\(stormMarkers.count == 1 ? "" : "s") here",
                                   systemImage: "cloud.bolt.rain.fill", showsSpinner: false)
                    }
                    if quickLogMode {
                        Text("⚡️ Quick Log on — tap a roof, pick a status")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.92), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showStormOverlay {
                    stormLegend
                }
            }
            .overlay(alignment: .bottomTrailing) {
                zoomControls
            }
            .overlay(alignment: .bottom) {
                bottomBar
            }
            .overlay(alignment: .bottom) {
                if let undo {
                    undoToast(undo)
                }
            }
            .sensoryFeedback(.success, trigger: undo?.id)
            .sheet(item: $tappedCoordinate) { spot in
                PropertySheetView(coordinate: spot.coordinate)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStormFilter) {
                StormFilterSheet(filter: $stormFilter)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: stormFilter) {
                if let region = visibleRegion { scheduleStormOverlayRefresh(for: region) }
            }
            .confirmationDialog(
                "Log this door",
                isPresented: Binding(
                    get: { quickLogSpot != nil },
                    set: { if !$0 { quickLogSpot = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let spot = quickLogSpot {
                    Button("Not Home") { quickLog(.notHome, at: spot.coordinate) }
                    Button("Interested") { quickLog(.interested, at: spot.coordinate) }
                    Button("Appointment Set") { quickLog(.appointment, at: spot.coordinate) }
                    Button("Not Interested") { quickLog(.notInterested, at: spot.coordinate) }
                    Button("Signed!") { quickLog(.signed, at: spot.coordinate) }
                    Button("Full Details…") { tappedCoordinate = spot }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text("Address and storm evidence are saved automatically.")
            }
            .onAppear {
                switch locationManager.authorization {
                case .authorizedWhenInUse, .authorizedAlways:
                    locationManager.start()
                case .notDetermined where onboardingDone:
                    // Onboarding primes + asks for new users; this only covers
                    // someone who finished onboarding on an older build.
                    locationManager.requestPermission()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Tap routing

    private func handleTap(at coordinate: CLLocationCoordinate2D) {
        if quickLogMode {
            quickLogSpot = TappedSpot(coordinate: coordinate)
        } else {
            tappedCoordinate = TappedSpot(coordinate: coordinate)
        }
    }

    // MARK: - Quick log

    private func quickLog(_ status: Lead.Status, at coordinate: CLLocationCoordinate2D) {
        if let existing = leadStore.lead(near: coordinate.latitude, longitude: coordinate.longitude) {
            let priorStatus = existing.status
            leadStore.setStatus(status, for: existing)
            showUndo(UndoState(leadID: existing.id, status: priorStatus, wasNew: false))
            return
        }

        let lead = Lead(
            status: status,
            address: "Locating address…",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            lastKnockAt: Date()
        )
        leadStore.add(lead)
        showUndo(UndoState(leadID: lead.id, status: status, wasNew: true))

        // Address + storm evidence fill in behind the scenes — the canvasser
        // is already walking to the next door.
        let radius = radiusMiles
        let lookback = lookbackDays
        Task {
            var updated = lead
            if let geocode = await GeocodingService.reverseGeocode(coordinate) {
                updated.address = geocode.address
            } else {
                updated.address = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            }
            let reports = await StormDataService.shared.reports(
                near: coordinate,
                radiusMiles: radius,
                lookbackDays: lookback
            )
            updated.stormSummary = StormDataService.summary(of: reports, lookbackDays: lookback)
            leadStore.update(updated)
        }
    }

    private func showUndo(_ state: UndoState) {
        let heavy = state.status == .signed
        if heavy {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        withAnimation { undo = state }
        let pending = state.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo?.id == pending { withAnimation { undo = nil } }
        }
    }

    private func performUndo(_ state: UndoState) {
        if state.wasNew {
            if let lead = leadStore.leads.first(where: { $0.id == state.leadID }) {
                leadStore.delete(lead)
            }
        } else if let lead = leadStore.leads.first(where: { $0.id == state.leadID }) {
            leadStore.setStatus(state.status, for: lead)
        }
        withAnimation { undo = nil }
    }

    private func undoToast(_ state: UndoState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.wasNew ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                .foregroundStyle(.white)
            Text("Logged: \(currentStatusLabel(for: state.leadID))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button("Undo") { performUndo(state) }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.82), in: Capsule())
        .padding(.horizontal, 40)
        .padding(.bottom, 56)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func currentStatusLabel(for id: UUID) -> String {
        leadStore.leads.first(where: { $0.id == id })?.status.rawValue ?? "door"
    }

    // MARK: - Storm overlay

    private func stormMarker(_ item: NearbyStormReport) -> some View {
        Image(systemName: item.report.kind.symbolName)
            .font(.system(size: 11, weight: .bold))
            .padding(5)
            .background(item.report.kind.color.opacity(0.85), in: Circle())
            .foregroundStyle(.white)
            .shadow(radius: 1)
            .onTapGesture {
                tappedCoordinate = TappedSpot(coordinate: item.report.coordinate)
            }
    }

    private var stormLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { showLegend.toggle() }
            } label: {
                Image(systemName: showLegend ? "chevron.down.circle.fill" : "list.bullet.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor, Color(.systemBackground))
            }
            .buttonStyle(.plain)
            if showLegend {
                ForEach(StormReport.Kind.allCases, id: \.self) { kind in
                    HStack(spacing: 6) {
                        Circle().fill(kind.color).frame(width: 9, height: 9)
                        Text(kind.label).font(.caption2)
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .padding(.leading, 10)
        .padding(.bottom, 56)
    }

    private func statusPill(text: String, systemImage: String?, showsSpinner: Bool) -> some View {
        HStack(spacing: 6) {
            if showsSpinner {
                ProgressView().controlSize(.mini)
            } else if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 2)
    }

    private func scheduleStormOverlayRefresh(for region: MKCoordinateRegion) {
        guard showStormOverlay else { return }
        stormOverlayTask?.cancel()
        stormOverlayTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            isLoadingStorms = true
            // Cover the visible area, but stay within sane fetch bounds.
            let radius = min(max(region.span.latitudeDelta * 69 * 0.75, 2), 60)
            let reports = await StormDataService.shared.reports(
                near: region.center,
                radiusMiles: radius,
                lookbackDays: lookbackDays
            )
            guard !Task.isCancelled else { return }
            stormMarkers = Array(reports.filter { stormFilter.matches($0.report) }.prefix(80))
            isLoadingStorms = false
        }
    }

    // MARK: - Status chips & stats

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "All (\(leadStore.leads.count))", isOn: statusFilter == nil) {
                    statusFilter = nil
                }
                ForEach(Lead.Status.allCases) { status in
                    let count = leadStore.leads.filter { $0.status == status }.count
                    if count > 0 {
                        chip(label: "\(status.rawValue) (\(count))", isOn: statusFilter == status) {
                            statusFilter = (statusFilter == status) ? nil : status
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isOn ? Color.accentColor : Color(.systemBackground).opacity(0.9), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
                .shadow(color: .black.opacity(0.1), radius: 2)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        Group {
            if leadStore.leads.isEmpty {
                if !searchFocused {
                    Text(quickLogMode
                         ? "Tap a roof to log your first door"
                         : "Tap a rooftop to pull its storm report")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            } else {
                todayStats
            }
        }
        .padding(.bottom, 12)
    }

    private var todayStats: some View {
        let calendar = Calendar.current
        let today = leadStore.leads.filter { calendar.isDateInToday($0.knockedAt) }
        let appointments = today.filter { $0.status == .appointment }.count
        let interested = today.filter { $0.status == .interested }.count
        let signed = today.filter { $0.status == .signed }.count

        var parts = ["Today: \(today.count) door\(today.count == 1 ? "" : "s")"]
        if interested > 0 { parts.append("\(interested) interested") }
        if appointments > 0 { parts.append("\(appointments) appt\(appointments == 1 ? "" : "s")") }
        if signed > 0 { parts.append("\(signed) signed 🎉") }

        return Text(parts.joined(separator: " · "))
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
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
                toggleFollowMe()
            } label: {
                Image(systemName: followMe ? "location.fill" : "location")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(followMe ? Color.accentColor : .primary)
            }
            .accessibilityLabel(followMe ? "Following your location — tap to stop" : "Follow my location while canvassing")
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

    private func toggleFollowMe() {
        followMe.toggle()
        guard followMe else { return }
        locationManager.start()
        let span = visibleRegion.map { region -> MKCoordinateSpan in
            // Snap to a street-level zoom the first time you start following.
            min(region.span.latitudeDelta, region.span.longitudeDelta) > 0.02
                ? MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                : region.span
        } ?? MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        if let here = locationManager.lastLocation {
            withAnimation(.easeOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: here.coordinate, span: span))
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                cameraPosition = .userLocation(fallback: .automatic)
            }
        }
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

    private func color(for status: Lead.Status) -> Color { status.color }

    // MARK: - Camera persistence

    /// First launch (or after the user's last region was cleared) follows the
    /// device location, falling back to Charlotte; otherwise restores the last
    /// region the rep was looking at.
    private static func initialCameraPosition() -> MapCameraPosition {
        let defaults = UserDefaults.standard
        let lat = defaults.double(forKey: AppSettings.lastCameraLatKey)
        let lon = defaults.double(forKey: AppSettings.lastCameraLonKey)
        let span = defaults.double(forKey: AppSettings.lastCameraSpanKey)
        if lat != 0, lon != 0, span > 0 {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))
        }
        return .userLocation(fallback: .region(MKCoordinateRegion(
            center: charlotte,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )))
    }

    private static func persistCamera(_ region: MKCoordinateRegion) {
        let defaults = UserDefaults.standard
        defaults.set(region.center.latitude, forKey: AppSettings.lastCameraLatKey)
        defaults.set(region.center.longitude, forKey: AppSettings.lastCameraLonKey)
        defaults.set(region.span.latitudeDelta, forKey: AppSettings.lastCameraSpanKey)
    }
}
