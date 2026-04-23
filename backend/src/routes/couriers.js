import { Router } from 'express'
import { list, locations } from '../controllers/courierController.js'

const router = Router()

router.get('/', list)
router.get('/locations', locations)

export default router
