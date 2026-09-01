<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ value: string; size?: number }>()

const MODULES = 21
const CELL = 8
const PAD = 12

function finderCell(r: number, c: number): boolean | null {
  let lr: number, lc: number

  if (r <= 6 && c <= 6) { lr = r; lc = c }
  else if (r <= 6 && c >= MODULES - 7) { lr = r; lc = c - (MODULES - 7) }
  else if (r >= MODULES - 7 && c <= 6) { lr = r - (MODULES - 7); lc = c }
  else return null

  const onEdge = lr === 0 || lr === 6 || lc === 0 || lc === 6
  const inCore = lr >= 2 && lr <= 4 && lc >= 2 && lc <= 4
  return onEdge || inCore
}

const grid = computed<boolean[][]>(() => {
  const rows: boolean[][] = []
  for (let r = 0; r < MODULES; r++) {
    const row: boolean[] = []
    for (let c = 0; c < MODULES; c++) {
      const fp = finderCell(r, c)
      if (fp !== null) {
        row.push(fp)
      } else if (r === 6 || c === 6) {
        row.push((r + c) % 2 === 0)
      } else {
        const idx = (r * MODULES + c) % props.value.length
        const ch = props.value.charCodeAt(idx)
        row.push(((ch * 37 + r * 17 + c * 13) & 1) === 0)
      }
    }
    rows.push(row)
  }
  return rows
})

const total = computed(() => MODULES * CELL + PAD * 2)
</script>

<template>
  <svg
    :width="size ?? total"
    :height="size ?? total"
    :viewBox="`0 0 ${total} ${total}`"
    xmlns="http://www.w3.org/2000/svg"
  >
    <rect width="100%" height="100%" fill="white" rx="12" />
    <template v-for="(row, r) in grid" :key="r">
      <template v-for="(dark, c) in row" :key="c">
        <rect
          v-if="dark"
          :x="c * CELL + PAD"
          :y="r * CELL + PAD"
          :width="CELL"
          :height="CELL"
          fill="#111827"
        />
      </template>
    </template>
  </svg>
</template>
