// Disposable local test service only. The importer uses this read-only account.
db.getSiblingDB('monosfer_legacy_test').createUser({
  user: 'legacy_reader', pwd: 'local-read-only', roles: [{ role: 'read', db: 'monosfer_legacy_test' }],
});
