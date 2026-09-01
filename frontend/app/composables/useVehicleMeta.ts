import { PhBicycle, PhMotorcycle, PhCar, PhPersonSimpleWalk } from '@phosphor-icons/vue'
import type { Component } from 'vue'

export type VehicleType = 'bicycle' | 'motorcycle' | 'car' | 'on_foot'

const LABELS: Record<VehicleType, string> = {
  bicycle: 'Bisiklet',
  motorcycle: 'Motosiklet',
  car: 'Araç',
  on_foot: 'Yaya',
}

const EMOJIS: Record<VehicleType, string> = {
  bicycle: '🚲',
  motorcycle: '🏍️',
  car: '🚗',
  on_foot: '🚶',
}

const ICONS: Record<VehicleType, Component> = {
  bicycle: PhBicycle,
  motorcycle: PhMotorcycle,
  car: PhCar,
  on_foot: PhPersonSimpleWalk,
}

export function vehicleLabel(type: string): string {
  return LABELS[type as VehicleType] || type
}

export function vehicleEmoji(type: string): string {
  return EMOJIS[type as VehicleType] || EMOJIS.motorcycle
}

export function vehicleIcon(type: string): Component {
  return ICONS[type as VehicleType] || ICONS.motorcycle
}
