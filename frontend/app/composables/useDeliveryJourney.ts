import { computed, onMounted, onUnmounted, ref, type Ref } from 'vue'

/** Maps native page scrolling onto a pinned story; never intercepts wheel or touch. */
export function useDeliveryJourney(rail: Ref<HTMLElement | null>, pin: Ref<HTMLElement | null>, count: number) {
  const activeStep = ref(0)
  const progress = ref(0)
  const paused = ref(false)
  const reducedMotion = ref(false)
  const compactViewport = ref(false)
  const visible = ref(false)
  const pageVisible = ref(true)
  const scrollDriven = computed(() => !reducedMotion.value && !compactViewport.value)
  const playing = computed(() => visible.value && pageVisible.value && !paused.value && !reducedMotion.value)
  let observer: IntersectionObserver | undefined
  let resizeObserver: ResizeObserver | undefined
  let preference: MediaQueryList | undefined
  let compactPreference: MediaQueryList | undefined
  let frame = 0

  function scrollGeometry() {
    if (!rail.value || !pin.value) return null
    return {
      top: rail.value.getBoundingClientRect().top,
      offset: Number.parseFloat(getComputedStyle(pin.value).top) || 0,
      distance: rail.value.offsetHeight - pin.value.offsetHeight,
    }
  }

  function updateScroll() {
    frame = 0
    if (!scrollDriven.value) return
    const geometry = scrollGeometry()
    if (!geometry || geometry.distance <= 0) return
    const position = Math.min(1, Math.max(0, (geometry.offset - geometry.top) / geometry.distance)) * count
    activeStep.value = Math.min(count - 1, Math.floor(position))
    progress.value = position >= count ? 1 : position - activeStep.value
  }

  function scheduleScroll() {
    if (!frame) frame = requestAnimationFrame(updateScroll)
  }

  function selectStep(index: number) {
    const target = (index + count) % count
    if (!scrollDriven.value) {
      activeStep.value = target
      progress.value = 0
      return
    }
    const geometry = scrollGeometry()
    if (!geometry || geometry.distance <= 0) return
    // Land just inside the chapter, avoiding rounding at a chapter boundary.
    window.scrollTo({
      top: window.scrollY + geometry.top - geometry.offset + ((target + 0.08) / count) * geometry.distance,
      behavior: 'smooth',
    })
  }

  function togglePlayback() {
    paused.value = !paused.value
  }

  function syncPreference() {
    reducedMotion.value = preference?.matches ?? false
    compactViewport.value = compactPreference?.matches ?? false
    scheduleScroll()
  }

  function syncVisibility() {
    pageVisible.value = !document.hidden
  }

  onMounted(() => {
    preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    compactPreference = window.matchMedia('(max-height: 620px)')
    syncPreference()
    syncVisibility()
    preference.addEventListener('change', syncPreference)
    compactPreference.addEventListener('change', syncPreference)
    document.addEventListener('visibilitychange', syncVisibility)
    window.addEventListener('scroll', scheduleScroll, { passive: true })
    window.addEventListener('resize', scheduleScroll, { passive: true })
    observer = new IntersectionObserver(([entry]) => {
      visible.value = entry?.isIntersecting ?? false
    }, { threshold: 0.1 })
    if (pin.value) observer.observe(pin.value)
    // Keep the mapping correct after viewport changes and late font/layout updates.
    resizeObserver = new ResizeObserver(scheduleScroll)
    if (rail.value) resizeObserver.observe(rail.value)
    if (pin.value) resizeObserver.observe(pin.value)
  })

  onUnmounted(() => {
    cancelAnimationFrame(frame)
    observer?.disconnect()
    resizeObserver?.disconnect()
    preference?.removeEventListener('change', syncPreference)
    compactPreference?.removeEventListener('change', syncPreference)
    document.removeEventListener('visibilitychange', syncVisibility)
    window.removeEventListener('scroll', scheduleScroll)
    window.removeEventListener('resize', scheduleScroll)
  })

  return { activeStep, progress, paused, reducedMotion, scrollDriven, playing, visible, selectStep, togglePlayback }
}
