import { createRouter, createWebHistory } from 'vue-router'
import { useWalletStore } from '../stores/useWalletStore'
import HomeView from '../views/HomeView.vue'
import LoginView from '../views/LoginView.vue'
import RegisterView from '../views/RegisterView.vue'

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
    {
      path: '/login',
      name: 'login',
      component: LoginView,
    },
    {
      path: '/register',
      name: 'register',
      component: RegisterView,
    },
    {
      path: '/dashboard',
      name: 'dashboard',
      component: () => import('../views/DashboardView.vue'),
      meta: { requiresAuth: true }
    },
    {
      path: '/payment/:id',
      name: 'payment',
      component: () => import('../views/PaymentView.vue'),
      meta: { requiresAuth: true }
    },
    {
      path: '/courier/receive/:id',
      name: 'courier-receive',
      component: () => import('../views/CourierReceiveView.vue'),
      meta: { requiresAuth: true }
    },
    {
      path: '/delivery/:id/confirm',
      name: 'delivery-confirm',
      component: () => import('../views/DeliveryConfirmView.vue'),
      meta: { requiresAuth: true }
    },
  ],
})

router.beforeEach((to, from, next) => {
  const wallet = useWalletStore()

  // Protect routes that require auth
  if (to.meta.requiresAuth || to.path === '/create') {
    if (!wallet.connected) {
      return next('/login')
    }
  }

  // Redirect away from login/register if already connected
  if ((to.path === '/login' || to.path === '/register') && wallet.connected) {
    return next('/dashboard')
  }

  next()
})

export default router
