import SwiftUI
import MapKit

/// The canvassing map: tap any house to pull its address, storm history, and
/// public contact lookups. Saved leads show as colored pins.
struct CanvassMapView: View {
    @EnvironmentObject private var leadStore: LeadStore
    @EnvironmentObject private var locationManager: LocationManager

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var tappedCoordinate: TappedSpot?
    @State private var useHybrid = true

    struct TappedSpot: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

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
                    MapUserLocationButton()
                    MapCompass()
                }
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
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
            .overlay(alignment: .bottom) {
                if leadStore.leads.isEmpty {
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
