import { Router } from 'express'
import { register, login, me, updateMe } from '../controllers/authController.js'
import { authenticate } from '../middlewares/authenticate.js'

const authRouter = Router()

authRouter.post('/register', register)
authRouter.post('/login', login)
authRouter.get('/me', authenticate, me)
authRouter.patch('/me', authenticate, updateMe)

export default authRouter
