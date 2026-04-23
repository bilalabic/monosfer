import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '../views/HomeView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView,
    },
    {
      path: '/deliveries',
      name: 'deliveries',
      component: () => import('../views/DeliveriesView.vue'),
    },
    {
      path: '/delivery/:id',
      name: 'delivery-detail',
      component: () => import('../views/DeliveryDetailView.vue'),
    },
    {
      path: '/couriers',
      name: 'couriers',
      component: () => import('../views/CouriersView.vue'),
    },
    {
      path: '/create',
      name: 'create-delivery',
      component: () => import('../views/CreateDeliveryView.vue'),
    },
  ],
})

export default router
