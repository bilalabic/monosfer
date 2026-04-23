<script setup lang="ts">
import { RouterLink } from 'vue-router'
</script>

<template>
  <footer class="mt-16 border-t border-stone-200 bg-white">
    <div class="mx-auto max-w-6xl px-5 py-10 sm:px-8">
      <div class="grid gap-8 sm:grid-cols-3">
        <div>
          <div class="mb-3 flex items-center gap-2">
            <img src="/gemini-svg-_1_.png" alt="Delivera" class="size-7 rounded-lg object-cover">
            <span class="font-bold text-stone-900">Delivera</span>
          </div>
          <p class="text-sm leading-relaxed text-stone-500">
            Merkeziyetsiz, güvenli ve rekabetçi teslimat ağı.
          </p>
          <div class="mt-4 flex items-center gap-2">
            <span class="size-1.5 rounded-full bg-green-500 animate-pulse-dot" />
            <span class="text-xs text-stone-400">Monad Testnet'te Canlı</span>
          </div>
        </div>

        <div>
          <h4 class="mb-3 text-sm font-semibold text-stone-900">Platform</h4>
          <ul class="space-y-2 text-sm text-stone-500">
            <li><RouterLink to="/deliveries" class="hover:text-stone-900 transition">Teslimatlar</RouterLink></li>
            <li><RouterLink to="/couriers" class="hover:text-stone-900 transition">Leaderboard</RouterLink></li>
            <li><RouterLink to="/create" class="hover:text-stone-900 transition">Teslimat Oluştur</RouterLink></li>
          </ul>
        </div>

        <div>
          <h4 class="mb-3 text-sm font-semibold text-stone-900">Teknoloji</h4>
          <ul class="space-y-2 text-sm text-stone-500">
            <li>Monad Blockchain</li>
            <li>Solidity Akıllı Sözleşmeler</li>
            <li>Escrow & Teminat</li>
            <li>Merkeziyetsiz Jüri</li>
          </ul>
        </div>
      </div>

      <div class="mt-8 border-t border-stone-100 pt-6 flex flex-col items-center justify-between gap-3 sm:flex-row">
        <p class="text-xs text-stone-400">© 2026 Delivera · Monad Hackathon</p>
        <a href="https://monad.xyz" target="_blank" rel="noopener" class="text-xs text-stone-400 hover:text-stone-600 transition">
          Built on Monad ↗
        </a>
      </div>
    </div>
  </footer>
</template>
