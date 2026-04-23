## Contracts Workspace

Bu klasor Monad icin Foundry tabanli smart contract calisma alanidir.

### Dizinler

- `src/` kontratlar
- `test/` Forge testleri
- `script/` deploy scriptleri
- `lib/` Foundry bagimliliklari

### Ortam Degiskenleri

`.env.example` dosyasini kopyalayip kendi degerlerinizi girin.

```sh
cp .env.example .env
```

### Komutlar

```sh
forge build
forge test
forge fmt
```

### Root Komutlari

Proje kokunden Scaffold-ETH benzeri local akis:

```sh
npm run chain
npm run deploy
npm start
```

- `npm run chain` local Anvil node baslatir
- `npm run deploy` local Anvil chain'e `Counter` kontratini JSON-RPC ile deploy eder
- `npm start` frontend ve backend gelistirme sunucularini birlikte baslatir

Monad testnet deploy icin:

```sh
npm run deploy:monad-testnet
```

### Monad Testnet Deploy

```sh
source .env
forge script script/DeployCounter.s.sol:DeployCounterScript \
  --rpc-url $MONAD_TESTNET_RPC_URL \
  --broadcast
```
