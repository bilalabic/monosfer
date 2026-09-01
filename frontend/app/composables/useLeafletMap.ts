import L from 'leaflet'

export const OSM_LIGHT_TILE_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
export const OSM_LIGHT_ATTRIBUTION = '&copy; OpenStreetMap contributors'
export const CARTO_DARK_TILE_URL = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'

interface CreateLeafletMapOptions {
  center: L.LatLngExpression
  zoom: number
  zoomControl?: boolean
  attributionControl?: boolean
  tileUrl?: string
  tileOptions?: L.TileLayerOptions
}

export function createLeafletMap(elementId: string, options: CreateLeafletMapOptions): L.Map {
  const map = L.map(elementId, {
    center: options.center,
    zoom: options.zoom,
    zoomControl: options.zoomControl ?? true,
    attributionControl: options.attributionControl ?? true,
  })

  L.tileLayer(options.tileUrl ?? OSM_LIGHT_TILE_URL, {
    attribution: OSM_LIGHT_ATTRIBUTION,
    subdomains: 'abc',
    maxZoom: 19,
    ...options.tileOptions,
  }).addTo(map)

  return map
}

export function destroyLeafletMap(map: L.Map | null): null {
  if (map) map.remove()
  return null
}
