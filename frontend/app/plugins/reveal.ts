import type { Directive } from 'vue'

// Scroll-triggered entrance animation. Plain IntersectionObserver + CSS
// transition (see .reveal in assets/main.css) — no animation library, so it
// can't be affected by SSR/hydration timing the way a directive-based motion
// library can. `mounted` never runs during SSR, so the server always renders
// the static "reveal" class (invisible) and the client alone decides when to
// add "is-visible", which keeps the two renders identical (no mismatch).
const vReveal: Directive<HTMLElement, { delay?: number; type?: '3d' } | undefined> = {
  mounted(el, binding) {
    el.classList.add(binding.value?.type === '3d' ? 'reveal-3d' : 'reveal')
    const delay = binding.value?.delay
    if (delay) el.style.transitionDelay = `${delay}ms`

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          el.classList.add('is-visible')
          observer.unobserve(el)
        }
      },
      { threshold: 0.15 },
    )
    observer.observe(el)
  },
}

export default defineNuxtPlugin((nuxtApp) => {
  nuxtApp.vueApp.directive('reveal', vReveal)
})
