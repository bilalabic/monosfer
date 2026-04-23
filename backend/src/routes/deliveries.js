import { Router } from 'express'
import { authenticate } from '../middlewares/authenticate.js'
import {
  list, getOne, create,
  addBid, selectBid,
  lockEscrow, confirmPickup, complete,
} from '../controllers/deliveryController.js'

const deliveriesRouter = Router()

deliveriesRouter.get('/', list)
deliveriesRouter.get('/:id', getOne)
deliveriesRouter.post('/', authenticate, create)
deliveriesRouter.post('/:id/bids', authenticate, addBid)
deliveriesRouter.patch('/:id/select-bid', authenticate, selectBid)
deliveriesRouter.patch('/:id/escrow', authenticate, lockEscrow)
deliveriesRouter.patch('/:id/pickup', authenticate, confirmPickup)
deliveriesRouter.patch('/:id/complete', authenticate, complete)

export default deliveriesRouter
