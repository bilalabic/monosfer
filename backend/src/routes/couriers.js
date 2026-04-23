import { Router } from 'express'
import { list } from '../controllers/courierController.js'

const router = Router()

router.get('/', list)

export default router
