import L from 'leaflet'
import { vehicleEmoji } from '@/composables/useVehicleMeta'

export interface CourierMarkerOptions {
  vehicleType: string
  name: string
  size?: number
  /** Any valid CSS `background` value — a solid color or a gradient. Defaults to the brand orange gradient. */
  background?: string
  ringColor?: string
  /** Animates via the global `pulse-ring` keyframe (assets/main.css) — use for the selected/active courier. */
  pulse?: boolean
}

const DEFAULT_BACKGROUND = 'linear-gradient(135deg, #f97316, #ea580c)'
const DEFAULT_RING = '#ea580c'

/** Circular, vehicle-emoji courier marker shared by every Leaflet map in the app. */
export function createCourierMarkerIcon({
  vehicleType,
  name,
  size = 44,
  background = DEFAULT_BACKGROUND,
  ringColor = DEFAULT_RING,
  pulse = false,
}: CourierMarkerOptions): L.DivIcon {
  return L.divIcon({
    html: `
      <div style="position:relative;">
        <div style="
          width:${size}px; height:${size}px;
          background: ${background};
          border: 3px solid ${ringColor};
          border-radius: 50%;
          display:flex; align-items:center; justify-content:center;
          box-shadow: 0 4px 16px rgba(0,0,0,0.3);
          font-size:${Math.round(size * 0.45)}px;
          ${pulse ? 'animation: pulse-ring 1.5s ease-out infinite;' : ''}
        ">${vehicleEmoji(vehicleType)}</div>
        <div style="
          position:absolute; bottom:-8px; left:50%; transform:translateX(-50%);
          font-size:11px; font-weight:700;
          background:#1e293b; color:#f97316;
          border-radius:6px; padding:2px 6px;
          white-space:nowrap;
          box-shadow:0 2px 6px rgba(0,0,0,0.4);
          border: 1px solid rgba(249,115,22,0.3);
        ">${name.split(' ')[0]}</div>
      </div>
    `,
    className: '',
    iconSize: [size, size + 14],
    iconAnchor: [size / 2, size / 2],
    popupAnchor: [0, -(size / 2 + 8)],
  })
}

export interface PointMarkerOptions {
  emoji: string
  color: string
  label?: string
  size?: number
}

/** Small circular pin used for pickup/dropoff/route-endpoint markers. */
export function createPointMarkerIcon({ emoji, color, label, size = 32 }: PointMarkerOptions): L.DivIcon {
  return L.divIcon({
    html: `
      <div style="position:relative;">
        <div style="
          width:${size}px; height:${size}px;
          background:${color};
          border: 3px solid #fff;
          border-radius:50%;
          display:flex; align-items:center; justify-content:center;
          box-shadow: 0 3px 10px ${color}80;
          font-size:${Math.round(size * 0.5)}px;
        ">${emoji}</div>
        ${label ? `<div style="
          position:absolute; bottom:-18px; left:50%; transform:translateX(-50%);
          font-size:9px; font-weight:600;
          background:#1e293b; color:#fff;
          border-radius:4px; padding:1px 5px; white-space:nowrap;
        ">${label}</div>` : ''}
      </div>
    `,
    className: '',
    iconSize: [size, label ? size + 16 : size],
    iconAnchor: [size / 2, size / 2],
  })
}
