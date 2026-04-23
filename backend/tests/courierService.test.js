import test from 'node:test'
import assert from 'node:assert/strict'
import User from '../src/models/User.js'
import CourierStats from '../src/models/CourierStats.js'
import { listCouriers } from '../src/services/courierService.js'

function queryMatchesRole(query, user) {
  const allowedRoles = query?.role?.$in
  return !allowedRoles || allowedRoles.includes(user.role)
}

test('listCouriers includes customer users because every user can be a courier', async () => {
  const originalUserFind = User.find
  const originalStatsFind = CourierStats.find

  const users = [
    {
      _id: { toString: () => 'customer-id' },
      walletAddress: '0x1111111111111111111111111111111111111111',
      name: 'Normal Kullanici',
      role: 'customer',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
    },
    {
      _id: { toString: () => 'courier-id' },
      walletAddress: '0x2222222222222222222222222222222222222222',
      name: 'Kayitli Kurye',
      role: 'courier',
      courierProfile: { specialties: ['Gida'] },
      createdAt: new Date('2026-01-02T00:00:00.000Z'),
    },
  ]

  User.find = query => ({
    select: () => ({
      lean: async () => users.filter(user => queryMatchesRole(query, user)),
    }),
  })
  CourierStats.find = () => ({
    lean: async () => [],
  })

  try {
    const couriers = await listCouriers()

    assert.deepEqual(
      couriers.map(courier => courier.name),
      ['Normal Kullanici', 'Kayitli Kurye'],
    )
  } finally {
    User.find = originalUserFind
    CourierStats.find = originalStatsFind
  }
})
