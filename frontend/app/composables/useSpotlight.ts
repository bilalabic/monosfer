export function onSpotlightMouseMove(e: MouseEvent) {
  const el = e.currentTarget as HTMLElement
  const rect = el.getBoundingClientRect()
  el.style.setProperty('--x', `${e.clientX - rect.left}px`)
  el.style.setProperty('--y', `${e.clientY - rect.top}px`)
}

const MAX_TILT_DEG = 8

// Tilts a `.tilt-card` child instead of `e.currentTarget` itself — the listener's own
// element also carries the v-reveal directive's `transform: translateY(...)`, and the two
// compete for the same CSS property on the same element in some browsers. Keeping the tilt
// on a separate inner element sidesteps that entirely.
function tiltTarget(el: HTMLElement): HTMLElement {
  return el.querySelector<HTMLElement>('.tilt-card') ?? el
}

export function onTiltMouseMove(e: MouseEvent) {
  const el = e.currentTarget as HTMLElement
  const rect = el.getBoundingClientRect()
  const px = (e.clientX - rect.left) / rect.width
  const py = (e.clientY - rect.top) / rect.height
  const rotateX = (0.5 - py) * MAX_TILT_DEG * 2
  const rotateY = (px - 0.5) * MAX_TILT_DEG * 2
  tiltTarget(el).style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`
}

export function onTiltMouseLeave(e: MouseEvent) {
  const el = e.currentTarget as HTMLElement
  tiltTarget(el).style.transform = ''
}

export function onSpotlightTiltMouseMove(e: MouseEvent) {
  onSpotlightMouseMove(e)
  onTiltMouseMove(e)
}
