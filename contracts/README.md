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

Gercek private key sadece `.env` icinde tutulmalidir. `.env` dosyasi repoya commitlenmez.

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

Bu komut `contracts/.env` dosyasini okur, Foundry ile `monad_testnet` RPC alias'ina deploy eder ve deploy sonucunu `contracts/deployments/monad-testnet.json` dosyasina yazar.

### Monad Testnet Deploy

```sh
cd contracts
cp .env.example .env
```

1. `contracts/.env` icinde `PRIVATE_KEY` degerini girin.
2. Deploy edecek cuzdan adresine Monad testnet faucet uzerinden test MON alin.
3. Proje kokunden `npm run contracts:test` ve `npm run contracts:build` calistirin.
4. Proje kokunden `npm run deploy:monad-testnet` calistirin.
5. Deploy edilen adresi Monad testnet explorer uzerinden kontrol edin.

Kendi node'unuzu kurmaniz gerekmez. Public Monad testnet RPC veya tercih ettiginiz provider RPC yeterlidir.
