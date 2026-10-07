# İç sayfaların görsel uyumu — 7 Ekim 2026

Ana sayfadaki krem zemin, sıcak turuncu vurgu, Space Grotesk başlıkları,
yuvarlatılmış beyaz yüzeyler ve hafif gölgeler iç sayfalara taşındı.
Ortak başlık `frontend/app/components/PageHeader.vue`, ortak stil ve responsive
kurallar `frontend/app/assets/styles/pages.css` içinde tutulur. Ana sayfanın
yerleşimi korunur.

Teslimat ve kurye listeleri, teslimat detayı, panel, oluşturma formu,
giriş/kayıt, ödeme ve onay ekranları, destek ekranları ve harita çerçeveleri
ortak görsel dili kullanır. Teklif penceresi küçük ekranlarda kaydırılabilir.
Kurye kartlarındaki araç türü ve teklif sayısı mevcut veriden gelir; bulunmayan
itibar puanı sıfır olarak gösterilmez.

## Doğrulama

- Node 24 ile `npm run typecheck`, değişen Vue/TS dosyalarında ESLint,
  `npm run build` ve `git diff --check`.
- Chrome üzerinde 12 ilan / 6 kurye / 20 teklif ile liste, arama, durum filtreleri,
  teklif penceresi, teslimat detayı, kullanıcı paneli ve oluşturma formu.
- 390 × 844 mobil görünümde form, liste ve kurye kartları; form/liste/dizin
  sayfalarında yatay taşma gözlenmedi. Masaüstünde giriş/kayıt, ödeme, destek kapalı durumu ve iki harita ekranı.
- Kanıt görselleri: `frontend/test-artifacts/theme/`.

## Devam notları

`frontend/app/pages/support/` altında yetkili vaka içerikleri ve
`frontend/app/pages/courier/receive/[id].vue` içinde atanmış kurye işlem dalları
ortak stilleri kullanır; destek modülü kapalı ve mevcut oturum gönderici olduğu
için bu dalların dolu durumları tarayıcıda ayrıca doğrulanmalıdır. Ödeme, imza,
teklif gönderme veya profil kaydetme işlemleri bu görsel kontrolde yapılmadı.

`frontend/app/pages/map.vue` için genel konum API'si boş döner; özel canlı takip
teslimat detayından açılır. Boş durum metni bunu açıklar.
`frontend/app/pages/kuryem-nerede.vue` örnek rota gösterimidir.

## Sonraki iki görev

1. Liste/detay/form/teklif penceresi için masaüstü ve mobil görsel regresyon
   kontrolleri ekle; ortak stillerdeki değişimlerin taşma oluşturmasını yakala.
2. Kurye dizinine araç filtresi ve doğrulanmış değerlendirme verilerini bağla;
   göndericinin kurye seçimini kolaylaştır.
